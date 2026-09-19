import SwiftUI
import AppKit

// MARK: - Themes

struct Palette: Identifiable {
    let id: String          // display name
    let isLight: Bool
    let bg: Color
    let text: Color
    let dim: Color
    let accent: Color
    let result: Color
}

private func c(_ hex: UInt) -> Color {
    Color(red: Double((hex >> 16) & 0xff) / 255,
          green: Double((hex >> 8) & 0xff) / 255,
          blue: Double(hex & 0xff) / 255)
}

let kPalettes: [Palette] = [
    Palette(id: "mono",     isLight: false, bg: c(0x0d1117), text: c(0xdbe4ef), dim: c(0x5b6472), accent: c(0x57c7ff), result: c(0x9ad4ff)),
    Palette(id: "matrix",   isLight: false, bg: c(0x061109), text: c(0x7cffa0), dim: c(0x2f6b45), accent: c(0x38f58a), result: c(0xb6ffcb)),
    Palette(id: "tokyo",    isLight: false, bg: c(0x1a1b26), text: c(0xa9b1d6), dim: c(0x565f89), accent: c(0x7aa2f7), result: c(0xbb9af7)),
    Palette(id: "vendetta", isLight: false, bg: c(0x14090b), text: c(0xe6c9c9), dim: c(0x7a4a4f), accent: c(0xff4d5e), result: c(0xffa3ad)),
    Palette(id: "piccolo",  isLight: false, bg: c(0x0d1410), text: c(0xd6f5c9), dim: c(0x4a7a5a), accent: c(0x8bd450), result: c(0xb6e88f)),
    Palette(id: "a24",      isLight: false, bg: c(0x0e0e10), text: c(0xededed), dim: c(0x6a6a70), accent: c(0xe5533c), result: c(0xf0a58f)),
    Palette(id: "paper",    isLight: true,  bg: c(0xf5f1e6), text: c(0x2c2a25), dim: c(0x8a8578), accent: c(0xb5622f), result: c(0x6a5a3a)),
]

func palette(named name: String) -> Palette {
    kPalettes.first { $0.id == name } ?? kPalettes[0]
}

// MARK: - Contextual math

enum Maths {
    /// Antinote-style "descriptive math": ignore words, evaluate the numbers + operators on a line.
    static func line(_ raw: String) -> Double? {
        let allowed = Set("0123456789.+-*/() ")
        let cleaned = String(raw.filter { allowed.contains($0) })
        guard cleaned.contains(where: { "+-*/".contains($0) }) else { return nil }
        let digits = cleaned.filter { $0.isNumber }
        guard digits.count >= 2 else { return nil }
        return Calc.evaluate(cleaned)
    }

    static func fmt(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.4g", v)
    }
}

struct MathHit: Identifiable {
    let id = UUID()
    let source: String
    let value: Double
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var updater: UpdateChecker
    @EnvironmentObject var timer: FocusTimer

    @AppStorage("theme") private var themeName = "mono"
    @AppStorage("grid") private var grid = false
    @AppStorage("wordGoal") private var wordGoal = 500
    @State private var flash: String?

    private var pal: Palette { palette(named: themeName) }

    private var orderedNotes: [Note] { store.notes }
    private var index: Int { orderedNotes.firstIndex { $0.id == store.selectedID } ?? 0 }

    private var currentBody: String { store.selectedNote?.wrappedValue.body ?? "" }

    private var mathHits: [MathHit] {
        currentBody
            .components(separatedBy: "\n")
            .compactMap { l in
                let t = l.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, let v = Maths.line(t) else { return nil }
                return MathHit(source: t, value: v)
            }
    }

    var body: some View {
        ZStack {
            VisualEffect(material: pal.isLight ? .contentBackground : .hudWindow).ignoresSafeArea()
            pal.bg.opacity(pal.isLight ? 0.55 : 0.72).ignoresSafeArea()
            if grid { GridPaper(color: pal.dim.opacity(0.18)).ignoresSafeArea() }

            VStack(spacing: 0) {
                if let release = updater.available { updateBar(release) }

                if let note = store.selectedNote {
                    Scratchpad(note: note, pal: pal, onBody: handleBody)
                } else {
                    VStack(spacing: 8) {
                        Text("empty").foregroundStyle(pal.dim)
                        Text("press ⌘N or type  :new").foregroundStyle(pal.dim)
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !mathHits.isEmpty { resultsStrip }
                statusBar
            }
        }
        .foregroundStyle(pal.text)
        .tint(pal.accent)
        .background(WindowConfigurator())
        .preferredColorScheme(pal.isLight ? .light : .dark)
        .overlay(alignment: .top) { if let f = flash { toast(f) } }
        .alert("Software Update", isPresented: Binding(
            get: { updater.manualMessage != nil },
            set: { if !$0 { updater.manualMessage = nil } }
        )) {
            Button("OK") { updater.manualMessage = nil }
        } message: { Text(updater.manualMessage ?? "") }
    }

    // MARK: Results strip (inline math)

    private var resultsStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(mathHits.suffix(4)) { hit in
                HStack(spacing: 8) {
                    Text(hit.source).foregroundStyle(pal.dim).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("= \(Maths.fmt(hit.value))").foregroundStyle(pal.result)
                }
                .font(.system(size: 11, design: .monospaced))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.bg.opacity(0.6))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(pal.dim.opacity(0.25)), alignment: .top)
    }

    // MARK: Status bar

