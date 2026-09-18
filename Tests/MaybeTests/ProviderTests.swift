import Foundation
import Testing
@testable import Maybe

struct ProviderTests {
    private let endpoint = URL(string: "https://example.invalid/probably")!

    private func transport(_ json: String, status: Int = 200,
                           inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) -> HTTPTransport {
        HTTPTransport { request, limit in
            #expect(limit == 1_000_000)
            try inspect(request)
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func demoIsDeterministicAndShowsUncertainty() async throws {
        let provider = DemoProvider()
        let labels = ["urgent", "NOT: urgent"]
        let urgent = try await provider.judge(value: .string("The site is down!"), labels: labels)
        let ambiguous = try await provider.judge(value: .string("Can we talk about the launch sometime today?"), labels: labels)
        #expect(urgent["urgent"] == 0.94)
        #expect(ambiguous["urgent"] == 0.52)
        #expect(try await provider.judge(value: .string("The site is down!"), labels: labels) == urgent)
        #expect(try await provider.write(prompt: "Rewrite", context: .string("Leverage synergies.")) == "use teamwork.")
    }

    @Test func proxyWritingContractPreservesTypedContext() async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "short-lived", transport: transport("{\"text\":\"  Hello!  \"}") { request in
            #expect(request.httpMethod == "POST")
            #expect(request.timeoutInterval == 25)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer short-lived")
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            #expect(body == .object(["operation": .string("write"), "prompt": .string("Greet"), "context": .bool(true)]))
        })
        #expect(try await provider.write(prompt: "Greet", context: .bool(true)) == "Hello!")
    }

