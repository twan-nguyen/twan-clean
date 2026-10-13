import Darwin

/// The processes running on this Mac and the executables they run.
enum ProcessList {
    static func executablePaths() -> [(pid: pid_t, path: String)] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(Int(count)).compactMap { pid in
            guard pid > 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
            return (pid, String(nulTerminated: path))
        }
    }

    /// Whether this process may signal `pid`, which rules out other users'
    /// and the system's processes.
    static func canSignal(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    static func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
