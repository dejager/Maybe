import Foundation
import Testing
@testable import Maybe

private struct Stub: ModelProvider {
    var yes = 0.9
    var text = "plain"
    func write(prompt: String, context: Value?) async throws -> String { text }
    func judge(value: Value, labels: [String]) async throws -> [String: Double] {
        Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0 == 0 ? yes : (1 - yes) / Double(labels.count - 1)) })
    }
}

private struct NoCalls: ModelProvider {
    func write(prompt: String, context: Value?) async throws -> String { throw MaybeError("Unexpected write") }
    func judge(value: Value, labels: [String]) async throws -> [String: Double] { throw MaybeError("Unexpected judge") }
}

private let confidenceProgram = #"if input() feels "urgent" with confidence 80% { print("yes") } otherwise maybe { print("maybe") } else { print("no") }"#

@Test(arguments: [(0.91, "yes"), (0.60, "maybe"), (0.09, "no"), (0.80, "yes")])
func symmetricConfidence(example: (Double, String)) async throws {
    let result = try await Maybe(provider: Stub(yes: example.0)).run(confidenceProgram)
    #expect(result.output == [example.1])
}

@Test func scopesAssignmentsAndPrimitiveOutput() async throws {
    let result = try await Maybe(provider: NoCalls()).run(#"let x="outer" repeat 2 { let local="inner" x=local } print(x) print(3) print(true)"#)
    #expect(result.output == ["inner", "3", "true"])
    await #expect(throws: MaybeError.self) { try await Maybe(provider: NoCalls()).run(#"repeat 1 { let x=1 } print(x)"#) }
    await #expect(throws: MaybeError.self) { try await Maybe(provider: NoCalls()).run("let x=1 let x=2") }
    let shadow = try await Maybe(provider: NoCalls()).run(#"let x="outer" repeat 1 { let x="inner" print(x) } print(x)"#)
    #expect(shadow.output == ["inner", "outer"])
}

@Test func tiedJudgmentsAndMissingMaybe() async throws {
    let tied = try await Maybe(provider: Stub(yes: 0.5)).run(#"if input() feels "ok" { print("yes") } else { print("no") }"#)
    #expect(tied.output == ["yes"])
    let match = try await Maybe(provider: Stub(yes: 0.5)).run(#"match input() { "first" => { print("first") } "second" => { print("second") } }"#)
    #expect(match.output == ["first"])
    let uncertain = try await Maybe(provider: Stub(yes: 0.6)).run(#"if input() feels "ok" with confidence 80% { print("yes") } else { print("no") }"#)
    #expect(uncertain.output.isEmpty)
}

@Test func chaosAndReplayPreserveMinorityOutcome() async throws {
    let source = #"let text=llm "rewrite" using input() chaos { if text feels "urgent" { print("yes") } else { print("no") } }"#
    let first = try await Maybe(provider: Stub(), timeout: .seconds(90), random: { 0.95 }).run(source, input: "jargon")
    #expect(first.output == ["no"])
    let encoded = try first.json()
    let decoded = try Recording.decode(encoded)
    let replay = try await Maybe(provider: NoCalls()).replay(decoded)
    #expect(replay == first)
    let gated = try await Maybe(provider: Stub(yes: 0.6), timeout: .seconds(90), random: { 0.01 }).run("chaos { \(confidenceProgram) }")
    #expect(gated.output == ["maybe"])
}

@Test func whileReevaluatesAndHonorsBudget() async throws {
    struct Rewriter: ModelProvider {
        func write(prompt: String, context: Value?) async throws -> String { "plain" }
        func judge(value: Value, labels: [String]) async throws -> [String: Double] {
            let yes = value == .string("jargon") ? 0.99 : 0.01
            return [labels[0]: yes, labels[1]: 1 - yes]
        }
    }
    let result = try await Maybe(provider: Rewriter()).run(#"let text=input() while text feels "jargon" { text=llm "fix" using text } print(text)"#, input: "jargon")
    #expect(result.output == ["plain"])
    #expect(result.tape.count == 3)
    await #expect(throws: MaybeError.self) { try await Maybe(provider: Stub()).run(#"while "x" feels "yes" { print("again") }"#) }
    await #expect(throws: MaybeError.self) { try await Maybe(provider: Stub()).run(#"repeat 5 { repeat 5 { print(llm "hello") } }"#) }
    await #expect(throws: MaybeError.self) { try await Maybe(provider: NoCalls()).run(#"repeat 5 { repeat 5 { repeat 5 { print("one") print("two") } } }"#) }
}

@Test func replayRejectsMissingExtraChangedAndInvalidEffects() async throws {
    let saved = try await Maybe(provider: Stub()).run(confidenceProgram, input: "one")
    func recording(source: String? = nil, input: String? = nil, tape: [Effect]? = nil, version: Int = 1) -> Recording {
        Recording(version: version, source: source ?? saved.source, input: input ?? saved.input, tape: tape ?? saved.tape, output: [], trace: [])
    }
    let engine = Maybe(provider: NoCalls())
    await #expect(throws: MaybeError.self) { try await engine.replay(recording(input: "two")) }
    await #expect(throws: MaybeError.self) { try await engine.replay(recording(tape: [])) }
    await #expect(throws: MaybeError.self) { try await engine.replay(recording(source: #"print("hi")"#)) }
    await #expect(throws: MaybeError.self) { try await engine.replay(recording(version: 2)) }
    let damaged = Effect(kind: .judge, args: saved.tape[0].args, result: .object(["urgent": .number(0.8)]))
    await #expect(throws: MaybeError.self) { try await engine.replay(recording(tape: [damaged])) }
}

@Test func explicitContextDoesNotLeakLocals() async throws {
    struct ContextChecker: ModelProvider {
        func write(prompt: String, context: Value?) async throws -> String {
            #expect(prompt == "rewrite")
            #expect(context == .string("public"))
            return "done"
        }
        func judge(value: Value, labels: [String]) async throws -> [String: Double] { throw MaybeError("unexpected") }
    }
    let result = try await Maybe(provider: ContextChecker()).run(#"let secret="not passed" print(llm "rewrite" using input())"#, input: "public")
    #expect(result.output == ["done"])
}

@Test func cancellationAndTimeoutDoNotEmitLateEffects() async throws {
    struct Slow: ModelProvider {
        func write(prompt: String, context: Value?) async throws -> String { try await Task.sleep(for: .seconds(10)); return "too late" }
        func judge(value: Value, labels: [String]) async throws -> [String: Double] { throw MaybeError("unexpected") }
    }
    let task = Task { try await Maybe(provider: Slow()).run(#"print(llm "hello")"#) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    await #expect(throws: MaybeError.self) {
        try await Maybe(provider: Slow(), timeout: .milliseconds(10)).run(#"print(llm "hello")"#)
    }
}

@Test func validationRejectsBadProbabilityAndOversizedIO() async throws {
    for raw: [String: Double] in [["a": 2, "b": -1], ["a": .nan, "b": 1], ["a": 0, "b": 0], ["a": 0.5], ["a": .infinity, "b": 0]] {
        #expect(throws: MaybeError.self) { try normalized(raw, labels: ["a", "b"]) }
    }
    #expect(try normalized(["a": 0.501, "b": 0.501], labels: ["a", "b"]) == ["a": 0.5, "b": 0.5])
    await #expect(throws: MaybeError.self) { try await Maybe(provider: NoCalls()).run("", input: String(repeating: "🦆", count: 3_001)) }
    await #expect(throws: MaybeError.self) { try await Maybe(provider: Stub(text: String(repeating: "x", count: 12_001))).run(#"print(llm "hello")"#) }
    await #expect(throws: MaybeError.self) { try await Maybe(provider: Stub(), timeout: .seconds(90), random: { .nan }).run(#"chaos { if "x" feels "ok" {} }"#) }
}

@Test func sameEngineRunsConcurrentlyWithoutSharedVariables() async throws {
    let engine = Maybe(provider: NoCalls())
    try await withThrowingTaskGroup(of: String.self) { group in
        for input in ["one", "two", "three"] { group.addTask { try await engine.run("let x=input() print(x)", input: input).output[0] } }
        var outputs: Set<String> = []
        for try await output in group { outputs.insert(output) }
        #expect(outputs == ["one", "two", "three"])
    }
}

@Test func numericOutputMatchesJavaScriptBoundaries() async throws {
    let result = try await Maybe(provider: NoCalls()).run("print(0.000001) print(0.0000001) print(100000000000000000000) print(1000000000000000000000)")
    #expect(result.output == ["0.000001", "1e-7", "100000000000000000000", "1e+21"])
}

@Test func replayRejectsCanonicallyEquivalentButChangedInput() async throws {
    let original = try await Maybe(provider: Stub()).run(confidenceProgram, input: "é")
    let changed = Recording(source: original.source, input: "e\u{301}", tape: original.tape, output: [], trace: [])
    await #expect(throws: MaybeError.self) { try await Maybe(provider: NoCalls()).replay(changed) }
}
