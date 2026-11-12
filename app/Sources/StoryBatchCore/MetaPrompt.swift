import Foundation

public struct MetaPromptError: LocalizedError, Equatable {
    public let message: String
    public let line: Int
    public let column: Int
    public init(_ message: String, line: Int = 1, column: Int = 1) {
        self.message = message; self.line = line; self.column = column
    }
    public var errorDescription: String? { "Line \(line), column \(column): \(message)" }
}

public enum ShiftBump: String, CaseIterable, Identifiable {
    case minusOne = "-1", minusQuarter = "-0.25", minusTenth = "-0.1", minusFiveHundredths = "-0.05"
    case plusFiveHundredths = "+0.05", plusTenth = "+0.1", plusQuarter = "+0.25", plusOne = "+1"
    public var id: String { rawValue }
}

public struct ShiftValue: Codable, Equatable {
    /// Preserve the supplied precision for filenames and reporting; never format overrides to three places.
    public let text: String
    public let jsonNumber: String
    public init(_ input: String) throws {
        let raw = input.trimmingCharacters(in: .whitespaces)
        let pattern = #"^\+?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil,
              let value = Double(raw), value.isFinite, value > 0,
              Float(value).isFinite, Float(value) > 0 else {
            throw MetaPromptError("Shift must be a finite positive number supported by Draw Things.")
        }
        // Canonical JSON numeric spelling, retaining all fractional digits (including trailing zeroes).
        var canonical = raw.hasPrefix("+") ? String(raw.dropFirst()) : raw
        let exponentIndex = canonical.firstIndex(where: { $0 == "e" || $0 == "E" })
        let exponent = exponentIndex.map { String(canonical[$0...]) } ?? ""
        if let i = exponentIndex { canonical = String(canonical[..<i]) }
        let pieces = canonical.split(separator: ".", omittingEmptySubsequences: false)
        var whole = String(pieces[0]); while whole.count > 1 && whole.first == "0" { whole.removeFirst() }
        if whole.isEmpty { whole = "0" }
        let fraction = pieces.count == 2 && !pieces[1].isEmpty ? "." + pieces[1] : ""
        self.text = raw; self.jsonNumber = whole + fraction + exponent
    }
    public static func random<R: RandomNumberGenerator>(using rng: inout R) -> ShiftValue {
        let millis = Int.random(in: 1500...2250, using: &rng)
        return try! ShiftValue(String(format: "%d.%03d", millis / 1000, millis % 1000))
    }
    public static func viewerInput(_ input: String) throws -> ShiftValue {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^(?:[0-9]+(?:\.[0-9]{1,3})?|\.[0-9]{1,3})$"#, options: .regularExpression) != nil else {
            throw MetaPromptError("Enter a shift above 0 with at most 3 decimal places.")
        }
        return try ShiftValue(value)
    }
    public static func evaluating(_ input: String) throws -> ShiftValue {
        // Keep plain literals exactly as supplied; only arithmetic results are normalized.
        if let literal = try? ShiftValue(input) { return literal }
        var expression = ShiftExpression(input)
        let values = try expression.evaluate()
        guard values.count == 1 else { throw MetaPromptError("Expected one shift value, not a list.") }
        return try ShiftValue(NSDecimalNumber(decimal: values[0]).stringValue)
    }
    public static func evaluatingList(_ input: String) throws -> [ShiftValue] {
        // Split only top-level commas, preserving plain literals and item-specific feedback.
        var depth = 0; var items = [String](); var item = ""
        for character in input {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character == "," && depth == 0 { items.append(item); item = "" }
            else { item.append(character) }
        }
        items.append(item)
        if items.count > 1 {
            return try items.enumerated().flatMap { index, value in
                do { return try evaluatingList(value) }
                catch { throw MetaPromptError("Shift list item \(index + 1) is invalid: " + ((error as? MetaPromptError)?.message ?? error.localizedDescription)) }
            }
        }
        if let literal = try? ShiftValue(input) { return [literal] }
        var expression = ShiftExpression(input)
        return try expression.evaluate().enumerated().map { index, value in
            do { return try ShiftValue(NSDecimalNumber(decimal: value).stringValue) }
            catch { throw MetaPromptError("Shift result \(index + 1) is invalid: " + ((error as? MetaPromptError)?.message ?? error.localizedDescription)) }
        }
    }
    public func bumped(by bump: ShiftBump) throws -> ShiftValue {
        let locale = Locale(identifier: "en_US_POSIX")
        guard var value = Decimal(string: jsonNumber, locale: locale),
              var change = Decimal(string: bump.rawValue, locale: locale) else {
            throw MetaPromptError("This shift cannot be adjusted with decimal arithmetic.")
        }
        var result = Decimal()
        guard NSDecimalAdd(&result, &value, &change, .plain) == .noError else {
            throw MetaPromptError("This shift adjustment exceeds supported decimal precision.")
        }
        return try ShiftValue(NSDecimalNumber(decimal: result).stringValue)
    }
}

