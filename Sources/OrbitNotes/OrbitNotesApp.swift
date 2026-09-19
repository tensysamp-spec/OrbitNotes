import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
@MainActor
struct OrbitNotesApp: App {
    @StateObject private var store = NoteStore()
    @StateObject private var updater = UpdateChecker()
    @StateObject private var timer = FocusTimer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(updater)
                .environmentObject(timer)
                .frame(minWidth: 340, idealWidth: 420, maxWidth: 900, minHeight: 480, idealHeight: 760, maxHeight: .infinity)
                .onAppear {
                    Notifications.shared.setup()
                    updater.checkIfDue()
                    timer.onPhaseComplete = { minutes, isBreak in
                        store.logSession(minutes: minutes, isBreak: isBreak)
                    }
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(manual: true) }
                }
                .disabled(updater.isChecking)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Export Note as Markdown…") { exportSelectedNote() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.selectedID == nil)
                Divider()
                Button("Delete Note") {
                    if let id = store.selectedID { store.delete(id) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selectedID == nil)
            }
            CommandMenu("Focus") {
                Button(timer.isRunning ? "Pause Timer" : "Start Timer") { timer.toggle() }
                    .keyboardShortcut(.space, modifiers: [.command, .shift])
                Button("Reset Timer") { timer.reset() }
                Button("Skip Phase") { timer.skip() }
            }
        }

        Settings {
            Form {
                Section("Focus timer") {
                    Stepper("Focus length: \(timer.focusMinutes) min", value: $timer.focusMinutes, in: 5...90, step: 5)
                    Stepper("Break length: \(timer.breakMinutes) min", value: $timer.breakMinutes, in: 1...30, step: 1)
                }
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.autoCheck)
                    LabeledContent("Version", value: AppConfig.version)
                }
            }
            .formStyle(.grouped)
            .frame(width: 460, height: 260)
        }
    }

    private func exportSelectedNote() {
        guard let note = store.selectedNote?.wrappedValue else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (note.title.isEmpty ? "Untitled" : note.title) + ".md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let text = "# \(note.title)\n\n\(note.body)\n"
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
