import ServiceManagement

/// Registers the LaunchAgent bundled in Contents/Library/LaunchAgents. macOS
/// starts it every hour, even when Twan Clean is closed; the run itself
/// decides whether anything is due.
enum SchedulerAgent {
    static let plistName = "com.twan.twanclean.scheduler.plist"

    static var service: SMAppService { .agent(plistName: plistName) }

    static var status: SMAppService.Status { service.status }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status != .notRegistered && service.status != .notFound {
            try service.unregister()
        }
    }
}

/// Opening Twan Clean at login.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
