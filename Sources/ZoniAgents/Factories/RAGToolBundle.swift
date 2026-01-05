// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// RAGToolBundle.swift - Pre-configured bundles of RAG tools for agents.

import Zoni

// MARK: - RAGToolBundle

/// Pre-configured bundles of RAG tools for common agent use cases.
///
/// These bundles provide ready-to-use tool collections that can be added
/// to SwiftAgents agents for different RAG capabilities.
///
/// ## Available Bundles
///
/// - **searchOnly**: Read-only knowledge base access with a search tool
/// - **withQuery**: Search plus a query tool for question answering
///
/// ## Usage
///
/// ```swift
/// // Search-only bundle for read-only knowledge base access
/// let tools = RAGToolBundle.searchOnly(retriever: myRetriever)
///
/// // Add to agent
/// let agent = ReActAgent.Builder()
///     .addTools(tools)
///     .build()
/// ```
///
/// ## Extending Bundles
///
/// You can combine bundles or add individual tools:
///
/// ```swift
/// var tools = RAGToolBundle.searchOnly(retriever: retriever)
/// tools.append(MyCustomTool())
/// ```
public enum RAGToolBundle {

    // MARK: - Tool Bundles

    /// Creates a minimal search-only tool bundle.
    ///
    /// This bundle includes only the search tool, suitable for agents that
    /// need to query a knowledge base without modifying it.
    ///
    /// **Included Tools:**
    /// - `RAGSearchTool`: Searches the knowledge base by query
    ///
    /// - Parameter retriever: The retriever to use for searches.
    /// - Returns: An array containing a single RAGSearchTool.
    ///
    /// ```swift
    /// let tools = RAGToolBundle.searchOnly(retriever: vectorRetriever)
    /// // Returns: [RAGSearchTool]
    /// ```
    public static func searchOnly(retriever: any Retriever) -> [any Tool] {
        [RAGSearchTool(retriever: retriever)]
    }

    /// Creates a bundle with search and query tools.
    ///
    /// This bundle is suitable for agents that need to search a knowledge
    /// base and answer questions based on the retrieved context.
    ///
    /// **Included Tools:**
    /// - `RAGSearchTool`: Searches the knowledge base by query
    /// - `RAGQueryTool`: Answers questions using the RAG pipeline
    ///
    /// - Parameters:
    ///   - retriever: The retriever to use for searches.
    ///   - pipeline: The RAG pipeline for question answering.
    /// - Returns: An array of search and query tools.
    ///
    /// ```swift
    /// let tools = RAGToolBundle.withQuery(
    ///     retriever: vectorRetriever,
    ///     pipeline: ragPipeline
    /// )
    /// ```
    public static func withQuery(
        retriever: any Retriever,
        pipeline: RAGPipeline
    ) -> [any Tool] {
        [
            RAGSearchTool(retriever: retriever),
            RAGQueryTool(pipeline: pipeline)
        ]
    }

    /// Creates a custom bundle from individual tools.
    ///
    /// Use this when you need a specific combination of tools.
    ///
    /// - Parameter tools: The tools to include in the bundle.
    /// - Returns: The same array of tools (for fluent API).
    ///
    /// ```swift
    /// let tools = RAGToolBundle.custom([
    ///     RAGSearchTool(retriever: retriever),
    ///     MyCustomTool()
    /// ])
    /// ```
    public static func custom(_ tools: [any Tool]) -> [any Tool] {
        tools
    }
}

// MARK: - Tool Combination Helpers

extension Array where Element == any Tool {

    /// Combines this tool array with another.
    ///
    /// - Parameter other: Tools to add.
    /// - Returns: Combined array of tools.
    ///
    /// ```swift
    /// let allTools = RAGToolBundle.searchOnly(retriever: retriever)
    ///     .combined(with: [MyCustomTool()])
    /// ```
    public func combined(with other: [any Tool]) -> [any Tool] {
        self + other
    }

    /// Returns tool names for logging/debugging.
    public var toolNames: [String] {
        map { $0.name }
    }
}
