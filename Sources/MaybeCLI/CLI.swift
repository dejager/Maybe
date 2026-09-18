import Foundation
import Maybe

/// A deliberately small CLI. No argument-parser dependency is needed for three commands.
@main
struct MaybeCommand {
    static func main() async {
        do { try await execute(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("maybe: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func execute(_ arguments: [String]) async throws {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
            print(help)
            return
        }
        if arguments == ["--version"] { print("Maybe 0.1.0 · Probably 0.1 language"); return }
        let command = arguments[0]
        guard ["demo", "run", "replay"].contains(command) else { throw MaybeError("Unknown command '\(command)'. Try maybe --help.") }
        var file: String?
        var input: String?
        var save: String?
        var live = false
        var trace = false
        var index = 1
        var seen: Set<String> = []
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                guard seen.insert(argument).inserted else { throw MaybeError("Repeated option \(argument).") }
                switch argument {
                case "--live": live = true
                case "--trace": trace = true
                case "--input", "--save":
                    index += 1
                    guard index < arguments.count else { throw MaybeError("\(argument) needs a value.") }
                    if argument == "--input" { input = arguments[index] } else { save = arguments[index] }
                default: throw MaybeError("Unknown option \(argument).")
                }
            } else {
                guard command != "demo", file == nil else { throw MaybeError("Unexpected argument '\(argument)'.") }
                file = argument
            }
            index += 1
        }
        if command != "demo", file == nil { throw MaybeError("\(command) requires a file path.") }
        if command == "replay", input != nil || live { throw MaybeError("Replay uses recorded input and makes no live calls; omit --input and --live.") }
        let provider: any ModelProvider
        if live {
            let environment = ProcessInfo.processInfo.environment
            guard let key = environment["JEV_API_KEY"] ?? environment["TYPESAFE_API_KEY"] else {
                throw MaybeError("Live mode needs JEV_API_KEY (or TYPESAFE_API_KEY). See docs/providers.md.")
            }
            provider = try JevProvider(apiKey: key, model: environment["JEV_MODEL"] ?? "jev-latest")
        } else { provider = DemoProvider() }
        let engine = Maybe(provider: provider)
        let result: Recording
        if command == "replay" {
            let recording = try Recording.decode(read(file!, maximumBytes: Recording.maximumJSONBytes))
            status("REPLAY · recorded decisions · zero model calls")
            result = try await engine.replay(recording, onEvent: observer(trace: trace))
        } else {
            status(live ? "LIVE · remote model calls may incur charges" : "DEMO · deterministic simulated model · no keys, no network")
            let source: String
            if command == "demo" {
                source = demo
                print("\nMaybe. A programming language with room for doubt.\n")
                print(source)
                print("\n── The verdict ──")
            } else {
                let data = try read(file!, maximumBytes: 48_000)
                guard let decoded = String(data: data, encoding: .utf8) else { throw MaybeError("Source must be UTF-8 text.") }
                source = decoded
            }
            result = try await engine.run(source, input: input ?? (command == "demo" ? "We might need this soon." : ""), onEvent: observer(trace: trace || command == "demo"))
        }
        if let save {
            try result.json().write(to: URL(fileURLWithPath: save), options: .atomic)
            status("Saved recording to \(save). It includes your input and generated text.")
        }
    }

    static func observer(trace: Bool) -> @Sendable (RunEvent) -> Void {
        { event in
            if event.kind == .print { print(event.text) }
            else if trace && (event.kind == .judge || event.kind == .write) { status("  L\(event.line) · \(event.text)") }
        }
    }

    static func status(_ text: String) { FileHandle.standardError.write(Data("\(text)\n".utf8)) }

    static func read(_ path: String, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw MaybeError("File exceeds the \(maximumBytes)-byte import limit.") }
        return data
    }

    static let demo = #"""
    let message = input()
    if message feels "urgent" with confidence 80% {
      print("Put the coffee down. This one needs you.")
    } otherwise maybe {
      print("The model is squinting. Ask one more question.")
    } else {
      print("Keep the coffee. It can wait.")
    }
    """#

    static let help = """
    Maybe 0.1.0 — control flow with room for doubt.

      swift run maybe demo [--input TEXT] [--save FILE]
      swift run maybe run FILE.prob [--input TEXT] [--trace] [--save FILE] [--live]
      swift run maybe replay FILE.json [--trace] [--save FILE]

    All runs use the deterministic DemoProvider unless --live is explicit.
    Live mode connects directly to JEV using JEV_API_KEY (or TYPESAFE_API_KEY).
    Optional JEV_MODEL defaults to jev-latest. JEV does not support llm text generation.
    Replay uses recorded source, input, model responses and random draws.
    Recordings include user input and generated text; choose what you share.
    """
}
