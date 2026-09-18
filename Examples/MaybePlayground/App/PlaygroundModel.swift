import Foundation
import Observation
import Maybe

/// Synchronous callbacks can arrive faster than MainActor can display them. Keep an
/// ordered copy so a subsequent failure still preserves every already-emitted step.
private final class EventBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RunEvent] = []

    func append(_ event: RunEvent) { lock.withLock { storage.append(event) } }
    func snapshot() -> [RunEvent] { lock.withLock { storage } }
}

/// Slows down the local fake so the decision trace is legible and Stop is useful.
/// This delay is a presentation choice; the framework imposes no artificial latency.
private struct PacedDemoProvider: ModelProvider {
    let demo = DemoProvider()
    private var delay: Duration {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-slow-provider") { return .seconds(8) }
        #endif
        return .milliseconds(850)
    }

    func write(prompt: String, context: Value?) async throws -> String {
        try await Task.sleep(for: delay)
        return try await demo.write(prompt: prompt, context: context)
    }

    func judge(value: Value, labels: [String]) async throws -> [String: Double] {
        try await Task.sleep(for: delay)
        return try await demo.judge(value: value, labels: labels)
    }
}

@MainActor @Observable
final class PlaygroundModel {
    enum Status: Equatable {
        case ready, running, complete, replayed, cancelled, failed(String)

        var label: String {
            switch self {
            case .ready: "Ready to run"
            case .running: "Running…"
            case .complete: "Completed"
            case .replayed: "Replayed · no model calls"
            case .cancelled: "Stopped"
            case .failed: "Unable to Run"
            }
        }
    }

    var selected: Example = .urgency
    var source = Example.urgency.source
    var input = Example.urgency.input
    private(set) var status: Status = .ready
    private(set) var output: [String] = []
    private(set) var events: [RunEvent] = []
    private(set) var recording: Recording?
    private(set) var exportURL: URL?
    private(set) var exportError: String?
    private(set) var usesJev = false
    private(set) var lastRunUsedJev = false
    @ObservationIgnored private var apiKey = ""

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activeID: UUID?

    init() {
        #if DEBUG
        // A deterministic parser failure lets the UI suite verify the error surface.
        if ProcessInfo.processInfo.arguments.contains("--ui-test-invalid-source") {
            source = "print("
        }
        #endif
    }

    var isRunning: Bool { status == .running }
    var canRun: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func select(_ example: Example) {
        stop()
        selected = example
        source = example.source
        input = example.input
        status = .ready
        output = []
        events = []
        recording = nil
        exportURL = nil
        exportError = nil
    }

    /// Keep a user-supplied key only for this process; recordings contain no settings.
    func configureJev(apiKey: String?) throws {
        if let apiKey { _ = try JevProvider(apiKey: apiKey) }
        stop()
        self.apiKey = apiKey ?? ""
        usesJev = apiKey != nil
        status = .ready
        output = []
        events = []
        recording = nil
        exportURL = nil
        exportError = nil
    }

    func run() { execute(replaying: nil) }

    func replay() {
        guard let recording else { return }
        // Replay restores the recorded source/input, so edits cannot disguise what ran.
        source = recording.source
        input = recording.input
        execute(replaying: recording)
    }

    func stop() {
        guard isRunning else { return }
        // Invalidate before cancelling: already-enqueued callbacks must not update a new run.
        activeID = nil
        task?.cancel()
        task = nil
        status = .cancelled
    }

    private func execute(replaying previous: Recording?) {
        stop()
        let id = UUID()
        activeID = id
        let runSource = source
        let runInput = input
        status = .running
        output = []
        events = []
        recording = nil
        exportURL = nil
        exportError = nil
        let buffer = EventBuffer()
        let engine: Maybe
        do {
            // Replay needs no credential, regardless of the provider used originally.
            if previous != nil { engine = Maybe(provider: DemoProvider()) }
            else if usesJev { engine = Maybe(provider: try JevProvider(apiKey: apiKey)) }
            else { engine = Maybe(provider: PacedDemoProvider()) }
        } catch {
            activeID = nil
            status = .failed(error.localizedDescription)
            return
        }
        if previous == nil { lastRunUsedJev = usesJev }

        task = Task { [weak self, engine] in
            let receive: @Sendable (RunEvent) -> Void = { [weak self] event in
                buffer.append(event)
                Task { @MainActor [weak self] in
                    guard let self, self.activeID == id else { return }
                    self.events = buffer.snapshot()
                    self.output = self.events.filter { $0.kind == .print }.map(\.text)
                }
            }
            do {
                let result: Recording
                if let previous {
                    result = try await engine.replay(previous, onEvent: receive)
                } else {
                    result = try await engine.run(runSource, input: runInput, onEvent: receive)
                }
                guard let self, self.activeID == id else { return }
                self.activeID = nil
                // A completed recording is authoritative even if an event is still queued.
                self.output = result.output
                self.events = result.trace
                self.recording = result
                self.status = previous == nil ? .complete : .replayed
                self.task = nil
                self.prepareExport(result)
            } catch {
                guard let self, self.activeID == id else { return }
                self.activeID = nil
                self.events = buffer.snapshot()
                self.output = self.events.filter { $0.kind == .print }.map(\.text)
                self.status = error is CancellationError ? .cancelled : .failed(error.localizedDescription)
                self.task = nil
            }
        }
    }

    private func prepareExport(_ recording: Recording) {
        do {
            // A single replaceable temporary file avoids accumulating copies of user input.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("maybe-run.json")
            try recording.json().write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportError = "The run succeeded, but its JSON could not be prepared: \(error.localizedDescription)"
        }
    }
}
