import AppKit
import CryptoKit

/// Removes items that `RemovalService` could not touch for lack of permission,
/// after the user approves the macOS administrator prompt.
///
/// Paths never enter a shell command. Each item is written with its scanned
/// identity, and its parent folder's identity, to a private staging file, and
/// the privileged command, which runs with an empty environment:
/// 1. copies that file somewhere only root can write and checks its SHA-256
///    against the digest computed here, so nothing can rewrite the list while
///    the password prompt is open;
/// 2. enters each item's parent folder with `cd -P` and goes on only if that
///    folder is still the one staged. From then on the working directory pins
///    the folder, so swapping an ancestor for a symlink cannot redirect what
///    follows;
/// 3. removes `./name` only if it is still the same file system object
///    (`stat -f %d:%i`, which does not follow a final symlink);
/// 4. uses `rm -x`, which never crosses into another mounted volume.
///
/// Items whose purpose is the Trash are recycled through `NSWorkspace`, which
/// asks for authorization itself; they are never deleted instead. A system
/// daemon among them keeps running after its plist is gone, so the daemons are
/// first stopped by the same kind of privileged command.
struct PrivilegedRemover: Sendable {
    enum StagingError: Error {
        case unsafeStagingPath(String)
        case pathContainsNUL
        /// The item's folder cannot be examined, so it cannot be pinned.
        case parentUnexaminable(String)
    }

    /// What the privileged command does to each item that is unchanged.
    enum RootAction: Sendable, Equatable {
        case remove
        /// Stops the system daemon that a plist directly inside `daemonFolder`
        /// defines. The plist itself is left alone. The folder and tool are
        /// parameters only so tests can point them elsewhere.
        case stopSystemDaemon(daemonFolder: String = RootAction.systemDaemonFolder, launchctl: String = "/bin/launchctl")

        static let systemDaemonFolder = "/Library/LaunchDaemons"
    }

    /// Runs an AppleScript and reports how it ended.
    typealias ScriptRunner = @Sendable (String) async -> ProcessResult?
    /// Moves items to the Trash, asking for authorization where needed, and
    /// returns where each one went.
    typealias Recycler = @Sendable ([URL]) async throws -> [URL: URL]

    let service: RemovalService
    /// Shown in the administrator prompt.
    let prompt: String
    let runScript: ScriptRunner
    let recycle: Recycler
    /// Where launchd system daemons are defined; a parameter so tests can use
    /// a folder of their own.
    let daemonFolder: String

    init(service: RemovalService = RemovalService(), prompt: String,
         runScript: @escaping ScriptRunner = Self.runWithOsascript,
         recycle: @escaping Recycler = Self.recycleWithWorkspace,
         daemonFolder: String = RootAction.systemDaemonFolder) {
        self.service = service
        self.prompt = prompt
        self.runScript = runScript
        self.recycle = recycle
        self.daemonFolder = daemonFolder
    }

    func remove(_ requests: [RemovalRequest]) async -> RemovalReport {
        var report = RemovalReport()
        var deletions: [(request: RemovalRequest, url: URL)] = []
        var recycling: [(request: RemovalRequest, url: URL)] = []
        for request in requests {
            guard let url = service.validate(request, into: &report) else { continue }
            switch request.purpose.mode {
            case .delete: deletions.append((request, url))
            case .trash: recycling.append((request, url))
            }
        }
        if !deletions.isEmpty {
            await deleteAsAdministrator(deletions, into: &report)
        }
        let daemons = recycling.filter { Self.isSystemDaemon($0.url, in: daemonFolder) }
        if !daemons.isEmpty {
            // Best effort: if the user cancels, the plists still go to the
            // Trash and the daemons stop at the next restart.
            _ = await runAsAdministrator(daemons.map { ($0.request.identity, $0.url.path) },
                                         action: .stopSystemDaemon(daemonFolder: daemonFolder),
                                         prompt: String(localized: "Twan Clean needs your password to stop the app's background services."))
        }
        if !recycling.isEmpty {
            await recycleAsAdministrator(recycling, into: &report)
        }
        return report
    }

    /// A launchd plist directly inside the system daemon folder.
    static func isSystemDaemon(_ url: URL, in folder: String = RootAction.systemDaemonFolder) -> Bool {
        url.pathExtension == "plist"
            && PathPolicy.isSame(url.deletingLastPathComponent().path, folder)
    }

    // MARK: - Delete

