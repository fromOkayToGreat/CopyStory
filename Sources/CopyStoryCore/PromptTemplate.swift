import Foundation

public enum TemplateError: LocalizedError, Equatable {
    case malformedPlaceholder, missingValue(String), invalidVariables, invalidDropdown(String), emptyEntry, oversized
    public var errorDescription: String? {
        switch self {
        case .malformedPlaceholder: return "Use {{name}} for variables. Names must start with a letter or underscore and contain only letters, numbers, or underscores."
        case .missingValue(let name): return "Enter a value for \(name)."
        case .invalidVariables: return "Variable settings must match the variables in the prompt."
        case .invalidDropdown(let name): return "Give \(name) distinct, nonempty options and choose a default from those options."
        case .emptyEntry: return "Enter a title and prompt text."
        case .oversized: return "This prompt is too large. Keep templates and completed text under 32 MB."
        }
    }
}

public struct TemplateVariable: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case text, dropdown }
    public var name: String
    public var kind: Kind
    public var defaultValue: String
    public var options: [String]
    public var id: String { name }
    public init(name: String, kind: Kind = .text, defaultValue: String = "", options: [String] = []) {
        self.name = name; self.kind = kind; self.defaultValue = defaultValue; self.options = options
    }
}

/// A deliberately small, non-executable template language. Values are inserted once.
public struct PromptTemplate: Sendable {
    private enum Part: Sendable { case literal(String), variable(String) }
    private let parts: [Part]
    public let variableNames: [String]

    public init(_ text: String) throws {
        guard text.utf8.count <= HistoryStore.maximumTextBytes else { throw TemplateError.oversized }
        var parts: [Part] = [], names: [String] = [], seen = Set<String>()
        var cursor = text.startIndex, literal = ""
        func flush() { if !literal.isEmpty { parts.append(.literal(literal)); literal = "" } }
        while cursor < text.endIndex {
            let remaining = text[cursor...]
            let escaped = remaining.hasPrefix("\\{{")
            if escaped || remaining.hasPrefix("{{") {
                let start = text.index(cursor, offsetBy: escaped ? 3 : 2)
                guard let end = text.range(of: "}}", range: start..<text.endIndex) else { throw TemplateError.malformedPlaceholder }
                let name = String(text[start..<end.lowerBound])
                if escaped { literal += "{{" + name + "}}" }
                else {
                    guard Self.validName(name) else { throw TemplateError.malformedPlaceholder }
                    flush(); parts.append(.variable(name))
                    if seen.insert(name).inserted { names.append(name) }
                }
                cursor = end.upperBound
            } else if remaining.hasPrefix("}}") {
                throw TemplateError.malformedPlaceholder
            } else {
                literal.append(text[cursor]); cursor = text.index(after: cursor)
            }
        }
        flush(); self.parts = parts; variableNames = names
    }

    private static func validName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        func letter(_ c: UInt8) -> Bool { (65...90).contains(c) || (97...122).contains(c) || c == 95 }
        guard let first = bytes.first, letter(first) else { return false }
        return bytes.dropFirst().allSatisfy { letter($0) || (48...57).contains($0) }
    }

    public func render(values: [String: String]) throws -> String {
        var output = "", byteCount = 0
        for part in parts {
            let value: String
            switch part {
            case .literal(let text): value = text
            case .variable(let name):
                guard let supplied = values[name], !supplied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TemplateError.missingValue(name)
                }
                value = supplied
            }
            byteCount += value.utf8.count
            guard byteCount <= HistoryStore.maximumTextBytes else { throw TemplateError.oversized }
            output += value
        }
        return output
    }
}

public struct LibraryEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var template: String
    public var variables: [TemplateVariable]
    public var isFavorite: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public init(id: String = UUID().uuidString.lowercased(), title: String = "", template: String = "",
                variables: [TemplateVariable] = [], isFavorite: Bool = false, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id; self.title = title; self.template = template; self.variables = variables
        self.isFavorite = isFavorite; self.createdAt = createdAt; self.modifiedAt = modifiedAt
    }
    public var defaultValues: [String: String] { variables.reduce(into: [:]) { $0[$1.name] = $1.defaultValue } }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TemplateError.emptyEntry }
        let parsed = try PromptTemplate(template)
        guard variables.map(\.name) == parsed.variableNames else { throw TemplateError.invalidVariables }
        for variable in variables where variable.kind == .dropdown {
            guard !variable.options.isEmpty, Set(variable.options).count == variable.options.count,
                  variable.options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  variable.options.contains(variable.defaultValue) else { throw TemplateError.invalidDropdown(variable.name) }
        }
    }

    public func render(values: [String: String]) throws -> String {
        try validate()
        for variable in variables where variable.kind == .dropdown {
            guard let value = values[variable.name], variable.options.contains(value) else { throw TemplateError.missingValue(variable.name) }
        }
        return try PromptTemplate(template).render(values: values)
    }
}
