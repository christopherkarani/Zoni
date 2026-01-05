// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// ZoniRetrieverAdapter.swift - Adapter wrapping Zoni Retriever for agent use.

import Zoni

// MARK: - AgentRetrievalResult

/// A simplified retrieval result for agent consumption.
///
/// This struct provides a flattened view of Zoni's `RetrievalResult`,
/// making it easier to use in agent workflows while preserving all metadata.
///
/// ## Score Interpretation
///
/// Scores are typically cosine similarity values:
/// - **1.0**: Identical vectors (perfect match)
/// - **0.7-0.9**: High relevance
/// - **0.5-0.7**: Moderate relevance
/// - **Below 0.5**: Low relevance
///
/// The exact interpretation depends on the underlying vector store's
/// similarity metric.
public struct AgentRetrievalResult: Sendable, Equatable, Hashable {

    /// Unique identifier for the retrieved chunk.
    public let id: String

    /// The text content of the retrieved chunk.
    public let content: String

    /// The relevance score (higher = more relevant).
    ///
    /// For cosine similarity (default), values range from -1.0 to 1.0.
    public let score: Float

    /// The source document path or URL, if available.
    public let source: String?

    /// The document ID this chunk belongs to.
    public let documentId: String?

    /// The chunk index within the document.
    public let chunkIndex: Int

    /// Additional string metadata from the chunk.
    ///
    /// Non-string metadata values are converted to their string representation.
    public let metadata: [String: String]

    /// Creates a new agent retrieval result.
    ///
    /// - Parameters:
    ///   - id: The chunk identifier.
    ///   - content: The text content.
    ///   - score: The relevance score.
    ///   - source: The source document.
    ///   - documentId: The parent document ID.
    ///   - chunkIndex: The chunk index within the document.
    ///   - metadata: Additional metadata.
    public init(
        id: String,
        content: String,
        score: Float,
        source: String?,
        documentId: String? = nil,
        chunkIndex: Int = 0,
        metadata: [String: String]
    ) {
        self.id = id
        self.content = content
        self.score = score
        self.source = source
        self.documentId = documentId
        self.chunkIndex = chunkIndex
        self.metadata = metadata
    }

    /// Creates a result from a Zoni RetrievalResult, preserving all metadata.
    init(from result: RetrievalResult) {
        self.id = result.chunk.id
        self.content = result.chunk.content
        self.score = result.score
        self.source = result.chunk.metadata.source
        self.documentId = result.chunk.metadata.documentId
        self.chunkIndex = result.chunk.metadata.index

        // Preserve all custom metadata, converting to strings
        var extractedMetadata: [String: String] = [:]
        for (key, value) in result.chunk.metadata.custom {
            extractedMetadata[key] = value.stringRepresentation
        }
        self.metadata = extractedMetadata
    }
}

// MARK: - MetadataValue String Conversion

extension MetadataValue {
    /// Converts any metadata value to its string representation.
    var stringRepresentation: String {
        switch self {
        case .null:
            return ""
        case .string(let s):
            return s
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .bool(let b):
            return String(b)
        case .array(let arr):
            // Convert array elements to strings and join
            return arr.map { $0.stringRepresentation }.joined(separator: ", ")
        case .dictionary(let dict):
            // Convert dictionary to JSON-like string
            let pairs = dict.map { "\($0.key): \($0.value.stringRepresentation)" }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }
}

// MARK: - ZoniRetrieverAdapter

/// Adapts a Zoni `Retriever` for simplified agent use.
///
/// This adapter provides a streamlined retrieval interface with:
/// - Default limit of 5 results
/// - Optional minimum score filtering
/// - Input validation
/// - Simplified result type preserving all metadata
///
/// ## Usage
///
/// ```swift
/// let retriever = VectorRetriever(vectorStore: store, embeddingProvider: embedder)
/// let adapter = ZoniRetrieverAdapter(retriever)
///
/// // Simple retrieval
/// let results = try await adapter.retrieve(query: "How does Swift concurrency work?")
///
/// // With options
/// let filtered = try await adapter.retrieve(
///     query: "Swift async/await",
///     limit: 10,
///     minScore: 0.7
/// )
/// ```
///
/// ## Thread Safety
///
/// This adapter is `Sendable` and can be safely used across actor boundaries.
/// The generic constraint on `R` ensures compile-time verification of
/// `Sendable` conformance for Swift 6 strict concurrency.
///
/// ## Error Handling
///
/// Methods throw specific `ZoniError` types:
/// - `ZoniError.retrievalFailed`: Search failures
/// - `ZoniError.invalidConfiguration`: Invalid parameters
public struct ZoniRetrieverAdapter<R: Retriever>: AgentsRetriever, Sendable {

    // MARK: - Properties

    /// The wrapped Zoni retriever.
    private let retriever: R

    // MARK: - Initialization

    /// Creates a new adapter wrapping the given Zoni retriever.
    ///
    /// - Parameter retriever: A Zoni retriever to wrap.
    public init(_ retriever: R) {
        self.retriever = retriever
    }

    // MARK: - AgentsRetriever

    /// Retrieves results matching the query.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum number of results. Must be > 0. Default: 5.
    ///   - minScore: Minimum relevance score filter (typically 0.0-1.0). Default: nil.
    /// - Returns: An array of retrieval results sorted by relevance (highest first).
    ///
    /// - Throws:
    ///   - `ZoniError.invalidConfiguration`: If limit <= 0 or minScore is invalid.
    ///   - `ZoniError.retrievalFailed`: If the underlying retrieval fails.
    public func retrieve(
        query: String,
        limit: Int = 5,
        minScore: Float? = nil
    ) async throws -> [AgentRetrievalResult] {
        // Validate inputs
        guard limit > 0 else {
            throw ZoniError.invalidConfiguration(
                reason: "Limit must be greater than 0"
            )
        }

        if let minScore = minScore {
            guard minScore.isFinite else {
                throw ZoniError.invalidConfiguration(
                    reason: "minScore must be a finite value"
                )
            }
        }

        let results = try await retriever.retrieve(
            query: query,
            limit: limit,
            filter: nil
        )

        // Apply minimum score filter if specified
        let filtered: [RetrievalResult]
        if let minScore = minScore {
            filtered = results.filter { $0.score >= minScore }
        } else {
            filtered = results
        }

        // Convert to agent results
        return filtered.map { AgentRetrievalResult(from: $0) }
    }

    // MARK: - Public Utilities

    /// Access the underlying Zoni retriever.
    ///
    /// Use this to access retriever-specific features not exposed through
    /// the `AgentsRetriever` protocol, such as:
    /// - Custom metadata filtering
    /// - Retriever-specific configuration
    /// - Advanced query options
    ///
    /// ```swift
    /// let adapter = ZoniRetrieverAdapter(vectorRetriever)
    /// let retriever = adapter.underlyingRetriever
    /// // Access retriever-specific features...
    /// ```
    public var underlyingRetriever: R {
        retriever
    }
}
