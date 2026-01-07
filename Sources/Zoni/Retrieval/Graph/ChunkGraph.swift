// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ChunkGraph.swift - Graph data structure for graph-based retrieval

import Foundation

// MARK: - EdgeType

/// The type of relationship between two chunks in the graph.
///
/// `EdgeType` categorizes edges to enable type-specific graph traversal
/// and retrieval strategies.
///
/// Example usage:
/// ```swift
/// let edge = Edge(targetId: "chunk-2", type: .sequential, weight: 1.0)
/// switch edge.type {
/// case .sequential:
///     print("Adjacent chunk in same document")
/// case .semantic:
///     print("Semantically similar chunk")
/// case .reference:
///     print("Explicit cross-reference")
/// }
/// ```
public enum EdgeType: String, Sendable, Codable {
    /// Adjacent chunks in the same document.
    ///
    /// Sequential edges connect chunks that appear consecutively
    /// in the original document, preserving reading order.
    case sequential

    /// High embedding similarity between chunks.
    ///
    /// Semantic edges connect chunks whose embeddings have
    /// cosine similarity above a configurable threshold.
    case semantic

    /// Explicit cross-reference between chunks.
    ///
    /// Reference edges represent explicit links such as
    /// citations, hyperlinks, or manual annotations.
    case reference
}

// MARK: - Edge

/// A directed edge in the chunk graph.
///
/// `Edge` represents a relationship from a source chunk to a target chunk,
/// with a type categorizing the relationship and a weight indicating strength.
///
/// Example usage:
/// ```swift
/// let edge = Edge(
///     targetId: "chunk-456",
///     type: .semantic,
///     weight: 0.85
/// )
/// ```
public struct Edge: Sendable {
    /// The unique identifier of the target chunk.
    public let targetId: String

    /// The type of relationship this edge represents.
    public let type: EdgeType

    /// The strength of the relationship.
    ///
    /// For sequential edges, this is typically 1.0.
    /// For semantic edges, this is the cosine similarity score.
    public let weight: Float

    /// Creates a new edge.
    ///
    /// - Parameters:
    ///   - targetId: The unique identifier of the target chunk.
    ///   - type: The type of relationship.
    ///   - weight: The strength of the relationship.
    public init(targetId: String, type: EdgeType, weight: Float) {
        self.targetId = targetId
        self.type = type
        self.weight = weight
    }
}

// MARK: - Edge Equatable

extension Edge: Equatable {
    public static func == (lhs: Edge, rhs: Edge) -> Bool {
        lhs.targetId == rhs.targetId &&
        lhs.type == rhs.type &&
        lhs.weight == rhs.weight
    }
}

// MARK: - Edge Hashable

extension Edge: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(targetId)
        hasher.combine(type)
        hasher.combine(weight)
    }
}

// MARK: - ChunkGraph

