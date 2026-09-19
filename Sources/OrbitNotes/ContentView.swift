import SwiftUI
import AppKit

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var updater: UpdateChecker
    @EnvironmentObject var timer: FocusTimer

    @AppStorage("theme") private var themeName = "white"
    @AppStorage("grid") private var grid = true
    @AppStorage("wordGoal") private var wordGoal = 500
    @State private var flash: String?
    @State private var showCommands = false

    private var pal: Palette { palette(named: themeName) }
    private var orderedNotes: [Note] { store.notes }
    private var index: Int { orderedNotes.firstIndex { $0.id == store.selectedID } ?? 0 }
    private var body_: String { store.selectedNote?.wrappedValue.body ?? "" }

    var body: some View {
        ZStack {
            VisualEffect(material: pal.isLight ? .contentBackground : .hudWindow).ignoresSafeArea()
            pal.bg.opacity(pal.isLight ? 0.55 : 0.68).ignoresSafeArea()
            if grid { GridPaper(color: pal.dim.opacity(0.16)).ignoresSafeArea() }

            VStack(spacing: 0) {
                if let release = updater.available { updateBar(release) }
                topBar

                if let noteBinding = store.selectedNote {
                    HStack(spacing: 0) {
                        // Left timer progress bar (Antinote-style)
                        Group {
                            if timer.isRunning {
                                GeometryReader { geo in
                                    ZStack(alignment: .top) {
                                        Rectangle().fill(pal.dim.opacity(0.25))
                                        Rectangle().fill(timer.phase == .focus ? pal.accent : pal.result)
                                            .frame(height: geo.size.height * timer.progress)
                                    }
                                }
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 2)

                        ZStack(alignment: .topLeading) {
                            CodeTextView(text: noteBinding.body, pal: pal)
                            if body_.isEmpty {
                                Text("write anything…  5 + 12   ·   /timer 25   ·   [ ] a task")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(pal.dim.opacity(0.7))
                                    .padding(.horizontal, 15).padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: body_) { newValue in handleBody(newValue) }
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("empty").foregroundStyle(pal.dim)
                        Text("press ⌘N or type  /new").foregroundStyle(pal.dim)
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                statusBar
            }
        }
        .foregroundStyle(pal.text)
        .tint(pal.accent)
        .background(WindowConfigurator())
        .preferredColorScheme(pal.isLight ? .light : .dark)
        .overlay(alignment: .top) { if let f = flash { toast(f) } }
        .alert("Software Update", isPresented: Binding(
            get: { updater.manualMessage != nil }, set: { if !$0 { updater.manualMessage = nil } }
        )) { Button("OK") { updater.manualMessage = nil } } message: { Text(updater.manualMessage ?? "") }
    }

    // MARK: Top bar + palette

    private var topBar: some View {
        HStack {
            Text("orbit").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(pal.dim)
            Spacer()
            Button { showCommands.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10, weight: .bold))
                    Text("commands").font(.system(size: 11, design: .monospaced))
                }
            }
            .buttonStyle(.plain).foregroundStyle(pal.accent)
            .popover(isPresented: $showCommands, arrowEdge: .bottom) { commandPalette }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    private var commandPalette: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("tap to run · or type / then a command").font(.system(size: 10, design: .monospaced)).foregroundStyle(pal.dim).padding(.bottom, 6)
                ForEach(kCommands) { cmd in
                    Button {
                        showCommands = false
                        if cmd.noArgs { run(cmd.name) } else { appendLine("/\(cmd.name) ") }
                    } label: {
                        HStack(spacing: 8) {
                            Text("/\(cmd.name)").foregroundStyle(pal.accent)
                            Text(cmd.args).foregroundStyle(pal.result)
                            Spacer(minLength: 8)
                            Text(cmd.desc).foregroundStyle(pal.dim).lineLimit(1)
                        }
                        .font(.system(size: 11, design: .monospaced)).padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .frame(width: 320, height: 380).background(pal.bg)
    }

    private var statusBar: some View {
        let words = body_.split { $0.isWhitespace || $0.isNewline }.count
        let lines = body_.isEmpty ? 0 : body_.components(separatedBy: "\n").count
        return HStack(spacing: 12) {
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
            Button { grid.toggle() } label: { Text(grid ? "grid" : "plain") }.buttonStyle(.plain).foregroundStyle(pal.dim)
            Button { cycleTheme() } label: { Text(themeName) }.buttonStyle(.plain).foregroundStyle(pal.accent)
        }
        .font(.system(size: 11, design: .monospaced)).foregroundStyle(pal.dim)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(pal.bg.opacity(0.45))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(pal.dim.opacity(0.2)), alignment: .top)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            .buttonStyle(.plain).foregroundStyle(pal.dim)
    }

    private func updateBar(_ release: UpdateChecker.Release) -> some View {
        HStack(spacing: 8) {
            Text(updater.installState ?? "update \(release.version) available").foregroundStyle(pal.accent)
            Spacer()
            if updater.installState == nil {
                Button("update") { updater.downloadAndInstall(release) }.buttonStyle(.plain).foregroundStyle(pal.result)
                Button("skip") { updater.skip(release.version) }.buttonStyle(.plain).foregroundStyle(pal.dim)
            }
        }
        .font(.system(size: 11, design: .monospaced)).padding(.horizontal, 14).padding(.vertical, 6).background(pal.bg.opacity(0.7))
    }

    private func toast(_ text: String) -> some View {
        Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(pal.bg)
            .padding(.horizontal, 12).padding(.vertical, 6).background(pal.accent, in: Capsule())
            .padding(.top, 10).transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Note text helpers

    private func setBody(_ s: String) { store.selectedNote?.wrappedValue.body = s }
    private func appendLine(_ s: String) {
        let b = body_
        if b.isEmpty { setBody(s) } else if b.hasSuffix("\n") { setBody(b + s) } else { setBody(b + "\n" + s) }
    }
    private func mapLines(_ f: ([String]) -> [String]) {
        setBody(f(body_.components(separatedBy: "\n")).joined(separator: "\n"))
    }
    private func numbers(in s: String) -> [Double] {
        var out: [Double] = []; var cur = ""
        func flush() { if let d = Double(cur) { out.append(d) }; cur = "" }
        for ch in s { if ch.isNumber || ch == "." { cur.append(ch) } else { flush() } }
        flush(); return out
    }

    private func move(_ delta: Int) {
        guard !orderedNotes.isEmpty else { return }
        store.selectedID = orderedNotes[(index + delta + orderedNotes.count) % orderedNotes.count].id
    }
    private func cycleTheme() {
        let i = kPalettes.firstIndex { $0.id == themeName } ?? 0
        themeName = kPalettes[(i + 1) % kPalettes.count].id
    }
    private func show(_ text: String) {
        withAnimation { flash = text }
        Task { @MainActor in try? await Task.sleep(nanoseconds: 1_500_000_000); withAnimation { flash = nil } }
    }

    // MARK: Command + /x handling (fires when a line is completed with Enter)

    private func handleBody(_ text: String) {
        guard text.hasSuffix("\n") else { return }
        var lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return }
        let completed = lines[lines.count - 2]
        let editedID = store.selectedID

        // ":" or "/" command
        if completed.hasPrefix(":") || completed.hasPrefix("/") {
            lines.remove(at: lines.count - 2)
            writeToEdited(editedID, lines.joined(separator: "\n"))
            run(String(completed.dropFirst()))
            return
        }
        // "/x" at end of a line toggles its checkbox
        if completed.hasSuffix("/x") {
            var line = String(completed.dropLast(2)).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[x]") { line = "[ ]" + line.dropFirst(3) }
            else if line.hasPrefix("[ ]") { line = "[x]" + line.dropFirst(3) }
            else { line = "[x] " + line }
            lines[lines.count - 2] = line
            writeToEdited(editedID, lines.joined(separator: "\n"))
        }
    }

    private func writeToEdited(_ id: UUID?, _ text: String) {
        if let id, let idx = store.notes.firstIndex(where: { $0.id == id }) { store.notes[idx].body = text }
    }

    private func run(_ raw: String) {
        let cmd = raw.trimmingCharacters(in: .whitespaces)
        let parts = cmd.split(separator: " ", maxSplits: 1).map(String.init)
        let name = parts.first?.lowercased() ?? ""
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        switch name {
        case "new": store.newNote(); if !arg.isEmpty { store.selectedNote?.wrappedValue.title = arg }; show("new note")
        case "del", "delete": if let id = store.selectedID { store.delete(id); show("deleted") }
        case "next": move(1)
        case "prev": move(-1)
        case "open":
            if let i = Int(arg), i >= 1, i <= orderedNotes.count { store.selectedID = orderedNotes[i-1].id; show("note \(i)") } else { show("usage: /open 2") }
        case "title", "rename":
            if !arg.isEmpty { store.selectedNote?.wrappedValue.title = arg; show("renamed") } else { show("usage: /title Trip") }
        case "pin": if let id = store.selectedID { store.togglePin(id); show("pin toggled") }
        case "clear": setBody(""); show("cleared")
        case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(body_, forType: .string); show("copied")
        case "timer", "t":
            let m = Int(arg) ?? timer.focusMinutes; timer.focusMinutes = max(1, m); timer.reset(); timer.start(); show("timer \(timer.focusMinutes)m")
        case "pom", "pomodoro": timer.focusMinutes = 25; timer.reset(); timer.start(); show("pomodoro")
        case "stop": timer.pause(); show("stopped")
        case "goal": if let n = Int(arg), n > 0 { wordGoal = n; show("goal \(n)w") } else { show("usage: /goal 500") }
        case "remind":
            if let id = store.selectedID, let s = parseInterval(arg) { store.setReminder(Date().addingTimeInterval(s), for: id); show("reminder set") } else { show("usage: /remind 30m") }
        case "white", "light": themeName = "white"; show("white")
        case "dark": themeName = "mono"; show("dark")
        case "theme": if kPalettes.contains(where: { $0.id == arg }) { themeName = arg; show("theme \(arg)") } else { cycleTheme(); show("theme \(themeName)") }
        case "grid": grid.toggle(); show(grid ? "grid on" : "grid off")
        case "date": appendLine(Date().formatted(date: .abbreviated, time: .omitted)); show("date")
        case "time": appendLine(Date().formatted(date: .omitted, time: .shortened)); show("time")
        case "now": appendLine(Date().formatted(date: .abbreviated, time: .shortened)); show("now")
        case "todo": appendLine("[ ] "); show("todo")
        case "done": mapLines { $0.map { $0.replacingOccurrences(of: "[ ]", with: "[x]") } }; show("checked")
        case "bullet": mapLines { $0.map { l in l.trimmingCharacters(in: .whitespaces).isEmpty ? l : "- " + l } }; show("bulleted")
        case "number":
            var n = 0
            mapLines { lines in lines.map { l -> String in
                if l.trimmingCharacters(in: .whitespaces).isEmpty { return l }; n += 1; return "\(n). " + l } }
            show("numbered")
        case "sort": mapLines { $0.sorted() }; show("sorted")
        case "rev": mapLines { Array($0.reversed()) }; show("reversed")
        case "shuffle": mapLines { $0.shuffled() }; show("shuffled")
        case "dedup": mapLines { lines in var seen = Set<String>(); return lines.filter { seen.insert($0).inserted } }; show("deduped")
        case "trim": mapLines { $0.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }; show("trimmed")
        case "upper": setBody(body_.uppercased()); show("upper")
        case "lower": setBody(body_.lowercased()); show("lower")
        case "count":
            let w = body_.split { $0.isWhitespace || $0.isNewline }.count
            show("\(w)w · \(body_.components(separatedBy: "\n").count)l · \(body_.count)c")
        case "sum": let s = numbers(in: body_).reduce(0, +); appendLine("total = \(Fmt.trim(s))"); show("sum \(Fmt.trim(s))")
        case "avg": let n = numbers(in: body_); let a = n.isEmpty ? 0 : n.reduce(0, +)/Double(n.count); appendLine("avg = \(Fmt.trim(a))"); show("avg \(Fmt.trim(a))")
        case "calc": if let v = Calc.evaluate(arg) { appendLine("\(arg) = \(Fmt.trim(v))"); show(Fmt.trim(v)) } else { show("bad expression") }
        case "roll": let s = max(2, Int(arg) ?? 6); let r = Int.random(in: 1...s); appendLine("🎲 \(r)"); show("rolled \(r)")
        case "flip": let h = Bool.random(); appendLine(h ? "heads" : "tails"); show(h ? "heads" : "tails")
        case "pick":
            let opts = arg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let c = opts.randomElement() { appendLine("→ \(c)"); show(c) } else { show("usage: /pick a, b, c") }
        case "help": showCommands = true
        default: show("? /\(name)")
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
