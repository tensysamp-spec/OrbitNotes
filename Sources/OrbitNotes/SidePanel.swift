import SwiftUI
import Charts

// MARK: - Theme

enum Theme {
    static let accentStart = Color(red: 0.36, green: 0.40, blue: 0.98)  // indigo
    static let accentEnd   = Color(red: 0.16, green: 0.72, blue: 0.96)  // cyan
    static let accent = LinearGradient(colors: [accentStart, accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardRadius: CGFloat = 18
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.7),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

// MARK: - Side panel

enum PanelTab: String, CaseIterable, Identifiable {
    case focus = "Focus", tools = "Tools", reminders = "Reminders", insights = "Insights"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .focus: return "timer"
        case .tools: return "square.grid.2x2"
        case .reminders: return "bell"
        case .insights: return "chart.xyaxis.line"
        }
    }
}

struct SidePanel: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var timer: FocusTimer
    @AppStorage("panelTab") private var tabRaw = PanelTab.focus.rawValue

    private var tab: Binding<PanelTab> {
        Binding(get: { PanelTab(rawValue: tabRaw) ?? .focus }, set: { tabRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: tab) {
                ForEach(PanelTab.allCases) { t in
                    Image(systemName: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text(tab.wrappedValue.rawValue)
                    .font(.title3.weight(.bold))
                Spacer()
            }

            ScrollView {
                Group {
                    switch tab.wrappedValue {
                    case .focus: FocusView()
                    case .tools: ToolsView()
                    case .reminders: RemindersView()
                    case .insights: InsightsView()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tabRaw)
        }
        .padding(16)
    }
}

// MARK: - Focus

struct FocusView: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var store: NoteStore

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 18) {
                Text(timer.phase == .focus ? "FOCUS" : "BREAK")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(AngularGradient(colors: [Theme.accentStart, Theme.accentEnd, Theme.accentStart],
                                                center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.accentEnd.opacity(0.5), radius: timer.isRunning ? 10 : 0)
                        .animation(.linear(duration: 0.25), value: timer.progress)
                    VStack(spacing: 4) {
                        Text(timer.timeString)
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(timer.isRunning ? "running" : "paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 200)
                .padding(.vertical, 6)

                HStack(spacing: 10) {
                    Button { timer.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.bordered)
                        .help("Reset")
                    Button { timer.toggle() } label: {
                        Label(timer.isRunning ? "Pause" : "Start", systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                            .frame(minWidth: 90)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [.command, .shift])
                    Button { timer.skip() } label: { Image(systemName: "forward.end.fill") }
                        .buttonStyle(.bordered)
                        .help("Skip to \(timer.phase == .focus ? "break" : "focus")")
                }
            }
            .frame(maxWidth: .infinity)
            .glassCard()

            HStack(spacing: 12) {
                StatTile(value: "\(store.focusMinutesToday)", unit: "min", label: "Focused today")
                StatTile(value: "\(timer.completedToday)", unit: "", label: "Sessions")
                StatTile(value: "\(store.streak)", unit: "d", label: "Streak")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Durations").font(.headline)
                Stepper("Focus: \(timer.focusMinutes) min", value: $timer.focusMinutes, in: 5...90, step: 5)
                Stepper("Break: \(timer.breakMinutes) min", value: $timer.breakMinutes, in: 1...30, step: 1)
            }
            .disabled(timer.isRunning)
            .glassCard()
        }
    }
}

struct StatTile: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Reminders

struct RemindersView: View {
    @EnvironmentObject var store: NoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.upcomingReminders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No upcoming reminders")
                        .foregroundStyle(.secondary)
                    Text("Select a note and press the bell to set one.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .glassCard()
            } else {
                ForEach(store.upcomingReminders) { note in
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(note.reminder!, format: .dateTime.weekday(.wide).hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.setReminder(nil, for: note.id)
                        } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Remove reminder")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectedID = note.id }
                    .glassCard()
                }
            }
        }
    }
}

// MARK: - Insights

struct InsightsView: View {
    @EnvironmentObject var store: NoteStore
    @State private var days = 14

    var body: some View {
        VStack(spacing: 14) {
            Picker("Range", selection: $days) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 12) {
                StatTile(value: "\(store.wordsToday)", unit: "", label: "Words today")
                StatTile(value: "\(store.totalWords)", unit: "", label: "Total words")
                StatTile(value: "\(store.notes.count)", unit: "", label: "Notes")
            }

            ChartCard(title: "Words written", data: store.wordsWritten(days: days), unit: "words")
            ChartCard(title: "Focus minutes", data: store.focusMinutes(days: days), unit: "min", line: true)
            ChartCard(title: "Notes created", data: store.notesCreated(days: days), unit: "notes")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: days)
    }
}

