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

    static func contains(_ name: String) -> Bool {
        let normalized = name.normalizedForMatching
        return prefixes.contains(where: normalized.hasPrefix)
    }
}
