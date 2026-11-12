import Foundation

/// Portable metaprompt storage. UI panels are views of this one document, so
/// saved drafts, queued snapshots and old reports continue to use one source.
public struct PromptDocument {
    public static let fieldsMarker = "%%FIELDS%%"
    public var header: String
    public var prompt: String
    public var fieldsText: String
    public var hasFieldsSection: Bool
    public let hasHeaderNewline: Bool
    public init(_ source: String) {
        let clean = (source.hasPrefix("\u{FEFF}") ? String(source.dropFirst()) : source)
            .replacingOccurrences(of: "\r\n", with: "\n")
        guard let newline = clean.firstIndex(of: "\n") else {
            header = clean; prompt = ""; fieldsText = ""; hasFieldsSection = false; hasHeaderNewline = false
            return
        }
        hasHeaderNewline = true
        header = String(clean[..<newline])
        let lines = String(clean[clean.index(after: newline)...]).components(separatedBy: "\n")
        if let marker = lines.firstIndex(of: Self.fieldsMarker) {
            prompt = lines[..<marker].joined(separator: "\n")
            fieldsText = lines.dropFirst(marker + 1).joined(separator: "\n")
            hasFieldsSection = true
        } else {
            prompt = lines.joined(separator: "\n"); fieldsText = ""; hasFieldsSection = false
        }
    }
    public var source: String {
        header + "\n" + prompt + (hasFieldsSection || !fieldsText.isEmpty ? "\n" + Self.fieldsMarker + "\n" + fieldsText : "")
    }
    public struct Field {
        public let name: String
        public let value: String
        public let line: Int
    }
    public static func isFieldName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
    public func fields() throws -> [Field] {
        var result: [Field] = []; var names = Set<String>()
        var current: String?; var value = [String](); var started = 0
        let firstLine = prompt.components(separatedBy: "\n").count + 3
        func appendCurrent() {
            if let name = current { result.append(Field(name: name, value: value.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), line: started)) }
        }
        for (offset, line) in fieldsText.components(separatedBy: "\n").enumerated() {
            if let equals = line.firstIndex(of: "="), !line.hasPrefix(" "), !line.hasPrefix("\t"),
               Self.isFieldName(String(line[..<equals]).trimmingCharacters(in: .whitespaces)) {
                appendCurrent()
                let name = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
                guard names.insert(name).inserted else { throw MetaPromptError("Field \(name) is defined more than once.", line: firstLine + offset) }
                current = name; started = firstLine + offset; value = [String(line[line.index(after: equals)...])]
            } else if current != nil { value.append(line) }
            else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw MetaPromptError("Start a field with NAME=value at the beginning of a line.", line: firstLine + offset)
            }
        }
        appendCurrent(); return result
    }

    /// Extract only outer choices, retaining the exact original nested syntax.
    /// Unique names keep each original occurrence independent and RNG order intact.
    public func extractingChoices() throws -> PromptDocument {
        _ = try CompiledMetaPrompt.compile(source)
        var result = self; var used = Set(try fields().map(\.name))
        let chars = Array(prompt); var index = 0; var output = ""; var definitions = [String](); var number = 1
        while index < chars.count {
            if chars[index] == "\\", index + 1 < chars.count {
                output.append(chars[index]); output.append(chars[index + 1]); index += 2; continue
            }
            guard chars[index] == "{" else { output.append(chars[index]); index += 1; continue }
            let start = index; var depth = 0
            repeat {
                if chars[index] == "\\", index + 1 < chars.count { index += 2; continue }
                if chars[index] == "{" { depth += 1 }
                if chars[index] == "}" { depth -= 1 }
                index += 1
            } while index < chars.count && depth > 0
            while used.contains("FIELD_\(number)") { number += 1 }
            let name = "FIELD_\(number)"; number += 1; used.insert(name)
            definitions.append(name + "=" + String(chars[start..<index]))
            output += "[\(name)]"
        }
        if !definitions.isEmpty {
            result.prompt = output
            result.fieldsText = fieldsText + (fieldsText.isEmpty || fieldsText.hasSuffix("\n") ? "" : "\n") + definitions.joined(separator: "\n")
            result.hasFieldsSection = true
        }
        return result
    }
}
