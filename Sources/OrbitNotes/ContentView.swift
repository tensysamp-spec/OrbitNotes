import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var updater: UpdateChecker
    @AppStorage("showPanel") private var showPanel = true
    @State private var search = ""

    private var visibleNotes: [Note] {
        let sorted = store.notes.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.modified > $1.modified
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if let release = updater.available {
                        UpdateBanner(release: release)
                            .padding([.horizontal, .top], 16)
                    }
                    if let binding = store.selectedNote {
                        NoteEditor(note: binding)
                            .id(binding.wrappedValue.id)
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showPanel {
                    Divider()
                    SidePanel()
                        .frame(width: 340)
                        .background(.regularMaterial)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showPanel)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPanel.toggle() } label: {
                        Label("Panel", systemImage: "sidebar.trailing")
                    }
                    .help(showPanel ? "Hide panel" : "Show panel")
                    .keyboardShortcut("p", modifiers: [.command, .option])
                }
            }
        }
        .tint(Theme.accentStart)
        .preferredColorScheme(.light)
        .alert("Software Update", isPresented: Binding(
            get: { updater.manualMessage != nil },
            set: { if !$0 { updater.manualMessage = nil } }
        )) {
            Button("OK") { updater.manualMessage = nil }
        } message: {
            Text(updater.manualMessage ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $store.selectedID) {
            Section("Notes") {
                ForEach(visibleNotes) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                        .contextMenu {
                            Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                                store.togglePin(note.id)
                            }
                            Button("Delete", role: .destructive) { store.delete(note.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search")
        .onDeleteCommand {
            if let id = store.selectedID { store.delete(id) }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 340)
        .overlay {
            if visibleNotes.isEmpty && !search.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { store.newNote() }
                } label: {
                    Label("New Note", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
                Button {
                    if let id = store.selectedID { store.delete(id) }
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.large)
                .disabled(store.selectedID == nil)
                .help("Delete note")
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(.bar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No Note Selected")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("New Note") { store.newNote() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRow: View {
    let note: Note

    private var preview: String {
        let firstLine = note.body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return firstLine.isEmpty ? "No additional text" : firstLine
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(note.modified, format: .relative(presentation: .named))
                    Text(preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(45))
                }
                if let r = note.reminder, r > Date() {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                        .help("Reminder \(r.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct UpdateBanner: View {
    @EnvironmentObject var updater: UpdateChecker
    let release: UpdateChecker.Release

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("Orbit Notes \(release.version) is available")
                .fontWeight(.medium)
            Spacer()
            Button("Skip") { updater.skip(release.version) }
                .buttonStyle(.borderless)
            Button("Download") {
                NSWorkspace.shared.open(release.downloadURL)
                updater.available = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.accentStart.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accentStart.opacity(0.25)))
    }
}

struct NoteEditor: View {
    @Binding var note: Note
    @EnvironmentObject var store: NoteStore
    @State private var showReminderPicker = false
    @State private var pickedDate = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(note.wordCount) word\(note.wordCount == 1 ? "" : "s") · Edited \(note.modified, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.togglePin(note.id)
                } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                        .rotationEffect(.degrees(note.pinned ? 45 : 0))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(note.pinned ? "Unpin" : "Pin to top")
                reminderButton
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            TextField("Title", text: $note.title)
                .font(.system(size: 28, weight: .bold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 6)

            ZStack(alignment: .topLeading) {
                if note.body.isEmpty {
                    Text("Start writing…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note.body)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var reminderButton: some View {
        Button {
            pickedDate = note.reminder ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            showReminderPicker.toggle()
        } label: {
            if let r = note.reminder, r > Date() {
                Label(r.formatted(date: .abbreviated, time: .shortened), systemImage: "bell.fill")
            } else {
                Label("Remind me", systemImage: "bell")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $showReminderPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Remind me about this note").font(.headline)
                DatePicker("When", selection: $pickedDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.stepperField)
                HStack(spacing: 8) {
                    Button("Tomorrow 9 AM") { pickedDate = tomorrow(at: 9) }
                    Button("In 1 hour") { pickedDate = Date().addingTimeInterval(3600) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                HStack {
                    if note.reminder != nil {
                        Button("Remove", role: .destructive) {
                            store.setReminder(nil, for: note.id)
                            showReminderPicker = false
                        }
                    }
                    Spacer()
                    Button("Set Reminder") {
                        store.setReminder(pickedDate, for: note.id)
                        showReminderPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 300)
        }
    }

    private func tomorrow(at hour: Int) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)!
    }
}