    private func deleteAsAdministrator(_ items: [(request: RemovalRequest, url: URL)],
                                       into report: inout RemovalReport) async {
        let failure = await runAsAdministrator(items.map { ($0.request.identity, $0.url.path) },
                                               action: .remove, prompt: prompt)

        // Trust only what actually changed on disk. An app may already have
        // recreated a cache folder, which counts as removed.
        for item in items {
            if Self.isGone(item) {
                report.removed.append(item.request)
            } else {
                let message = failure?.localizedDescription
                    ?? String(localized: "The item is still present after administrator removal.")
                report.failed.append(.init(request: item.request, message: message))
            }
        }
    }

    /// Stages the items and runs the privileged command on them. Returns why
    /// it failed, or nil when it ran to the end.
    private func runAsAdministrator(_ entries: [(identity: FileIdentity, path: String)],
                                    action: RootAction, prompt: String) async -> Error? {
        var stagingFolder: URL?
        defer {
            if let stagingFolder { try? FileManager.default.removeItem(at: stagingFolder) }
        }
        do {
            let staged = try Self.stage(entries)
            stagingFolder = staged.file.deletingLastPathComponent()
            let command = try Self.shellCommand(stagingFile: staged.file, digest: staged.digest, action: action)
            guard let result = await runScript(Self.appleScript(shellCommand: command, prompt: prompt)) else {
                return AdministratorError(output: "")
            }
            if result.timedOut { return AdministratorError(output: "timed out waiting for the command") }
            return result.succeeded ? nil : AdministratorError(output: result.errorText)
        } catch {
            return error
        }
    }

