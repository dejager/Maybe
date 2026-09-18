import Foundation

/// Tokens retain their starting line so errors point to the user's program.
struct Token {
    enum Kind { case word, string, number, symbol, end }
    let kind: Kind
    let text: String
    let line: Int
}

struct Lexer {
    static let maximumSourceLength = 12_000

    static func tokenize(_ source: String) throws -> [Token] {
        // Match JavaScript's source budget: an emoji usually occupies two UTF-16 units.
        guard source.utf16.count <= maximumSourceLength else {
            throw MaybeError("Program exceeds 12,000 UTF-16 code units.", line: 1)
        }
        let characters = Array(source.unicodeScalars)
        var position = 0
        var line = 1
        var tokens: [Token] = []

        func isDigit(_ scalar: Unicode.Scalar) -> Bool { (48...57).contains(scalar.value) }
        func isLetter(_ scalar: Unicode.Scalar) -> Bool {
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value) || scalar == "_"
        }
        func text(_ start: Int, _ end: Int) -> String {
            String(String.UnicodeScalarView(characters[start..<end]))
        }
        func append(_ kind: Token.Kind, _ value: String, at startingLine: Int? = nil) {
            tokens.append(Token(kind: kind, text: value, line: startingLine ?? line))
        }

        while position < characters.count {
            let character = characters[position]
            // ECMAScript whitespace (including BOM); only LF advances the original line counter.
            if [9, 10, 11, 12, 13, 32, 160, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains(character.value)
                || (0x2000...0x200A).contains(character.value) {
                if character == "\n" { line += 1 }
                position += 1
                continue
            }
            if character == "/", position + 1 < characters.count, characters[position + 1] == "/" {
                while position < characters.count, characters[position] != "\n" { position += 1 }
                continue
            }
            if character == "\"" {
                let start = position
                let startLine = line
                position += 1
                while position < characters.count, characters[position] != "\"" {
                    if characters[position] == "\n" {
                        throw MaybeError("Use \\n inside strings.", line: startLine)
                    }
                    if characters[position] == "\\" { position += 1 }
                    position += 1
                }
                guard position < characters.count else {
                    throw MaybeError("Unterminated string.", line: startLine)
                }
                position += 1
                // Let the standard JSON decoder handle escapes, control characters, and pairs
                // of Unicode surrogates. Swift strings require well-formed Unicode.
                guard let value = try? JSONDecoder().decode(String.self, from: Data(text(start, position).utf8)) else {
                    throw MaybeError("Invalid string escape or control character.", line: startLine)
                }
                append(.string, value, at: startLine)
                continue
            }
            if isLetter(character) {
                let start = position
                position += 1
                while position < characters.count, isLetter(characters[position]) || isDigit(characters[position]) {
                    position += 1
                }
                append(.word, text(start, position))
                continue
            }
            if isDigit(character) {
                let start = position
                while position < characters.count, isDigit(characters[position]) { position += 1 }
                if position + 1 < characters.count, characters[position] == ".", isDigit(characters[position + 1]) {
                    position += 1
                    while position < characters.count, isDigit(characters[position]) { position += 1 }
                }
                let literal = text(start, position)
                guard let number = Double(literal), number.isFinite else {
                    throw MaybeError("Numbers must be finite.", line: line)
                }
                append(.number, literal)
                continue
            }
            if character == "=", position + 1 < characters.count, characters[position + 1] == ">" {
                append(.symbol, "=>")
                position += 2
                continue
            }
            if "{}()=%;".unicodeScalars.contains(character) {
                append(.symbol, String(character))
                position += 1
                continue
            }
            throw MaybeError("Unexpected character \(String(character).debugDescription).", line: line)
        }
        append(.end, "<end>")
        return tokens
    }
}
