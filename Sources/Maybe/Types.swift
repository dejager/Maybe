import Foundation

/// The three kinds of value in the Probably 0.1 language. Numbers use Double, just like the original runtime.
public enum Value: Sendable, Equatable, Codable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .number(try container.decode(Double.self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    public var description: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return javascriptNumber(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }
}

/// Implement these two operations to bring your own model, server, or test double.
/// Providers should cooperate with Swift task cancellation. The interpreter checks
/// cancellation before and after each call; it cannot terminate arbitrary provider code.
public protocol ModelProvider: Sendable {
    func write(prompt: String, context: Value?) async throws -> String
    func judge(value: Value, labels: [String]) async throws -> [String: Double]
}

/// JSON values keep exported recordings compatible with Probably 0.1's effect tape.
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        // Swift's normal String equality folds canonical Unicode equivalents.
        // Replay needs exact scalar equality, as in the original JSON contract.
        case (.string(let a), .string(let b)): return a.utf16.elementsEqual(b.utf16)
        case (.number(let a), .number(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            return a.allSatisfy { key, value in
                b.contains { otherKey, otherValue in
                    key.utf16.elementsEqual(otherKey.utf16) && value == otherValue
                }
            }
        default: return false
        }
    }

    public init(_ value: Value) {
        switch value {
        case .string(let value): self = .string(value)
        case .number(let value): self = .number(value)
        case .bool(let value): self = .bool(value)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A single observable step. Events already emitted remain useful if a later step fails.
public struct RunEvent: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case write, judge, print, assign, `repeat` }
    public let kind: Kind
    public let line: Int
    public let text: String
    public let detail: JSONValue?

    public init(kind: Kind, line: Int, text: String, detail: JSONValue? = nil) {
        self.kind = kind; self.line = line; self.text = text; self.detail = detail
    }
}

/// A recorded external effect. Its arguments are checked before a replay can consume it.
public struct Effect: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case write, judge }
    public let kind: Kind
    public let args: JSONValue
    public let result: JSONValue
    public let draw: Double?

    public init(kind: Kind, args: JSONValue, result: JSONValue, draw: Double? = nil) {
        self.kind = kind; self.args = args; self.result = result; self.draw = draw
    }
}

/// A portable run, including the input and generated text. Treat exports as user data.
public struct Recording: Sendable, Equatable, Codable {
    /// Enough for a maximum-size valid run, including escaped text duplicated in its trace.
    /// Shared by the CLI and decoder so a saved run can always be imported again.
    public static let maximumJSONBytes = 32 * 1_024 * 1_024

    public let version: Int
    public let source: String
    public let input: String
    public let tape: [Effect]
    public let output: [String]
    public let trace: [RunEvent]

    public init(version: Int = 1, source: String, input: String, tape: [Effect], output: [String], trace: [RunEvent]) {
        self.version = version; self.source = source; self.input = input
        self.tape = tape; self.output = output; self.trace = trace
    }

    /// Pretty-printed, stable-key JSON suitable for a saved file or a share sheet.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumJSONBytes else { throw MaybeError("Recording exceeds 32 MiB.") }
        return data
    }

    public static func decode(_ data: Data) throws -> Recording {
        guard data.count <= maximumJSONBytes else { throw MaybeError("Recording exceeds 32 MiB.") }
        return try JSONDecoder().decode(Recording.self, from: data)
    }
}

/// A readable error, optionally pointing to a source line.
public struct MaybeError: Error, LocalizedError, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let line: Int?
    public init(_ message: String, line: Int? = nil) { self.message = message; self.line = line }
    public var description: String { line.map { "Line \($0): \(message)" } ?? message }
    public var errorDescription: String? { description }
}

// The syntax tree is internal: clients work with source strings, not parser implementation details.
indirect enum Expression: Sendable, Equatable {
    case literal(Value)
    case variable(String)
    case input
    case write(prompt: String, context: Expression?)
}

struct Statement: Sendable, Equatable {
    let line: Int
    let kind: Kind
    indirect enum Kind: Sendable, Equatable {
        case declare(name: String, value: Expression)
        case assign(name: String, value: Expression)
        case print(Expression)
        case conditional(value: Expression, question: String, confidence: Double, yes: [Statement], maybe: [Statement], no: [Statement])
        case match(value: Expression, branches: [Branch])
        case loop(value: Expression, question: String, body: [Statement])
        case repeatCount(Int, body: [Statement])
        case chaos([Statement])
    }
    struct Branch: Sendable, Equatable { let label: String; let body: [Statement] }
}

// JavaScript uses ordinary decimal notation for [1e-6, 1e21), while Swift
// switches to exponent notation sooner. Keep printed numbers replay-compatible.
private func javascriptNumber(_ value: Double) -> String {
    guard value.isFinite else { return String(value) }
    if value == 0 { return "0" }
    let text = String(value)
    let components = text.lowercased().split(separator: "e")
    guard components.count == 2, let exponent = Int(components[1]) else {
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
    var mantissa = String(components[0])
    if mantissa.hasSuffix(".0") { mantissa = String(mantissa.dropLast(2)) }
    let absolute = abs(value)
    if absolute < 0.000001 || absolute >= 1e21 {
        return "\(mantissa)e\(exponent >= 0 ? "+" : "")\(exponent)"
    }
    let sign = mantissa.hasPrefix("-") ? "-" : ""
    if !sign.isEmpty { mantissa.removeFirst() }
    let parts = mantissa.split(separator: ".")
    let digits = parts.joined()
    let decimalIndex = parts[0].count + exponent
    if decimalIndex <= 0 { return sign + "0." + String(repeating: "0", count: -decimalIndex) + digits }
    if decimalIndex >= digits.count { return sign + digits + String(repeating: "0", count: decimalIndex - digits.count) }
    let split = digits.index(digits.startIndex, offsetBy: decimalIndex)
    return sign + digits[..<split] + "." + digits[split...]
}
