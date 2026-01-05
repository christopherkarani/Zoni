// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGSearchTool.swift - Vector search tool for knowledge base retrieval.

import Foundation

// MARK: - RAGSearchTool

/// A tool for searching the knowledge base using semantic similarity.
///
/// `RAGSearchTool` searches for relevant text chunks in the vector store
/// based on a query. It returns the most relevant chunks with their
/// sources and relevance scores.
///
/// ## Example Usage
///
/// ```swift
/// let searchTool = RAGSearchTool(retriever: myRetriever)
///
/// let result = try await searchTool.execute(arguments: [
///     "query": .string("Swift concurrency patterns"),
///     "limit": .int(5),
///     "min_score": .double(0.7)
/// ])
///
/// if let results = result.dictionaryValue?["results"]?.arrayValue {
///     for item in results {
///         print(item.dictionaryValue?["content"]?.stringValue ?? "")
///     }
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
///     .addTool(RAGSearchTool(retriever: myRetriever))
///     .build()
/// ```
public struct RAGSearchTool: Tool, Sendable {

    // MARK: - Tool Protocol Properties

    /// The unique name identifying this tool.
    public let name = "search_knowledge"

    /// A description of what this tool does.
    public let description = """
        Search the knowledge base for information relevant to a query.
        Returns the most relevant text chunks with their sources and relevance scores.
        Use this when you need to find specific information from documents.
        """

    /// The parameters this tool accepts.
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "query",
            description: "The search query to find relevant information",
            type: .string,
            isRequired: true,
            defaultValue: nil
        ),
        ToolParameter(
            name: "limit",
            description: "Maximum number of results to return (default: 5)",
            type: .int,
            isRequired: false,
            defaultValue: .int(5)
        ),
        ToolParameter(
            name: "min_score",
            description: "Minimum relevance score threshold (0.0-1.0, default: 0.0)",
            type: .double,
            isRequired: false,
            defaultValue: .double(0.0)
        )
    ]

    // MARK: - Private Properties

    /// The retriever used to search the knowledge base.
    private let retriever: any Retriever

    // MARK: - Initialization

    /// Creates a new search tool with the specified retriever.
    ///
    /// - Parameter retriever: The retriever to use for searching.
    public init(retriever: any Retriever) {
        self.retriever = retriever
    }

    // MARK: - Tool Execution

    /// Executes the search operation.
    ///
    /// - Parameter arguments: The arguments dictionary containing:
    ///   - `query` (String, required): The search query.
    ///   - `limit` (Int, optional): Maximum results to return (must be >= 1). Default: 5.
    ///   - `min_score` (Double, optional): Minimum relevance score (0.0-1.0). Default: 0.0.
    /// - Returns: A dictionary containing:
    ///   - `results`: Array of matching chunks with content, source, score, and IDs.
    ///   - `total_found`: Number of results returned.
    ///   - `query`: The original search query.
    /// - Throws: `ZoniError.invalidConfiguration` if required arguments are missing
    ///           or if arguments have invalid values.
    ///           `ZoniError.retrievalFailed` if the search fails.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        // Extract required query argument
        let query = try arguments.requireString("query")

        // Extract and validate optional arguments
        let limit = arguments.optionalInt("limit", default: 5)
        guard limit >= 1 else {
            throw ZoniError.invalidConfiguration(
                reason: "limit must be at least 1, got \(limit)"
            )
        }

        // Clamp min_score to valid range [0.0, 1.0]
        let rawMinScore = arguments.optionalDouble("min_score", default: 0.0)
        let minScore = Float(min(max(rawMinScore, 0.0), 1.0))

        // Execute the retrieval
        let results = try await retriever.retrieve(
            query: query,
            limit: limit,
            filter: nil
        )

        // Filter by minimum score
        let filteredResults = results.filter { $0.score >= minScore }

        // Convert results to SendableValue
        let resultsArray: [SendableValue] = filteredResults.map { result in
            result.toSendableValue()
        }

        // Return structured response
        return .dictionary([
            "results": .array(resultsArray),
            "total_found": .int(resultsArray.count),
            "query": .string(query)
        ])
    }
}
