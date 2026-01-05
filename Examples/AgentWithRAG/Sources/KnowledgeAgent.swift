// AgentWithRAG Example
//
// KnowledgeAgent.swift - An agent that uses RAG tools to answer questions.

import Zoni
import ZoniAgents

// MARK: - KnowledgeAgent

/// An agent that uses RAG tools to answer questions from a knowledge base.
///
/// `KnowledgeAgent` demonstrates how to build an AI agent that can:
/// - Search a knowledge base for relevant information
/// - Ingest new documents into the knowledge base
/// - Answer questions using retrieved context
///
/// The agent follows a simple decision loop:
/// 1. Analyze the user's query
/// 2. Select appropriate tool(s) to use
/// 3. Execute tools and gather information
/// 4. Formulate a response
///
/// ## Example Usage
///
/// ```swift
/// let agent = KnowledgeAgent(pipeline: ragPipeline)
///
/// // Ask a question
/// let response = try await agent.ask("What is Swift concurrency?")
/// print(response.answer)
///
/// // Add new knowledge
/// try await agent.learn(content: "Swift 6 introduces...", title: "Swift 6 Features")
///
/// // Search without answering
/// let results = try await agent.search("concurrency patterns")
/// ```
@MainActor
public final class KnowledgeAgent: Sendable {

    // MARK: - Types

    /// Response from the agent containing the answer and metadata.
    public struct Response: Sendable {
        /// The generated answer text.
        public let answer: String

        /// The tools that were used to generate this response.
        public let toolsUsed: [String]

        /// The sources consulted for this answer.
        public let sources: [SourceReference]

        /// Confidence level in the answer.
        public let confidence: Confidence

        /// Creates a new response.
        public init(
            answer: String,
            toolsUsed: [String],
            sources: [SourceReference],
            confidence: Confidence
        ) {
            self.answer = answer
            self.toolsUsed = toolsUsed
            self.sources = sources
            self.confidence = confidence
        }
    }

    /// A reference to a source document used in the response.
    public struct SourceReference: Sendable {
        /// The source identifier or title.
        public let source: String

        /// Relevance score (0.0 to 1.0).
        public let score: Float

        /// A brief excerpt from the source.
        public let excerpt: String
    }

    /// Confidence level in an answer.
    public enum Confidence: String, Sendable {
        case high
        case medium
        case low
        case unknown
    }

    // MARK: - Properties

    /// The RAG tools available to this agent.
    private let tools: [any Tool]

    /// Tool lookup by name for quick access.
    private let toolsByName: [String: any Tool]

    /// The RAG pipeline for direct access when needed.
    private let pipeline: RAGPipeline

    // MARK: - Initialization

    /// Creates a new knowledge agent with the given RAG pipeline.
    ///
    /// - Parameter pipeline: The RAG pipeline providing knowledge base access.
    public init(pipeline: RAGPipeline) {
        self.pipeline = pipeline

        // Create the tool bundle
        let ragTools: [any Tool] = [
            SearchKnowledgeBaseTool(pipeline: pipeline),
            IngestDocumentTool(pipeline: pipeline),
            QueryKnowledgeTool(pipeline: pipeline)
        ]
        self.tools = ragTools
        self.toolsByName = Dictionary(uniqueKeysWithValues: ragTools.map { ($0.name, $0) })
    }

    // MARK: - Public Methods

    /// Asks a question and gets an answer from the knowledge base.
    ///
    /// This method uses the RAG pipeline to:
    /// 1. Search for relevant documents
    /// 2. Generate an answer using the retrieved context
    ///
    /// - Parameter question: The question to answer.
    /// - Returns: A response containing the answer and metadata.
    /// - Throws: `ZoniError` if the query fails.
    public func ask(_ question: String) async throws -> Response {
        // Use the query tool to get a comprehensive answer
        guard let queryTool = toolsByName["query_knowledge"] else {
            throw ZoniError.invalidConfiguration(reason: "Query tool not available")
        }

        let result = try await queryTool.execute(arguments: [
            "question": .string(question),
            "max_sources": .int(5),
            "include_sources": .bool(true)
        ])

        // Parse the result
        guard let resultDict = result.dictionaryValue else {
            throw ZoniError.generationFailed(reason: "Invalid tool response format")
        }

        let answer = resultDict["answer"]?.stringValue ?? "Unable to generate an answer."
        let confidenceStr = resultDict["confidence"]?.stringValue ?? "unknown"
        let confidence = Confidence(rawValue: confidenceStr) ?? .unknown

        // Extract sources
        var sources: [SourceReference] = []
        if let sourcesArray = resultDict["sources"]?.arrayValue {
            for sourceValue in sourcesArray {
                if let sourceDict = sourceValue.dictionaryValue {
                    let sourceId = sourceDict["source"]?.stringValue ?? "unknown"
                    let score = Float(sourceDict["score"]?.doubleValue ?? 0.0)
                    let excerpt = sourceDict["content"]?.stringValue ?? ""
                    sources.append(SourceReference(source: sourceId, score: score, excerpt: excerpt))
                }
            }
        }

        return Response(
            answer: answer,
            toolsUsed: ["query_knowledge"],
            sources: sources,
            confidence: confidence
        )
    }

