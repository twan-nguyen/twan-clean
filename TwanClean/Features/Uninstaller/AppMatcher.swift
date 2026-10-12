import Foundation

/// The rule that tied a file to an app, from the most to the least certain.
enum MatchTier: Int, Comparable, Sendable {
    /// A per-app override for an app whose files do not follow its name.
    case override = 0
    case bundleIdentifier
    case displayName
    case fileStem
    case lettersOnlyName
    case bundleLastTwoComponents
    case baseBundleIdentifier
    case versionStrippedName
    case teamIdentifier
    case developerName

    static func < (lhs: MatchTier, rhs: MatchTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Strong enough to remove a system-level item without the user picking it.
    var isExact: Bool { self == .bundleIdentifier || self == .displayName }
}

extension String {
    /// Lowercased with spaces, dashes, underscores and dots removed, so
    /// "com.Example.My-App" and "My App" compare as "comexamplemyapp" and "myapp".
    var normalizedForMatching: String {
        var result = lowercased()
        result.removeAll { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." }
        return result
    }
}

/// Decides whether a file name belongs to an app, at a given sensitivity.
///
/// Each rule is a normalized token with a tier. In strict mode a name must
/// equal a token; otherwise containing it is enough. Tokens shorter than five
/// characters are ignored, so an app called "SSH" can never claim `~/.ssh`.
struct AppMatcher: Sendable {
    struct Token: Sendable {
        let tier: MatchTier
        let value: String
    }

    static let minimumTokenLength = 5

    /// Name prefixes never treated as app files.
    static let ignoredPrefixes = ["mobiledocuments", "reminders", "dsstore", "comapplepasswordmanager"]

    /// File extensions dropped before an exact comparison.
    static let ignoredExtensions: Set<String> = ["plist", "savedstate", "binarycookies", "log", "sfl2", "sfl3", "lockfile"]

    let sensitivity: SearchSensitivity
    let tokens: [Token]
    let override: AppOverride?
    private let teamPrefix: String?

    init(app: InstalledApp, sensitivity: SearchSensitivity) {
        self.sensitivity = sensitivity
        override = AppOverride.matching(app.bundleIdentifier)
        teamPrefix = app.teamIdentifier.map { $0.lowercased() }

        var candidates: [(MatchTier, String)] = [
            (.bundleIdentifier, app.bundleIdentifier),
            (.displayName, app.name),
            (.fileStem, app.fileStem),
            (.lettersOnlyName, app.name.filter(\.isLetter)),
        ]
        if sensitivity != .strict {
            let parts = app.bundleIdentifier.split(separator: ".").map(String.init)
            candidates.append((.bundleLastTwoComponents, parts.suffix(2).joined()))
            if parts.count >= 4, let last = parts.last?.lowercased(), Self.helperSuffixes.contains(last) {
                candidates.append((.baseBundleIdentifier, parts.dropLast().joined(separator: ".")))
            }
            let stripped = app.name.replacingOccurrences(of: #"\s+\d+(\.\d+)*\s*$"#, with: "", options: .regularExpression)
            if stripped != app.name { candidates.append((.versionStrippedName, stripped)) }
        }
        if sensitivity == .deep {
            let parts = app.bundleIdentifier.split(separator: ".").map(String.init)
            if parts.count == 3 { candidates.append((.developerName, parts[1])) }
        }

        var seen = Set<String>()
        tokens = candidates.compactMap { tier, raw in
            let value = raw.normalizedForMatching
            guard value.count >= Self.minimumTokenLength, seen.insert(value).inserted else { return nil }
            return Token(tier: tier, value: value)
        }
    }

    static let helperSuffixes: Set<String> = [
        "helper", "agent", "daemon", "service", "xpc", "launcher", "updater", "installer",
        "uninstaller", "login", "extension", "plugin",
    ]

    /// The strongest rule `name` matches, or nil.
    func match(_ name: String) -> MatchTier? {
        let normalized = name.normalizedForMatching
        guard !normalized.isEmpty, !Self.ignoredPrefixes.contains(where: normalized.hasPrefix) else { return nil }

        if let override {
            if override.excludeTerms.contains(where: normalized.contains) { return nil }
            if override.includeTerms.contains(where: normalized.contains) { return .override }
        }

        let lowered = name.lowercased()
        if let teamPrefix, sensitivity != .strict, lowered.hasPrefix(teamPrefix + ".") {
            return .teamIdentifier
        }

        let variants = Self.variants(of: name, teamPrefix: teamPrefix)
        for token in tokens {
            let matched = sensitivity == .strict
                ? variants.contains(token.value)
                : normalized.contains(token.value)
            if matched { return token.tier }
        }
        return nil
    }

    /// The forms of a name compared exactly in strict mode: as is, without a
    /// known extension, and without a "group." or team identifier prefix.
    private static func variants(of name: String, teamPrefix: String?) -> Set<String> {
        var forms = [name]
        let ext = (name as NSString).pathExtension.lowercased()
        if ignoredExtensions.contains(ext) { forms.append((name as NSString).deletingPathExtension) }
        for form in forms {
            let lowered = form.lowercased()
            if lowered.hasPrefix("group.") { forms.append(String(form.dropFirst(6))) }
            if let teamPrefix, lowered.hasPrefix(teamPrefix + ".") { forms.append(String(form.dropFirst(teamPrefix.count + 1))) }
        }
        return Set(forms.map(\.normalizedForMatching))
    }
}

/// Matching overrides for apps whose files do not follow their names. Data
/// adapted from MClean (MIT), see THIRD_PARTY_NOTICES.
struct AppOverride: Sendable {
    /// A bundle identifier family: the identifier itself, a child of it, a
    /// parent ending with it, or, for a single word such as "jetbrains", any
    /// identifier with that component.
    let family: String
    let includeTerms: [String]
    let excludeTerms: [String]
    /// Home-relative folders that always belong to the app.
    let extraFolders: [String]