private struct ShiftExpression {
    private enum Value {
        case scalar(Decimal), vector([Decimal])
        var values: [Decimal] { switch self { case .scalar(let value): return [value]; case .vector(let values): return values } }
    }
    private let chars: [Character]
    private let label: String
    private var index = 0
    private var depth = 0
    init(_ input: String, label: String = "Shift expression") { chars = Array(input); self.label = label }
    mutating func evaluate() throws -> [Decimal] {
        guard chars.count <= 4096 else { throw MetaPromptError("\(label) is too long.") }
        let value = try list(); spaces()
        guard index == chars.count else { throw error("Unexpected character. Supported arithmetic: +, -, *, / and parentheses.") }
        return value.values
    }
    private func error(_ message: String) -> MetaPromptError { MetaPromptError("\(label) at character \(index + 1): " + message) }
    private mutating func spaces() { while index < chars.count && chars[index].isWhitespace { index += 1 } }
    private mutating func take(_ character: Character) -> Bool {
        spaces(); guard index < chars.count && chars[index] == character else { return false }
        index += 1; return true
    }
    private mutating func list() throws -> Value {
        let first = try sum()
        guard take(",") else { return first }
        var values = first.values
        repeat { values.append(contentsOf: try sum().values) } while take(",")
        return .vector(values)
    }
    private mutating func sum() throws -> Value {
        var value = try product()
        while true {
            if take("+") { value = try calculate(value, product(), operation: "+") }
            else if take("-") { value = try calculate(value, product(), operation: "-") }
            else { return value }
        }
    }
    private mutating func product() throws -> Value {
        var value = try factor()
        while true {
            if take("*") { value = try calculate(value, factor(), operation: "*") }
            else if take("/") { value = try calculate(value, factor(), operation: "/") }
            else { return value }
        }
    }
    private mutating func factor() throws -> Value {
        depth += 1; defer { depth -= 1 }
        guard depth <= 64 else { throw error("Expression nesting is too deep.") }
        if take("+") { return try factor() }
        if take("-") { return try calculate(.scalar(0), factor(), operation: "-") }
        if take("(") {
            let value = try list()
            guard take(")") else { throw error("Missing closing parenthesis.") }
            return value
        }
        spaces(); let start = index; var digits = 0
        func isDigit(_ character: Character) -> Bool { "0123456789".contains(character) }
        while index < chars.count && isDigit(chars[index]) { index += 1; digits += 1 }
        if index < chars.count && chars[index] == "." {
            index += 1
            while index < chars.count && isDigit(chars[index]) { index += 1; digits += 1 }
        }
        guard digits > 0 else { throw error("Expected a number.") }
        if index < chars.count && (chars[index] == "e" || chars[index] == "E") {
            index += 1
            if index < chars.count && (chars[index] == "+" || chars[index] == "-") { index += 1 }
            let exponentStart = index
            while index < chars.count && isDigit(chars[index]) { index += 1 }
            guard index > exponentStart else { throw error("Expected exponent digits.") }
        }
        guard let value = Decimal(string: String(chars[start..<index]), locale: Locale(identifier: "en_US_POSIX")) else { throw error("Number exceeds decimal arithmetic limits.") }
        return .scalar(value)
    }
    private func calculate(_ lhs: Value, _ rhs: Value, operation: Character) throws -> Value {
        switch (lhs, rhs) {
        case (.scalar(let a), .scalar(let b)): return .scalar(try calculateScalar(a, b, operation: operation))
        case (.vector(let a), .scalar(let b)): return .vector(try a.map { try calculateScalar($0, b, operation: operation) })
        case (.scalar(let a), .vector(let b)): return .vector(try b.map { try calculateScalar(a, $0, operation: operation) })
        case (.vector(let a), .vector(let b)):
            guard a.count == b.count else { throw error("Lists used together must have the same length.") }
            return .vector(try zip(a, b).map { try calculateScalar($0.0, $0.1, operation: operation) })
        }
    }
    private func calculateScalar(_ lhs: Decimal, _ rhs: Decimal, operation: Character) throws -> Decimal {
        var a = lhs, b = rhs, result = Decimal()
        let status: Decimal.CalculationError
        switch operation {
        case "+": status = NSDecimalAdd(&result, &a, &b, .plain)
        case "-": status = NSDecimalSubtract(&result, &a, &b, .plain)
        case "*": status = NSDecimalMultiply(&result, &a, &b, .plain)
        default:
            guard b != 0 else { throw error("Division by zero is not allowed.") }
            status = NSDecimalDivide(&result, &a, &b, .plain)
        }
        guard status == .noError || status == .lossOfPrecision else { throw error("Arithmetic overflow or underflow.") }
        return result
    }
}

