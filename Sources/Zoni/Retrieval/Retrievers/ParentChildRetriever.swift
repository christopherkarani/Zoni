// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ParentChildRetriever.swift - Retriever that searches children but returns parents.

import Foundation

// MARK: - ScoreAggregation

/// Methods for aggregating child chunk scores to compute parent scores.
///
/// When multiple child chunks from the same parent match a query, their scores
/// must be combined to produce a single score for the parent. Different aggregation
/// methods suit different use cases.
///
/// ## Choosing an Aggregation Method
///
/// - **`.max`**: Best for finding documents with at least one highly relevant section.
///   Use when you want to surface documents that contain a "perfect match" somewhere.
///
/// - **`.average`**: Best for finding documents that are consistently relevant throughout.
///   Use when you want to avoid documents that have one good section but are otherwise
///   irrelevant.
///
/// - **`.sum`**: Best for finding documents with the most relevant content overall.
///   Use when you want to prefer documents where the query topic appears multiple times.
///
/// ## Example
///
/// ```swift
/// // Find documents with at least one highly relevant section
/// let retriever = ParentChildRetriever(
///     embeddingProvider: embedder,
///     childStore: store,
///     parentLookup: lookup,
///     aggregation: .max
/// )
///
/// // Find documents that are consistently relevant
/// let consistentRetriever = ParentChildRetriever(
///     embeddingProvider: embedder,
///     childStore: store,
///     parentLookup: lookup,
///     aggregation: .average
/// )
/// ```
public enum ScoreAggregation: Sendable, Equatable {
    /// Uses the highest child score as the parent score.
    ///
    /// This method selects the maximum score among all matching children.
    /// It's useful when you want to find parents that contain at least one
    /// highly relevant section, regardless of other sections.
    ///
    /// **Formula**: `parentScore = max(childScores)`
    case max

    /// Uses the average of all child scores as the parent score.
    ///
    /// This method computes the mean score across all matching children.
    /// It's useful when you want to find parents that are consistently
    /// relevant throughout, rather than having isolated relevant sections.
    ///
    /// **Formula**: `parentScore = sum(childScores) / count(childScores)`
    case average

    /// Uses the sum of all child scores as the parent score.
    ///
    /// This method adds up all child scores. It naturally favors parents
    /// with more matching children, which can be useful for finding
    /// documents where the query topic appears multiple times.
    ///
    /// **Formula**: `parentScore = sum(childScores)`
    case sum
}

// MARK: - ParentChildRetriever

