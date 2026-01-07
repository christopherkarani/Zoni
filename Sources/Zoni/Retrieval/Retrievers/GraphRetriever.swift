// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// GraphRetriever.swift - Graph-based retrieval strategy using BFS traversal

import Foundation

// MARK: - GraphRetriever

/// A retriever that uses graph relationships between chunks for enhanced retrieval.
///
/// `GraphRetriever` combines vector similarity search with graph traversal to find
/// semantically related chunks. It first identifies seed chunks using vector search,
/// then expands the result set by traversing the chunk graph using BFS.
///
/// The graph traversal discovers related chunks through:
/// - **Sequential edges**: Adjacent chunks in the same document
/// - **Semantic edges**: Chunks with high embedding similarity
/// - **Reference edges**: Explicit cross-references between chunks
///
/// This approach provides better context by including surrounding and related chunks
/// that pure vector similarity might miss.
///
/// Example usage:
/// ```swift
/// let graph = ChunkGraph(similarityThreshold: 0.8)
/// await graph.addChunks(chunks, embeddings: embeddings)
///
/// let retriever = GraphRetriever(
///     graph: graph,
///     embeddingProvider: embedder,
///     vectorStore: store,
///     hops: 2,
///     edgeWeightThreshold: 0.7
/// )
///
/// let results = try await retriever.retrieve(
///     query: "What is Swift concurrency?",
///     limit: 10,
///     filter: nil
/// )
/// ```
public actor GraphRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "graph"

    /// The chunk graph containing nodes and their relationships.
    private let graph: ChunkGraph

    /// The embedding provider for query embedding.
    private let embeddingProvider: any EmbeddingProvider

    /// The vector store for initial seed retrieval.
    private let vectorStore: any VectorStore

    /// The maximum number of hops for BFS traversal.
    ///
    /// Higher values explore more of the graph but may include
    /// less relevant chunks. Defaults to 2.
    private let hops: Int

    /// The minimum edge weight required to traverse an edge.
    ///
    /// Edges with weights below this threshold are ignored during
    /// BFS traversal. Defaults to 0.7.
    private let edgeWeightThreshold: Float

    // MARK: - Initialization

    /// Creates a new graph retriever.
    ///
    /// - Parameters:
    ///   - graph: The chunk graph containing node relationships.
    ///   - embeddingProvider: The provider for generating query embeddings.
    ///   - vectorStore: The vector store for initial seed retrieval.
    ///   - hops: Maximum BFS depth. Defaults to 2.
    ///   - edgeWeightThreshold: Minimum edge weight for traversal. Defaults to 0.7.
    public init(
        graph: ChunkGraph,
        embeddingProvider: any EmbeddingProvider,
        vectorStore: any VectorStore,
        hops: Int = 2,
        edgeWeightThreshold: Float = 0.7
    ) {
        self.graph = graph
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
        self.hops = hops
        self.edgeWeightThreshold = edgeWeightThreshold
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant chunks using graph-based BFS expansion.
    ///
    /// The retrieval process:
    /// 1. Embeds the query text using the embedding provider
    /// 2. Retrieves seed chunks via vector similarity search
    /// 3. Expands results using BFS traversal of the chunk graph
    /// 4. Applies score decay based on hop distance
    /// 5. Returns top results sorted by propagated score
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter (applied to seed search only).
    /// - Returns: Matching chunks sorted by score (descending).
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Step 1: Embed the query
        let queryEmbedding: Embedding
        do {
            queryEmbedding = try await embeddingProvider.embed(query)
        } catch {
            throw ZoniError.retrievalFailed(
                reason: "Failed to embed query: \(error.localizedDescription)"
            )
        }

        // Step 2: Get seed results via vector search
        let seedLimit = max(3, limit / 2)
        let seedResults: [RetrievalResult]
        do {
            seedResults = try await vectorStore.search(
                query: queryEmbedding,
                limit: seedLimit,
                filter: filter
            )
        } catch {
            throw ZoniError.retrievalFailed(
                reason: "Vector store search failed: \(error.localizedDescription)"
            )
        }

        // Early return if no seeds found
        guard !seedResults.isEmpty else {
            return []
        }

        // Step 3: Initialize BFS data structures
        var visited = Set<String>()
        var scores: [String: Float] = [:]
        var frontier: [String] = []

        // Add seeds to visited and scores
        for result in seedResults {
            let chunkId = result.chunk.id
            visited.insert(chunkId)
            scores[chunkId] = result.score
            frontier.append(chunkId)
        }

        // Step 4: BFS traversal
        for hop in 0..<hops {
            let decayFactor = Float(1.0 / Double(hop + 2))
            var nextFrontier: [String] = []

            for nodeId in frontier {
                guard let parentScore = scores[nodeId] else { continue }

                // Get neighbors from graph
                let edges = await graph.neighbors(of: nodeId)

                for edge in edges {
                    // Skip if visited or below threshold
                    guard !visited.contains(edge.targetId) else { continue }
                    guard edge.weight >= edgeWeightThreshold else { continue }

                    // Mark as visited and add to next frontier
                    visited.insert(edge.targetId)
                    nextFrontier.append(edge.targetId)

                    // Calculate propagated score
                    let propagatedScore = parentScore * edge.weight * decayFactor

                    // Keep maximum score if already exists
                    if let existingScore = scores[edge.targetId] {
                        scores[edge.targetId] = max(existingScore, propagatedScore)
                    } else {
                        scores[edge.targetId] = propagatedScore
                    }
                }
            }

            frontier = nextFrontier
        }

        // Step 5: Sort by score and take top limit
        let sortedIds = scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)

        // Step 6: Fetch chunks and build results
        var results: [RetrievalResult] = []
        for chunkId in sortedIds {
            guard let chunk = await graph.chunk(forId: chunkId),
                  let score = scores[chunkId] else {
                continue
            }

            let result = RetrievalResult(
                chunk: chunk,
                score: score,
                metadata: ["retriever": .string(name)]
            )
            results.append(result)
        }

        return results
    }
}

// MARK: - GraphRetriever Configuration Extensions

extension GraphRetriever {

    /// Returns the configured number of BFS hops.
    public var configuredHops: Int {
        hops
    }

    /// Returns the configured edge weight threshold.
    public var configuredEdgeWeightThreshold: Float {
        edgeWeightThreshold
    }
}
