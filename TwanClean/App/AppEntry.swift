import Foundation

@main
enum AppEntry {
    static func main() {
        switch LaunchMode(arguments: CommandLine.arguments) {
        case .gui:
            TwanCleanApp.main()
        case .scheduledRun:
            // No window and no Dock icon: run the scheduled scan and exit. A run
            // that hangs is stopped, releasing its lock for the next one.
            DispatchQueue.main.asyncAfter(deadline: .now() + ScheduledRunner.timeLimit) {
                exit(EX_TEMPFAIL)
            }
            Task {
                await ScheduledRunner().run()
                exit(EXIT_SUCCESS)
            }
            dispatchMain()
        }
    }
}