    private var statusBar: some View {
        let words = currentBody.split { $0.isWhitespace || $0.isNewline }.count
        let lines = currentBody.isEmpty ? 0 : currentBody.components(separatedBy: "\n").count
        return HStack(spacing: 14) {
            HStack(spacing: 6) {
                navButton("chevron.left") { move(-1) }
                Text("\(orderedNotes.isEmpty ? 0 : index + 1)/\(orderedNotes.count)")
                navButton("chevron.right") { move(1) }
            }
            Text("\(words)w · \(lines)l")
            if timer.isRunning {
                HStack(spacing: 5) {
                    Circle().fill(timer.phase == .focus ? pal.accent : pal.result).frame(width: 6, height: 6)
                    Text(timer.timeString)
                }
            }
            Spacer()
            Button { grid.toggle() } label: { Text(grid ? "grid" : "plain") }
                .buttonStyle(.plain).foregroundStyle(pal.dim)
            Button { cycleTheme() } label: { Text(themeName) }
                .buttonStyle(.plain).foregroundStyle(pal.accent)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(pal.dim)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(pal.bg.opacity(0.5))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(pal.dim.opacity(0.25)), alignment: .top)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            .buttonStyle(.plain).foregroundStyle(pal.dim)
    }

    private func updateBar(_ release: UpdateChecker.Release) -> some View {
        HStack(spacing: 8) {
            Text(updater.installState ?? "update \(release.version) available")
                .foregroundStyle(pal.accent)
            Spacer()
            if updater.installState == nil {
                Button("update") { updater.downloadAndInstall(release) }
                    .buttonStyle(.plain).foregroundStyle(pal.result)
                Button("skip") { updater.skip(release.version) }
                    .buttonStyle(.plain).foregroundStyle(pal.dim)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(pal.bg.opacity(0.7))
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(pal.bg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(pal.accent, in: Capsule())
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        guard !orderedNotes.isEmpty else { return }
        let i = (index + delta + orderedNotes.count) % orderedNotes.count
        store.selectedID = orderedNotes[i].id
    }

    private func cycleTheme() {
        let i = kPalettes.firstIndex { $0.id == themeName } ?? 0
        themeName = kPalettes[(i + 1) % kPalettes.count].id
    }

    private func show(_ text: String) {
        withAnimation { flash = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { flash = nil }
        }
    }

    // MARK: Inline command lines (":" or "/"), run when completed with Enter

    private func handleBody(_ text: String) {
        guard text.hasSuffix("\n") else { return }
        var lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return }
        let completed = lines[lines.count - 2]
        guard completed.hasPrefix(":") || completed.hasPrefix("/") else { return }
        // Strip the command line from the note it was typed in, by id,
        // BEFORE running (the command may change which note is selected).
        let editedID = store.selectedID
        lines.remove(at: lines.count - 2)
        let rebuilt = lines.joined(separator: "\n")
        if let id = editedID, let idx = store.notes.firstIndex(where: { $0.id == id }) {
            store.notes[idx].body = rebuilt
        }
        run(String(completed.dropFirst()))
    }

    private func run(_ raw: String) {
        let cmd = raw.trimmingCharacters(in: .whitespaces)
        let parts = cmd.split(separator: " ", maxSplits: 1).map(String.init)
        let name = parts.first?.lowercased() ?? ""
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        switch name {
        case "new":
            store.newNote()
            if !arg.isEmpty { store.selectedNote?.wrappedValue.title = arg }
            show("new note")
        case "del", "delete":
            if let id = store.selectedID { store.delete(id); show("deleted") }
        case "timer", "t":
            let m = Int(arg) ?? timer.focusMinutes
            timer.focusMinutes = max(1, m); timer.reset(); timer.start()
            show("timer \(timer.focusMinutes)m")
        case "pom", "pomodoro":
            timer.focusMinutes = 25; timer.reset(); timer.start(); show("pomodoro started")
        case "stop":
            timer.pause(); show("timer stopped")
        case "goal":
            if let n = Int(arg), n > 0 { wordGoal = n; show("goal \(n)w") } else { show("usage: :goal 500") }
        case "theme":
            if kPalettes.contains(where: { $0.id == arg }) { themeName = arg; show("theme \(arg)") }
            else { cycleTheme(); show("theme \(themeName)") }
        case "grid":
            grid.toggle(); show(grid ? "grid on" : "grid off")
        case "pin":
            if let id = store.selectedID { store.togglePin(id); show("pin toggled") }
        case "remind":
            if let id = store.selectedID, let s = parseInterval(arg) {
                store.setReminder(Date().addingTimeInterval(s), for: id); show("reminder set")
            } else { show("usage: :remind 30m") }
        case "help":
            show(":new :timer :pom :stop :goal :theme :grid :remind :del")
        default:
            show("? \(name)")
        }
    }

    private func parseInterval(_ s: String) -> TimeInterval? {
        let t = s.lowercased()
        if t.hasSuffix("m"), let n = Double(t.dropLast()) { return n * 60 }
        if t.hasSuffix("h"), let n = Double(t.dropLast()) { return n * 3600 }
        if let n = Double(t) { return n * 60 }
        return nil
    }
}

// MARK: - Scratchpad editor

struct Scratchpad: View {
    @Binding var note: Note
    let pal: Palette
    let onBody: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if note.body.isEmpty {
                Text("write anything… try  5 + 12  or  :timer 25")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(pal.dim.opacity(0.7))
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $note.body)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(pal.text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .onChange(of: note.body) { newValue in onBody(newValue) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid paper

struct GridPaper: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let step: CGFloat = 24
                var y: CGFloat = step
                while y < geo.size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
                var x: CGFloat = step
                while x < geo.size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
            }
            .stroke(color, lineWidth: 0.5)
        }
    }
}

// MARK: - Translucency

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Makes the hosting window non-opaque so the translucency shows the desktop,
/// and hides the title bar for a clean scratchpad look.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
