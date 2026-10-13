import Foundation
import ServiceManagement

/// The part of `SMAppService` the scheduler uses, so registration logic can
/// be tested without touching the real login items.
protocol SchedulerService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: SchedulerService {}

/// Registers the LaunchAgent bundled in Contents/Library/LaunchAgents. macOS
/// starts it every hour, even when Twan Clean is closed; the run itself
/// decides whether anything is due.
enum SchedulerAgent {
    static let label = "com.twan.twanclean.scheduler"
    static let plistName = "\(label).plist"

    static var service: SchedulerService { SMAppService.agent(plistName: plistName) }

    static var status: SMAppService.Status { service.status }

    /// Turns the background task on or off. When macOS asks the user to
    /// approve the task in Login Items, registering reports an error but the
    /// task is waiting, not failed: that is not thrown, and `status` is
    /// `.requiresApproval` for the interface to explain.
    static func setEnabled(_ enabled: Bool, service: SchedulerService = SchedulerAgent.service) throws {
        if enabled {
            guard service.status != .enabled else { return }
            do {
                try service.register()
            } catch {
                guard service.status == .requiresApproval else { throw error }
                SchedulerLog.logger.notice("Background task is waiting for approval in Login Items")
            }
        } else if service.status != .notRegistered && service.status != .notFound {
            try service.unregister()
        }
    }

    enum Reconciliation: Equatable {
        /// Nothing to repair.
        case consistent
        /// The task was missing or not loaded, and registered again.
        case registeredAgain
        /// The task waits for the user's approval in Login Items.
        case awaitingApproval
        /// The task could not be registered.
        case failed
        /// The saved schedule was unreadable. It was set aside and the task
        /// removed, so the app shows what is actually scheduled: nothing.
        case scheduleDiscarded
    }

    /// Makes the registered task match the saved schedule when the app
    /// starts. Updating the app can remove the task (Homebrew runs
    /// `launchctl remove` before an upgrade) while macOS still lists it, and
    /// the schedule would then silently never run.
    @discardableResult
    static func reconcile(store: ScheduleStore = ScheduleStore(),
                          service: SchedulerService = SchedulerAgent.service,
                          isJobLoaded: () -> Bool = SchedulerAgent.jobIsLoaded) -> Reconciliation {
        let settings: ScheduleSettings
        do {
            settings = try store.loadSettingsChecked()
        } catch {
            SchedulerLog.logger.error("Schedule file is unreadable, setting it aside: \(error.localizedDescription, privacy: .public)")
            store.quarantineSettings()
            if service.status == .enabled || service.status == .requiresApproval {
                try? service.unregister()
            }
            return .scheduleDiscarded
        }
        guard settings.isEnabled else { return .consistent }

        switch service.status {
        case .notRegistered:
            return register(service)
        case .enabled:
            guard !isJobLoaded() else { return .consistent }
            try? service.unregister()
            return register(service)
        case .requiresApproval:
            return .awaitingApproval
        case .notFound:
            SchedulerLog.logger.error("The scheduler's launch agent is missing from the app")
            return .failed
        @unknown default:
            return .consistent
        }
    }

    private static func register(_ service: SchedulerService) -> Reconciliation {
        do {
            try service.register()
            return .registeredAgain
        } catch {
            if service.status == .requiresApproval { return .awaitingApproval }
            SchedulerLog.logger.error("Could not register the background task: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Runs the reconciliation off the main thread, except in unit tests,
    /// which must never register the real task.
    static func reconcileInBackground() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task.detached(priority: .utility) { reconcile() }
    }

    /// Whether launchd has the task loaded. Defaults to true when launchctl
    /// cannot be asked, so a failure to check never causes a re-registration.
    static func jobIsLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return true
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
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