    @Test func proxyNormalizesRoundingAndMapsLabels() async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "token", transport: transport("{\"probabilities\":{\"yes\":0.60,\"no\":0.39}}") { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            #expect(body == .object(["operation": .string("judge"), "value": .number(42), "labels": .array([.string("yes"), .string("no")])]))
        })
        let result = try await provider.judge(value: .number(42), labels: ["yes", "no"])
        #expect(abs(result["yes"]! - 0.6 / 0.99) < 0.000001)
        #expect(abs(result.values.reduce(0, +) - 1) < 0.000001)
    }

    @Test(arguments: [
        "{}", "{\"probabilities\":{\"yes\":0.5}}",
        "{\"probabilities\":{\"yes\":-0.1,\"no\":1.1}}",
        "{\"probabilities\":{\"yes\":0.1,\"no\":0.1}}",
        "{\"probabilities\":{\"yes\":true,\"no\":0}}",
        "{\"probabilities\":{\"yes\":1e999,\"no\":0}}",
        "{\"probabilities\":{\"yes\":\"NaN\",\"no\":0}}"
    ])
    func invalidJudgmentsFail(json: String) async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "token", transport: transport(json))
        await #expect(throws: MaybeError.self) { try await provider.judge(value: .string("hi"), labels: ["yes", "no"]) }
    }

    @Test(arguments: ["", "not JSON", "{\"text\":\" \"}", "{\"text\":42}"])
    func invalidWritingFails(json: String) async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "token", transport: transport(json))
        await #expect(throws: MaybeError.self) { try await provider.write(prompt: "hi", context: nil) }
    }

    @Test func httpErrorRedactsResponseAndToken() async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "secret-token", transport: transport("secret-token private user text", status: 401))
        await #expect(throws: MaybeError("Provider request failed (HTTP 401).")) { try await provider.write(prompt: "hi", context: nil) }
    }

    @Test func transportErrorsAreRedacted() async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "token", transport: HTTPTransport { _, _ in
            throw MaybeError("credential=secret")
        })
        await #expect(throws: MaybeError("Provider network request failed.")) { try await provider.write(prompt: "hi", context: nil) }
    }

    @Test func oversizedResponseFailsEvenWithCustomTransport() async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "token", transport: transport(String(repeating: "x", count: 1_000_001)))
        await #expect(throws: MaybeError("Provider response exceeds 1 MB.")) { try await provider.write(prompt: "hi", context: nil) }
    }

    @Test func cancellationPropagates() async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "token", transport: HTTPTransport { _, _ in throw URLError(.cancelled) })
        await #expect(throws: CancellationError.self) { try await provider.write(prompt: "hi", context: nil) }
    }

    @Test func timeoutHasSafeMessage() async throws {
        let provider = try ProxyProvider(endpoint: endpoint, bearerToken: "token", transport: HTTPTransport { _, _ in throw URLError(.timedOut) })
        await #expect(throws: MaybeError("Model request timed out after 25 seconds.")) { try await provider.write(prompt: "hi", context: nil) }
    }

    @Test func rejectsInsecureEndpointsAndHeaderInjection() throws {
        #expect(throws: MaybeError.self) { try ProxyProvider(endpoint: URL(string: "http://example.com")!, bearerToken: "token") }
        #expect(throws: MaybeError.self) { try ProxyProvider(endpoint: URL(string: "https://user:pass@example.com")!, bearerToken: "token") }
        #expect(throws: MaybeError.self) { try ProxyProvider(endpoint: endpoint, bearerToken: "token\r\nOther: injected") }
        #expect(throws: MaybeError.self) { try JevProvider(apiKey: "token\r\nOther: injected") }
    }

    @Test func directJevUsesOptionKeysAndMapsBackToLabels() async throws {
        let provider = try JevProvider(apiKey: "jev-secret", transport: transport("{\"answers\":{\"decision\":{\"probabilities\":{\"option_0\":0.8,\"option_1\":0.2}}}}") { request in
            #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jev-secret")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            #expect(request.httpMethod == "POST")
            #expect(request.timeoutInterval == 25)
            #expect(body["model"] as? String == "jev-latest")
            #expect(body["state"] as? [String: String] == ["value": "ASAP"])
            #expect(Set(body.keys) == ["model", "state", "questions"])
            let questions = body["questions"] as! [String: [String: Any]]
            #expect(questions["decision"]?["criteria"] as? [String: String] == ["option_0": "urgent", "option_1": "NOT: urgent"])
        })
        #expect(try await provider.judge(value: .string("ASAP"), labels: ["urgent", "NOT: urgent"]) == ["urgent": 0.8, "NOT: urgent": 0.2])
    }

    @Test(arguments: ["", " ", "key\n", "key\rInjected: yes"])
    func rejectsInvalidJevKeys(key: String) {
        #expect(throws: MaybeError.self) { try JevProvider(apiKey: key) }
    }

    @Test func jevModelAndTypedStateArePreserved() async throws {
        let provider = try JevProvider(apiKey: "test", model: "jev-1.13.0", transport: transport(#"{"answers":{"decision":{"probabilities":{"option_0":1}}}}"#) { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            guard case .object(let object) = body else { Issue.record("Expected object"); return }
            #expect(object["model"] == .string("jev-1.13.0"))
            #expect(object["state"] == .object(["value": .bool(true)]))
        })
        #expect(try await provider.judge(value: .bool(true), labels: [""]) == ["": 1])
        #expect(throws: MaybeError.self) { try JevProvider(apiKey: "test", model: " ") }
    }

    @Test func jevRejectsInvalidLabelsBeforeNetworking() async throws {
        let provider = try JevProvider(apiKey: "test", transport: HTTPTransport { _, _ in
            Issue.record("Invalid labels must not trigger a request")
            throw MaybeError("Unexpected request")
        })
        for labels in [[], ["same", "same"], (0..<256).map(String.init)] {
            await #expect(throws: MaybeError.self) { try await provider.judge(value: .bool(true), labels: labels) }
        }
    }

    @Test(arguments: ["{}", #"{"answers":{"decision":{"probabilities":{"option_0":1}}}}"#,
        #"{"answers":{"decision":{"probabilities":{"option_0":-1,"option_1":2}}}}"#,
        #"{"answers":{"decision":{"probabilities":{"option_0":0.1,"option_1":0.1}}}}"#])
    func jevRejectsMalformedJudgments(json: String) async throws {
        let provider = try JevProvider(apiKey: "test", transport: transport(json))
        await #expect(throws: MaybeError.self) { try await provider.judge(value: .number(2), labels: ["yes", "no"]) }
    }

    @Test(arguments: [401, 429, 529])
    func jevErrorsDoNotExposeKeyOrResponse(status: Int) async throws {
        let provider = try JevProvider(apiKey: "test-secret", transport: transport("test-secret private input", status: status))
        await #expect(throws: MaybeError("Provider request failed (HTTP \(status)).")) {
            try await provider.judge(value: .bool(true), labels: ["yes"])
        }
    }

    @Test func jevDoesNotPretendToGenerateText() async throws {
        let provider = try JevProvider(apiKey: "test", transport: HTTPTransport { _, _ in
            Issue.record("Writing must not call JEV")
            throw MaybeError("Unexpected request")
        })
        await #expect(throws: MaybeError("JEV makes decisions but does not generate text. Supply JevProvider's write closure to use llm expressions.")) {
            try await provider.write(prompt: "Hello", context: nil)
        }
    }

    @Test func jevOptionalWriterForwardsAndValidates() async throws {
        let provider = try JevProvider(apiKey: "test", write: { prompt, context in
            #expect(prompt == "Rewrite")
            #expect(context == .string("hello"))
            return "  Hi  "
        })
        #expect(try await provider.write(prompt: "Rewrite", context: .string("hello")) == "Hi")
        let empty = try JevProvider(apiKey: "test", write: { _, _ in " " })
        await #expect(throws: MaybeError.self) { try await empty.write(prompt: "", context: nil) }
    }

    @Test func jevRecordingExcludesCredentialAndReplaysOffline() async throws {
        let provider = try JevProvider(apiKey: "secret-not-in-recording", transport: transport(#"{"answers":{"decision":{"probabilities":{"option_0":0.94,"option_1":0.06},"confidence":0.1}}}"#))
        let recording = try await Maybe(provider: provider).run(#"if input() feels "urgent" with confidence 80% { print("yes") } else { print("no") }"#, input: "ASAP")
        #expect(recording.output == ["yes"])
        #expect(!String(decoding: try recording.json(), as: UTF8.self).contains("secret-not-in-recording"))
        let offline = try JevProvider(apiKey: "unused", transport: HTTPTransport { _, _ in
            Issue.record("Replay must not use the network")
            throw MaybeError("Unexpected request")
        })
        #expect(try await Maybe(provider: offline).replay(recording).output == ["yes"])
    }

    @Test func labelsMustBeDistinctButMayBeEmptyStrings() async throws {
        let provider = DemoProvider()
        #expect(try await provider.judge(value: .string("hello"), labels: [""]).keys.contains(""))
        await #expect(throws: MaybeError.self) { try await provider.judge(value: .bool(true), labels: []) }
        await #expect(throws: MaybeError.self) { try await provider.judge(value: .bool(true), labels: ["same", "same"]) }
    }

    @Test func closureAdapterForwardsArguments() async throws {
        let provider = ClosureProvider(write: { prompt, value in "\(prompt): \(value!)" }, judge: { _, labels in [labels[0]: 1] })
        #expect(try await provider.write(prompt: "Count", context: .number(2)) == "Count: 2")
        #expect(try await provider.judge(value: .bool(true), labels: ["yes"]) == ["yes": 1])
    }
}
