// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGSummarizeTool.swift - Topic summarization tool for knowledge base.

import Foundation

// MARK: - RAGSummarizeTool

/// A tool for summarizing information about a topic from the knowledge base.
///
/// `RAGSummarizeTool` retrieves relevant documents about a topic and
/// generates a summary using the RAG pipeline. It supports different
/// summary styles: brief, detailed, or bullet points.
///
/// ## Example Usage
///
/// ```swift
/// let summarizeTool = RAGSummarizeTool(pipeline: myPipeline)
///
/// let result = try await summarizeTool.execute(arguments: [
///     "topic": .string("Swift concurrency"),
///     "style": .string("bullet_points"),
///     "max_sources": .int(10)
/// ])
///
/// if let summary = result.dictionaryValue?["summary"]?.stringValue {
///     print("Summary: \(summary)")
/// }
/// ```
///
/// ## SwiftAgents Integration
///
/// This tool conforms to the `Tool` protocol and can be used directly
/// with SwiftAgents:
///
/// ```swift
/// let agent = ReActAgent.Builder()
///     .addTool(RAGSummarizeTool(pipeline: myPipeline))
///     .build()
/// ```
public struct RAGSummarizeTool: Tool, Sendable {

    // MARK: - Tool Protocol Properties

    /// The unique name identifying this tool.
    public let name = "summarize_knowledge"

    /// A description of what this tool does.
    public let description = """
        Summarize information from the knowledge base on a topic.
        Retrieves relevant documents and generates a comprehensive summary.
        Use this when you need an overview of information on a topic.
        """

    /// The parameters this tool accepts.
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "topic",
            description: "The topic to summarize",
            type: .string,
            isRequired: true,
            defaultValue: nil
        ),
        ToolParameter(
            name: "max_sources",
            description: "Maximum number of sources to include (default: 10)",
            type: .int,
            isRequired: false,
            defaultValue: .int(10)
        ),
        ToolParameter(
            name: "style",
            description: "Summary style: 'brief', 'detailed', or 'bullet_points' (default: 'detailed')",
            type: .oneOf(["brief", "detailed", "bullet_points"]),
            isRequired: false,
            defaultValue: .string("detailed")
        )
    ]

    // MARK: - Private Properties

    /// The RAG pipeline used to generate summaries.
    private let pipeline: RAGPipeline

    // MARK: - Initialization

    /// Creates a new summarize tool with the specified pipeline.
    ///
    /// - Parameter pipeline: The RAG pipeline to use for summarization.
    public init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Constants

    /// Valid summary styles.
    private static let validStyles = ["brief", "detailed", "bullet_points"]

    // MARK: - Tool Execution

    /// Executes the summarization operation.
    ///
    /// - Parameter arguments: The arguments dictionary containing:
    ///   - `topic` (String, required): The topic to summarize.
    ///   - `max_sources` (Int, optional): Maximum sources to consider (must be >= 1). Default: 10.
    ///   - `style` (String, optional): Summary style ("brief", "detailed", "bullet_points"). Default: "detailed".
    /// - Returns: A dictionary containing:
    ///   - `summary`: The generated summary text.
    ///   - `topic`: The original topic.
    ///   - `sources_used`: Number of sources used.
    ///   - `style`: The summary style used.
    /// - Throws: `ZoniError.invalidConfiguration` if required arguments are missing
    ///           or if arguments have invalid values.
    ///           `ZoniError.generationFailed` if summarization fails.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        // Extract required topic argument
        let topic = try arguments.requireString("topic")

        // Extract and validate optional arguments
        let maxSources = arguments.optionalInt("max_sources", default: 10)
        guard maxSources >= 1 else {
            throw ZoniError.invalidConfiguration(
                reason: "max_sources must be at least 1, got \(maxSources)"
            )
        }

        let style = arguments.optionalString("style") ?? "detailed"
        guard Self.validStyles.contains(style) else {
            throw ZoniError.invalidConfiguration(
                reason: "Invalid style '\(style)'. Must be one of: \(Self.validStyles.joined(separator: ", "))"
            )
        }

        // Build the summarization prompt based on style
        let prompt = buildSummarizationPrompt(topic: topic, style: style)

        // Build the system prompt for summarization
        let systemPrompt = """
            You are a summarization assistant. Create clear, well-organized summaries \
            based on the provided context. Be accurate and cite information from the sources. \
            If the context doesn't contain relevant information, say so clearly.
            """

        // Build query options
        let options = QueryOptions(
            retrievalLimit: maxSources,
            systemPrompt: systemPrompt
        )

        // Execute the RAG query for summarization
        let response = try await pipeline.query(prompt, options: options)

        // Handle case where no relevant information was found
        if response.sources.isEmpty {
            return .dictionary([
                "summary": .string("No relevant information found for this topic in the knowledge base."),
                "topic": .string(topic),
                "sources_used": .int(0),
                "style": .string(style)
            ])
        }

        // Return the summarization result
        return .dictionary([
            "summary": .string(response.answer),
            "topic": .string(topic),
            "sources_used": .int(response.sources.count),
            "style": .string(style)
        ])
    }

    // MARK: - Private Helpers

    /// Builds a summarization prompt based on the style.
    ///
    /// - Parameters:
    ///   - topic: The topic to summarize.
    ///   - style: The desired summary style (must be pre-validated).
    /// - Returns: A prompt string for the LLM.
    private func buildSummarizationPrompt(topic: String, style: String) -> String {
        switch style {
        case "brief":
            return """
                Provide a brief 2-3 sentence summary about: \(topic)
                Focus on the most essential points only.
                """
        case "bullet_points":
            return """
                Summarize the key points about "\(topic)" as a bullet-point list.
                - Use clear, concise bullet points
                - Include the most important information
                - Organize points logically
                """
        case "detailed":
            return """
                Provide a comprehensive summary about: \(topic)
                Cover all major aspects and key details from the available information.
                Organize the summary in a clear, logical structure.
                """
        default:
            // Style is validated before this function is called, so this should never execute
            fatalError("Invalid style '\(style)' - this indicates a validation bug")
        }
    }
}
