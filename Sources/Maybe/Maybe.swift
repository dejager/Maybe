import Foundation

/// A tiny interpreter for programs that occasionally need a judgment call.
///
/// The interpreter controls execution. A model only sees the instruction and value
/// explicitly passed to it; it never receives your source code or all local variables.
/// Each run owns its state, so one instance can safely serve concurrent callers.
public struct Maybe: Sendable {
    private let provider: any ModelProvider
    private let timeout: Duration
    private let random: @Sendable () -> Double

    public init(provider: any ModelProvider) {
        self.init(provider: provider, timeout: .seconds(90), random: { Double.random(in: 0..<1) })
    }

    // Injectable clock budget and randomness make boundary tests deterministic.
    init(provider: any ModelProvider, timeout: Duration, random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.provider = provider; self.timeout = timeout; self.random = random
    }

    /// Execute Probably 0.1 source. Cancel the calling Task to stop a run.
    /// Events arrive on the executor, not the main actor; hop to MainActor for UI updates.
    public func run(_ source: String, input: String = "", onEvent: (@Sendable (RunEvent) -> Void)? = nil) async throws -> Recording {
        try await execute(source, input: input, tape: nil, onEvent: onEvent)
    }

    /// Recompute output from recorded effects without contacting a provider.
    /// Source/input and each effect's arguments must agree. Stored output and trace
    /// are deliberately recomputed: a recording is a debugging aid, not signed evidence.
    public func replay(_ recording: Recording, onEvent: (@Sendable (RunEvent) -> Void)? = nil) async throws -> Recording {
        guard recording.version == 1 else { throw MaybeError("Unsupported recording version \(recording.version).") }
        guard recording.tape.count <= 12 else { throw MaybeError("Recording exceeds the 12 model-call limit.") }
        return try await execute(recording.source, input: recording.input, tape: recording.tape, onEvent: onEvent)
    }