public struct ShiftRange: Codable, Equatable {
    public let text: String
    public let lowerThousandth: Int
    public let upperThousandth: Int
    public init(_ input: String) throws {
        let parts = input.components(separatedBy: "..")
        guard parts.count == 2 else { throw MetaPromptError("Shift range must be lower..upper, for example 4.2..4.8.") }
        let lower = try ShiftValue.evaluating(parts[0]), upper = try ShiftValue.evaluating(parts[1])
        let locale = Locale(identifier: "en_US_POSIX")
        guard let a = Decimal(string: lower.jsonNumber, locale: locale),
              let b = Decimal(string: upper.jsonNumber, locale: locale), a <= b else {
            throw MetaPromptError("Shift range must have a lower bound no greater than its upper bound.")
        }
        var scaledLower = a * 1000, scaledUpper = b * 1000
        var first = Decimal(), last = Decimal()
        NSDecimalRound(&first, &scaledLower, 0, .up)
        NSDecimalRound(&last, &scaledUpper, 0, .down)
        guard first <= last, first >= 1, last < Decimal(Int.max) else {
            throw MetaPromptError("Shift range must contain a positive value at three decimal places within the supported range. Use a fixed shift for finer precision.")
        }
        text = lower.text + ".." + upper.text
        lowerThousandth = NSDecimalNumber(decimal: first).intValue
        upperThousandth = NSDecimalNumber(decimal: last).intValue
    }
    public func random<R: RandomNumberGenerator>(using rng: inout R) -> ShiftValue {
        let millis = Int.random(in: lowerThousandth...upperThousandth, using: &rng)
        return try! ShiftValue(String(millis / 1000) + "." + String(format: "%03d", millis % 1000))
    }
}

