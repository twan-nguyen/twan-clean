import Foundation

@main
enum AppEntry {
    static func main() {
        switch LaunchMode(arguments: CommandLine.arguments) {
        case .gui:
            TwanCleanApp.main()
        case .scheduledRun:
            // No window and no Dock icon: run the scheduled scan and exit. A run
            // that hangs is stopped, releasing its lock for the next one; the
            // runner marks its attempt first, so the next check is not a restart.
            DispatchQueue.main.asyncAfter(deadline: .now() + ScheduledRunner.timeLimit) {
                exit(EX_TEMPFAIL)
            }
            Task {
                let outcome = await ScheduledRunner().run()
                exit(outcome.exitStatus)
            }
            dispatchMain()
        }
    }
}
