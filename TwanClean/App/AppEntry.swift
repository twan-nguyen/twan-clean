import Foundation

@main
enum AppEntry {
    static func main() {
        switch LaunchMode(arguments: CommandLine.arguments) {
        case .gui:
            TwanCleanApp.main()
        case .scheduledRun:
            // No window and no Dock icon: run the scheduled scan and exit.
            Task {
                await ScheduledRunner().run()
                exit(EXIT_SUCCESS)
            }
            dispatchMain()
        }
    }
}