    /// Searches the knowledge base without generating an answer.
    ///
    /// Use this method when you want to see what documents are available
    /// for a particular topic without asking a specific question.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum number of results. Default: 5.
    /// - Returns: An array of source references.
    /// - Throws: `ZoniError` if the search fails.
    public func search(_ query: String, limit: Int = 5) async throws -> [SourceReference] {
        guard let searchTool = toolsByName["search_knowledge_base"] else {
            throw ZoniError.invalidConfiguration(reason: "Search tool not available")
        }

        let result = try await searchTool.execute(arguments: [
            "query": .string(query),
            "limit": .int(limit)
        ])

        guard let resultDict = result.dictionaryValue,
              let resultsArray = resultDict["results"]?.arrayValue else {
            return []
        }

        return resultsArray.compactMap { value -> SourceReference? in
            guard let dict = value.dictionaryValue else { return nil }
            let source = dict["source"]?.stringValue ?? dict["document_id"]?.stringValue ?? "unknown"
            let score = Float(dict["score"]?.doubleValue ?? 0.0)
            let content = dict["content"]?.stringValue ?? ""
            return SourceReference(source: source, score: score, excerpt: String(content.prefix(200)))
        }
    }

    /// Adds new content to the knowledge base.
    ///
    /// This method allows the agent to learn new information that can
    /// be retrieved in future queries.
    ///
    /// - Parameters:
    ///   - content: The content to add.
    ///   - title: Optional title for the document.
    ///   - source: Optional source identifier.
    /// - Returns: The ID of the ingested document.
    /// - Throws: `ZoniError` if ingestion fails.
    @discardableResult
    public func learn(content: String, title: String? = nil, source: String? = nil) async throws -> String {
        guard let ingestTool = toolsByName["ingest_document"] else {
            throw ZoniError.invalidConfiguration(reason: "Ingest tool not available")
        }

        var arguments: [String: SendableValue] = [
            "content": .string(content)
        ]

        if let title = title {
            arguments["title"] = .string(title)
        }

        if let source = source {
            arguments["source"] = .string(source)
        }

        let result = try await ingestTool.execute(arguments: arguments)

        guard let resultDict = result.dictionaryValue,
              let documentId = resultDict["document_id"]?.stringValue else {
            throw ZoniError.insertionFailed(reason: "Failed to ingest document")
        }

        return documentId
    }

    /// Returns all available tools for this agent.
    ///
    /// This is useful for inspecting the agent's capabilities or for
    /// passing tools to another agent framework.
    public func availableTools() -> [any Tool] {
        tools
    }

    /// Returns tool definitions for use in prompts or documentation.
    ///
    /// Each tool definition includes the tool name, description, and parameters.
    public func toolDefinitions() -> [AgentToolDefinition] {
        tools.map { $0.agentDefinition }
    }
}

// MARK: - Agent Execution Trace

/// A record of agent actions for debugging and observability.
public struct AgentTrace: Sendable {
    /// The original user query.
    public let query: String

    /// Tools executed during this interaction.
    public let toolCalls: [ToolCall]

    /// The final response.
    public let response: KnowledgeAgent.Response

    /// Total execution time.
    public let duration: Duration

    /// A single tool call record.
    public struct ToolCall: Sendable {
        /// The tool that was called.
        public let toolName: String

        /// Arguments passed to the tool.
        public let arguments: [String: SendableValue]

        /// The tool's response.
        public let result: SendableValue

        /// Time taken for this tool call.
        public let duration: Duration
    }
}
