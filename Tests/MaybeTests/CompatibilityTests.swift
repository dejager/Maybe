import Foundation
import Testing
@testable import Maybe

private struct Corpus: Decodable {
    let success: [Recording]
    let rejected: [String]
}

@Test func originalInterpreterFixturesReplayExactly() async throws {
    let url = try #require(Bundle.module.url(forResource: "oracle", withExtension: "json", subdirectory: "Fixtures"))
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    let provider = ClosureProvider(
        write: { _, _ in throw MaybeError("Replay called a model") },
        judge: { _, _ in throw MaybeError("Replay called a model") }
    )
    let engine = Maybe(provider: provider)
    #expect(corpus.success.count == 17)
    for recording in corpus.success {
        let actual = try await engine.replay(recording)
        #expect(actual.output == recording.output, "Output differed for: \(recording.source)")
        #expect(actual.trace == recording.trace, "Trace differed for: \(recording.source)")
        #expect(actual.tape == recording.tape)
    }
    for source in corpus.rejected {
        await #expect(throws: (any Error).self) { try await engine.run(source) }
    }
}