struct ChartCard: View {
    let title: String
    let data: [DayValue]
    let unit: String
    var line = false

    private var total: Int { data.reduce(0) { $0 + $1.value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text("\(total) \(unit)").font(.caption).foregroundStyle(.secondary)
            }
            Chart(data) { point in
                if line {
                    AreaMark(x: .value("Day", point.day, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.accentStart.opacity(0.45), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Day", point.day, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                } else {
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value(title, point.value))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, data.count / 5))) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 120)
        }
        .glassCard()
    }
}


// MARK: - Tools (mini extensions)

struct ToolsView: View {
    @EnvironmentObject var store: NoteStore
    @AppStorage("wordGoal") private var wordGoal = 500
    @AppStorage("countdownLabel") private var countdownLabel = "Next deadline"
    @AppStorage("countdownDate") private var countdownStamp = 0.0
    @AppStorage("calcInput") private var calcInput = ""
    @State private var editingCountdown = false

    private var countdownDate: Binding<Date> {
        Binding(
            get: { countdownStamp > 0 ? Date(timeIntervalSince1970: countdownStamp)
                                      : Date().addingTimeInterval(86400 * 3) },
            set: { countdownStamp = $0.timeIntervalSince1970 }
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            wordGoalCard
            countdownCard
            noteStatsCard
            calculatorCard
        }
    }

    // Daily word goal
    private var wordGoalCard: some View {
        let done = store.wordsToday
        let progress = min(1.0, Double(done) / Double(max(1, wordGoal)))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daily word goal", systemImage: "target").font(.headline)
                Spacer()
                Text("\(done)/\(wordGoal)").font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 10)
            Stepper("Goal: \(wordGoal) words", value: $wordGoal, in: 50...5000, step: 50)
                .font(.callout)
            if progress >= 1 {
                Label("Goal reached — nice!", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(Theme.accentStart)
            }
        }
        .glassCard()
    }

    // Countdown to a deadline
    private var countdownCard: some View {
        let target = countdownDate.wrappedValue
        let remaining = target.timeIntervalSinceNow
        let days = Int(remaining / 86400)
        let hours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Countdown", systemImage: "hourglass").font(.headline)
                Spacer()
                Button { editingCountdown.toggle() } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
            }
            TextField("Label", text: $countdownLabel)
                .textFieldStyle(.plain)
                .font(.subheadline.weight(.medium))
            if remaining > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(days)").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("d").foregroundStyle(.secondary)
                    Text("\(hours)").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("h left").foregroundStyle(.secondary)
                }
                .foregroundStyle(Theme.accent)
            } else {
                Text("Time's up").font(.title3.weight(.semibold)).foregroundStyle(.orange)
            }
            Text(target, format: .dateTime.weekday(.wide).day().month().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            if editingCountdown {
                DatePicker("When", selection: countdownDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
            }
        }
        .glassCard()
    }

    // Live stats for the selected note
    private var noteStatsCard: some View {
        let note = store.selectedNote?.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            Label("This note", systemImage: "textformat.123").font(.headline)
            if let note {
                HStack(spacing: 10) {
                    StatTile(value: "\(note.wordCount)", unit: "", label: "Words")
                    StatTile(value: "\(note.charCount)", unit: "", label: "Characters")
                    StatTile(value: "\(note.readingMinutes)", unit: "min", label: "Read time")
                }
            } else {
                Text("Select a note to see its stats.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    // Quick calculator
    private var calculatorCard: some View {
        let result = Calc.evaluate(calcInput)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Quick calculator", systemImage: "plusminus").font(.headline)
            TextField("e.g. 12 * (3 + 4)", text: $calcInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Text("=").foregroundStyle(.secondary)
                Text(resultString(result))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(result == nil && !calcInput.isEmpty ? Color.secondary : Theme.accentStart)
                    .textSelection(.enabled)
                Spacer()
                if result != nil {
                    Button("Insert") {
                        store.selectedNote?.wrappedValue.body += resultString(result)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(store.selectedID == nil)
                }
            }
        }
        .glassCard()
    }

    private func resultString(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%g", value)
    }
}
