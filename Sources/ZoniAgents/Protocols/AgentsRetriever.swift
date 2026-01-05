// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// AgentsRetriever.swift - Protocol for retrievers in agent contexts.

import Zoni

// MARK: - AgentsRetriever

/// A protocol for retrievers that can be used by SwiftAgents.
///
/// This protocol defines a simplified retrieval interface suitable for
/// agent applications, abstracting away the complexity of Zoni's retriever
/// internals like metadata filtering.
///
/// ## Usage
///
/// ```swift
/// // Create a retriever adapter
/// let adapter = ZoniRetrieverAdapter(vectorRetriever)
///
/// // Use in agent context
/// let results = try await adapter.retrieve(query: "How does async work?")
///
/// for result in results {
///     print("[\(result.score)] \(result.content)")
/// }
/// ```
///
/// ## Concurrency
///
/// Conforming types must be `Sendable` to ensure thread-safe usage across
/// actor boundaries in SwiftAgents applications.
///
/// ## Error Handling
///
/// Methods throw `ZoniError` types:
/// - `ZoniError.retrievalFailed`: Search failures
/// - `ZoniError.invalidConfiguration`: Invalid parameters
public protocol AgentsRetriever: Sendable {

    /// Retrieves documents matching the given query.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results to return. Default: 5.
    ///   - minScore: Optional minimum score threshold (0.0-1.0).
    /// - Returns: An array of retrieval results sorted by relevance.
    ///
    /// - Throws:
    ///   - `ZoniError.invalidConfiguration`: If parameters are invalid.
    ///   - `ZoniError.retrievalFailed`: If the retrieval operation fails.
    func retrieve(
        query: String,
        limit: Int,
        minScore: Float?
    ) async throws -> [AgentRetrievalResult]
}

// MARK: - Default Parameters

extension AgentsRetriever {

    /// Retrieves documents matching the given query with default parameters.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results to return. Default: 5.
    ///   - minScore: Optional minimum score threshold.
    /// - Returns: An array of retrieval results sorted by relevance.
    public func retrieve(
        query: String,
        limit: Int = 5,
        minScore: Float? = nil
    ) async throws -> [AgentRetrievalResult] {
        try await retrieve(query: query, limit: limit, minScore: minScore)
    }
}
