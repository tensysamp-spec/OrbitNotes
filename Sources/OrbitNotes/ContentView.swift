import SwiftUI
import AppKit

// MARK: - Themes

struct Palette: Identifiable {
    let id: String
    let isLight: Bool
    let bgHex: UInt
    let textHex: UInt
    let dimHex: UInt
    let accentHex: UInt
    let resultHex: UInt
    let labelHex: UInt

    var bg: Color { col(bgHex) }
    var text: Color { col(textHex) }
    var dim: Color { col(dimHex) }
    var accent: Color { col(accentHex) }
    var result: Color { col(resultHex) }
    var label: Color { col(labelHex) }

    var nsText: NSColor { ns(textHex) }
    var nsDim: NSColor { ns(dimHex) }
    var nsAccent: NSColor { ns(accentHex) }
    var nsResult: NSColor { ns(resultHex) }
    var nsLabel: NSColor { ns(labelHex) }

    private func col(_ h: UInt) -> Color {
        Color(red: Double((h >> 16) & 0xff)/255, green: Double((h >> 8) & 0xff)/255, blue: Double(h & 0xff)/255)
    }
    private func ns(_ h: UInt) -> NSColor {
        NSColor(srgbRed: CGFloat((h >> 16) & 0xff)/255, green: CGFloat((h >> 8) & 0xff)/255, blue: CGFloat(h & 0xff)/255, alpha: 1)
    }
}

let kPalettes: [Palette] = [
    Palette(id: "white",    isLight: true,  bgHex: 0xfbfbf9, textHex: 0x2a2a2a, dimHex: 0xafaba0, accentHex: 0x2f6bff, resultHex: 0x1f9d55, labelHex: 0x0e9c9c),
    Palette(id: "paper",    isLight: true,  bgHex: 0xf3efe4, textHex: 0x2c2a25, dimHex: 0xa89f8c, accentHex: 0xb5622f, resultHex: 0x5f8a2f, labelHex: 0x2f8a8a),
    Palette(id: "mono",     isLight: false, bgHex: 0x0d1117, textHex: 0xdbe4ef, dimHex: 0x5b6472, accentHex: 0x9d8bff, resultHex: 0x5be08a, labelHex: 0x4fd1c5),
    Palette(id: "matrix",   isLight: false, bgHex: 0x061109, textHex: 0xbfead0, dimHex: 0x2f6b45, accentHex: 0x9dff70, resultHex: 0x38f58a, labelHex: 0x35d0a0),
    Palette(id: "tokyo",    isLight: false, bgHex: 0x1a1b26, textHex: 0xc0caf5, dimHex: 0x565f89, accentHex: 0xbb9af7, resultHex: 0x9ece6a, labelHex: 0x7dcfff),
    Palette(id: "vendetta", isLight: false, bgHex: 0x14090b, textHex: 0xe6c9c9, dimHex: 0x7a4a4f, accentHex: 0xff8b96, resultHex: 0xff5d6c, labelHex: 0xff9d5c),
    Palette(id: "a24",      isLight: false, bgHex: 0x0e0e10, textHex: 0xededed, dimHex: 0x6a6a70, accentHex: 0xff6a4d, resultHex: 0x7ad1a0, labelHex: 0xe0b25c),
]

func palette(named name: String) -> Palette { kPalettes.first { $0.id == name } ?? kPalettes[0] }

// MARK: - Formatting

enum Fmt {
    static func num(_ v: Double, decimals: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = decimals
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
    static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.4g", v)
    }
}

// MARK: - Math engine (variables, descriptive math, conversions)