public enum ShiftListEntry: Codable, Equatable {
    case fixed(ShiftValue)
    case range(ShiftRange)
    public var text: String {
        switch self { case .fixed(let value): return value.text; case .range(let range): return range.text }
    }
    public func resolve<R: RandomNumberGenerator>(using rng: inout R) -> ShiftValue {
        switch self { case .fixed(let value): return value; case .range(let range): return range.random(using: &rng) }
    }
    static func parse(_ input: String, count: Int) throws -> [ShiftListEntry] {
        var items = [String](); var item = ""; var depth = 0
        for character in input {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character == ",", depth == 0 { items.append(item); item = "" }
            else { item.append(character) }
        }
        items.append(item)
        var entries = [ShiftListEntry]()
        for (index, item) in items.enumerated() {
            var raw = item.trimmingCharacters(in: .whitespaces)
            let fillsRemainder = raw.hasSuffix("*")
            if fillsRemainder {
                guard index == items.count - 1, raw.contains("..") else {
                    throw MetaPromptError("Only the final shift list item may use range* to fill the remainder.")
                }
                raw.removeLast()
            }
            let values: [ShiftListEntry]
            if raw.contains("..") { values = [.range(try ShiftRange(raw))] }
            else { values = try ShiftValue.evaluatingList(raw).map { .fixed($0) } }
            if fillsRemainder {
                guard entries.count <= count else {
                    throw MetaPromptError("Shift list has \(entries.count) entries before range*, but count is \(count). Increase count or remove entries.")
                }
                entries.append(contentsOf: repeatElement(values[0], count: count - entries.count))
            } else { entries.append(contentsOf: values) }
        }
        guard entries.count == count else {
            throw MetaPromptError("Shift list has \(entries.count) values, but count is \(count). Supply exactly \(count) entries or end with range* to fill the remainder.")
        }
        return entries
    }
}

public struct BatchParameters: Codable, Equatable {
    public var title: String
    public var seed: Int?
    public var seedValues: [Int?]?
    public var shift: ShiftValue?
    public var shiftRange: ShiftRange?
    public var shiftValues: [ShiftValue]?
    public var shiftEntries: [ShiftListEntry]? = nil
    public var steps: Int
    public var width: Int
    public var height: Int
    public var aspect: String? = nil
    public var pixelMax: Int? = nil
    public var count: Int
    public var notes: String
    public static let defaultPixelMax = 1024 * 1024
    public static let allowedKeys = ["title", "seed", "seeds", "shift", "steps", "resolution", "aspect", "pixel_max", "count", "notes"]
    public var seedDescription: String {
        if let seed { return String(seed) }
        if let seedValues { return seedValues.map { $0.map(String.init) ?? "_" }.joined(separator: ", ") }
        return "random per image"
    }
    public var shiftDescription: String {
        if let shift { return shift.text }
        if let shiftRange { return "random " + shiftRange.text }
        if let shiftValues { return shiftValues.map(\.text).joined(separator: ", ") }
        if let shiftEntries { return shiftEntries.map(\.text).joined(separator: ", ") }
        return "random 1.500–2.250"
    }

