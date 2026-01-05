// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGQueryTool.swift - Full RAG Q&A tool for knowledge base querying.

import Foundation

// MARK: - RAGQueryTool

/// A tool for asking questions and getting answers from the knowledge base.
///
/// `RAGQueryTool` performs a complete RAG pipeline operation: retrieving
/// relevant documents and generating an answer using an LLM. It returns
/// the synthesized answer along with source citations.
///
/// ## Example Usage
///
/// ```swift
/// let queryTool = RAGQueryTool(pipeline: myPipeline)
///
/// let result = try await queryTool.execute(arguments: [
///     "question": .string("How does Swift concurrency work?"),
///     "max_sources": .int(5),
///     "include_sources": .bool(true)
/// ])
///
/// if let answer = result.dictionaryValue?["answer"]?.stringValue {
///     print("Answer: \(answer)")
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
///     .addTool(RAGQueryTool(pipeline: myPipeline))
///     .build()
/// ```
public struct RAGQueryTool: Tool, Sendable {

    // MARK: - Tool Protocol Properties

    /// The unique name identifying this tool.
    public let name = "query_knowledge"

    /// A description of what this tool does.
    public let description = """
        Ask a question and get an answer based on the knowledge base.
        Returns an answer synthesized from relevant documents with source citations.
        Use this when you need to answer questions using stored knowledge.
        """

    /// The parameters this tool accepts.
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "question",
            description: "The question to answer",
            type: .string,
            isRequired: true,
            defaultValue: nil
        ),
        ToolParameter(
            name: "max_sources",
            description: "Maximum number of sources to consider (default: 5)",
            type: .int,
            isRequired: false,
            defaultValue: .int(5)
        ),
        ToolParameter(
            name: "include_sources",
            description: "Whether to include source excerpts in response (default: true)",
            type: .bool,
            isRequired: false,
            defaultValue: .bool(true)
        )
    ]

    // MARK: - Private Properties

    /// The RAG pipeline used to process queries.
    private let pipeline: RAGPipeline

    // MARK: - Initialization

    /// Creates a new query tool with the specified pipeline.
    ///
    /// - Parameter pipeline: The RAG pipeline to use for querying.
    public init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Tool Execution

    /// Executes the query operation.
    ///
    /// - Parameter arguments: The arguments dictionary containing:
    ///   - `question` (String, required): The question to answer.
    ///   - `max_sources` (Int, optional): Maximum sources to consider (must be >= 1). Default: 5.
    ///   - `include_sources` (Bool, optional): Include source excerpts. Default: true.
    /// - Returns: A dictionary containing:
    ///   - `answer`: The generated answer text.
    ///   - `confidence`: Confidence level ("high", "medium", or "low").
    ///   - `sources_used`: Number of sources used.
    ///   - `sources`: (optional) Array of source excerpts if requested.
    /// - Throws: `ZoniError.invalidConfiguration` if required arguments are missing
    ///           or if arguments have invalid values.
    ///           `ZoniError.generationFailed` if answer generation fails.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        // Extract required question argument
        let question = try arguments.requireString("question")

        // Extract and validate optional arguments
        let maxSources = arguments.optionalInt("max_sources", default: 5)
        guard maxSources >= 1 else {
            throw ZoniError.invalidConfiguration(
                reason: "max_sources must be at least 1, got \(maxSources)"
            )
        }
        let includeSources = arguments.optionalBool("include_sources", default: true)

        // Build query options
        let options = QueryOptions(retrievalLimit: maxSources)

        // Execute the RAG query
        let response = try await pipeline.query(question, options: options)

        // Build the result dictionary
        var result: [String: SendableValue] = [
            "answer": .string(response.answer),
            "confidence": .string(calculateConfidence(from: response.sources)),
            "sources_used": .int(response.sources.count)
        ]

        // Optionally include sources
        if includeSources && !response.sources.isEmpty {
            let sources: [SendableValue] = response.sources.map { source in
                // Truncate content to first 500 characters for readability
                let truncatedContent = String(source.chunk.content.prefix(500))
                let needsEllipsis = source.chunk.content.count > 500

                var sourceDict: [String: SendableValue] = [
                    "content": .string(truncatedContent + (needsEllipsis ? "..." : "")),
                    "relevance": .double(Double(source.score))
                ]

                if let sourceIdentifier = source.chunk.metadata.source {
                    sourceDict["source"] = .string(sourceIdentifier)
                }

                sourceDict["document_id"] = .string(source.chunk.metadata.documentId)

                return .dictionary(sourceDict)
            }
            result["sources"] = .array(sources)
        }

        return .dictionary(result)
    }

    // MARK: - Private Helpers

    /// Calculates a confidence level based on source relevance scores.
    ///
    /// - Parameter sources: The retrieval results to analyze.
    /// - Returns: A confidence level string: "high", "medium", or "low".
    private func calculateConfidence(from sources: [RetrievalResult]) -> String {
        guard !sources.isEmpty else { return "low" }

        let averageScore = sources.map(\.score).reduce(0, +) / Float(sources.count)

        if averageScore > 0.8 {
            return "high"
        } else if averageScore > 0.5 {
            return "medium"
        } else {
            return "low"
        }
    }
}
