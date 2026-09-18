import Testing
@testable import Maybe

@Suite("Maybe grammar")
struct ParserTests {
    @Test("All statements preserve their starting source line")
    func completeProgram() throws {
        let source = """
        // A small tour of every statement.
        let message = input();
        message = llm "Make it kind" using message
        print(message)
        if message feels "kind" with confidence 75% { print(true) }
        otherwise maybe { print("uncertain") } else { print(false) }
        match message { "calm" => { print(1) } "urgent" => { print(2) } }
        while message feels "too long" { message = write "Shorten" using message }
        repeat 2 { print("again") }
        chaos { print("surprise") }
        """
        let statements = try Parser.parse(source)
        #expect(statements.map(\.line) == [2, 3, 4, 5, 7, 8, 9, 10])
        #expect(statements[0].kind == .declare(name: "message", value: .input))
        #expect(statements[1].kind == .assign(name: "message", value: .write(prompt: "Make it kind", context: .variable("message"))))
        guard case let .conditional(value, question, confidence, yes, maybe, no) = statements[3].kind else {
            Issue.record("Expected a conditional"); return
        }
        #expect(value == .variable("message"))
        #expect(question == "kind")
        #expect(confidence == 0.75)
        #expect(yes.first?.kind == .print(.literal(.bool(true))))
        #expect(maybe.first?.kind == .print(.literal(.string("uncertain"))))
        #expect(no.first?.kind == .print(.literal(.bool(false))))
    }

