import Foundation

/// Why `PathPolicy` refused a path.
enum RefusalReason: Equatable, Sendable {
    case notAFileURL
    case unresolvable
    case protectedRoot
    case systemLocation
    case outsideAllowedArea
    case appleItem
    case notAnAppBundle
    case changedSinceScan
    case mountPoint
}

enum PolicyDecision: Equatable, Sendable {
    /// Removal may go ahead on this canonical URL.
    case allowed(URL)
    case refused(RefusalReason)
}

/// The single answer to "may this path be removed for this purpose?".
///
/// The parent folder is canonicalised with `realpath(3)` so a symlinked folder
/// cannot smuggle a protected location into an allowed tree. The last path
/// component is deliberately not resolved: if it is a symlink, only the link is
/// removed, never what it points to.
struct PathPolicy: Sendable {
    let rules: SafetyRules

    init(rules: SafetyRules = SafetyRules()) {
        self.rules = rules
    }

    func evaluate(_ url: URL, purpose: RemovalPurpose) -> PolicyDecision {
        guard url.isFileURL else { return .refused(.notAFileURL) }

        let standardized = url.standardizedFileURL.path
        let name = (standardized as NSString).lastPathComponent
        guard standardized.hasPrefix("/"), !name.isEmpty, name != "/", name != ".", name != ".." else {
            return .refused(.unresolvable)
        }

        let parent = (standardized as NSString).deletingLastPathComponent
        guard let canonicalParent = SafetyRules.canonicalPath(parent) else {
            return .refused(.unresolvable)
        }
        let canonical = canonicalParent == "/" ? "/\(name)" : "\(canonicalParent)/\(name)"

        if let reason = refusal(for: canonical, purpose: purpose) {
            return .refused(reason)
        }
        return .allowed(URL(fileURLWithPath: canonical))
    }

    private func refusal(for path: String, purpose: RemovalPurpose) -> RefusalReason? {
        if rules.protectedRoots.contains(where: { Self.isSame(path, $0) }) {
            return .protectedRoot
        }
        if rules.forbiddenTrees.contains(where: { Self.isSame(path, $0) || Self.isInside(path, $0) }) {
            return .systemLocation
        }
        guard let root = rules.allowedTrees(for: purpose).first(where: { Self.isInside(path, $0) }),
              !rules.excludedTrees(for: purpose).contains(where: { Self.isSame(path, $0) || Self.isInside(path, $0) })
        else {
            return .outsideAllowedArea
        }

        // Components below the allowed tree, e.g. ["com.example", "Cache.db"].
        let below = Self.components(of: path, below: root)

        switch purpose {
        case .appLeftover, .orphan:
            // Support files belong to an app's own folder, never to a whole
            // standard Library folder such as Application Support.
            if purpose == .appLeftover, Self.isSame(root, "\(rules.home)/Library"), below.count < 2 {
                return .protectedRoot
            }
            if below.contains(where: Self.isAppleName) {
                return .appleItem
            }
        case .appBundle:
            // An app inside another app is part of it.
            guard below.last.map(Self.isAppBundleName) == true, !below.dropLast().contains(where: Self.isAppBundleName)
            else { return .notAnAppBundle }
        case .regenerableCache where SafetyRules.sharedTemporaryFolders.contains(where: { Self.isSame(root, $0) }):
            if below.count != 1 { return .outsideAllowedArea }
            if Self.isAppleName(below[0]) { return .appleItem }
        default:
            break
        }
        return nil
    }

    private static func isAppleName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("com.apple.") || lowered.hasPrefix("group.com.apple.")
    }

    private static func isAppBundleName(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".app")
    }

    private static func components(of path: String, below root: String) -> [String] {
        let rootCount = (root as NSString).pathComponents.count
        return Array((path as NSString).pathComponents.dropFirst(rootCount))
    }

    // MARK: - Comparison

    // Paths are compared as Unicode scalars after canonical composition and
    // case folding. The boot volume ignores case and normalisation, so these
    // comparisons must too; comparing grapheme clusters would let a name that
    // starts with a combining mark merge with the "/" before it and slip past
    // a prefix check.

    private static func key(_ path: String) -> [Unicode.Scalar] {
        Array(path.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars)
    }

    static func isSame(_ path: String, _ other: String) -> Bool {
        key(path) == key(other)
    }

    /// True when `path` sits strictly below `root`. The separator boundary keeps
    /// "/Library/CachesX" out of "/Library/Caches".
    static func isInside(_ path: String, _ root: String) -> Bool {
        var prefix = key(root)
        if prefix.last != "/" { prefix.append("/") }
        let candidate = key(path)
        return candidate.count > prefix.count && candidate.starts(with: prefix)
    }
}
