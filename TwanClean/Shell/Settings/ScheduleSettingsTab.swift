import ServiceManagement
import SwiftUI

struct ScheduleSettingsTab: View {
    private let store = ScheduleStore()
    @State private var settings = ScheduleStore().loadSettings()
    @State private var summary = ScheduleStore().loadSummary()
    @State private var agentStatus = SchedulerAgent.status
    @State private var errorMessage: String?
    @State private var notificationsAllowed = true

    var body: some View {
        Form {
            Section {
                Toggle("Run automatically", isOn: Binding(get: { settings.isEnabled }, set: { setEnabled($0) }))
                if settings.isEnabled || agentStatus == .requiresApproval {
                    statusRow
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                HStack(spacing: 6) {
                    Text("Runs even when Twan Clean is closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    InfoButton("If the Mac is asleep at that time, the run starts soon after it wakes.")
                }
            }

            Section("When") {
                Picker("Repeat", selection: $settings.frequency) {
                    ForEach(ScheduleSettings.Frequency.allCases) { Text($0.title).tag($0) }
                }
                Picker("From", selection: $settings.hour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!,
                             format: .dateTime.hour().minute())
                            .tag(hour)
                    }
                }
            }

            Section("What") {
                Picker("Action", selection: $settings.action) {
                    ForEach(ScheduleSettings.Action.allCases) { Text($0.title).tag($0) }
                }
                if settings.action == .clean {
                    Stepper(value: Binding(get: { Int(settings.minimumBytesToClean / 1_000_000) },
                                           set: { settings.minimumBytesToClean = Int64($0) * 1_000_000 }),
                            in: 0...10_000, step: 50) {
                        LabeledContent("Only when at least", value: Int64(settings.minimumBytesToClean).formattedBytes)
                    }
                    HStack(spacing: 6) {
                        Text("Only caches and logs are cleaned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        InfoButton("Only data apps recreate is cleaned. Anything that needs your password, belongs to a running app or is your own file is left for you to review.")
                    }
                }
                ForEach(ScheduleSettings.schedulableCategories) { category in
                    Toggle(isOn: Binding(
                        get: { settings.categories.contains(category) },
                        set: { on in
                            settings.categories.removeAll { $0 == category }
                            if on { settings.categories.append(category) }
                        })) {
                        Label { Text(category.title) } icon: { Image(systemName: category.systemImage) }
                    }
                }
            }

            if let summary {
                Section("Last Run") {
                    LabeledContent("Date") { Text(summary.date, format: .dateTime) }
                    LabeledContent("Found", value: summary.foundBytes.formattedBytes)
                    if summary.cleanedBytes > 0 {
                        LabeledContent("Cleaned", value: summary.cleanedBytes.formattedBytes)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { save($0) }
        .task {
            notificationsAllowed = await NotificationService.isAuthorized()
            agentStatus = SchedulerAgent.status
        }
        // The user may have approved the agent in Login Items meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            agentStatus = SchedulerAgent.status
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch agentStatus {
        case .enabled:
            LabeledContent("Next run") {
                Text(settings.nextRun(now: Date()), format: .dateTime.weekday().day().month().hour().minute())
            }
        case .requiresApproval:
            HStack {
                Label("macOS needs your approval in Login Items.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        default:
            HStack {
                Label("The background task is not registered.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if !notificationsAllowed {
            Label("Notifications are off. Results show here and in the menu bar.", systemImage: "bell.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Saves what this tab edits on top of the stored settings, so the time
    /// of the last run, written by the background run, is never rolled back.
    private func save(_ edited: ScheduleSettings) {
        var stored = store.loadSettings()
        stored.isEnabled = edited.isEnabled
        stored.frequency = edited.frequency
        stored.hour = edited.hour
        stored.action = edited.action
        stored.categories = edited.categories
        stored.minimumBytesToClean = edited.minimumBytesToClean
        try? store.save(stored)
    }

    private func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            try SchedulerAgent.setEnabled(enabled)
            settings.isEnabled = enabled
        } catch {
            // Waiting for approval in Login Items is not a failure: the choice
            // stays on and the approval hint shows.
            if enabled, SchedulerAgent.status == .requiresApproval {
                settings.isEnabled = true
            } else {
                errorMessage = error.localizedDescription
                settings.isEnabled = false
            }
        }
        agentStatus = SchedulerAgent.status
        if enabled {
            Task { notificationsAllowed = await NotificationService.requestAuthorization() }
        }
    }
}
