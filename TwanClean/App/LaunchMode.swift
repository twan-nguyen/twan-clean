import Foundation

/// How the process was started: the normal windowed app, or the headless
/// scheduled run that the LaunchAgent triggers while the app may be closed.
enum LaunchMode: Equatable {
    case gui
    case scheduledRun

    static let scheduledRunFlag = "--scheduled-run"

    init(arguments: [String]) {
        // The first argument is the executable path; Xcode and launchd may add
        // unrelated flags, so only the exact scheduled-run flag switches modes.
        self = arguments.dropFirst().contains(Self.scheduledRunFlag) ? .scheduledRun : .gui
    }
}