enum Eval {
    static func variables(_ text: String) -> [String: Double] {
        var vars: [String: Double] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var rhs = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            rhs = rhs.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            if !name.isEmpty, name.count <= 40, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }),
               let v = Double(rhs) {
                vars[name] = v
            }
        }
        return vars
    }

    static func result(for rawLine: String, vars: [String: Double]) -> String? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return nil }
        if let c = convert(line) { return c }

        if let colon = line.firstIndex(of: ":") {
            let rhs = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if Double(rhs.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) != nil {
                return nil
            }
        }

        var expr = line
        if let colon = line.firstIndex(of: ":") { expr = String(line[line.index(after: colon)...]) }
        guard expr.contains(where: { "+-*/".contains($0) }) else { return nil }

        var s = " " + expr.lowercased() + " "
        for (name, value) in vars.sorted(by: { $0.key.count > $1.key.count }) {
            s = s.replacingOccurrences(of: name, with: " \(value) ")
        }
        let cleaned = String(s.filter { "0123456789.+-*/() ".contains($0) })
        guard cleaned.filter({ $0.isNumber }).count >= 1, let v = Calc.evaluate(cleaned) else { return nil }
        return Fmt.trim(v)
    }

    private static let units: [String: (String, Double)] = [
        "km": ("len", 1000), "m": ("len", 1), "cm": ("len", 0.01), "mm": ("len", 0.001),
        "mi": ("len", 1609.34), "mile": ("len", 1609.34), "miles": ("len", 1609.34),
        "ft": ("len", 0.3048), "feet": ("len", 0.3048), "foot": ("len", 0.3048),
        "in": ("len", 0.0254), "inch": ("len", 0.0254), "inches": ("len", 0.0254),
        "yd": ("len", 0.9144), "yard": ("len", 0.9144), "yards": ("len", 0.9144),
        "kg": ("wt", 1000), "g": ("wt", 1), "mg": ("wt", 0.001),
        "lb": ("wt", 453.592), "lbs": ("wt", 453.592), "pound": ("wt", 453.592), "pounds": ("wt", 453.592),
        "oz": ("wt", 28.3495), "ounce": ("wt", 28.3495), "ounces": ("wt", 28.3495),
        "usd": ("cur", 1), "eur": ("cur", 1.09), "gbp": ("cur", 1.27), "jpy": ("cur", 0.0066),
        "aed": ("cur", 0.27), "cad": ("cur", 0.73), "aud": ("cur", 0.66), "chf": ("cur", 1.13),
        "cny": ("cur", 0.14), "inr": ("cur", 0.012), "btc": ("cur", 62000), "eth": ("cur", 3000),
    ]

    static func convert(_ line: String) -> String? {
        let lower = line.lowercased()
        guard lower.contains(" to ") else { return nil }
        let parts = lower.components(separatedBy: " to ")
        guard parts.count == 2 else { return nil }
        let left = parts[0], right = parts[1].trimmingCharacters(in: .whitespaces)

        var numStr = ""
        for ch in left.replacingOccurrences(of: ",", with: "") where ch.isNumber || ch == "." { numStr.append(ch) }
        guard let value = Double(numStr) else { return nil }

        let leftWords = left.replacingOccurrences(of: "$", with: " ").split { !($0.isLetter) }.map(String.init)
        guard let srcKey = leftWords.first(where: { units[$0] != nil }), let src = units[srcKey] else { return nil }

        let dstKey = right.split { !($0.isLetter) }.map(String.init).first(where: { units[$0] != nil }) ?? right
        guard let dst = units[dstKey], dst.0 == src.0 else { return nil }

        let out = value * src.1 / dst.1
        let label = dst.0 == "cur" ? dstKey.uppercased() : dstKey
        return "\(Fmt.num(out, decimals: 2)) \(label)"
    }
}

// MARK: - Command catalog

struct Cmd: Identifiable {
    let name: String; let args: String; let desc: String
    var id: String { name }
    var noArgs: Bool { args.isEmpty }
}

let kCommands: [Cmd] = [
    Cmd(name: "new", args: "[title]", desc: "create a new note"),
    Cmd(name: "del", args: "", desc: "delete this note"),
    Cmd(name: "next", args: "", desc: "next note"),
    Cmd(name: "prev", args: "", desc: "previous note"),
    Cmd(name: "open", args: "<n>", desc: "open note number n"),
    Cmd(name: "title", args: "<text>", desc: "rename this note"),
    Cmd(name: "pin", args: "", desc: "pin / unpin note"),
    Cmd(name: "clear", args: "", desc: "erase this note"),
    Cmd(name: "copy", args: "", desc: "copy note to clipboard"),
    Cmd(name: "timer", args: "[min]", desc: "start a focus timer"),
    Cmd(name: "pom", args: "", desc: "start a 25-min pomodoro"),
    Cmd(name: "stop", args: "", desc: "stop the timer"),
    Cmd(name: "goal", args: "<n>", desc: "set daily word goal"),
    Cmd(name: "remind", args: "<30m|2h>", desc: "reminder for this note"),
    Cmd(name: "white", args: "", desc: "white theme"),
    Cmd(name: "dark", args: "", desc: "dark theme"),
    Cmd(name: "theme", args: "[name]", desc: "set / cycle theme"),
    Cmd(name: "grid", args: "", desc: "toggle grid paper"),
    Cmd(name: "date", args: "", desc: "insert today's date"),
    Cmd(name: "time", args: "", desc: "insert the time"),
    Cmd(name: "now", args: "", desc: "insert date + time"),
    Cmd(name: "todo", args: "", desc: "insert a checkbox"),
    Cmd(name: "done", args: "", desc: "check all boxes"),
    Cmd(name: "bullet", args: "", desc: "bullet every line"),
    Cmd(name: "number", args: "", desc: "number every line"),
    Cmd(name: "sort", args: "", desc: "sort lines A→Z"),
    Cmd(name: "rev", args: "", desc: "reverse lines"),
    Cmd(name: "shuffle", args: "", desc: "shuffle lines"),
    Cmd(name: "dedup", args: "", desc: "remove duplicate lines"),
    Cmd(name: "trim", args: "", desc: "remove blank lines"),
    Cmd(name: "upper", args: "", desc: "UPPERCASE"),
    Cmd(name: "lower", args: "", desc: "lowercase"),
    Cmd(name: "count", args: "", desc: "word / line / char count"),
    Cmd(name: "sum", args: "", desc: "sum every number"),
    Cmd(name: "avg", args: "", desc: "average every number"),
    Cmd(name: "calc", args: "<expr>", desc: "calculate"),
    Cmd(name: "roll", args: "[n]", desc: "roll a dice"),
    Cmd(name: "flip", args: "", desc: "flip a coin"),
    Cmd(name: "pick", args: "a, b, c", desc: "pick at random"),
    Cmd(name: "help", args: "", desc: "show commands"),
]

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

    private func setBody(_ s: String) { store.selectedNote?.wrappedValue.body = s }
    private func appendLine(_ s: String) {
        let b = body_
        if b.isEmpty { setBody(s) } else if b.hasSuffix("\n") { setBody(b + s) } else { setBody(b + "\n" + s) }
    }
