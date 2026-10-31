//
//  LuaTableParser.swift
//  rawpreview
//

import Foundation

/// A value from a Lua table literal, the format Lightroom Classic used for
/// `.lrtemplate` presets before 7.3.
nonisolated enum LuaValue: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case table(LuaTable)
    case `nil`

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var number: Double? {
        if case .number(let value) = self { value } else { nil }
    }

    var table: LuaTable? {
        if case .table(let value) = self { value } else { nil }
    }
}

nonisolated struct LuaTable: Sendable {
    /// Positional entries (`{ 0, 0, 255, 255 }`).
    var array: [LuaValue] = []
    /// Named entries (`key = value`, `["key"] = value`).
    var fields: [String: LuaValue] = [:]

    subscript(key: String) -> LuaValue? {
        fields[key]
    }
}

/// Parses the data subset of Lua that `.lrtemplate` files use: one optional
/// `name =` assignment of a table of strings, numbers, booleans and nested
/// tables. No expressions, no code is run.
nonisolated struct LuaTableParser {
    struct ParseError: LocalizedError {
        let offset: Int
        var errorDescription: String? { "Unexpected character at offset \(offset)." }
    }

    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ text: String) throws -> LuaValue {
        var parser = LuaTableParser(bytes: Array(text.utf8))
        parser.skipSpace()
        // lrtemplates start with `s = { … }`.
        let start = parser.index
        if parser.identifier() != nil {
            parser.skipSpace()
            if parser.peek == UInt8(ascii: "=") {
                parser.index += 1
            } else {
                parser.index = start
            }
        }
        return try parser.value()
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private var peek: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func peek(at offset: Int) -> UInt8? {
        index + offset < bytes.count ? bytes[index + offset] : nil
    }

    private mutating func skipSpace() {
        while let byte = peek {
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                index += 1
            } else if byte == UInt8(ascii: "-"), peek(at: 1) == UInt8(ascii: "-") {
                // `-- comment` to end of line.
                while let next = peek, next != UInt8(ascii: "\n") { index += 1 }
            } else {
                return
            }
        }
    }

    private mutating func expect(_ character: Character) throws {
        skipSpace()
        guard peek == character.asciiValue else { throw ParseError(offset: index) }
        index += 1
    }

    private mutating func value() throws -> LuaValue {
        skipSpace()
        guard let byte = peek else { throw ParseError(offset: index) }
        switch byte {
        case UInt8(ascii: "{"):
            return .table(try table())
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            return .string(try quotedString())
        case UInt8(ascii: "["):
            return .string(try longString())
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."):
            return .number(try number())
        default:
            switch identifier() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "nil": return .nil
            default: throw ParseError(offset: index)
            }
        }
    }

    private mutating func table() throws -> LuaTable {
        try expect("{")
        var table = LuaTable()
        while true {
            skipSpace()
            if peek == UInt8(ascii: "}") {
                index += 1
                return table
            }

            if peek == UInt8(ascii: "["), peek(at: 1) != UInt8(ascii: "["), peek(at: 1) != UInt8(ascii: "=") {
                // `["key"] = value`
                index += 1
                let key = try value()
                try expect("]")
                try expect("=")
                let fieldValue = try value()
                switch key {
                case .string(let name): table.fields[name] = fieldValue
                case .number(let number): table.fields[String(number)] = fieldValue
                default: throw ParseError(offset: index)
                }
            } else if let (name, afterName) = lookaheadAssignment() {
                // `key = value`
                index = afterName
                table.fields[name] = try value()
            } else {
                table.array.append(try value())
            }

            skipSpace()
            if peek == UInt8(ascii: ",") || peek == UInt8(ascii: ";") {
                index += 1
            } else if peek != UInt8(ascii: "}") {
                throw ParseError(offset: index)
            }
        }
    }

    /// `name =` (but not `name ==`) at the current position: the name and the
    /// index just past `=`. Leaves the position unchanged.
    private mutating func lookaheadAssignment() -> (String, Int)? {
        let start = index
        defer { index = start }
        guard let name = identifier() else { return nil }
        skipSpace()
        guard peek == UInt8(ascii: "="), peek(at: 1) != UInt8(ascii: "=") else { return nil }
        return (name, index + 1)
    }

    private mutating func identifier() -> String? {
        let start = index
        while let byte = peek, byte == UInt8(ascii: "_") || isAlphanumeric(byte) && (index > start || !isDigit(byte)) {
            index += 1
        }
        guard index > start else { return nil }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func number() throws -> Double {
        let start = index
        while let byte = peek, isAlphanumeric(byte) || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") {
            index += 1
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard let number = Double(text) else { throw ParseError(offset: start) }
        return number
    }

    private mutating func quotedString() throws -> String {
        let quote = bytes[index]
        index += 1
        var result: [UInt8] = []
        while let byte = peek {
            index += 1
            if byte == quote {
                return String(decoding: result, as: UTF8.self)
            }
            guard byte == UInt8(ascii: "\\"), let escaped = peek else {
                result.append(byte)
                continue
            }
            index += 1
            switch escaped {
            case UInt8(ascii: "n"): result.append(UInt8(ascii: "\n"))
            case UInt8(ascii: "r"): result.append(UInt8(ascii: "\r"))
            case UInt8(ascii: "t"): result.append(UInt8(ascii: "\t"))
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                // `\ddd`: up to three decimal digits.
                var code = Int(escaped - UInt8(ascii: "0"))
                for _ in 0..<2 {
                    guard let digit = peek, isDigit(digit) else { break }
                    code = code * 10 + Int(digit - UInt8(ascii: "0"))
                    index += 1
                }
                result.append(UInt8(truncatingIfNeeded: code))
            default: result.append(escaped) // \\ \" \' and anything else verbatim
            }
        }
        throw ParseError(offset: index)
    }

    /// `[[ … ]]` or `[==[ … ]==]`.
    private mutating func longString() throws -> String {
        let start = index
        index += 1
        var level = 0
        while peek == UInt8(ascii: "=") {
            level += 1
            index += 1
        }
        guard peek == UInt8(ascii: "[") else { throw ParseError(offset: start) }
        index += 1
        let close = [UInt8(ascii: "]")] + Array(repeating: UInt8(ascii: "="), count: level) + [UInt8(ascii: "]")]
        let contentStart = index
        while index + close.count <= bytes.count {
            if Array(bytes[index..<index + close.count]) == close {
                let content = String(decoding: bytes[contentStart..<index], as: UTF8.self)
                index += close.count
                return content
            }
            index += 1
        }
        throw ParseError(offset: start)
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private func isAlphanumeric(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }
}
