import Foundation

@main
enum AppEntry {
    static func main() {
        switch LaunchMode(arguments: CommandLine.arguments) {
        case .gui:
            TwanCleanApp.main()
        case .scheduledRun:
            FileHandle.standardError.write(Data("Scheduled runs are not available in this build.\n".utf8))
            exit(EX_UNAVAILABLE)
        }
    }
}