    /// Writes four NUL-separated fields per item to a new file only the current
    /// user can read, inside a fresh private folder: the item's "device:inode",
    /// its parent folder's "device:inode", the parent folder's path and the
    /// item's name. The parent's identity is read now, from the canonical path
    /// the policy approved.
    static func stage(_ entries: [(identity: FileIdentity, path: String)]) throws -> (file: URL, digest: String) {
        guard !entries.contains(where: { $0.path.utf8.contains(0) }) else { throw StagingError.pathContainsNUL }
        var payload = Data()
        for entry in entries {
            let parent = (entry.path as NSString).deletingLastPathComponent
            let name = (entry.path as NSString).lastPathComponent
            guard !name.isEmpty, let parentIdentity = FileIdentity.of(path: parent) else {
                throw StagingError.parentUnexaminable(entry.path)
            }
            for field in [identityToken(entry.identity), identityToken(parentIdentity), parent, name] {
                payload.append(contentsOf: Array(field.utf8))
                payload.append(0)
            }
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwanClean-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("paths")
        guard FileManager.default.createFile(atPath: file.path, contents: payload,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return (file, digest)
    }

    /// The identity as BSD `stat -f %d:%i` prints it.
    static func identityToken(_ identity: FileIdentity) -> String {
        "\(identity.device):\(identity.inode)"
    }

    /// Characters allowed in anything this app inserts into the root command.
    private static let plainCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-")

    /// The command run for each item, as
    /// `sh -c '<script>' sh <item id> <parent id> <parent path> <name>`.
    /// It goes inside single quotes, so it must never contain one.
    ///
    /// It enters the parent folder, then checks the folder and the item against
    /// the staged identities. Every later step uses `./name` relative to that
    /// folder, so nothing is looked up through a path again.
    static func itemScript(_ action: RootAction) throws -> String {
        let unchanged = #"cd -P -- "$3" || exit 0; "#
            + #"[ "$(/usr/bin/stat -f %d:%i .)" = "$2" ] || exit 0; "#
            + #"[ "$(/usr/bin/stat -f %d:%i "./$4")" = "$1" ] || exit 0; "#
        switch action {
        case .remove:
            return unchanged + #"/bin/rm -rfx -- "./$4"; exit 0"#
        case .stopSystemDaemon(let folder, let launchctl):
            for value in [folder, launchctl] where value.isEmpty || !value.unicodeScalars.allSatisfy(plainCharacters.contains) {
                throw StagingError.unsafeStagingPath(value)
            }
            // Only plists directly inside the daemon folder qualify. The
            // folder and the tool's own ancestors belong to root.
            return unchanged + #"[ "$3" = ""# + folder + #"" ] || exit 0; "#
                + #"case "$4" in *.plist) "# + launchctl + #" bootout system "$3/$4" 2>/dev/null;; esac; exit 0"#
        }
    }

    /// The tools and the only environment the root command gets, so nothing
    /// the user's session exports can steer an interpreter that runs as root.
    private static let cleanEnvironmentPrefix = "/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c "

    /// The root shell command. Only the staging path and digest, both
    /// generated by this app and limited to plain characters, are inserted.
    static func shellCommand(stagingFile: URL, digest: String, action: RootAction = .remove) throws -> String {
        let path = stagingFile.path
        guard !path.isEmpty, path.unicodeScalars.allSatisfy(plainCharacters.contains) else {
            throw StagingError.unsafeStagingPath(path)
        }
        guard digest.count == 64, digest.unicodeScalars.allSatisfy(plainCharacters.contains) else {
            throw StagingError.unsafeStagingPath(digest)
        }
        let perItem = try itemScript(action)
        // The digest comes from `openssl`, a compiled tool, not from a script
        // interpreter; its "<hex> *stdin" output is cut down to the hex.
        let script = [
            "list=$(/usr/bin/mktemp) || exit 1",
            // A FIFO swapped in for the list would block `cat` forever.
            "[ -f '\(path)' ] && [ ! -L '\(path)' ] || { /bin/rm -f \"$list\"; echo 'The list of items is not a plain file.' >&2; exit 3; }",
            "/bin/cat '\(path)' > \"$list\" || { /bin/rm -f \"$list\"; exit 1; }",
            "if [ \"$(/usr/bin/openssl dgst -sha256 -r < \"$list\" | /usr/bin/cut -d ' ' -f 1)\" != '\(digest)' ];"
                + " then /bin/rm -f \"$list\"; echo 'The list of items changed.' >&2; exit 3; fi",
            "/usr/bin/xargs -0 -n 4 /bin/sh -c '\(perItem)' sh < \"$list\"",
            "status=$?",
            "/bin/rm -f \"$list\"",
            "exit $status",
        ].joined(separator: "; ")
        return cleanEnvironmentPrefix + shellQuoted(script)
    }

    /// `text` as one single-quoted shell word.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func appleScript(shellCommand: String, prompt: String) -> String {
        "do shell script \(appleScriptLiteral(shellCommand)) with prompt \(appleScriptLiteral(prompt))"
            + " with administrator privileges"
    }

    /// An AppleScript string literal for `text`.
    static func appleScriptLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// How long `osascript` may run: generous, since the user may take a while
    /// to type the password, but finite so a command that never ends (say, a
    /// list file swapped for a FIFO) cannot leave the app waiting forever.
    static let osascriptTimeout: TimeInterval = 600

    static let runWithOsascript: ScriptRunner = { script in
        // The shell `do shell script` starts as root inherits this environment
        // before the command's own `env -i` runs, so it gets a clean one too.
        await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script],
                                environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], timeout: osascriptTimeout)
    }

    /// Gone, or replaced by a new object such as a cache folder an app
    /// recreated at once. An item that cannot be examined is not assumed gone.
    private static func isGone(_ item: (request: RemovalRequest, url: URL)) -> Bool {
        switch FileIdentity.lookup(item.url) {
        case .missing: true
        case .found(let identity): identity != item.request.identity
        case .unexaminable: false
        }
    }

    // MARK: - Trash

    static let recycleWithWorkspace: Recycler = { urls in
        try await NSWorkspace.shared.recycle(urls)
    }

    private func recycleAsAdministrator(_ items: [(request: RemovalRequest, url: URL)],
                                        into report: inout RemovalReport) async {
        // The password prompt for stopping daemons, or an updater, may have
        // gone by since the scan. Only the object that was scanned is moved.
        var current: [(request: RemovalRequest, url: URL)] = []
        for item in items {
            switch FileIdentity.lookup(item.url) {
            case .found(let identity) where identity == item.request.identity: current.append(item)
            case .missing: report.alreadyGone.append(item.request)
            case .found, .unexaminable: report.refused.append((item.request, .changedSinceScan))
            }
        }
        guard !current.isEmpty else { return }

        var failure: Error?
        var moved: [URL: URL] = [:]
        do {
            moved = try await recycle(current.map(\.url))
            report.trashedLocations += moved.values
        } catch {
            failure = error
        }
        for item in current {
            // A new object at the old path does not mean the scanned one left:
            // it must be the scanned object that arrived in the Trash.
            let wasRecycled = moved[item.url].map { FileIdentity.of($0) == item.request.identity } ?? false
            if wasRecycled || FileIdentity.lookup(item.url) == .missing {
                report.removed.append(item.request)
            } else {
                let message = failure?.localizedDescription
                    ?? String(localized: "The item could not be moved to the Trash.")
                report.failed.append(.init(request: item.request, message: message))
            }
        }
    }
}

/// The administrator command failed or the user cancelled the prompt.
struct AdministratorError: LocalizedError {
    let output: String

    /// AppleScript reports a cancelled authorization prompt as error -128.
    var wasCancelled: Bool { output.contains("-128") }

    var errorDescription: String? {
        if wasCancelled {
            return String(localized: "Administrator authorization was cancelled.")
        }
        let detail = output.split(separator: "\n").prefix(3).joined(separator: " ")
        return String(localized: "The administrator command failed: \(detail)")
    }
}
