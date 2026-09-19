import SwiftUI
import AppKit

// MARK: - Custom highlighting + inline-result text editor

struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    let pal: Palette

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = ResultTextView()
        tv.pal = pal
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textColor = pal.nsText
        tv.insertionPointColor = pal.nsAccent
        tv.textContainerInset = NSSize(width: 10, height: 14)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text
        tv.highlight()

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ResultTextView else { return }
        tv.pal = pal
        tv.insertionPointColor = pal.nsAccent
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        }
        tv.highlight()
        tv.needsDisplay = true
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeTextView
        init(_ p: CodeTextView) { parent = p }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? ResultTextView else { return }
            parent.text = tv.string
            tv.highlight()
            tv.needsDisplay = true
        }
    }
}

/// NSTextView that syntax-highlights and draws each line's computed result in the right margin.
final class ResultTextView: NSTextView {
    var pal: Palette = kPalettes[0]

    private static let number = try? NSRegularExpression(pattern: "[0-9][0-9.,]*")

    func highlight() {
        guard let ts = textStorage else { return }
        let nsStr = string as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        let baseFont = font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)

        ts.beginEditing()
        ts.setAttributes([.font: baseFont, .foregroundColor: pal.nsText], range: full)

        nsStr.enumerateSubstrings(in: full, options: .byLines) { sub, lineRange, _, _ in
            guard let line = sub, lineRange.length > 0 else { return }
            let loc = lineRange.location
            let ns = line as NSString

            if loc == 0 {
                ts.addAttribute(.foregroundColor, value: self.pal.nsAccent, range: lineRange)
                ts.addAttribute(.font, value: boldFont, range: lineRange)
            }

            if ns.hasPrefix("[x]") {
                ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
                ts.addAttribute(.foregroundColor, value: self.pal.nsDim, range: lineRange)
                ts.addAttribute(.foregroundColor, value: self.pal.nsResult, range: NSRange(location: loc, length: 3))
            } else if ns.hasPrefix("[ ]") {
                ts.addAttribute(.foregroundColor, value: self.pal.nsDim, range: NSRange(location: loc, length: 3))
            }

            if loc != 0 {
                let colon = ns.range(of: ":").location
                if colon != NSNotFound, colon < 40 {
                    ts.addAttribute(.foregroundColor, value: self.pal.nsLabel, range: NSRange(location: loc, length: colon))
                    ts.addAttribute(.foregroundColor, value: self.pal.nsAccent, range: NSRange(location: loc + colon, length: 1))
                }
            }

            if let re = ResultTextView.number {
                re.enumerateMatches(in: self.string, options: [], range: lineRange) { m, _, _ in
                    if let r = m?.range { ts.addAttribute(.foregroundColor, value: self.pal.nsText, range: r) }
                }
            }
        }
        ts.endEditing()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        let nsStr = string as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        let vars = Eval.variables(string)
        let f = font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: pal.nsResult]

        nsStr.enumerateSubstrings(in: full, options: .byLines) { sub, lineRange, _, _ in
            guard let line = sub, let res = Eval.result(for: line, vars: vars) else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            rect.origin.x += self.textContainerInset.width
            rect.origin.y += self.textContainerInset.height
            let str = "= \(res)" as NSString
            let size = str.size(withAttributes: attrs)
            let x = self.bounds.width - self.textContainerInset.width - size.width - 4
            let usedRight = rect.maxX + 12
            let drawX = max(x, usedRight)
            if drawX + size.width <= self.bounds.width - 4 {
                str.draw(at: NSPoint(x: drawX, y: rect.minY), withAttributes: attrs)
            }
        }
    }
}

// MARK: - Grid / translucency / window

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

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = material; v.blendingMode = .behindWindow; v.state = .active; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false; w.backgroundColor = .clear
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
