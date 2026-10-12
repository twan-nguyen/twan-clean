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

        if let reason = refusal(for: canonical, name: name, purpose: purpose) {
            return .refused(reason)
        }
        return .allowed(URL(fileURLWithPath: canonical))
    }

    private func refusal(for path: String, name: String, purpose: RemovalPurpose) -> RefusalReason? {
        if rules.protectedRoots.contains(where: { Self.isSame(path, $0) }) {
            return .protectedRoot
        }
        if rules.forbiddenTrees.contains(where: { Self.isSame(path, $0) || Self.isInside(path, $0) }) {
            return .systemLocation
        }
        let isAllowed = rules.allowedTrees(for: purpose).contains { Self.isInside(path, $0) }
            && !rules.excludedTrees(for: purpose).contains { Self.isSame(path, $0) || Self.isInside(path, $0) }
        guard isAllowed else { return .outsideAllowedArea }

        switch purpose {
        case .orphan where name.lowercased().hasPrefix("com.apple."):
            return .appleItem
        case .appBundle where !name.lowercased().hasSuffix(".app"):
            return .notAnAppBundle
        default:
            return nil
        }
    }

    // The boot volume is case-insensitive, so comparisons are too: refusing
    // "/system/x" matters more than allowing an oddly cased cache path.

    static func isSame(_ path: String, _ other: String) -> Bool {
        path.compare(other, options: .caseInsensitive) == .orderedSame
    }

    /// True when `path` sits strictly below `root`. The separator boundary keeps
    /// "/Library/CachesX" out of "/Library/Caches".
    static func isInside(_ path: String, _ root: String) -> Bool {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.count > prefix.count
            && path.lowercased().hasPrefix(prefix.lowercased())
    }
}
