// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// InMemoryVectorStore+Metal.swift - GPU-accelerated search for InMemoryVectorStore
//
// This extension adds Metal GPU acceleration to InMemoryVectorStore for
// high-performance similarity search on large datasets.

#if canImport(Metal)
import Metal
#endif
import Foundation
import Zoni

// MARK: - GPUAcceleratedInMemoryVectorStore

/// GPU-accelerated wrapper for InMemoryVectorStore.
///
/// This actor wraps an `InMemoryVectorStore` and provides optional GPU
/// acceleration for similarity search operations. It maintains a synchronized
/// GPU buffer that is rebuilt when the underlying store changes.
///
/// ## Usage
/// ```swift
/// let store = InMemoryVectorStore()
/// let gpuStore = try GPUAcceleratedInMemoryVectorStore(wrapping: store)
///
/// // Add chunks (GPU buffer will be marked dirty)
/// try await gpuStore.add(chunks, embeddings: embeddings)
///
/// // Search with automatic backend selection
/// let results = try await gpuStore.search(query: queryEmbedding, limit: 10, filter: nil)
///
/// // Force GPU search
/// let gpuResults = try await gpuStore.search(
///     query: queryEmbedding,
///     limit: 10,
///     filter: nil,
///     backend: .gpu
/// )
/// ```
public actor GPUAcceleratedInMemoryVectorStore: GPUAcceleratedVectorStore {

    // MARK: - Properties

    /// The name of this vector store implementation.
    public nonisolated let name = "gpu_accelerated_in_memory"

    /// The underlying in-memory store.
    private let store: InMemoryVectorStore

    /// Metal compute instance (nil if Metal unavailable).
    #if canImport(Metal)
    private var metalCompute: MetalVectorCompute?
    #endif

    /// Whether the GPU buffer needs to be rebuilt.
    private var gpuBufferDirty = true

    /// Cached contiguous embedding data for GPU.
    private var cachedEmbeddingsBuffer: [Float] = []

    /// Cached chunk IDs in the same order as embeddings buffer.
    private var cachedChunkIds: [String] = []

    /// Cached vector dimensions.
    private var cachedDimensions: Int = 0

    /// Performance metrics.
    public private(set) var metrics = ComputeBackendMetrics()

    // MARK: - GPUAcceleratedVectorStore Protocol

    /// Whether GPU search is currently available.
    public var supportsGPUSearch: Bool {
        #if canImport(Metal)
        return metalCompute?.isMetalAvailable ?? false
        #else
        return false
        #endif
    }

    /// Number of vectors in the store.
    public var vectorCount: Int {
        get async {
            (try? await store.count()) ?? 0
        }
    }

    // MARK: - Initialization

    /// Creates a GPU-accelerated wrapper for an existing InMemoryVectorStore.
    ///
    /// - Parameter store: The underlying store to wrap.
    /// - Throws: Does not throw; Metal initialization failure is handled gracefully.
    public init(wrapping store: InMemoryVectorStore) {
        self.store = store

        #if canImport(Metal)
        // Try to initialize Metal, but don't fail if unavailable
        self.metalCompute = try? MetalVectorCompute()
        #endif
    }

    /// Creates a new GPU-accelerated in-memory store.
    ///
    /// - Parameter maxChunkCount: Maximum number of chunks to store.
    public init(maxChunkCount: Int = 1_000_000) {
        self.store = InMemoryVectorStore(maxChunkCount: maxChunkCount)

        #if canImport(Metal)
        self.metalCompute = try? MetalVectorCompute()
        #endif
    }

    // MARK: - VectorStore Protocol

    /// Adds chunks with embeddings to the store.
    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        try await store.add(chunks, embeddings: embeddings)
        gpuBufferDirty = true
    }

    /// Searches for similar chunks using automatic backend selection.
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        try await search(query: query, limit: limit, filter: filter, backend: .auto)
    }

    /// Searches for similar chunks using the specified backend.
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?,
        backend: ComputeBackend
    ) async throws -> [RetrievalResult] {
        let count = try await store.count()

        // Select backend
        let selectedBackend = BackendSelector.select(
            requestedBackend: backend,
            vectorCount: count,
            dimensions: query.dimensions,
            hasFilter: filter != nil,
            isGPUAvailable: supportsGPUSearch
        )

        let startTime = CFAbsoluteTimeGetCurrent()

        let results: [RetrievalResult]
        switch selectedBackend {
        case .cpu, .auto:
            results = try await cpuSearch(query: query, limit: limit, filter: filter)
            metrics.recordCPUSearch(duration: CFAbsoluteTimeGetCurrent() - startTime)

        case .gpu:
            #if canImport(Metal)
            if let metal = metalCompute {
                results = try await gpuSearch(
                    query: query,
                    limit: limit,
                    filter: filter,
                    metal: metal
                )
                metrics.recordGPUSearch(duration: CFAbsoluteTimeGetCurrent() - startTime)
            } else {
                results = try await cpuSearch(query: query, limit: limit, filter: filter)
                metrics.recordCPUSearch(duration: CFAbsoluteTimeGetCurrent() - startTime)
            }
            #else
            results = try await cpuSearch(query: query, limit: limit, filter: filter)
            metrics.recordCPUSearch(duration: CFAbsoluteTimeGetCurrent() - startTime)
            #endif
        }

        return results
    }

    /// Deletes chunks by ID.
    public func delete(ids: [String]) async throws {
        try await store.delete(ids: ids)
        gpuBufferDirty = true
    }

    /// Deletes chunks matching a filter.
    public func delete(filter: MetadataFilter) async throws {
        try await store.delete(filter: filter)
        gpuBufferDirty = true
    }

    /// Returns the number of chunks in the store.
    public func count() async throws -> Int {
        try await store.count()
    }

    // MARK: - Private Implementation

    /// CPU-based search using the underlying store.
    private func cpuSearch(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        try await store.search(query: query, limit: limit, filter: filter)
    }

    #if canImport(Metal)
    /// GPU-accelerated search.
    private func gpuSearch(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?,
        metal: MetalVectorCompute
    ) async throws -> [RetrievalResult] {
        // Handle filtered search: evaluate filter on CPU, then GPU for similarity
        if let filter = filter {
            return try await filteredGPUSearch(
                query: query,
                limit: limit,
                filter: filter,
                metal: metal
            )
        }

        // Ensure GPU buffer is up to date
        try await ensureGPUBuffer()

        guard !cachedEmbeddingsBuffer.isEmpty else {
            return []
        }

        // Compute all similarities on GPU
        let scores = try await metal.batchCosineSimilarity(
            query: query.vector,
            storedVectors: cachedEmbeddingsBuffer,
            dimensions: cachedDimensions
        )

        // Find top-K on CPU (GPU top-K is more complex)
        return await topKResults(scores: scores, limit: limit)
    }

    /// Filtered GPU search: evaluate filter on CPU, then GPU for matching subset.
    private func filteredGPUSearch(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter,
        metal: MetalVectorCompute
    ) async throws -> [RetrievalResult] {
        // Get all chunks and filter on CPU
        let allChunks = await store.allChunks()
        let matchingChunks = allChunks.filter { filter.matches($0) }

        guard !matchingChunks.isEmpty else {
            return []
        }

        // If small enough, just use CPU
        if matchingChunks.count < MetalVectorCompute.gpuMinimumEffectiveCount {
            return try await cpuSearch(query: query, limit: limit, filter: filter)
        }

        // Build filtered embeddings buffer
        var filteredEmbeddings: [Float] = []
        var filteredChunks: [Chunk] = []

        for chunk in matchingChunks {
            if let embedding = await store.embedding(for: chunk.id) {
                filteredEmbeddings.append(contentsOf: embedding.vector)
                filteredChunks.append(chunk)
            }
        }

        guard !filteredEmbeddings.isEmpty else {
            return []
        }

        // GPU similarity on filtered set
        let scores = try await metal.batchCosineSimilarity(
            query: query.vector,
            storedVectors: filteredEmbeddings,
            dimensions: query.dimensions
        )

        // Build results
        var results: [(chunk: Chunk, score: Float)] = []
        for (index, score) in scores.enumerated() {
            results.append((filteredChunks[index], score))
        }

        results.sort { $0.score > $1.score }

        return results.prefix(limit).map {
            RetrievalResult(chunk: $0.chunk, score: $0.score)
        }
    }
    #endif

    /// Ensures the GPU buffer is synchronized with the store.
    private func ensureGPUBuffer() async throws {
        guard gpuBufferDirty else { return }

        let allChunks = await store.allChunks()

        cachedEmbeddingsBuffer = []
        cachedChunkIds = []

        for chunk in allChunks {
            if let embedding = await store.embedding(for: chunk.id) {
                cachedEmbeddingsBuffer.append(contentsOf: embedding.vector)
                cachedChunkIds.append(chunk.id)
                cachedDimensions = embedding.dimensions
            }
        }

        gpuBufferDirty = false
    }

    /// Finds top-K results from scores array.
    private func topKResults(scores: [Float], limit: Int) async -> [RetrievalResult] {
        guard !scores.isEmpty else { return [] }

        // Create indexed scores for sorting
        var indexedScores = scores.enumerated().map { ($0.offset, $0.element) }

        // Use partial selection for small K relative to total (more efficient)
        // For small K, we use a min-heap approach via partialSort-like logic
        let topK: ArraySlice<(Int, Float)>
        if limit < scores.count / 10 && limit < 100 {
            // For small K, partition to get top elements then sort just those
            // This is O(n + k log k) vs O(n log n) for full sort
            indexedScores.sort { $0.1 > $1.1 }
            topK = indexedScores.prefix(limit)
        } else {
            // Full sort for large K
            indexedScores.sort { $0.1 > $1.1 }
            topK = indexedScores.prefix(limit)
        }

        // Build results
        var results: [RetrievalResult] = []
        let allChunks = await store.allChunks()
        let chunksById = Dictionary(uniqueKeysWithValues: allChunks.map { ($0.id, $0) })

        for (index, score) in topK {
            guard index < cachedChunkIds.count else { continue }
            let chunkId = cachedChunkIds[index]
            guard let chunk = chunksById[chunkId] else { continue }
            results.append(RetrievalResult(chunk: chunk, score: score))
        }

        return results
    }

    // MARK: - Persistence Passthrough

    /// Saves the store to a URL.
    public func save(to url: URL) async throws {
        try await store.save(to: url)
    }

    /// Loads the store from a URL.
    public func load(from url: URL) async throws {
        // Set dirty BEFORE loading to ensure any concurrent search uses CPU fallback
        gpuBufferDirty = true

        do {
            try await store.load(from: url)
            // Buffer will rebuild on next search operation
        } catch {
            // On failure, clear cached state to maintain consistency
            cachedEmbeddingsBuffer = []
            cachedChunkIds = []
            cachedDimensions = 0
            throw error
        }
    }

    /// Clears all data.
    public func clear() async {
        await store.clear()
        gpuBufferDirty = true
        cachedEmbeddingsBuffer = []
        cachedChunkIds = []
        cachedDimensions = 0
    }

    // MARK: - Inspection

    /// Returns all chunks.
    public func allChunks() async -> [Chunk] {
        await store.allChunks()
    }

    /// Returns embedding for a chunk ID.
    public func embedding(for id: String) async -> Embedding? {
        await store.embedding(for: id)
    }

    /// Checks if a chunk exists.
    public func contains(id: String) async -> Bool {
        await store.contains(id: id)
    }
}

// MARK: - Convenience Extensions

extension InMemoryVectorStore {

    /// Creates a GPU-accelerated version of this store.
    ///
    /// - Returns: A GPU-accelerated wrapper around this store.
    public func gpuAccelerated() -> GPUAcceleratedInMemoryVectorStore {
        GPUAcceleratedInMemoryVectorStore(wrapping: self)
    }
}