    public static func parse(_ header: String, now: Date = Date(), defaultTitle: String? = nil) throws -> BatchParameters {
        var fields: [String: String] = [:]
        for entry in try splitHeader(header) where !entry.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { throw MetaPromptError("Header entries must be key=value, separated by semicolons.") }
            let suppliedKey = entry[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let key = suppliedKey == "seeds" ? "seed" : suppliedKey
            guard allowedKeys.contains(key) else { throw MetaPromptError("Unknown parameter ‘\(key)’. Allowed: \(allowedKeys.joined(separator: ", ")).") }
            guard fields[key] == nil else { throw MetaPromptError("Parameter ‘\(key)’ appears more than once.") }
            fields[key] = try unquote(String(entry[entry.index(after: equals)...]).trimmingCharacters(in: .whitespaces))
        }
        func integer(_ key: String, default fallback: Int, min: Int, max: Int = Int(UInt32.max)) throws -> Int {
            guard let raw = fields[key] else { return fallback }
            guard raw.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
                  let n = Int(raw), n >= min, n <= max else {
                throw MetaPromptError("\(key) must be an integer from \(min) to \(max).")
            }
            return n
        }
        let title = fields["title"] ?? defaultTitle ?? String(Int64(now.timeIntervalSince1970))
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw MetaPromptError("Title cannot be empty; omit it to use the epoch timestamp.") }
        let steps = try integer("steps", default: 3, min: 1)
        let count = try integer("count", default: 4, min: 1, max: Int.max)
        func parseSeed(_ input: String, label: String) throws -> Int? {
            let value = input.trimmingCharacters(in: .whitespaces)
            if value == "_" { return nil }
            guard value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
                  let seed = Int(value), seed <= Int(Int32.max) else {
                throw MetaPromptError("\(label) (‘\(value)’) is invalid. Use an integer from 0 to \(Int32.max), or _ for a random seed.")
            }
            return seed
        }
        var seed: Int?; var seedValues: [Int?]?
        if let raw = fields["seed"] {
            if raw.contains(",") || raw.trimmingCharacters(in: .whitespaces) == "_*" {
                var entries = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let fillsRemainder = entries.last == "_*"
                if fillsRemainder { entries.removeLast() }
                guard !entries.contains("_*") else {
                    throw MetaPromptError("Seed remainder marker _* must appear only once, as the final seed list item.")
                }
                var values = try entries.enumerated().map { try parseSeed($0.element, label: "Seed list item \($0.offset + 1)") }
                if fillsRemainder {
                    guard values.count <= count else {
                        throw MetaPromptError("Seed list has \(values.count) entries before _*, but count is \(count). Increase count or remove seed entries.")
                    }
                    values.append(contentsOf: repeatElement(nil, count: count - values.count))
                }
                guard values.count == count else {
                    throw MetaPromptError("Seed list has \(values.count) values, but count is \(count). Set count=\(values.count) or supply exactly \(count) seed values.")
                }
                seedValues = values
            } else { seed = try parseSeed(raw, label: "Seed") }
        }
        var shift: ShiftValue?; var shiftRange: ShiftRange?; var shiftValues: [ShiftValue]?; var shiftEntries: [ShiftListEntry]?
        if let raw = fields["shift"] {
            if raw.contains(".."), raw.contains(",") || raw.trimmingCharacters(in: .whitespaces).hasSuffix("*") {
                shiftEntries = try ShiftListEntry.parse(raw, count: count)
            }
            else if raw.contains("..") { shiftRange = try ShiftRange(raw) }
            else {
                let values = try ShiftValue.evaluatingList(raw)
                if values.count == 1 { shift = values[0] }
                else {
                guard values.count == count else {
                    throw MetaPromptError("Shift list has \(values.count) values, but count is \(count). Set count=\(values.count) or supply exactly \(count) shift values.")
                }
                shiftValues = values
                }
            }
        }
        guard fields["resolution"] == nil || fields["aspect"] == nil else {
            throw MetaPromptError("Use either resolution or aspect, not both.")
        }
        var pixelMax = defaultPixelMax
        if let raw = fields["pixel_max"] {
            var expression = ShiftExpression(raw, label: "pixel_max expression")
            let values = try expression.evaluate()
            guard values.count == 1, let value = values.first, value > 0, value <= Decimal(Int.max) else {
                throw MetaPromptError("pixel_max must resolve to one positive whole pixel count, for example (1024*1024).")
            }
            var input = value, whole = Decimal(); NSDecimalRound(&whole, &input, 0, .plain)
            guard value == whole else { throw MetaPromptError("pixel_max must be a whole number of pixels.") }
            pixelMax = Int(NSDecimalNumber(decimal: value).int64Value)
        }
        var width = 1024; var height = 1024; var aspect: String?
        if let raw = fields["resolution"] {
            let parts = raw.lowercased().components(separatedBy: CharacterSet(charactersIn: "*x×"))
            guard parts.count == 2,
                  let w = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let h = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  w > 0, h > 0, w % 64 == 0, h % 64 == 0,
                  w / 64 <= Int(UInt16.max), h / 64 <= Int(UInt16.max) else {
                throw MetaPromptError("Resolution must be width*height, with positive multiples of 64, for example 1024*1024.")
            }
            width = w; height = h
        }
        if let raw = fields["aspect"] {
            let size = try AspectSizing.resolve(raw, pixelMax: pixelMax)
            width = size.width; height = size.height; aspect = size.aspect
        }
        try AspectSizing.validate(width: width, height: height, pixelMax: pixelMax)
        return BatchParameters(title: title, seed: seed, seedValues: seedValues, shift: shift, shiftRange: shiftRange, shiftValues: shiftValues, shiftEntries: shiftEntries, steps: steps, width: width, height: height, aspect: aspect, pixelMax: pixelMax, count: count, notes: fields["notes"] ?? "")
    }
    public static func replacingParameter(in source: String, key: String, value: String) throws -> String {
        guard ["seeds", "shift"].contains(key), let newline = source.firstIndex(of: "\n") else {
            throw MetaPromptError("Keep a parameter line followed by a newline before collecting values.")
        }
        let original = String(source[..<newline]); let bom = original.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : ""
        let header = bom.isEmpty ? original : String(original.dropFirst())
        var replaced = false
        var entries: [String] = []
        for entry in try splitHeader(header) {
            let name = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            let matches = key == "seeds" ? ["seed", "seeds"].contains(name) : name == key
            if matches {
                if !replaced { entries.append("\(key)=\(value)"); replaced = true }
            } else if !entry.trimmingCharacters(in: .whitespaces).isEmpty { entries.append(entry) }
        }
        if !replaced { entries.append("\(key)=\(value)") }
        return bom + entries.joined(separator: ";") + String(source[newline...])
    }
    private static func splitHeader(_ s: String) throws -> [String] {
        var result: [String] = []; var part = ""; var quote: Character?; var escaped = false
        for c in s {
            if escaped { part.append(c); escaped = false; continue }
            if c == "\\" { part.append(c); escaped = true; continue }
            if let q = quote { part.append(c); if c == q { quote = nil }; continue }
            if c == "\"" || c == "'" {
                if let equals = part.firstIndex(of: "="), part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces).isEmpty { quote = c }
                part.append(c)
            }
            else if c == ";" { result.append(part); part = "" }
            else { part.append(c) }
        }
        guard quote == nil else { throw MetaPromptError("Unclosed quote in the parameter line.") }
        result.append(part); return result
    }
    private static func unquote(_ s: String) throws -> String {
        guard let first = s.first, first == "\"" || first == "'" else { return s }
        guard s.count >= 2, s.last == first else { throw MetaPromptError("Unclosed quoted value.") }
        let body = Array(s.dropFirst().dropLast()); var out = ""; var i = 0
        while i < body.count {
            if body[i] == "\\", i + 1 < body.count, [first, "\\", ";"].contains(body[i + 1]) { i += 1 }
            out.append(body[i]); i += 1
        }
        return out
    }
}

