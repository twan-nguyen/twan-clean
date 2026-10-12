import AppKit

/// Removes items that `RemovalService` could not touch for lack of permission,
/// after the user approves the macOS administrator prompt.
///
/// Paths never enter a shell command. They are written NUL-separated to a
/// private staging file, and the privileged command only reads that file with
/// `xargs -0`, so no file name can change what the command does. Items whose
/// purpose is the Trash are recycled through `NSWorkspace`, which asks for
/// authorization itself; they are never deleted instead.
struct PrivilegedRemover: Sendable {
    enum StagingError: Error {
        case unsafeStagingPath(String)
        case pathContainsNUL
    }

    let service: RemovalService
    /// Shown in the administrator prompt.
    let prompt: String

    init(service: RemovalService = RemovalService(), prompt: String) {
        self.service = service
        self.prompt = prompt
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

    private func deleteAsAdministrator(_ items: [(request: RemovalRequest, url: URL)], into report: inout RemovalReport) async {
        let outcome: Result<Void, Error>
        var stagingDirectory: URL?
        do {
            let stagingFile = try Self.stage(paths: items.map(\.url.path))
            stagingDirectory = stagingFile.deletingLastPathComponent()
            let script = try Self.script(stagingFile: stagingFile, prompt: prompt)
            outcome = await Self.runAppleScript(script)
        } catch {
            outcome = .failure(error)
        }
        if let stagingDirectory {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }

        // Trust only what is actually gone, whatever the command reported.
        for item in items {
            if FileIdentity.of(item.url) == nil {
                report.removed.append(item.request)
            } else {
                let message = switch outcome {
                case .success: String(localized: "The item is still present after administrator removal.")
                case .failure(let error): error.localizedDescription
                }
                report.failed.append(.init(request: item.request, message: message))
            }
        }
    }

    /// Writes the paths NUL-separated to a new file only the current user can
    /// read, inside a fresh private folder. Returns the file.
    static func stage(paths: [String]) throws -> URL {
        guard !paths.contains(where: { $0.utf8.contains(0) }) else { throw StagingError.pathContainsNUL }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwanClean-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("paths")
        var payload = Data()
        for path in paths {
            payload.append(contentsOf: Array(path.utf8))
            payload.append(0)
        }
        guard FileManager.default.createFile(atPath: file.path, contents: payload,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return file
    }

    /// The AppleScript that removes every path listed in `stagingFile` as root.
    /// Only the staging path, which this app generated, is interpolated, and it
    /// must consist of plain path characters.
    static func script(stagingFile: URL, prompt: String) throws -> String {
        let path = stagingFile.path
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-")
        guard !path.isEmpty, path.unicodeScalars.allSatisfy(safe.contains) else {
            throw StagingError.unsafeStagingPath(path)
        }
        return "do shell script \"/usr/bin/xargs -0 /bin/rm -rf -- < \" & quoted form of \(appleScriptLiteral(path))"
            + " with prompt \(appleScriptLiteral(prompt)) with administrator privileges"
    }

    /// An AppleScript string literal for `text`.
    static func appleScriptLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Runs the script through `osascript` off the main thread, so a long
    /// removal never freezes the interface.
    private static func runAppleScript(_ script: String) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { process in
                let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(()))
                } else {
                    continuation.resume(returning: .failure(AdministratorError(output: stderr)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }
    }

    // MARK: - Trash

    private func recycleAsAdministrator(_ items: [(request: RemovalRequest, url: URL)], into report: inout RemovalReport) async {
        var failure: Error?
        do {
            _ = try await NSWorkspace.shared.recycle(items.map(\.url))
        } catch {
            failure = error
        }
        for item in items {
            if FileIdentity.of(item.url) == nil {
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
        wasCancelled
            ? String(localized: "Administrator authorization was cancelled.")
            : String(localized: "The administrator command failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}
