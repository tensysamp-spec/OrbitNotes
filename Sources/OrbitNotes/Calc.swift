import Foundation

/// A tiny, crash-safe arithmetic evaluator: + - * / ( ) and decimals.
/// Returns nil for anything it can't parse, instead of throwing.
enum Calc {
    static func evaluate(_ input: String) -> Double? {
        let tokens = tokenize(input)
        guard !tokens.isEmpty, let rpn = toRPN(tokens) else { return nil }
        return evalRPN(rpn)
    }

    private enum Token: Equatable { case num(Double), op(Character), lparen, rparen }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || c == "." {
                var num = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    num.append(chars[i]); i += 1
                }
                guard let value = Double(num) else { return [] }
                tokens.append(.num(value))
                continue
            }
            switch c {
            case "+", "-", "*", "/", "×", "÷":
                let norm: Character = c == "×" ? "*" : (c == "÷" ? "/" : c)
                tokens.append(.op(norm))
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            default: return []   // unknown character → invalid
            }
            i += 1
        }
        return tokens
    }

    private static func precedence(_ op: Character) -> Int { (op == "+" || op == "-") ? 1 : 2 }

    private static func toRPN(_ tokens: [Token]) -> [Token]? {
        var output: [Token] = []
        var stack: [Token] = []
        for token in tokens {
            switch token {
            case .num: output.append(token)
            case .op(let o):
                while case let .op(top) = stack.last, precedence(top) >= precedence(o) {
                    output.append(stack.removeLast())
                }
                stack.append(token)
            case .lparen: stack.append(token)
            case .rparen:
                while let last = stack.last, last != .lparen { output.append(stack.removeLast()) }
                guard stack.last == .lparen else { return nil }
                stack.removeLast()
            }
        }
        while let last = stack.last {
            if last == .lparen || last == .rparen { return nil }
            output.append(stack.removeLast())
        }
        return output
    }

    private static func evalRPN(_ rpn: [Token]) -> Double? {
        var stack: [Double] = []
        for token in rpn {
            switch token {
            case .num(let v): stack.append(v)
            case .op(let o):
                guard stack.count >= 2 else { return nil }
                let b = stack.removeLast(), a = stack.removeLast()
                switch o {
                case "+": stack.append(a + b)
                case "-": stack.append(a - b)
                case "*": stack.append(a * b)
                case "/": guard b != 0 else { return nil }; stack.append(a / b)
                default: return nil
                }
            default: return nil
            }
        }
        return stack.count == 1 ? stack.first : nil
    }
}