public indirect enum PromptNode: Equatable {
    case text(String)
    case choice([WeightedTerm])
    case field(String, fresh: Bool)
}
public struct WeightedTerm: Equatable {
    public let nodes: [PromptNode]
    public let weight: Double
}
public struct CompiledMetaPrompt {
    public let source: String
    public let parameters: BatchParameters
    public let nodes: [PromptNode]
    public let fieldNodes: [String: [PromptNode]]
    init(source: String, parameters: BatchParameters, nodes: [PromptNode], fieldNodes: [String: [PromptNode]] = [:]) {
        self.source = source; self.parameters = parameters; self.nodes = nodes; self.fieldNodes = fieldNodes
    }
    public static func promptBody(in source: String) -> String? {
        let document = PromptDocument(source)
        return document.hasHeaderNewline ? document.prompt : nil
    }
    public static func samePromptBody(_ first: String, _ second: String) -> Bool {
        guard let a = promptBody(in: first), let b = promptBody(in: second) else { return false }
        guard let x = try? FragmentParser(a).parsed(), let y = try? FragmentParser(b).parsed() else { return false }
        // Variable contents (including inline choices) are configuration. Literal
        // template text and variable placement define batch identity.
        func identity(_ nodes: [PromptNode]) -> String {
            nodes.map { node in
                switch node {
                case .text(let text): return "T\(text.utf8.count):" + text
                case .choice, .field: return "V;"
                }
            }.joined()
        }
        return identity(x) == identity(y)
    }
    public static func compile(_ source: String, now: Date = Date(), defaultTitle: String? = nil) throws -> CompiledMetaPrompt {
        let document = PromptDocument(source)
        guard document.hasHeaderNewline else {
            throw MetaPromptError("Put parameters on the first line, then a newline and the prompt. A blank first line uses all defaults.")
        }
        let parameters = try BatchParameters.parse(document.header, now: now, defaultTitle: defaultTitle)
        let nodes = try FragmentParser(document.prompt).parsed()
        var fields = [String: [PromptNode]]()
        for field in try document.fields() {
            do { fields[field.name] = try FragmentParser(field.value, firstLine: field.line).parsed() }
            catch let error as MetaPromptError { throw MetaPromptError("Field \(field.name): " + error.message, line: error.line, column: error.column) }
        }
        // Validate every branch, including unused fields. Bound expansion before
        // generation so cycles or exponentially repeated references cannot hang.
        let limit = 1_000_000
        var visiting = Set<String>(); var sizes = [String: Int]()
        func size(_ nodes: [PromptNode], chain: [String]) throws -> Int {
            var total = 0
            for node in nodes {
                let n: Int
                switch node {
                case .text(let text): n = text.utf8.count
                case .choice(let choices): n = try choices.map { try size($0.nodes, chain: chain) }.max() ?? 0
                case .field(let name, _):
                    guard let value = fields[name] else { throw MetaPromptError("Unknown field [\(name)]. Define it in Fields or escape literal brackets with a backslash.") }
                    guard !visiting.contains(name) else { throw MetaPromptError("Circular field reference: " + (chain + [name]).joined(separator: " → ")) }
                    guard chain.count < 64 else { throw MetaPromptError("Field references exceed the supported nesting depth of 64.") }
                    if let cached = sizes[name] { n = cached }
                    else {
                        visiting.insert(name); defer { visiting.remove(name) }
                        n = try size(value, chain: chain + [name]); sizes[name] = n
                    }
                }
                guard n <= limit - total else { throw MetaPromptError("Expanded prompt or field exceeds the supported size of 1 MB.") }
                total += n
            }
            return total
        }
        for name in fields.keys.sorted() { _ = try size([.field(name, fresh: false)], chain: []) }
        _ = try size(nodes, chain: [])
        var heights = [String: Int]()
        func references(_ nodes: [PromptNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .text: return []
                case .field(let name, _): return [name]
                case .choice(let choices): return choices.flatMap { references($0.nodes) }
                }
            }
        }
        func height(_ name: String, level: Int) throws -> Int {
            guard level <= 64 else { throw MetaPromptError("Field references exceed the supported nesting depth of 64.") }
            if let cached = heights[name] {
                guard level + cached - 1 <= 64 else { throw MetaPromptError("Field references exceed the supported nesting depth of 64.") }
                return cached
            }
            let value = 1 + (try references(fields[name] ?? []).map { try height($0, level: level + 1) }.max() ?? 0)
            guard value <= 64 else { throw MetaPromptError("Field references exceed the supported nesting depth of 64.") }
            heights[name] = value; return value
        }
        for name in fields.keys.sorted() { _ = try height(name, level: 1) }
        return CompiledMetaPrompt(source: source, parameters: parameters, nodes: nodes, fieldNodes: fields)
    }
    public func resolve<R: RandomNumberGenerator>(using rng: inout R) -> String {
        var shared = [String: String]()
        return resolve(nodes, shared: &shared, using: &rng)
    }
    private func resolve<R: RandomNumberGenerator>(_ nodes: [PromptNode], shared: inout [String: String], using rng: inout R) -> String {
        var result = ""
        for node in nodes {
            switch node {
            case .text(let s): result += s
            case .field(let name, let fresh):
                if !fresh, let value = shared[name] { result += value }
                else {
                    let value = resolve(fieldNodes[name] ?? [], shared: &shared, using: &rng)
                    if !fresh { shared[name] = value }
                    result += value
                }
            case .choice(let options):
                let positive = options.filter { $0.weight > 0 }
                guard !positive.isEmpty else { continue }
                let selected: WeightedTerm
                if positive.count == 1 { selected = positive[0] }
                else {
                    // Normalize first, so large valid weights cannot overflow the total.
                    let scale = positive.map(\.weight).max()!
                    let total = positive.reduce(0) { $0 + $1.weight / scale }
                    let pick = Double.random(in: 0..<total, using: &rng)
                    var cumulative = 0.0; var choice = positive.last!
                    for option in positive { cumulative += option.weight / scale; if pick < cumulative { choice = option; break } }
                    selected = choice
                }
                result += resolve(selected.nodes, shared: &shared, using: &rng) // Never resolve an unselected nested branch.
            }
        }
        return result
    }
}

