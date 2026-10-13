import Foundation

/// Names that look orphaned but belong to macOS, shared frameworks or command
/// line tools. Compared as normalized prefixes. Adapted from MClean (MIT),
/// see THIRD_PARTY_NOTICES.
enum OrphanSkipList {
    static let prefixes: [String] = [
        // Apple and system
        "apple", "temporary", "btserver", "proapps", "scripteditor", "ilife", "livefsd", "siritoday",
        "addressbook", "animoji", "appstore", "askpermission", "callhistory", "clouddocs", "diskimages",
        "dock", "facetime", "fileprovider", "instruments", "knowledge", "mobilesync", "syncservices",
        "homeenergyd", "icloud", "icdd", "networkserviceproxy", "familycircle", "geoservices", "installation",
        "passkit", "sharedimagecache", "desktop", "mbuseragent", "swiftpm", "baseband", "coresimulator",
        "photoslegacyupgrade", "photosupgrade", "siritts", "ipod", "globalpreferences",
        // Analytics and telemetry
        "apmanalytics", "apmexperiment", "avatarcache", "byhost", "contextstoreagent", "mobilemeaccounts",
        "mobiledocuments", "mobile", "intentbuilderc", "loginwindow", "momc", "replayd", "sharedfilelistd",
        // Build tools
        "clang", "audiocomponent", "csexattrcryptoservice", "livetranscriptionagent", "sandboxhelper",
        "statuskitagent",
        // System daemons
        "betaenrollmentd", "contentlinkingd", "diagnosticextensionsd", "gamed", "heard", "homed",
        "itunescloudd", "lldb", "mds", "mediaanalysisd", "metrickitd", "mobiletimerd", "proactived",
        "ptpcamerad", "studentd", "talagent", "watchlistd", "apptranslocation", "xcrun",
        // Generic infrastructure
        "dsstore", "caches", "crashreporter", "trash",
        // macOS's own logs in /Library/Logs
        "windowserver", "xsan", "diagnosticreports", "diagnosticmessages", "hidfwcrashlogs", "mcxtools",
        "lkdcsetup", "softwareupdate", "managedclient", "dockaccessibility",
        // Shared SDKs and command line tools
        "amsdatamigratortool", "arfilecache", "assistant", "chromium", "cloudkit", "webkit", "databases",
        "diagnostic", "cache", "gamekit", "homebrew", "microsoft", "mozilla", "sync", "google", "sentinel",
        "hexnode", "sentry", "tvappservices", "reminders", "pbs", "notarytool", "differentialprivacy",
        "storeassetd", "webpush", "storedownloadd", "fsck", "crash", "python", "discrecording",
        "photossearch", "pylint", "jamf", "scopedbookmarkagent", "anonymous", "identifier", "isolated",
        "nobackup", "privacypreservingmeasurement", "symbols", "stickersd", "privatecloudcomputed", "tipsd",
        "controlcenter", "contactsd", "staticcheck", "index", "segment", "sparkle", "summaryevents",
        "launchdarkly", "identityservicesd", "embeddedbinaryvalidationutility", "aaprofilepicture",
        "minilauncher", "jna", "automator", "locationaccessstored", "spotlight", "cef",
        "pip", "pnpm", "yarn", "nodegyp", "typescript", "msplaywright", "uv", "go", "rust", "cargo",
        "jetbrains", "vscode", "electron", "twanclean", "comtwan",
    ]

    /// Entries shorter than this are only compared with a name as written: "go"
    /// would otherwise hide every reverse-DNS name whose app part starts
    /// with it.
    private static let shortestDerivedPrefix = 4

    static func contains(_ name: String) -> Bool {
        if prefixes.contains(where: name.normalizedForMatching.hasPrefix) { return true }
        // "org.swift.swiftpm" is the "swiftpm" of the list, and
        // "com.google.Keystone" is "google"'s.
        return reverseDNSRemainders(of: name).contains { rest in
            prefixes.contains { $0.count >= shortestDerivedPrefix && rest.hasPrefix($0) }
        }
    }

    /// For a reverse-DNS name, the name without its top-level domain and
    /// without its company part, normalized.
    private static func reverseDNSRemainders(of name: String) -> [String] {
        let parts = name.split(separator: ".").map(String.init)
        guard parts.count >= 3, parts[0].count <= 3, parts[0].allSatisfy(\.isLetter) else { return [] }
        return [parts.dropFirst().joined(), parts.dropFirst(2).joined()].map(\.normalizedForMatching)
    }
}