    @Test("Strings use JSON escapes and never become keywords")
    func strings() throws {
        let statements = try Parser.parse(#"print("\"\\\/\b\f\n\r\t\u0041\uD83D\uDE80") print("true") print("}")"#)
        #expect(statements[0].kind == .print(.literal(.string("\"\\/\u{8}\u{C}\n\r\tA🚀"))))
        #expect(statements[1].kind == .print(.literal(.string("true"))))
        #expect(statements[2].kind == .print(.literal(.string("}"))))
    }

    @Test("Comments and semicolons are optional separators")
    func separators() throws {
        let statements = try Parser.parse("; // greeting\n; print(\"https://example.com\"); ;\n print(0) // done")
        #expect(statements.map(\.line) == [2, 3])
        #expect(statements[0].kind == .print(.literal(.string("https://example.com"))))
        #expect(try Parser.parse(";;; // nothing").isEmpty)
    }

    @Test("Aliases and generation context values")
    func generation() throws {
        #expect(try Parser.parse(#"print(llm "hello")"#) == Parser.parse(#"print(write "hello")"#))
        let values: [(String, Expression)] = [
            (#""words""#, .literal(.string("words"))), ("1.25", .literal(.number(1.25))),
            ("false", .literal(.bool(false))), ("input()", .input), ("_item2", .variable("_item2"))
        ]
        for (source, expected) in values {
            let statement = try #require(Parser.parse("let response = llm \"summarize\" using \(source)").first)
            #expect(statement.kind == .declare(name: "response", value: .write(prompt: "summarize", context: expected)))
        }
    }

    @Test("Defaults, empty blocks, and nested declarations survive in the tree")
    func blocks() throws {
        let statement = try #require(Parser.parse(#"if "x" feels "y" { let a = 1 chaos { let a = 2 } }"#).first)
        guard case let .conditional(_, _, confidence, yes, maybe, no) = statement.kind else {
            Issue.record("Expected a conditional"); return
        }
        #expect(confidence == 0.5)
        #expect(maybe.isEmpty && no.isEmpty)
        #expect(yes[0].kind == .declare(name: "a", value: .literal(.number(1))))
        guard case let .chaos(nested) = yes[1].kind else { Issue.record("Expected chaos"); return }
        #expect(nested[0].kind == .declare(name: "a", value: .literal(.number(2))))
        #expect(try Parser.parse("repeat 1.0 {}").first?.kind == .repeatCount(1, body: []))
    }

    @Test("Match retains label order, including empty labels")
    func matchLabels() throws {
        let statement = try #require(Parser.parse(#"match input() { "" => {} "else" => {} "🚀" => {} }"#).first)
        guard case let .match(value, branches) = statement.kind else { Issue.record("Expected match"); return }
        #expect(value == .input)
        #expect(branches.map(\.label) == ["", "else", "🚀"])
        let eight = (0..<8).map { "\"label\($0)\" => {}" }.joined(separator: " ")
        #expect(try Parser.parse("match true { \(eight) }").count == 1)
    }

    @Test("Malformed input produces a readable language error", arguments: [
        "let", "let = 1", "let true = 1", "let café = 1", "let item =", "print", "print(",
        "print()", "print(1", "print(1))", "print(-1)", "print(1e3)", "print(.5)", "print(1.)",
        "print(1 + 1)", "print(input)", "print(input(1))",
        "{", "}", "chaos {", "chaos {} }", "repeat 0 {}", "repeat 6 {}", "repeat 1.5 {}",
        "repeat true {}", "repeat", "if true {}", "if true feels false {}",
        "if true feels \"x\" with confidence 49% {}", "if true feels \"x\" with confidence 101% {}",
        "if true feels \"x\" with confidence 75 {}", "if true feels \"x\" with confidence true% {}",
        "if true feels \"x\" {} otherwise {}", "if true feels \"x\" {} else {} otherwise maybe {}",
        "match input() {}", "match input() { \"a\" => {} }", "match input() { \"a\" => {} \"a\" => {} }",
        "match input() { \"a\" {} \"b\" => {} }", "match input() { \"a\" => {} ; \"b\" => {} }",
        "while input() feels \"x\"", "print(llm input())", "print(llm \"a\" using llm \"b\")",
        "if llm \"a\" feels \"x\" {}", "match write \"a\" {}", "while llm \"a\" feels \"x\" {}",
        "print(\"unterminated)", "print(\"raw\nnewline\")", "print(\"tab\tcharacter\")",
        #"print("\q")"#, #"print("\uZZZZ")"#, #"print("\uD800")"#, #"print("\uDC00")"#,
        "print(\"trailing\\", "/* comment */"
    ])
    func malformed(_ source: String) {
        #expect(throws: MaybeError.self) { try Parser.parse(source) }
    }

    @Test("Confidence accepts both bounds and fractional percentages")
    func confidence() throws {
        for percentage in [50.0, 50.5, 100.0] {
            let statement = try #require(Parser.parse("if true feels \"certain\" with confidence \(percentage)% {}").first)
            guard case let .conditional(_, _, confidence, _, _, _) = statement.kind else { Issue.record("Expected if"); return }
            #expect(confidence == percentage / 100)
        }
    }

    @Test("More than eight match branches are rejected")
    func branchLimit() {
        let branches = (0..<9).map { "\"label\($0)\" => {}" }.joined(separator: " ")
        #expect(throws: MaybeError.self) { try Parser.parse("match true { \(branches) }") }
    }

    @Test("Source budget counts UTF-16 units, not graphemes")
    func sourceLimit() throws {
        let boundary = "//" + String(repeating: "🚀", count: 5_999)
        #expect(boundary.utf16.count == 12_000)
        #expect(try Parser.parse(boundary).isEmpty)
        #expect(throws: MaybeError.self) { try Parser.parse(boundary + " ") }
        #expect(try Parser.parse(String(repeating: " ", count: 12_000)).isEmpty)
        #expect(throws: MaybeError.self) { try Parser.parse(String(repeating: " ", count: 12_001)) }
    }

    @Test("Twelve block levels are supported, thirteen are rejected")
    func nestingLimit() throws {
        func program(_ depth: Int) -> String { String(repeating: "chaos {", count: depth) + "print(1)" + String(repeating: "}", count: depth) }
        #expect(try Parser.parse(program(12)).count == 1)
        #expect(throws: MaybeError.self) { try Parser.parse(program(13)) }
        // Siblings release their depth; repeated shallow blocks do not accumulate nesting.
        #expect(try Parser.parse(String(repeating: "chaos {} ", count: 100)).count == 100)
    }

    @Test("Overflowing number literals are rejected")
    func finiteNumbers() {
        #expect(throws: MaybeError.self) { try Parser.parse("print(\(String(repeating: "9", count: 400)))") }
    }

    @Test("Errors point to their source line")
    func errorLine() {
        do {
            _ = try Parser.parse("// header\nprint(1)\nrepeat 7 {}")
            Issue.record("Expected a failure")
        } catch let error as MaybeError {
            #expect(error.line == 3)
            #expect(error.description == "Line 3: Repeat needs an integer from 1 to 5.")
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}
