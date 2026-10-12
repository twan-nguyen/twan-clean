import AppKit
import CryptoKit

/// Removes items that `RemovalService` could not touch for lack of permission,
/// after the user approves the macOS administrator prompt.
///
/// Paths never enter a shell command. Each item is written with its scanned
/// identity to a private staging file, and the privileged command:
/// 1. copies that file somewhere only root can write and checks its SHA-256
///    against the digest computed here, so nothing can rewrite the list while
///    the password prompt is open;
/// 2. removes each path only if it is still the same file system object
///    (`stat -f %d:%i`, which does not follow a final symlink and changes when
///    a parent folder is swapped for a link);
/// 3. uses `rm -x`, which never crosses into another mounted volume.
///
/// Items whose purpose is the Trash are recycled through `NSWorkspace`, which
/// asks for authorization itself; they are never deleted instead.
struct PrivilegedRemover: Sendable {
    enum StagingError: Error {
        case unsafeStagingPath(String)
        case pathContainsNUL
    }

    /// Runs an AppleScript and reports how it ended.
    typealias ScriptRunner = @Sendable (String) async -> ProcessResult?

    let service: RemovalService
    /// Shown in the administrator prompt.
    let prompt: String
    let runScript: ScriptRunner

    init(service: RemovalService = RemovalService(), prompt: String,
         runScript: @escaping ScriptRunner = Self.runWithOsascript) {
        self.service = service
        self.prompt = prompt
        self.runScript = runScript
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
        if !recycling.isEmpty {
            await recycleAsAdministrator(recycling, into: &report)
        }
        return report
    }

    // MARK: - Delete

    private func deleteAsAdministrator(_ items: [(request: RemovalRequest, url: URL)],
                                       into report: inout RemovalReport) async {
        var failure: Error?
        var stagingFolder: URL?
        do {
            let staged = try Self.stage(items.map { ($0.request.identity, $0.url.path) })
            stagingFolder = staged.file.deletingLastPathComponent()
            let command = try Self.shellCommand(stagingFile: staged.file, digest: staged.digest)
            let script = Self.appleScript(shellCommand: command, prompt: prompt)
            if let result = await runScript(script) {
                if !result.succeeded { failure = AdministratorError(output: result.errorText) }
            } else {
                failure = AdministratorError(output: "")
            }
        } catch {
            failure = error
        }
        if let stagingFolder {
            try? FileManager.default.removeItem(at: stagingFolder)
        }

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

    /// Writes "device:inode" and path pairs, NUL-separated, to a new file only
    /// the current user can read, inside a fresh private folder.
    static func stage(_ entries: [(identity: FileIdentity, path: String)]) throws -> (file: URL, digest: String) {
        guard !entries.contains(where: { $0.path.utf8.contains(0) }) else { throw StagingError.pathContainsNUL }
        var payload = Data()
        for entry in entries {
            payload.append(contentsOf: Array(identityToken(entry.identity).utf8))
            payload.append(0)
            payload.append(contentsOf: Array(entry.path.utf8))
            payload.append(0)
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

    /// The root shell command. Only the staging path and digest, both
    /// generated by this app and limited to plain characters, are inserted.
    static func shellCommand(stagingFile: URL, digest: String) throws -> String {
        let path = stagingFile.path
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-")
        guard !path.isEmpty, path.unicodeScalars.allSatisfy(safe.contains) else {
            throw StagingError.unsafeStagingPath(path)
        }
        guard digest.count == 64, digest.unicodeScalars.allSatisfy(safe.contains) else {
            throw StagingError.unsafeStagingPath(digest)
        }
        let removeIfUnchanged = #"[ "$(/usr/bin/stat -f %d:%i "$2")" = "$1" ] && /bin/rm -rfx -- "$2"; exit 0"#
        return [
            "list=$(/usr/bin/mktemp) || exit 1",
            "/bin/cat '\(path)' > \"$list\" || { /bin/rm -f \"$list\"; exit 1; }",
            "if [ \"$(/usr/bin/shasum -a 256 < \"$list\" | /usr/bin/cut -d ' ' -f 1)\" != '\(digest)' ];"
                + " then /bin/rm -f \"$list\"; echo 'The list of items changed.' >&2; exit 3; fi",
            "/usr/bin/xargs -0 -n 2 /bin/sh -c '\(removeIfUnchanged)' sh < \"$list\"",
            "status=$?",
            "/bin/rm -f \"$list\"",
            "exit $status",
        ].joined(separator: "; ")
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

    /// Runs through `osascript` with no timeout, since the user may take a
    /// while to type the password.
    static let runWithOsascript: ScriptRunner = { script in
        await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
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

    private func recycleAsAdministrator(_ items: [(request: RemovalRequest, url: URL)],
                                        into report: inout RemovalReport) async {
        var failure: Error?
        do {
            let moved = try await NSWorkspace.shared.recycle(items.map(\.url))
            report.trashedLocations += moved.values
        } catch {
            failure = error
        }
        for item in items {
            if Self.isGone(item) {
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
