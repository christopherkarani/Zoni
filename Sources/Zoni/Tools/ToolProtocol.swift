// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ToolProtocol.swift - SwiftAgents-compatible tool protocol definitions.

import Foundation

// MARK: - Tool Protocol

/// A protocol for tools that can be executed by AI agents.
///
/// This protocol matches SwiftAgents' `Tool` protocol for seamless integration.
/// Tools conforming to this protocol can be used directly with SwiftAgents
/// or standalone within Zoni.
///
/// Example usage:
/// ```swift
/// let searchTool = RAGSearchTool(retriever: myRetriever)
/// let result = try await searchTool.execute(arguments: [
///     "query": .string("Swift concurrency"),
///     "limit": .int(5)
/// ])
/// ```
public protocol Tool: Sendable {
    /// The unique name identifying this tool.
    var name: String { get }

    /// A description of what this tool does.
    var description: String { get }

    /// The parameters this tool accepts.
    var parameters: [ToolParameter] { get }

    /// Executes the tool with the given arguments.
    ///
    /// - Parameter arguments: A dictionary of argument names to values.
    /// - Returns: The result of the tool execution as a `SendableValue`.
    /// - Throws: `ZoniError` if execution fails.
    func execute(arguments: [String: SendableValue]) async throws -> SendableValue
}

// MARK: - ToolParameter

/// Describes a parameter that a tool accepts.
///
/// Example:
/// ```swift
/// let param = ToolParameter(
///     name: "query",
///     description: "The search query",
///     type: .string,
///     isRequired: true
/// )
/// ```
public struct ToolParameter: Sendable, Equatable {
    /// The name of the parameter.
    public let name: String

    /// A description of what this parameter is for.
    public let description: String

    /// The expected type of the parameter value.
    public let type: ParameterType

    /// Whether this parameter is required.
    public let isRequired: Bool

    /// The default value for this parameter, if any.
    public let defaultValue: SendableValue?

    /// Creates a new tool parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - description: A description of the parameter.
    ///   - type: The expected type.
    ///   - isRequired: Whether the parameter is required.
    ///   - defaultValue: Optional default value.
    public init(
        name: String,
        description: String,
        type: ParameterType,
        isRequired: Bool,
        defaultValue: SendableValue? = nil
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
}

// MARK: - ParameterType

/// The type of a tool parameter value.
///
/// Supports primitive types, arrays, objects, and enumerated values.
public indirect enum ParameterType: Sendable, Equatable {
    /// A string value.
    case string

    /// An integer value.
    case int

    /// A floating-point value.
    case double

    /// A boolean value.
    case bool

    /// An array of values with a specific element type.
    case array(elementType: ParameterType)

    /// An object with specific properties.
    case object(properties: [ToolParameter])

    /// One of a set of string values (enum).
    case oneOf([String])

    /// Any value type.
    case any
}

// MARK: - SendableValue

/// A type-safe value container for tool arguments and results.
///
/// `SendableValue` is similar to JSON and can represent null, booleans,
/// numbers, strings, arrays, and dictionaries. It is `Sendable` for
/// safe use across actor boundaries.
///
/// Example:
/// ```swift
/// let value: SendableValue = .dictionary([
///     "name": .string("John"),
///     "age": .int(30),
///     "scores": .array([.double(95.5), .double(87.0)])
/// ])
/// ```
public enum SendableValue: Sendable, Equatable {
    /// A null value.
    case null

    /// A boolean value.
    case bool(Bool)

    /// An integer value.
    case int(Int)

    /// A floating-point value.
    case double(Double)

    /// A string value.
    case string(String)

    /// An array of values.
    case array([SendableValue])

    /// A dictionary of string keys to values.
    case dictionary([String: SendableValue])
}

// MARK: - SendableValue + Codable

extension SendableValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([SendableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: SendableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode SendableValue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

// MARK: - SendableValue + Hashable

extension SendableValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0)
        case .bool(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .int(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .double(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .array(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .dictionary(let value):
            hasher.combine(6)
            for (key, val) in value.sorted(by: { $0.key < $1.key }) {
                hasher.combine(key)
                hasher.combine(val)
            }
        }
    }
}

// MARK: - SendableValue + ExpressibleByLiteral

extension SendableValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension SendableValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension SendableValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension SendableValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension SendableValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension SendableValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: SendableValue...) {
        self = .array(elements)
    }
}

extension SendableValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, SendableValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - SendableValue + CustomStringConvertible

extension SendableValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return String(value)
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return "\"\(value)\""
        case .array(let value):
            return "[\(value.map(\.description).joined(separator: ", "))]"
        case .dictionary(let value):
            let pairs = value.map { "\"\($0.key)\": \($0.value.description)" }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }
}
