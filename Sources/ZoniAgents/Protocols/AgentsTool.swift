// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// AgentsTool.swift - Tool protocol compatibility for SwiftAgents.

import Zoni

// MARK: - AgentTool Type Alias

/// Type alias confirming that Zoni's `Tool` protocol is compatible with SwiftAgents.
///
/// Zoni's `Tool` protocol was designed to match SwiftAgents' expected interface:
/// - `name: String` - Unique tool identifier
/// - `description: String` - Tool description for agent prompts
/// - `parameters: [ToolParameter]` - Parameter definitions
/// - `execute(arguments:) async throws -> SendableValue` - Execution method
///
/// This means you can use Zoni's RAG tools directly with SwiftAgents:
///
/// ```swift
/// let searchTool = RAGSearchTool(retriever: myRetriever)
///
/// // Use directly with SwiftAgents
/// let agent = ReActAgent.Builder()
///     .addTool(searchTool)
///     .build()
/// ```
public typealias AgentTool = Tool

// MARK: - AgentToolDefinition

/// A serializable representation of a tool's definition.
///
/// This struct can be encoded to JSON for inclusion in agent prompts
/// or for documentation purposes.
///
/// ```swift
/// let tool = RAGSearchTool(retriever: myRetriever)
/// let definition = tool.agentDefinition
///
/// let json = try JSONEncoder().encode(definition)
/// ```
public struct AgentToolDefinition: Sendable, Codable, Equatable {

    /// The unique name identifying this tool.
    public let name: String

    /// A description of what this tool does.
    public let description: String

    /// The parameters this tool accepts.
    public let parameters: [AgentToolParameterDefinition]

    /// Creates a new tool definition.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - parameters: The parameter definitions.
    public init(
        name: String,
        description: String,
        parameters: [AgentToolParameterDefinition]
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

// MARK: - AgentToolParameterDefinition

/// A serializable representation of a tool parameter.
public struct AgentToolParameterDefinition: Sendable, Codable, Equatable {

    /// The parameter name.
    public let name: String

    /// A description of this parameter.
    public let description: String

    /// The expected type as a string.
    public let type: String

    /// Whether this parameter is required.
    public let isRequired: Bool

    /// Creates a new parameter definition.
    public init(
        name: String,
        description: String,
        type: String,
        isRequired: Bool
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.isRequired = isRequired
    }
}

// MARK: - Tool Extension

extension Tool {

    /// Converts this tool to a serializable definition.
    ///
    /// Useful for generating agent prompts or documentation.
    ///
    /// ```swift
    /// let tool = RAGSearchTool(retriever: myRetriever)
    /// print(tool.agentDefinition)
    /// // AgentToolDefinition(name: "search_knowledge", ...)
    /// ```
    public var agentDefinition: AgentToolDefinition {
        AgentToolDefinition(
            name: name,
            description: description,
            parameters: parameters.map { param in
                AgentToolParameterDefinition(
                    name: param.name,
                    description: param.description,
                    type: param.type.typeString,
                    isRequired: param.isRequired
                )
            }
        )
    }
}

// MARK: - ParameterType Extension

extension ParameterType {

    /// Returns a string representation of this parameter type.
    var typeString: String {
        switch self {
        case .string:
            return "string"
        case .int:
            return "integer"
        case .double:
            return "number"
        case .bool:
            return "boolean"
        case .array(let elementType):
            return "array<\(elementType.typeString)>"
        case .object(let properties):
            let propertyNames = properties.map(\.name).joined(separator: ", ")
            return "object{\(propertyNames)}"
        case .oneOf(let options):
            return "enum[\(options.joined(separator: ", "))]"
        case .any:
            return "any"
        }
    }
}