    init(_ family: String, include: [String] = [], exclude: [String] = [], extraFolders: [String] = []) {
        self.family = family.lowercased()
        includeTerms = include.map(\.normalizedForMatching)
        excludeTerms = exclude.map(\.normalizedForMatching)
        self.extraFolders = extraFolders
    }

    static func matching(_ bundleIdentifier: String) -> AppOverride? {
        let identifier = bundleIdentifier.lowercased()
        let components = identifier.split(separator: ".").map(String.init)
        return all.first { override in
            identifier == override.family
                || identifier.hasPrefix(override.family + ".")
                || identifier.hasSuffix("." + override.family)
                || (!override.family.contains(".") && components.contains(override.family))
        }
    }

    static let all: [AppOverride] = [
        AppOverride("com.robotsandpencils.xcodesapp", exclude: ["com.apple.dt.xcode", "xcodecleaner"]),
        AppOverride("com.xcodesorg.xcodesapp", exclude: ["com.apple.dt.xcode", "xcodecleaner"]),
        AppOverride("us.zoom.xos", include: ["zoom"]),
        AppOverride("com.microsoft.teams2", exclude: ["office"]),
        AppOverride("com.brave.browser", include: ["brave"]),
        AppOverride("com.google.chrome", include: ["chrome"], exclude: ["iterm", "chromefeaturestate", "monochrome"]),
        AppOverride("com.microsoft.edgemac", exclude: ["vscode", "rdc", "appcenter", "office", "oneauth"]),
        AppOverride("org.mozilla.firefox.nightly", include: ["firefox"], exclude: ["thunderbird"]),
        AppOverride("org.mozilla.firefox", include: ["firefox"], exclude: ["thunderbird"]),
        AppOverride("org.mozilla.thunderbird", exclude: ["firefox"]),
        AppOverride("company.thebrowser.browser", include: ["firestore"],
                    extraFolders: ["Library/Application Support/Arc", "Library/Caches/Arc"]),
        AppOverride("com.microsoft.vscodeinsiders", include: ["vscodeinsiders"],
                    extraFolders: ["Library/Application Support/Code - Insiders"]),
        AppOverride("com.microsoft.vscode", include: ["vscode"], exclude: ["vscodeinsiders", "insiders"],
                    extraFolders: ["Library/Application Support/Code"]),
        AppOverride("com.github.githubclient", include: ["comgithubelectron"]),
        AppOverride("jetbrains", include: ["jcef"]),
        AppOverride("com.native-instruments.nativeaccess", include: ["comnative", "nativeinstruments"]),
        AppOverride("com.logi.optionsplus", include: ["logipluginservice", "logioptions"], exclude: ["login", "logic"]),
        AppOverride("com.1password.1password", include: ["sidekick"]),
        AppOverride("eu.exelban.stats", exclude: ["video"]),
        AppOverride("me.mhaeuser.batterytoolkit", include: ["memhaeuser"]),
        AppOverride("com.okta.mobile", include: ["okta"]),
        AppOverride("com.now.gg.bluestacks", include: ["bst_boost_interprocess"]),
        AppOverride("com.electron.sdm", include: ["strongdm"]),
        AppOverride("com.facebook.archon.developerid", include: ["archon.loginhelper"]),
    ]
}