    private func execute(_ source: String, input: String, tape: [Effect]?, onEvent: (@Sendable (RunEvent) -> Void)?) async throws -> Recording {
        try Task.checkCancellation()
        guard input.utf16.count <= 6_000 else { throw MaybeError("Input exceeds 6,000 characters.") }
        let statements = try Parser.parse(source)
        let executor = Executor(provider: provider, source: source, input: input, replayTape: tape, random: random, onEvent: onEvent)
        // Structured concurrency propagates cancellation to the provider. A custom
        // provider that ignores cancellation can delay this scope's return; see docs.
        return try await withThrowingTaskGroup(of: Recording.self) { group in
            group.addTask { try await executor.start(statements) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw MaybeError("Run exceeded its 90-second time budget.")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

/// Reject missing, non-finite, negative, or implausibly normalized probabilities.
/// Labels stay ordered separately: Dictionary iteration must never decide a tie.
func normalized(_ probabilities: [String: Double], labels: [String]) throws -> [String: Double] {
    guard !labels.isEmpty, Set(labels).count == labels.count else { throw MaybeError("Judgment needs distinct labels.") }
    var total = 0.0
    for label in labels {
        guard let number = probabilities[label], number.isFinite, (0...1).contains(number) else {
            throw MaybeError("Judge returned invalid probabilities.")
        }
        total += number
    }
    guard total > 0, abs(total - 1) <= 0.02 else { throw MaybeError("Judge probabilities do not sum to one.") }
    return Dictionary(uniqueKeysWithValues: labels.map { ($0, probabilities[$0]! / total) })
}

/// Mutable execution state belongs to one run and stays off the UI actor.
private actor Executor {
    let provider: any ModelProvider
    let source: String
    let input: String
    let replayTape: [Effect]?
    let random: @Sendable () -> Double
    let onEvent: (@Sendable (RunEvent) -> Void)?
    var scopes: [[String: Value]] = [[:]]
    var tape: [Effect] = []
    var output: [String] = []
    var trace: [RunEvent] = []
    var steps = 0
    var calls = 0
    var cursor = 0

    init(provider: any ModelProvider, source: String, input: String, replayTape: [Effect]?, random: @escaping @Sendable () -> Double, onEvent: (@Sendable (RunEvent) -> Void)?) {
        self.provider = provider; self.source = source; self.input = input
        self.replayTape = replayTape; self.random = random; self.onEvent = onEvent
    }

    func start(_ statements: [Statement]) async throws -> Recording {
        try await execute(statements)
        if let replayTape, cursor != replayTape.count { throw MaybeError("Replay has unused model results.") }
        try Task.checkCancellation()
        return Recording(source: source, input: input, tape: tape, output: output, trace: trace)
    }

    func emit(_ event: RunEvent) {
        trace.append(event)
        onEvent?(event)
    }

    func scope(containing name: String) -> Int? { scopes.indices.reversed().first { scopes[$0][name] != nil } }

    func effect(_ kind: Effect.Kind, args: JSONValue, chaos: Bool = false, call: @Sendable () async throws -> JSONValue) async throws -> Effect {
        try Task.checkCancellation()
        calls += 1
        guard calls <= 12 else { throw MaybeError("Run stopped at the 12 model-call limit.") }
        let result: Effect
        if let replayTape {
            guard cursor < replayTape.count, replayTape[cursor].kind == kind, replayTape[cursor].args == args else {
                throw MaybeError("Replay does not match this program and input.")
            }
            result = replayTape[cursor]
            cursor += 1
        } else {
            let value = try await call()
            try Task.checkCancellation()
            result = Effect(kind: kind, args: args, result: value, draw: chaos ? random() : nil)
        }
        if let draw = result.draw, !draw.isFinite || draw < 0 || draw >= 1 {
            throw MaybeError("Invalid chaos draw in recording.")
        }
        if chaos && result.draw == nil { throw MaybeError("Missing chaos draw in recording.") }
        tape.append(result)
        return result
    }

    func evaluate(_ expression: Expression, line: Int) async throws -> Value {
        switch expression {
        case .literal(let value): return value
        case .input: return .string(input)
        case .variable(let name):
            guard let index = scope(containing: name), let value = scopes[index][name] else {
                throw MaybeError("Unknown variable \(name).", line: line)
            }
            return value
        case .write(let prompt, let context):
            let value: Value?
            if let context { value = try await evaluate(context, line: line) } else { value = nil }
            var fields: [String: JSONValue] = ["prompt": .string(prompt)]
            if let value { fields["value"] = JSONValue(value) }
            let args = JSONValue.object(fields)
            let provider = self.provider
            let recorded = try await effect(.write, args: args) {
                .string(try await provider.write(prompt: prompt, context: value))
            }
            guard case .string(let text) = recorded.result, text.utf16.count <= 12_000 else {
                throw MaybeError("Writer returned invalid or oversized text.", line: line)
            }
            emit(RunEvent(kind: .write, line: line, text: text, detail: args))
            return .string(text)
        }
    }

    func choose(value: Value, labels: [String], line: Int, chaos: Bool, threshold: Double = 0.5) async throws -> String? {
        let args = JSONValue.object(["value": JSONValue(value), "labels": .array(labels.map(JSONValue.string))])
        let provider = self.provider
        let recorded = try await effect(.judge, args: args, chaos: chaos) {
            .object(try await provider.judge(value: value, labels: labels).mapValues(JSONValue.number))
        }
        guard case .object(let object) = recorded.result else { throw MaybeError("Judge returned no probabilities.", line: line) }
        var raw: [String: Double] = [:]
        for label in labels {
            if case .number(let probability) = object[label] { raw[label] = probability }
        }
        let probabilities = try normalized(raw, labels: labels)
        var winner = labels[0]
        for label in labels.dropFirst() where probabilities[label]! > probabilities[winner]! { winner = label }
        let uncertain = probabilities[winner]! < threshold
        // Confidence gates the distribution, BEFORE chaos samples an outcome.
        // A confident distribution can still sample its minority answer.
        if chaos && !uncertain {
            var remaining = recorded.draw!
            winner = labels.last!
            for label in labels {
                remaining -= probabilities[label]!
                if remaining < 0 { winner = label; break }
            }
        }
        var detail: [String: JSONValue] = [
            "value": JSONValue(value), "probabilities": .object(probabilities.mapValues(JSONValue.number)),
            "chosen": uncertain ? .null : .string(winner), "threshold": .number(threshold)
        ]
        if chaos { detail["draw"] = .number(recorded.draw!) }
        let percent = Int((probabilities[winner]! * 100).rounded())
        let text = uncertain ? "Uncertain → otherwise maybe" : "\(winner) → \(percent)% · \(chaos ? "sampled" : "highest probability")"
        emit(RunEvent(kind: .judge, line: line, text: text, detail: .object(detail)))
        return uncertain ? nil : winner
    }

    func execute(_ statements: [Statement], chaos: Bool = false, nested: Bool = false) async throws {
        if nested { scopes.append([:]) }
        defer { if nested { scopes.removeLast() } }
        for statement in statements {
            try Task.checkCancellation()
            steps += 1
            guard steps <= 200 else { throw MaybeError("Run stopped at the 200 statement limit.") }
            let line = statement.line
            switch statement.kind {
            case .declare(let name, let expression):
                let index = scopes.count - 1
                guard scopes[index][name] == nil else { throw MaybeError("\(name) is already declared in this block.", line: line) }
                let value = try await evaluate(expression, line: line)
                scopes[index][name] = value
                emit(RunEvent(kind: .assign, line: line, text: name, detail: .object(["value": JSONValue(value)])))
            case .assign(let name, let expression):
                guard let index = scope(containing: name) else { throw MaybeError("Unknown variable \(name). Use let first.", line: line) }
                let value = try await evaluate(expression, line: line)
                scopes[index][name] = value
                emit(RunEvent(kind: .assign, line: line, text: name, detail: .object(["value": JSONValue(value)])))
            case .print(let expression):
                let value = try await evaluate(expression, line: line).description
                output.append(value)
                emit(RunEvent(kind: .print, line: line, text: value))
            case .conditional(let expression, let question, let confidence, let yes, let maybe, let no):
                let value = try await evaluate(expression, line: line)
                let selected = try await choose(value: value, labels: [question, "NOT: \(question)"], line: line, chaos: chaos, threshold: confidence)
                try await execute(selected == nil ? maybe : selected == question ? yes : no, chaos: chaos, nested: true)
            case .match(let expression, let branches):
                let value = try await evaluate(expression, line: line)
                let selected = try await choose(value: value, labels: branches.map(\.label), line: line, chaos: chaos, threshold: 0)
                guard let branch = branches.first(where: { $0.label == selected }) else { throw MaybeError("No matching branch.", line: line) }
                try await execute(branch.body, chaos: chaos, nested: true)
            case .loop(let expression, let question, let body):
                var iteration = 0
                while true {
                    let value = try await evaluate(expression, line: line)
                    let selected = try await choose(value: value, labels: [question, "NOT: \(question)"], line: line, chaos: chaos)
                    guard selected == question else { break }
                    guard iteration < 5 else { throw MaybeError("Loop still feels true after 5 iterations. Try a different rewrite instruction.", line: line) }
                    iteration += 1
                    emit(RunEvent(kind: .repeat, line: line, text: "Iteration \(iteration) of at most 5"))
                    try await execute(body, chaos: chaos, nested: true)
                }
            case .repeatCount(let count, let body):
                for index in 1...count {
                    emit(RunEvent(kind: .repeat, line: line, text: "Iteration \(index) of \(count)"))
                    try await execute(body, chaos: chaos, nested: true)
                }
            case .chaos(let body): try await execute(body, chaos: true, nested: true)
            }
        }
    }
}
