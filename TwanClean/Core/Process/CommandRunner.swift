import Foundation

/// Runs developer tools such as `brew`, `npm` or `docker` to ask where their
/// caches live. Tools are found on a fixed search path and stopped after a
/// timeout. A tool that anyone but its owner (or root) could have rewritten is
/// never run, since it would inherit this app's file access.
struct CommandRunner: Sendable {
    let searchPaths: [String]
    let timeout: TimeInterval

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, timeout: TimeInterval = 10) {
        var paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        // Node installed through nvm lives in a versioned folder; newest first.
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            paths += versions
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { nvm.appendingPathComponent($0).appendingPathComponent("bin").path }
        }
        self.init(searchPaths: paths, timeout: timeout)
    }

    init(searchPaths: [String], timeout: TimeInterval) {
        self.searchPaths = searchPaths
        self.timeout = timeout
    }

    func locate(_ tool: String) -> URL? {
        searchPaths
            .map { URL(fileURLWithPath: $0).appendingPathComponent(tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) && Self.isTrusted($0.path) }
    }

    /// Whether a program, and the file a symlink to it finally resolves to, is
    /// owned by `user` or root and not writable by its group or by others.
    static func isTrusted(_ path: String, user: uid_t = getuid()) -> Bool {
        guard let resolved = SafetyRules.canonicalPath(path) else { return false }
        return [path, resolved].allSatisfy { candidate in
            var status = stat()
            guard lstat(candidate, &status) == 0 else { return false }
            let owner = status.st_uid
            return (owner == user || owner == 0) && status.st_mode & (S_IWGRP | S_IWOTH) == 0
        }
    }

    /// Standard output, trimmed, or nil when the tool is missing, fails or
    /// times out.
    func output(of tool: String, _ arguments: [String]) async -> String? {
        guard let executable = locate(tool) else { return nil }
        return await output(of: executable, arguments)
    }

    func output(of executable: URL, _ arguments: [String]) async -> String? {
        guard Self.isTrusted(executable.path),
              let result = await ProcessRunner.run(executable, arguments, environment: environment(), timeout: timeout),
              result.succeeded else { return nil }
        let text = result.outputText
        return text.isEmpty ? nil : text
    }

    /// The inherited environment with a predictable PATH. Homebrew variables
    /// are dropped so a stray HOMEBREW_CACHE cannot point the cache scan at an
    /// unrelated folder.
    private func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HOMEBREW_") }
        environment["PATH"] = searchPaths.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }
}
