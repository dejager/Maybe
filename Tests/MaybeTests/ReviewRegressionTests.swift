import Foundation
import Testing
@testable import Maybe

/// Regression cases discovered during independent integration review.
struct ReviewRegressionTests {
    private var offline: ClosureProvider {
        ClosureProvider(write: { _, _ in throw MaybeError("Unexpected model call") },
                        judge: { _, _ in throw MaybeError("Unexpected model call") })
    }

    @Test("Every recording exported by a valid run can be imported again")
    func largeRecordingRoundTrip() async throws {
        let engine = Maybe(provider: offline)
        let recording = try await engine.run(String(repeating: "print(input())\n", count: 200),
                                             input: String(repeating: "x", count: 6_000))
        let data = try recording.json()
        // Output appears both in the output array and in the trace. A valid program
        // exceeds the old 2 MB limit even without large model results or Unicode.
        #expect(data.count > 2_000_000)
        let decoded = try Recording.decode(data)
        #expect(try await engine.replay(decoded).output == recording.output)
    }

    @Test("Maximum escaped model output remains exportable and replayable")
    func escapedRecordingRoundTrip() async throws {
        // NUL requires six JSON bytes per UTF-16 unit. Use both the 12-call and
        // 200-statement budgets, with generated text also repeated as context.
        let generated = String(repeating: "\u{0}", count: 12_000)
        let provider = ClosureProvider(write: { _, _ in generated },
                                       judge: { _, _ in throw MaybeError("Unexpected judgment") })
        let source = "let text = llm \"hello\"\n"
            + String(repeating: "print(llm \"again\" using text)\n", count: 11)
            + String(repeating: "print(text)\n", count: 188)
        let recording = try await Maybe(provider: provider).run(source)
        let data = try recording.json()
        #expect(data.count > 31_000_000)
        let decoded = try Recording.decode(data)
        #expect(try await Maybe(provider: offline).replay(decoded).output == recording.output)
    }

    @Test("The built-in demo honors empty but distinct language labels")
    func emptyLanguageLabels() async throws {
        let engine = Maybe(provider: DemoProvider())
        let matched = try await engine.run(#"match input() { "" => { print("empty") } "other" => { print("other") } }"#)
        #expect(matched.output.count == 1)
        let conditional = try await engine.run(#"if input() feels "" { print("yes") } else { print("no") }"#)
        #expect(conditional.output.count == 1)
    }

    @Test("The proxy forwards empty labels without rewriting them")
    func emptyProxyLabel() async throws {
        let transport = HTTPTransport { request, _ in
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            guard case .object(let object) = body else { throw MaybeError("Expected object") }
            #expect(object["labels"] == .array([.string(""), .string("other")]))
            let data = Data(#"{"probabilities":{"":0.7,"other":0.3}}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let provider = try ProxyProvider(endpoint: URL(string: "https://example.invalid/model")!, bearerToken: "token", transport: transport)
        #expect(try await provider.judge(value: .string("hello"), labels: ["", "other"]) == ["": 0.7, "other": 0.3])
    }

    @Test("Malformed optional draws fail even outside chaos", arguments: [-0.1, 1.0, Double.nan, Double.infinity])
    func malformedOptionalDraw(draw: Double) async throws {
        let effect = Effect(kind: .write, args: .object(["prompt": .string("hello")]), result: .string("text"), draw: draw)
        let recording = Recording(source: #"print(llm "hello")"#, input: "", tape: [effect], output: [], trace: [])
        await #expect(throws: MaybeError.self) { try await Maybe(provider: offline).replay(recording) }
    }
}
