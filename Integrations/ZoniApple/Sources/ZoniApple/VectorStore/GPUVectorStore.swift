// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// GPUVectorStore.swift - Metal-accelerated vector store for Apple platforms.
//

#if canImport(Metal)
import Metal
#endif
import Foundation
import Zoni

// MARK: - GPUVectorStore

/// A vector store that uses Metal for GPU-accelerated similarity search.
///
/// `GPUVectorStore` keeps data in memory (similar to `InMemoryVectorStore`) but
/// offloads the computationally intensive similarity search to the GPU using
/// `MetalVectorCompute`.
///
/// This provides significant performance benefits for large datasets (> 10k vectors)
/// on Apple Silicon devices.
///
/// ## Thread Safety
/// Implemented as an `actor` to ensure safe concurrent access.
public actor GPUVectorStore: VectorStore {

    // MARK: - Properties

    public nonisolated let name = "gpu_accelerated"

    /// Storage for chunks indexed by their unique ID.
    private var chunks: [String: Chunk] = [:]

    /// Storage for embeddings indexed by their unique ID.
    private var embeddings: [String: Embedding] = [:]

    /// Flat array of all embedding vectors for GPU processing.
    /// This is rebuilt/updated when vectors are added or removed.
    private var flatVectors: [Float] = []

    /// Ordered list of IDs corresponding to the flat vectors.
    /// Used to map GPU result indices back to chunk IDs.
    private var orderedIDs: [String] = []

    /// The Metal compute engine.
    #if canImport(Metal)
    private let metalCompute: MetalVectorCompute
    #endif

    /// Expected dimensions for coherence checking.
    private var expectedDimensions: Int?

    // MARK: - Initialization

    /// Creates a new GPU-accelerated vector store.
    ///
    /// - Throws: `MetalComputeError` if Metal is not available or initialization fails.
    public init() throws {
        #if canImport(Metal)
        self.metalCompute = try MetalVectorCompute()
        guard self.metalCompute.isMetalAvailable else {
            throw MetalVectorCompute.MetalComputeError.metalNotAvailable
        }
        #else
        throw NSError(domain: "ZoniApple", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal not available"])
        #endif
    }

    // MARK: - VectorStore Protocol

    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        guard chunks.count == embeddings.count else {
            throw ZoniError.insertionFailed(reason: "Count mismatch")
        }

        // 1. Validate dimensions
        if let firstDim = embeddings.first?.dimensions {
            if expectedDimensions == nil {
                expectedDimensions = firstDim
            } else if firstDim != expectedDimensions {
                throw ZoniError.insertionFailed(reason: "Dimension mismatch")
            }
        }

        // 2. Update dictionary storage
        for (chunk, embedding) in zip(chunks, embeddings) {
            self.chunks[chunk.id] = chunk
            self.embeddings[chunk.id] = embedding
        }

        // 3. Rebuild flat storage for GPU
        // Optimization: In a real prod implementation we might append, but strictly
        // rebuilding ensures consistency and handles updates/overwrites simply.
        rebuildFlatStorage()
    }

    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        #if canImport(Metal)
        guard !orderedIDs.isEmpty else { return [] }
        
        let dimensions = query.dimensions
        
        // 1. Compute scores on GPU
        // Note: MetalVectorCompute.batchCosineSimilarity returns a score for EVERY stored vector
        let scores = try await metalCompute.batchCosineSimilarity(
            query: query.vector,
            storedVectors: flatVectors,
            dimensions: dimensions
        )

        // 2. Filter and Sort (on CPU)
        // We have to iterate results to map back to chunks and apply metadata filters
        var results: [RetrievalResult] = []
        results.reserveCapacity(limit) // hint

        // We map (index, score) -> chunk
        // This part runs on CPU but is O(N) simple lookups compared to O(N*D) dot products
        
        // Use a heap or just sort? For standard limits, full sort is fine.
        // We collect all valid candidates first.
        var candidates: [(Chunk, Float)] = []
        candidates.reserveCapacity(scores.count)

        for (index, score) in scores.enumerated() {
            guard index < orderedIDs.count else { break }
            let id = orderedIDs[index]
            
            guard let chunk = chunks[id] else { continue }

            // Apply filter
            if let filter = filter, !filter.matches(chunk) {
                continue
            }

            candidates.append((chunk, score))
        }

        // Sort descending
        candidates.sort { $0.1 > $1.1 }

        // Take top N
        return candidates.prefix(limit).map { RetrievalResult(chunk: $0.0, score: $0.1) }
        #else
        return []
        #endif
    }

    public func delete(ids: [String]) async throws {
        for id in ids {
            chunks.removeValue(forKey: id)
            embeddings.removeValue(forKey: id)
        }
        rebuildFlatStorage()
    }

    public func delete(filter: MetadataFilter) async throws {
        let idsToRemove = chunks.filter { filter.matches($0.value) }.map { $0.key }
        try await delete(ids: idsToRemove)
    }

    public func count() async throws -> Int {
        return chunks.count
    }

    public func isEmpty() async throws -> Bool {
        return chunks.isEmpty
    }

    // MARK: - Private Helpers

    private func rebuildFlatStorage() {
        // Clear existing
        orderedIDs.removeAll(keepingCapacity: true)
        flatVectors.removeAll(keepingCapacity: true)

        // Re-populate from dictionaries
        for (id, embedding) in embeddings {
            orderedIDs.append(id)
            flatVectors.append(contentsOf: embedding.vector)
        }
    }
}
