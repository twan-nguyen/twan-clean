import AppKit

/// What a process was when it was found: the program it runs and when it
/// started. A process id that is later reused by another program no longer
/// matches, so it is never signalled by mistake.
struct ProcessIdentity: Equatable, Sendable {
    let path: String
    let startSeconds: Int64
    let startMicroseconds: Int64

    static func of(_ pid: pid_t) -> ProcessIdentity? {
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProcessIdentity(path: String(nulTerminated: path), startSeconds: Int64(info.pbi_start_tvsec),
                               startMicroseconds: Int64(info.pbi_start_tvusec))
    }
}

/// A process that is part of an app being uninstalled.
struct RunningProcess {
    let pid: pid_t
    let name: String
    /// Set for processes that are apps, which are asked to quit politely.
    let application: NSRunningApplication?
    /// Set for the others, which are only signalled while they are still the
    /// process that was found.
    let identity: ProcessIdentity?

    init(pid: pid_t, name: String, application: NSRunningApplication? = nil, identity: ProcessIdentity? = nil) {
        self.pid = pid
        self.name = name
        self.application = application
        self.identity = identity
    }
}

/// Finds and stops the processes of an app. A seam so the uninstall flow can
/// be tested without touching real processes.
@MainActor
protocol AppProcessControl {
    /// Processes of `app`: the app itself, and helpers started from inside its
    /// bundle. With `matchingIdentifier`, also any process with the app's
    /// bundle identifier, wherever it runs from.
    func running(for app: InstalledApp, matchingIdentifier: Bool) -> [RunningProcess]
    func terminate(_ process: RunningProcess, force: Bool)
    func hasExited(_ process: RunningProcess) -> Bool
}

@MainActor
struct SystemAppProcessControl: AppProcessControl {
    /// Sends a signal; replaced in tests so nothing real is ever signalled.
    var send: @MainActor (pid_t, Int32) -> Void = { kill($0, $1) }

    func running(for app: InstalledApp, matchingIdentifier: Bool) -> [RunningProcess] {
        let ownPID = getpid()
        var found: [pid_t: RunningProcess] = [:]
        for process in NSWorkspace.shared.runningApplications where process.processIdentifier != ownPID {
            let path = (process.bundleURL ?? process.executableURL)?.path
            if UninstallerViewModel.belongs(bundleIdentifier: matchingIdentifier ? process.bundleIdentifier : nil,
                                            path: path, to: app.bundleIdentifier, at: app.url.path) {
                found[process.processIdentifier] = RunningProcess(
                    pid: process.processIdentifier, name: process.localizedName ?? app.name, application: process)
            }
        }
        // Only processes this user may stop: a root helper inside the bundle
        // would otherwise block the uninstall for good.
        for (pid, path) in ProcessList.executablePaths()
        where pid != ownPID && found[pid] == nil && ProcessList.canSignal(pid)
            && UninstallerViewModel.belongs(bundleIdentifier: nil, path: path, to: app.bundleIdentifier, at: app.url.path) {
            found[pid] = RunningProcess(pid: pid, name: (path as NSString).lastPathComponent,
                                        identity: ProcessIdentity.of(pid))
        }
        return Array(found.values)
    }

    func terminate(_ process: RunningProcess, force: Bool) {
        if let application = process.application {
            if force { application.forceTerminate() } else { application.terminate() }
            return
        }
        // The process may have exited and its id been given to another program.
        guard let identity = process.identity, ProcessIdentity.of(process.pid) == identity else { return }
        send(process.pid, force ? SIGKILL : SIGTERM)
    }

    func hasExited(_ process: RunningProcess) -> Bool {
        if let application = process.application { return application.isTerminated }
        guard let identity = process.identity else { return !ProcessList.isRunning(process.pid) }
        return ProcessIdentity.of(process.pid) != identity
    }
}