/// A graph data structure for graph-based chunk retrieval.
///
/// `ChunkGraph` stores chunks as nodes and maintains edges representing
/// relationships between chunks. It supports three types of edges:
/// - Sequential: Connecting adjacent chunks in the same document
/// - Semantic: Connecting chunks with high embedding similarity
/// - Reference: Explicit cross-references between chunks
///
/// The graph is built from chunks and their embeddings, automatically
/// creating sequential and semantic edges based on document structure
/// and embedding similarity.
///
/// Example usage:
/// ```swift
/// let graph = ChunkGraph(similarityThreshold: 0.75)
///
/// // Add chunks with embeddings
/// await graph.addChunks(chunks, embeddings: embeddings)
///
/// // Query neighbors
/// let edges = await graph.neighbors(of: "chunk-123")
/// for edge in edges {
///     print("Connected to \(edge.targetId) via \(edge.type)")
/// }
/// ```
public actor ChunkGraph {

    // MARK: - Private Types

    /// Internal node representation storing chunk data and connections.
    private struct Node: Sendable {
        var chunk: Chunk
        var embedding: Embedding?
        var edges: [Edge]
    }

    // MARK: - Properties

    /// The nodes in the graph, keyed by chunk ID.
    private var nodes: [String: Node] = [:]

    /// The minimum cosine similarity required to create a semantic edge.
    private let similarityThreshold: Float

    // MARK: - Initialization

    /// Creates a new chunk graph.
    ///
    /// - Parameter similarityThreshold: The minimum cosine similarity
    ///   required to create semantic edges between chunks. Defaults to 0.8.
    public init(similarityThreshold: Float = 0.8) {
        self.similarityThreshold = similarityThreshold
    }

    // MARK: - Public Methods

    /// Adds chunks and their embeddings to the graph.
    ///
    /// This method builds the graph structure by:
    /// 1. Adding all chunks as nodes
    /// 2. Creating sequential edges between adjacent chunks in each document
    /// 3. Creating semantic edges between chunks with high embedding similarity
    ///
    /// - Parameters:
    ///   - chunks: The chunks to add to the graph.
    ///   - embeddings: The embeddings corresponding to each chunk.
    ///     Must have the same count as chunks.
    ///
    /// - Note: If chunks and embeddings counts don't match, embeddings
    ///   are paired with chunks by index until one array is exhausted.
    public func addChunks(_ chunks: [Chunk], embeddings: [Embedding]) async {
        // Step 1: Add all nodes
        for (index, chunk) in chunks.enumerated() {
            let embedding = index < embeddings.count ? embeddings[index] : nil
            nodes[chunk.id] = Node(
                chunk: chunk,
                embedding: embedding,
                edges: []
            )
        }

        // Step 2: Build sequential edges
        buildSequentialEdges(chunks)

        // Step 3: Build semantic edges
        buildSemanticEdges(chunks, embeddings: embeddings)
    }

    /// Returns the edges from a node to its neighbors.
    ///
    /// - Parameter nodeId: The ID of the node to query.
    /// - Returns: An array of edges from the node, or an empty array
    ///   if the node doesn't exist.
    public func neighbors(of nodeId: String) -> [Edge] {
        nodes[nodeId]?.edges ?? []
    }

    /// Returns the chunk for a given ID.
    ///
    /// - Parameter id: The chunk ID to look up.
    /// - Returns: The chunk if found, or `nil` if not in the graph.
    public func chunk(forId id: String) -> Chunk? {
        nodes[id]?.chunk
    }

    // MARK: - Private Methods

    /// Builds bidirectional sequential edges between adjacent chunks.
    ///
    /// Chunks are grouped by document ID and sorted by index.
    /// Adjacent chunks receive bidirectional edges with weight 1.0.
    private func buildSequentialEdges(_ chunks: [Chunk]) {
        // Group chunks by document ID
        var documentChunks: [String: [Chunk]] = [:]
        for chunk in chunks {
            let documentId = chunk.metadata.documentId
            documentChunks[documentId, default: []].append(chunk)
        }

        // Sort each document's chunks by index and create sequential edges
        for (_, docChunks) in documentChunks {
            let sorted = docChunks.sorted { $0.metadata.index < $1.metadata.index }

            for i in 0..<sorted.count - 1 {
                let current = sorted[i]
                let next = sorted[i + 1]

                // Add bidirectional edges
                addEdge(
                    from: current.id,
                    to: next.id,
                    type: .sequential,
                    weight: 1.0
                )
                addEdge(
                    from: next.id,
                    to: current.id,
                    type: .sequential,
                    weight: 1.0
                )
            }
        }
    }

    /// Builds bidirectional semantic edges based on embedding similarity.
    ///
    /// For each pair of chunks, if their cosine similarity exceeds the
    /// threshold, bidirectional edges are created with the similarity as weight.
    private func buildSemanticEdges(_ chunks: [Chunk], embeddings: [Embedding]) {
        // Need at least 2 chunks to compare
        guard chunks.count >= 2 else { return }

        // Build pairs and check similarity
        for i in 0..<chunks.count {
            guard i < embeddings.count else { break }
            let embeddingA = embeddings[i]

            for j in (i + 1)..<chunks.count {
                guard j < embeddings.count else { break }
                let embeddingB = embeddings[j]

                let similarity = cosineSimilarity(embeddingA.vector, embeddingB.vector)

                if similarity >= similarityThreshold {
                    let chunkA = chunks[i]
                    let chunkB = chunks[j]

                    // Add bidirectional semantic edges
                    addEdge(
                        from: chunkA.id,
                        to: chunkB.id,
                        type: .semantic,
                        weight: similarity
                    )
                    addEdge(
                        from: chunkB.id,
                        to: chunkA.id,
                        type: .semantic,
                        weight: similarity
                    )
                }
            }
        }
    }

    /// Adds an edge from source to target, avoiding duplicates.
    ///
    /// - Parameters:
    ///   - sourceId: The ID of the source node.
    ///   - targetId: The ID of the target node.
    ///   - type: The type of edge.
    ///   - weight: The edge weight.
    private func addEdge(
        from sourceId: String,
        to targetId: String,
        type: EdgeType,
        weight: Float
    ) {
        guard var node = nodes[sourceId] else { return }

        // Check for duplicate edge (same target and type)
        let isDuplicate = node.edges.contains { edge in
            edge.targetId == targetId && edge.type == type
        }

        guard !isDuplicate else { return }

        let newEdge = Edge(targetId: targetId, type: type, weight: weight)
        node.edges.append(newEdge)
        nodes[sourceId] = node
    }

    /// Computes cosine similarity between two vectors.
    ///
    /// - Parameters:
    ///   - a: The first vector.
    ///   - b: The second vector.
    /// - Returns: The cosine similarity in range [-1, 1], or 0 if
    ///   vectors have different dimensions or zero magnitude.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else {
            return 0.0
        }

        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        let magnitudeProduct = magnitudeA.squareRoot() * magnitudeB.squareRoot()

        guard magnitudeProduct > 0 else {
            return 0.0
        }

        return dotProduct / magnitudeProduct
    }
}

// MARK: - ChunkGraph Query Extensions

extension ChunkGraph {

    /// Returns the number of nodes in the graph.
    public var nodeCount: Int {
        nodes.count
    }

    /// Returns all chunk IDs in the graph.
    public var allChunkIds: [String] {
        Array(nodes.keys)
    }

    /// Returns edges of a specific type from a node.
    ///
    /// - Parameters:
    ///   - nodeId: The ID of the node to query.
    ///   - type: The edge type to filter by.
    /// - Returns: Edges matching the specified type.
    public func neighbors(of nodeId: String, type: EdgeType) -> [Edge] {
        neighbors(of: nodeId).filter { $0.type == type }
    }

    /// Returns the embedding for a chunk.
    ///
    /// - Parameter chunkId: The chunk ID to look up.
    /// - Returns: The embedding if the chunk exists and has one.
    public func embedding(forChunkId chunkId: String) -> Embedding? {
        nodes[chunkId]?.embedding
    }
}

// MARK: - CustomStringConvertible

extension Edge: CustomStringConvertible {
    public var description: String {
        "Edge(target: \(targetId), type: \(type.rawValue), weight: \(weight))"
    }
}