/// A retriever that searches child chunk embeddings but returns parent chunks.
///
/// `ParentChildRetriever` implements a hierarchical retrieval strategy designed
/// to balance precision with context. Child chunks (smaller, more precise) are
/// used for embedding-based similarity search, while parent chunks (larger, more
/// contextual) are returned as results.
///
/// ## How It Works
///
/// 1. **Query Embedding**: The query text is embedded using the embedding provider.
///
/// 2. **Child Search**: The child store is searched for chunks matching `isChild == true`,
///    fetching `limit * childMultiplier` candidates.
///
/// 3. **Parent Grouping**: Results are grouped by `parentId` from chunk metadata.
///
/// 4. **Score Aggregation**: Child scores are aggregated per parent using the
///    configured ``ScoreAggregation`` method.
///
/// 5. **Parent Ranking**: Parents are sorted by aggregated score, top `limit` selected.
///
/// 6. **Parent Retrieval**: Full parent chunks are fetched via ``ParentLookup``.
///
/// 7. **Result Enrichment**: Results include metadata about matched children.
///
/// ## Why Parent-Child Retrieval?
///
/// Traditional retrieval faces a tradeoff:
/// - **Small chunks**: Precise matching, but limited context for generation
/// - **Large chunks**: Rich context, but imprecise matching (semantic drift)
///
/// Parent-child retrieval solves this by using small chunks for matching and
/// large chunks for context, getting the best of both worlds.
///
/// ## Integration with ParentChildChunker
///
/// This retriever is designed to work with ``ParentChildChunker``, which creates
/// the hierarchical chunk structure. The chunker produces:
/// - **Child chunks** with `isChild: true` and `parentId` metadata
/// - **Parent chunks** with `isParent: true` metadata
///
/// ## Example Usage
///
/// ```swift
/// // Step 1: Create chunker and process documents
/// let chunker = ParentChildChunker(
///     parentSize: 2000,
///     childSize: 400,
///     childOverlap: 50
/// )
/// let allChunks = try await chunker.chunk(document)
///
/// // Step 2: Separate and store children and parents
/// let childChunks = allChunks.filter { $0.metadata.custom["isChild"]?.boolValue == true }
/// let parentChunks = allChunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
///
/// let childStore = InMemoryVectorStore()
/// let parentStore = InMemoryVectorStore()
///
/// let childEmbeddings = try await embedder.embed(childChunks.map(\.content))
/// let parentEmbeddings = try await embedder.embed(parentChunks.map(\.content))
///
/// try await childStore.add(childChunks, embeddings: childEmbeddings)
/// try await parentStore.add(parentChunks, embeddings: parentEmbeddings)
///
/// // Step 3: Create parent lookup and retriever
/// let parentLookup = VectorStoreParentLookup(vectorStore: parentStore)
/// let retriever = ParentChildRetriever(
///     embeddingProvider: embedder,
///     childStore: childStore,
///     parentLookup: parentLookup,
///     childMultiplier: 3,
///     aggregation: .max
/// )
///
/// // Step 4: Retrieve with rich context
/// let results = try await retriever.retrieve(
///     query: "How does Swift handle memory management?",
///     limit: 5,
///     filter: nil
/// )
///
/// for result in results {
///     print("Score: \(result.score)")
///     print("Matched children: \(result.metadata["matchedChildren"]?.intValue ?? 0)")
///     print("Content: \(result.chunk.content.prefix(200))...")
/// }
/// ```
///
/// ## Result Metadata
///
/// Each ``RetrievalResult`` includes enriched metadata:
/// - `matchedChildren`: Number of child chunks that matched the query
/// - `bestChildScore`: The highest individual child score for this parent
/// - `aggregationMethod`: The method used to compute the parent score
///
/// ## Performance Tuning
///
/// - **childMultiplier**: Higher values find more diverse parents but increase
///   computation. Default of 3 works well for most cases.
///
/// - **aggregation**: `.max` is fastest; `.average` provides balanced results;
///   `.sum` favors documents with repeated topic mentions.
///
/// - **Preloading**: Use ``VectorStoreParentLookup/preload(ids:)`` to batch-fetch
///   parents for better performance.
///
/// ## Thread Safety
///
/// This retriever is implemented as an `actor`, ensuring safe concurrent access.
/// Multiple queries can be processed simultaneously without data races.
///
/// ## See Also
///
/// - ``ParentChildChunker``: Creates the hierarchical chunk structure.
/// - ``ParentLookup``: Protocol for fetching parent chunks.
/// - ``VectorStoreParentLookup``: Production-ready parent lookup with caching.
/// - ``ScoreAggregation``: Options for combining child scores.
public actor ParentChildRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "parent_child"

    /// The embedding provider for generating query embeddings.
    private let embeddingProvider: any EmbeddingProvider

    /// The vector store containing child chunks.
    private let childStore: any VectorStore

    /// The lookup for fetching parent chunks by ID.
    private let parentLookup: any ParentLookup

    /// Multiplier for child fetch count relative to desired parent count.
    ///
    /// For example, if `limit` is 5 and `childMultiplier` is 3, the retriever
    /// will fetch 15 child chunks to identify the top 5 parents.
    public let childMultiplier: Int

    /// The method used to aggregate child scores into parent scores.
    public var aggregation: ScoreAggregation

    // MARK: - Initialization

    /// Creates a new parent-child retriever.
    ///
    /// - Parameters:
    ///   - embeddingProvider: Provider for generating query embeddings.
    ///   - childStore: Vector store containing child chunks with `isChild` metadata.
    ///   - parentLookup: Lookup for fetching parent chunks by ID.
    ///   - childMultiplier: Multiplier for child fetch count. Defaults to 3.
    ///   - aggregation: Method for aggregating child scores. Defaults to `.max`.
    ///
    /// ## Example
    /// ```swift
    /// let retriever = ParentChildRetriever(
    ///     embeddingProvider: embedder,
    ///     childStore: childVectorStore,
    ///     parentLookup: VectorStoreParentLookup(vectorStore: parentStore),
    ///     childMultiplier: 5,
    ///     aggregation: .average
    /// )
    /// ```
    public init(
        embeddingProvider: any EmbeddingProvider,
        childStore: any VectorStore,
        parentLookup: any ParentLookup,
        childMultiplier: Int = 3,
        aggregation: ScoreAggregation = .max
    ) {
        self.embeddingProvider = embeddingProvider
        self.childStore = childStore
        self.parentLookup = parentLookup
        self.childMultiplier = max(1, childMultiplier)
        self.aggregation = aggregation
    }

    // MARK: - Configuration

    /// Updates the score aggregation method.
    ///
    /// - Parameter method: The new aggregation method to use.
    ///
    /// ## Example
    /// ```swift
    /// // Switch to average aggregation for more balanced results
    /// await retriever.setAggregation(.average)
    /// ```
    public func setAggregation(_ method: ScoreAggregation) {
        self.aggregation = method
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant parent chunks by searching child embeddings.
    ///
    /// This method implements the full parent-child retrieval pipeline:
    /// 1. Embeds the query using the embedding provider
    /// 2. Searches the child store for matching chunks
    /// 3. Groups and aggregates child scores by parent
    /// 4. Fetches and returns the top-scoring parent chunks
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of parent results to return.
    ///   - filter: Optional metadata filter applied to child chunks.
    /// - Returns: Parent chunks ranked by aggregated child scores.
    /// - Throws: ``ZoniError/retrievalFailed(reason:)`` if retrieval fails.
    ///
    /// ## Filter Behavior
    ///
    /// The provided filter is combined with `isChild == true` to ensure only
    /// child chunks are searched. You can use additional filters to narrow
    /// results by document ID, source, or custom metadata.
    ///
    /// ## Example
    /// ```swift
    /// // Basic retrieval
    /// let results = try await retriever.retrieve(
    ///     query: "Swift concurrency patterns",
    ///     limit: 5,
    ///     filter: nil
    /// )
    ///
    /// // Filtered retrieval (only from specific document)
    /// let filteredResults = try await retriever.retrieve(
    ///     query: "async/await best practices",
    ///     limit: 3,
    ///     filter: .equals("documentId", "swift-guide-v2")
    /// )
    /// ```
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Check for cancellation before starting expensive operations
        try Task.checkCancellation()

        // Step 1: Embed the query
        let queryEmbedding: Embedding
        do {
            queryEmbedding = try await embeddingProvider.embed(query)
        } catch {
            throw ZoniError.retrievalFailed(
                reason: "Failed to embed query: \(error.localizedDescription)"
            )
        }

        // Check for cancellation after embedding
        try Task.checkCancellation()

        // Step 2: Build filter for child chunks
        let childFilter = buildChildFilter(baseFilter: filter)

        // Step 3: Search child store for candidates
        let childLimit = limit * childMultiplier
        let childResults: [RetrievalResult]
        do {
            childResults = try await childStore.search(
                query: queryEmbedding,
                limit: childLimit,
                filter: childFilter
            )
        } catch {
            throw ZoniError.retrievalFailed(
                reason: "Child store search failed: \(error.localizedDescription)"
            )
        }

        // Step 4: Group children by parent ID
        let parentGroups = groupByParent(childResults)

        // Step 5: Aggregate scores and rank parents
        let rankedParents = aggregateAndRank(parentGroups, limit: limit)

        // Step 6: Fetch parent chunks
        let results = try await fetchParentResults(rankedParents)

        return results
    }

    // MARK: - Private Methods

    /// Builds a combined filter that includes the child chunk constraint.
    ///
    /// - Parameter baseFilter: Optional user-provided filter.
    /// - Returns: A filter that includes `isChild == true`.
    private func buildChildFilter(baseFilter: MetadataFilter?) -> MetadataFilter {
        let childConstraint = MetadataFilter.equals("isChild", .bool(true))

        if let base = baseFilter {
            return MetadataFilter.and([childConstraint, base])
        } else {
            return childConstraint
        }
    }

    /// Groups child results by their parent ID.
    ///
    /// - Parameter results: Child retrieval results.
    /// - Returns: Dictionary mapping parent ID to child results.
    private func groupByParent(_ results: [RetrievalResult]) -> [String: [RetrievalResult]] {
        var groups: [String: [RetrievalResult]] = [:]

        for result in results {
            // Extract parentId from child metadata
            guard let parentId = result.chunk.metadata.custom["parentId"]?.stringValue else {
                // Skip children without parentId (shouldn't happen with proper chunking)
                continue
            }

            groups[parentId, default: []].append(result)
        }

        return groups
    }

    /// Aggregates child scores and ranks parents.
    ///
    /// - Parameters:
    ///   - groups: Dictionary mapping parent ID to child results.
    ///   - limit: Maximum number of parents to return.
    /// - Returns: Ranked list of (parentId, aggregatedScore, childResults) tuples.
    private func aggregateAndRank(
        _ groups: [String: [RetrievalResult]],
        limit: Int
    ) -> [(parentId: String, score: Float, children: [RetrievalResult])] {
        var aggregated: [(parentId: String, score: Float, children: [RetrievalResult])] = []

        for (parentId, children) in groups {
            let scores = children.map(\.score)
            let aggregatedScore: Float

            switch aggregation {
            case .max:
                aggregatedScore = scores.max() ?? 0

            case .average:
                aggregatedScore = scores.isEmpty ? 0 : scores.reduce(0, +) / Float(scores.count)

            case .sum:
                aggregatedScore = scores.reduce(0, +)
            }

            aggregated.append((parentId, aggregatedScore, children))
        }

        // Sort by score descending and take top limit
        return aggregated
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Fetches parent chunks and builds final results.
    ///
    /// - Parameter rankedParents: Ranked list of parent info from aggregation.
    /// - Returns: Final retrieval results with parent chunks and enriched metadata.
    private func fetchParentResults(
        _ rankedParents: [(parentId: String, score: Float, children: [RetrievalResult])]
    ) async throws -> [RetrievalResult] {
        var results: [RetrievalResult] = []

        for (parentId, score, children) in rankedParents {
            // Check for cancellation during parent fetching
            try Task.checkCancellation()

            // Fetch parent chunk
            let parentChunk: Chunk?
            do {
                parentChunk = try await parentLookup.parent(forId: parentId)
            } catch {
                // Log error for debugging but continue with other parents
                #if DEBUG
                print("[ParentChildRetriever] Failed to fetch parent '\(parentId)': \(error.localizedDescription)")
                #endif
                continue
            }

            // Skip if parent not found
            guard let parent = parentChunk else {
                continue
            }

            // Compute best child score for metadata
            let bestChildScore = children.map(\.score).max() ?? 0

            // Build enriched metadata
            var metadata: [String: MetadataValue] = [:]
            metadata["matchedChildren"] = .int(children.count)
            metadata["bestChildScore"] = .double(Double(bestChildScore))
            metadata["aggregationMethod"] = .string(aggregationMethodName)

            let result = RetrievalResult(
                chunk: parent,
                score: score,
                metadata: metadata
            )

            results.append(result)
        }

        return results
    }

    /// Returns a string name for the current aggregation method.
    private var aggregationMethodName: String {
        switch aggregation {
        case .max:
            return "max"
        case .average:
            return "average"
        case .sum:
            return "sum"
        }
    }
}

// MARK: - CustomStringConvertible

extension ParentChildRetriever: CustomStringConvertible {
    /// A textual representation of the retriever for debugging.
    nonisolated public var description: String {
        "ParentChildRetriever(childMultiplier: \(childMultiplier))"
    }
}
