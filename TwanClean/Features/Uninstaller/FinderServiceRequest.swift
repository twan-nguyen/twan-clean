import Foundation

/// Why an app handed over from Finder's Services menu cannot be uninstalled.
enum FinderServiceRejection: Error, Equatable {
    case noApplication
    case symbolicLink(name: String)
    case protectedApp(name: String)
    case outsideApplications(name: String)
    case busy

    var message: String {
        switch self {
        case .noApplication:
            String(localized: "Choose an application to uninstall.")
        case .symbolicLink(let name):
            String(localized: "\(name) is a link to another app. Uninstall the original app instead.")
        case .protectedApp(let name):
            String(localized: "\(name) is part of macOS or protected, so Twan Clean cannot uninstall it.")
        case .outsideApplications:
            String(localized: "Twan Clean can only uninstall apps in the Applications folder.")
        case .busy:
            String(localized: "Twan Clean is busy uninstalling another app. Try again in a moment.")
        }
    }
}

enum FinderServiceRequest {
    /// The first app in `urls` that can be uninstalled, or the reason the
    /// first one cannot.
    static func app(from urls: [URL], policy: PathPolicy = PathPolicy()) -> Result<InstalledApp, FinderServiceRejection> {
        let candidates = urls.filter { $0.pathExtension.lowercased() == "app" }
        var firstRejection: FinderServiceRejection?
        for url in candidates {
            switch validate(url, policy: policy) {
            case .success(let app): return .success(app)
            case .failure(let rejection): firstRejection = firstRejection ?? rejection
            }
        }
        return .failure(firstRejection ?? .noApplication)
    }

    static func validate(_ url: URL, policy: PathPolicy = PathPolicy()) -> Result<InstalledApp, FinderServiceRejection> {
        let name = url.deletingPathExtension().lastPathComponent
        // The link, not its target, is what removal would move to the Trash.
        guard !InstalledAppIndex.isSymbolicLink(url) else { return .failure(.symbolicLink(name: name)) }
        if let app = InstalledAppIndex.read(url, readingTeam: false), InstalledAppIndex.isProtected(app) {
            return .failure(.protectedApp(name: app.name))
        }
        // Only installed apps: not one on a disk image, nor a helper inside
        // another app.
        guard case .allowed = policy.evaluate(url, purpose: .appBundle) else {
            return .failure(.outsideApplications(name: name))
        }
        guard let app = InstalledAppIndex.app(at: url) else { return .failure(.noApplication) }
        return .success(app)
    }
}