private struct FragmentParser {
    let chars: [Character]; let firstLine: Int; var index = 0; var depth = 0
    init(_ s: String, firstLine: Int = 2) { chars = Array(s); self.firstLine = firstLine }
    func parsed() throws -> [PromptNode] { var copy = self; return try copy.parse() }
    mutating func parse() throws -> [PromptNode] {
        let nodes = try sequence(inChoice: false)
        if index != chars.count { throw error("Unexpected closing brace.") }
        return nodes
    }
    func error(_ message: String, at position: Int? = nil) -> MetaPromptError {
        let before = chars.prefix(position ?? index); let line = firstLine + before.filter { $0 == "\n" }.count
        let col = before.reversed().prefix { $0 != "\n" }.count + 1
        return MetaPromptError(message, line: line, column: col)
    }
    func isWeight() -> Bool { index + 2 < chars.count && chars[index] == ":" && chars[index + 1] == ":" && chars[index + 2] == ":" }
    mutating func sequence(inChoice: Bool) throws -> [PromptNode] {
        var nodes: [PromptNode] = []; var text = ""
        func flushed(_ text: inout String, _ nodes: inout [PromptNode]) { if !text.isEmpty { nodes.append(.text(text)); text = "" } }
        while index < chars.count {
            let c = chars[index]
            if inChoice && (c == "|" || c == "}" || isWeight()) { break }
            if c == "}" { throw error("Closing brace has no matching opening brace. Escape literal braces with a backslash.") }
            if c == "\\", index + 1 < chars.count, "{}|:\\[]".contains(chars[index + 1]) {
                index += 1; text.append(chars[index]); index += 1; continue
            }
            if c == "{" { flushed(&text, &nodes); nodes.append(try choice()); continue }
            if c == "[" {
                let opened = index; index += 1; let start = index
                while index < chars.count && chars[index] != "]" { index += 1 }
                guard index < chars.count else { throw error("Field reference is not closed. Escape literal brackets with a backslash.", at: opened) }
                var name = String(chars[start..<index]); let fresh = name.hasSuffix("*")
                if fresh { name.removeLast() }
                guard PromptDocument.isFieldName(name) else { throw error("Use [NAME] for a shared field or [NAME*] for a fresh value.", at: opened) }
                flushed(&text, &nodes); nodes.append(.field(name, fresh: fresh)); index += 1; continue
            }
            text.append(c); index += 1
        }
        flushed(&text, &nodes); return nodes
    }
    mutating func choice() throws -> PromptNode {
        let opened = index; index += 1; depth += 1
        guard depth <= 256 else { throw error("Fragment nesting exceeds the supported depth of 256.", at: opened) }
        defer { depth -= 1 }
        if index < chars.count && chars[index] == "}" { index += 1; return .choice([]) }
        var options: [WeightedTerm] = []
        while true {
            let nodes = try sequence(inChoice: true); var weight = 1.0
            if isWeight() {
                index += 3; let start = index
                while index < chars.count && chars[index] != "|" && chars[index] != "}" { index += 1 }
                guard index < chars.count else { throw error("Fragment opened here is not closed.", at: opened) }
                let raw = String(chars[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let n = Double(raw), n.isFinite, n >= 0 else { throw error("Weight must be a finite nonnegative number.", at: start) }
                weight = n
            }
            options.append(WeightedTerm(nodes: nodes, weight: weight))
            guard index < chars.count else { throw error("Fragment opened here is not closed.", at: opened) }
            if chars[index] == "}" {
                index += 1
                guard options.contains(where: { $0.weight > 0 }) else { throw error("A fragment needs at least one positive-weight term.", at: opened) }
                return .choice(options)
            }
            guard chars[index] == "|" else { throw error("Expected | or } in fragment.") }
            index += 1
        }
    }
}
