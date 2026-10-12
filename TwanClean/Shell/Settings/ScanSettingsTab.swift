import SwiftUI

struct ScanSettingsTab: View {
    @State private var settings = ScanSettings.load()

    private var largeMegabytes: Binding<Int> {
        Binding(get: { Int(settings.largeFileMinimumBytes / 1_000_000) },
                set: { settings.largeFileMinimumBytes = Int64($0) * 1_000_000 })
    }

    var body: some View {
        Form {
            Section("Large & Old Files") {
                Stepper(value: largeMegabytes, in: 10...10_000, step: 10) {
                    LabeledContent("Large files are at least", value: "\(largeMegabytes.wrappedValue) MB")
                }
                Stepper(value: $settings.oldFileMonths, in: 1...120) {
                    LabeledContent("Old files are untouched for", value: String(localized: "\(settings.oldFileMonths) months"))
                }
            }
            Section("Folders to Skip") {
                if settings.excludedFolders.isEmpty {
                    Text("No folders skipped.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.excludedFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            settings.excludedFolders.removeAll { $0 == folder }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Stop skipping this folder"))
                    }
                }
                Button("Add Folder…", action: addFolder)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { $0.save() }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !settings.excludedFolders.contains(url.path) {
            settings.excludedFolders.append(url.path)
        }
    }
}
