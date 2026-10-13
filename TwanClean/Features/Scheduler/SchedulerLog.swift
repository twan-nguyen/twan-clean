import os

/// Where the scheduler explains what it could not do. The scheduled run has
/// no window, so this is the only place a failure is visible.
enum SchedulerLog {
    static let logger = Logger(subsystem: "com.twan.twanclean", category: "scheduler")
}
