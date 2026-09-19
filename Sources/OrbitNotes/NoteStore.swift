import Foundation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var created: Date
    var modified: Date
    var reminder: Date?
    var pinned: Bool

    init(id: UUID = UUID(), title: String = "", body: String = "",
         created: Date = Date(), modified: Date = Date(), reminder: Date? = nil, pinned: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.created = created
        self.modified = modified
        self.reminder = reminder
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey { case id, title, body, created, modified, reminder, pinned }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        reminder = try c.decodeIfPresent(Date.self, forKey: .reminder)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    var wordCount: Int { body.split { $0.isWhitespace || $0.isNewline }.count }
    var charCount: Int { body.count }
    var readingMinutes: Int { max(1, Int((Double(wordCount) / 200.0).rounded(.up))) }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var done: Bool = false
}

struct FocusSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var minutes: Int
    var isBreak: Bool
}

/// One point on a daily chart.
struct DayValue: Identifiable {
    var id: Date { day }
    let day: Date
    let value: Int
}

/// Everything saved to disk.
private struct StoreData: Codable {
    var notes: [Note]
    var wordsPerDay: [String: Int]      // "2026-09-18" → words written that day
    var sessions: [FocusSession]
    var todos: [TodoItem]

    init(notes: [Note], wordsPerDay: [String: Int], sessions: [FocusSession], todos: [TodoItem]) {
        self.notes = notes; self.wordsPerDay = wordsPerDay; self.sessions = sessions; self.todos = todos
    }

    enum CodingKeys: String, CodingKey { case notes, wordsPerDay, sessions, todos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = try c.decode([Note].self, forKey: .notes)
        wordsPerDay = try c.decodeIfPresent([String: Int].self, forKey: .wordsPerDay) ?? [:]
        sessions = try c.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? []
        todos = try c.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
    }
}

/// Keeps notes, writing activity and focus sessions; saves to
/// ~/Library/Application Support/OrbitNotes/data.json (debounced).
@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = [] { didSet { scheduleSave() } }
    @Published var wordsPerDay: [String: Int] = [:] { didSet { scheduleSave() } }
    @Published var sessions: [FocusSession] = [] { didSet { scheduleSave() } }
    @Published var todos: [TodoItem] = [] { didSet { scheduleSave() } }
    @Published var selectedID: UUID?

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("OrbitNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(StoreData.self, from: data) {
            notes = decoded.notes.sorted { $0.modified > $1.modified }
            wordsPerDay = decoded.wordsPerDay
            sessions = decoded.sessions
            todos = decoded.todos
        }
        if notes.isEmpty {
            notes = [Note(
                title: "Welcome to Orbit Notes",
                body: """
                A calm place to write, focus and keep track of your day.

                • ⌘N makes a new note.
                • The bell button sets a reminder — you'll get a notification.
                • The panel on the right has a focus timer, your reminders, and charts of how much you write and focus.
                """
            )]
        }
        selectedID = notes.first?.id
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = StoreData(notes: notes, wordsPerDay: wordsPerDay, sessions: sessions, todos: todos)
        if let data = try? encoder.encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Notes

    func newNote() {
        let note = Note()
        notes.insert(note, at: 0)
        selectedID = note.id
    }

    func delete(_ id: UUID) {
        Notifications.shared.cancelReminder(for: id)
        notes.removeAll { $0.id == id }
        if selectedID == id { selectedID = notes.first?.id }
    }

    func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].pinned.toggle()
    }

    func setReminder(_ date: Date?, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].reminder = date
        if let date {
            Notifications.shared.scheduleReminder(for: notes[index], at: date)
        } else {
            Notifications.shared.cancelReminder(for: id)
        }
    }

    /// Notes with a reminder in the future, soonest first.
    var upcomingReminders: [Note] {
        notes.filter { ($0.reminder ?? .distantPast) > Date() }
             .sorted { $0.reminder! < $1.reminder! }
    }

    /// A binding to the selected note. Editing it also records words written today.
    var selectedNote: Binding<Note>? {
        guard let id = selectedID,
              let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.notes[index] },
            set: { newValue in
                guard index < self.notes.count, self.notes[index].id == id else { return }
                let old = self.notes[index]
                guard newValue != old else { return }
                var updated = newValue
                updated.modified = Date()
                let delta = updated.wordCount - old.wordCount
                if delta > 0 { self.wordsPerDay[Self.key(for: Date()), default: 0] += delta }
                self.notes[index] = updated
            }
        )
    }

    // MARK: - Focus sessions

    func logSession(minutes: Int, isBreak: Bool) {
        sessions.append(FocusSession(date: Date(), minutes: minutes, isBreak: isBreak))
    }

    // MARK: - To-dos

    func addTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoItem(text: trimmed))
    }

    func toggleTodo(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
    }

    func clearFinishedTodos() {
        todos.removeAll { $0.done }
    }

    var openTodoCount: Int { todos.filter { !$0.done }.count }

    // MARK: - Chart data

    static func key(for date: Date) -> String { dayFormatter.string(from: date) }

    private func lastDays(_ n: Int) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    func wordsWritten(days n: Int) -> [DayValue] {
        lastDays(n).map { DayValue(day: $0, value: wordsPerDay[Self.key(for: $0)] ?? 0) }
    }

    func focusMinutes(days n: Int) -> [DayValue] {
        let cal = Calendar.current
        return lastDays(n).map { day in
            let total = sessions
                .filter { !$0.isBreak && cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.minutes }
            return DayValue(day: day, value: total)
        }
    }

    func notesCreated(days n: Int) -> [DayValue] {
        let cal = Calendar.current
        return lastDays(n).map { day in
            DayValue(day: day, value: notes.filter { cal.isDate($0.created, inSameDayAs: day) }.count)
        }
    }

    var totalWords: Int { notes.reduce(0) { $0 + $1.wordCount } }
    var focusMinutesToday: Int { focusMinutes(days: 1).last?.value ?? 0 }
    var wordsToday: Int { wordsWritten(days: 1).last?.value ?? 0 }

    /// Consecutive days (ending today or yesterday) with any writing or focus.
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        var count = 0
        func active(_ d: Date) -> Bool {
            (wordsPerDay[Self.key(for: d)] ?? 0) > 0 ||
            sessions.contains { !$0.isBreak && cal.isDate($0.date, inSameDayAs: d) }
        }
        if !active(day), let y = cal.date(byAdding: .day, value: -1, to: day) { day = y }
        while active(day), let prev = cal.date(byAdding: .day, value: -1, to: day) {
            count += 1
            day = prev
        }
        return count
    }
}
