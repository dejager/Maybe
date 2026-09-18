import Foundation

/// A recursive-descent parser for Maybe 0.1's deliberately small grammar.
/// No expression evaluates host code, imports modules, or invokes arbitrary functions.
struct Parser {
    private static let reserved: Set<String> = [
        "let", "print", "if", "feels", "with", "confidence", "otherwise", "maybe", "else",
        "match", "repeat", "while", "chaos", "llm", "write", "using", "input", "true", "false"
    ]
    private let tokens: [Token]
    private var position = 0
    private var depth = 0

    static func parse(_ source: String) throws -> [Statement] {
        var parser = Parser(tokens: try Lexer.tokenize(source))
        let body = try parser.statements()
        guard parser.current.kind == .end else {
            throw MaybeError("Unexpected closing brace.", line: parser.current.line)
        }
        return body
    }

    private var current: Token { tokens[position] }
    private func isToken(_ text: String) -> Bool { current.kind != .string && current.text == text }
    private mutating func take() -> Token {
        let token = current
        // Keep a stable end sentinel, even when incomplete input asks for another token.
        if token.kind != .end { position += 1 }
        return token
    }
    private mutating func accept(_ text: String) -> Bool {
        guard isToken(text) else { return false }
        _ = take()
        return true
    }
    private mutating func require(_ text: String) throws {
        guard accept(text) else {
            throw MaybeError("Expected \(text), got \(current.text).", line: current.line)
        }
    }
    private mutating func quotedString() throws -> String {
        let token = take()
        guard token.kind == .string else { throw MaybeError("Expected a quoted string.", line: token.line) }
        return token.text
    }
    private mutating func variableName() throws -> String {
        let token = take()
        guard token.kind == .word, !Self.reserved.contains(token.text) else {
            throw MaybeError("Expected a variable name.", line: token.line)
        }
        return token.text
    }

    private mutating func expression(allowGeneration: Bool = true) throws -> Expression {
        let token = current
        if token.kind == .string { _ = take(); return .literal(.string(token.text)) }
        if token.kind == .number {
            _ = take()
            guard let value = Double(token.text), value.isFinite else {
                throw MaybeError("Numbers must be finite.", line: token.line)
            }
            return .literal(.number(value))
        }
        if accept("true") { return .literal(.bool(true)) }
        if accept("false") { return .literal(.bool(false)) }
        if accept("input") {
            try require("("); try require(")")
            return .input
        }
        if isToken("llm") || isToken("write") {
            guard allowGeneration else {
                throw MaybeError("Assign generated text before using it.", line: token.line)
            }
            _ = take()
            let prompt = try quotedString()
            let context = accept("using") ? try expression(allowGeneration: false) : nil
            return .write(prompt: prompt, context: context)
        }
        return .variable(try variableName())
    }

    private mutating func block() throws -> [Statement] {
        try require("{")
        depth += 1
        guard depth <= 12 else { throw MaybeError("Nesting exceeds 12 blocks.", line: current.line) }
        defer { depth -= 1 }
        let body = try statements()
        try require("}")
        return body
    }

    private mutating func statements() throws -> [Statement] {
        var result: [Statement] = []
        while current.kind != .end, !isToken("}") {
            if accept(";") { continue }
            let line = current.line
            let kind: Statement.Kind
            if accept("let") {
                let name = try variableName()
                try require("=")
                kind = .declare(name: name, value: try expression())
            } else if accept("print") {
                try require("(")
                let value = try expression()
                try require(")")
                kind = .print(value)
            } else if accept("if") {
                let value = try expression(allowGeneration: false)
                try require("feels")
                let question = try quotedString()
                var confidence = 0.5
                if accept("with") {
                    try require("confidence")
                    let token = take()
                    guard token.kind == .number, let percentage = Double(token.text), (50...100).contains(percentage) else {
                        throw MaybeError("Confidence must be 50–100%.", line: token.line)
                    }
                    confidence = percentage / 100
                    try require("%")
                }
                let yes = try block()
                var maybe: [Statement] = []
                if accept("otherwise") { try require("maybe"); maybe = try block() }
                let no = accept("else") ? try block() : []
                kind = .conditional(value: value, question: question, confidence: confidence, yes: yes, maybe: maybe, no: no)
            } else if accept("match") {
                let value = try expression(allowGeneration: false)
                try require("{")
                var branches: [Statement.Branch] = []
                while !isToken("}"), current.kind != .end {
                    let label = try quotedString()
                    try require("=>")
                    branches.append(.init(label: label, body: try block()))
                }
                try require("}")
                guard (2...8).contains(branches.count), Set(branches.map(\.label)).count == branches.count else {
                    throw MaybeError("Match needs 2–8 distinct labels.", line: line)
                }
                // The match's outer braces group labels; branch bodies alone introduce scope.
                kind = .match(value: value, branches: branches)
            } else if accept("while") {
                let value = try expression(allowGeneration: false)
                try require("feels")
                let question = try quotedString()
                kind = .loop(value: value, question: question, body: try block())
            } else if accept("repeat") {
                let token = take()
                guard token.kind == .number, let count = Double(token.text), count.rounded() == count, (1...5).contains(count) else {
                    throw MaybeError("Repeat needs an integer from 1 to 5.", line: token.line)
                }
                kind = .repeatCount(Int(count), body: try block())
            } else if accept("chaos") {
                kind = .chaos(try block())
            } else {
                let name = try variableName()
                try require("=")
                kind = .assign(name: name, value: try expression())
            }
            result.append(Statement(line: line, kind: kind))
        }
        return result
    }
}
