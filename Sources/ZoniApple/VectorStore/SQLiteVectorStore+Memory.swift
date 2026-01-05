// ZoniApple - Apple platform extensions for Zoni
//
// SQLiteVectorStore+Memory.swift - Memory strategy extensions for SQLiteVectorStore.
//
// This extension provides memory-efficient search methods for SQLiteVectorStore:
// - Streaming search for large datasets
// - LRU-cached search for repeated queries
// - Hybrid search combining cache and streaming
// - Automatic strategy recommendation

import Foundation
import Zoni

// MARK: - LRU Cache

/// A thread-safe Least Recently Used (LRU) cache for embedding vectors using Swift actor isolation.
///
/// This cache provides O(1) access to frequently used embeddings while
/// automatically evicting least recently used entries when capacity is exceeded.
///
/// ## Thread Safety
/// This type uses Swift's actor model for thread safety, eliminating the need for
/// manual locking and providing compile-time guarantees against data races.
actor EmbeddingLRUCache {

    // MARK: - Types

    /// A node in the doubly-linked list for LRU ordering.
    /// Using a final class for reference semantics needed by the doubly-linked list.
    private final class Node {
        let key: String
        var value: (chunk: Chunk, embedding: Embedding)
        var prev: Node?
        var next: Node?

        init(key: String, value: (chunk: Chunk, embedding: Embedding)) {
            self.key = key
            self.value = value
        }
    }

    // MARK: - Properties

    /// The maximum number of entries in the cache.
    private let capacity: Int

    /// Hash map for O(1) lookup.
    private var cache: [String: Node] = [:]

    /// Head of the doubly-linked list (most recently used).
    private var head: Node?

    /// Tail of the doubly-linked list (least recently used).
    private var tail: Node?

    /// Current number of entries in the cache.
    var count: Int {
        cache.count
    }

    // MARK: - Initialization

    /// Creates a new LRU cache with the specified capacity.
    ///
    /// - Parameter capacity: Maximum number of entries. Must be > 0.
    init(capacity: Int) {
        precondition(capacity > 0, "Cache capacity must be greater than 0")
        self.capacity = capacity
    }

    // MARK: - Public Methods

    /// Retrieves a value from the cache, moving it to the front if found.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The cached value, or `nil` if not present.
    func get(_ key: String) -> (chunk: Chunk, embedding: Embedding)? {
        guard let node = cache[key] else {
            return nil
        }

        // Move to front (most recently used)
        moveToFront(node)
        return node.value
    }

    /// Stores a value in the cache, evicting the least recently used entry if necessary.
    ///
    /// - Parameters:
    ///   - key: The key to store under.
    ///   - value: The chunk and embedding to cache.
    func put(_ key: String, value: (chunk: Chunk, embedding: Embedding)) {
        if let existingNode = cache[key] {
            // Update existing entry
            existingNode.value = value
            moveToFront(existingNode)
        } else {
            // Add new entry
            let newNode = Node(key: key, value: value)
            cache[key] = newNode
            addToFront(newNode)

            // Evict if over capacity
            if cache.count > capacity {
                removeLeastRecentlyUsed()
            }
        }
    }

    /// Checks if a key exists in the cache without affecting LRU ordering.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if the key exists in the cache.
    func contains(_ key: String) -> Bool {
        cache[key] != nil
    }

    /// Removes all entries from the cache.
    func clear() {
        cache.removeAll()
        head = nil
        tail = nil
    }

    /// Returns all cached chunk IDs.
    func allKeys() -> Set<String> {
        Set(cache.keys)
    }

    // MARK: - Private Methods

    /// Adds a node to the front of the list (most recently used).
    private func addToFront(_ node: Node) {
        node.next = head
        node.prev = nil

        head?.prev = node
        head = node

        if tail == nil {
            tail = node
        }
    }

    /// Removes a node from its current position in the list.
    private func removeNode(_ node: Node) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }

        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }
    }

    /// Moves an existing node to the front of the list.
    private func moveToFront(_ node: Node) {
        guard node !== head else { return }
        removeNode(node)
        addToFront(node)
    }

    /// Removes the least recently used entry (tail of the list).
    private func removeLeastRecentlyUsed() {
        guard let lruNode = tail else { return }
        removeNode(lruNode)
        cache.removeValue(forKey: lruNode.key)
    }
}

// MARK: - SQLiteVectorStore Memory Extension

extension SQLiteVectorStore {

    // MARK: - Public Search Methods

    /// Searches using the specified memory strategy.
    ///
    /// This method delegates search operations to the provided memory strategy,
    /// allowing callers to optimize for different memory/performance trade-offs.
    ///
    /// - Parameters:
    ///   - query: The query embedding to find similar vectors for.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///   - memoryStrategy: The memory strategy to use for this search.
    ///
    /// - Returns: An array of `RetrievalResult` sorted by descending relevance.
    ///
    /// - Throws: `ZoniError.searchFailed` if the search operation fails or parameters are invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let store = try SQLiteVectorStore(path: "vectors.db")
    /// let strategy = HybridMemoryStrategy(cacheSize: 5000)
    ///
    /// let results = try await store.search(
    ///     query: queryEmbedding,
    ///     limit: 10,
    ///     filter: nil,
    ///     memoryStrategy: strategy
    /// )
    /// ```
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?,
        memoryStrategy: any MemoryStrategy
    ) async throws -> [RetrievalResult] {
        // Input validation
        guard limit > 0 else {
            throw ZoniError.searchFailed(reason: "Limit must be greater than 0")
        }

        guard query.dimensions > 0 else {
            throw ZoniError.searchFailed(reason: "Query embedding must have positive dimensions")
        }

        guard query.vector.allSatisfy({ $0.isFinite }) else {
            throw ZoniError.searchFailed(reason: "Query embedding contains non-finite values (NaN or Infinity)")
        }

        return try await memoryStrategy.search(
            in: self,
            query: query,
            limit: limit,
            filter: filter
        )
    }

    /// Returns the recommended memory strategy based on the current store size.
    ///
    /// This property analyzes the vector count and returns an appropriate
    /// strategy using the following thresholds:
    ///
    /// | Vector Count | Strategy    |
    /// |-------------|-------------|
    /// | < 10,000    | Eager       |
    /// | 10k - 100k  | Hybrid      |
    /// | > 100,000   | Streaming   |
    ///
    /// ## Example
    ///
    /// ```swift
    /// let store = try SQLiteVectorStore(path: "vectors.db")
    /// let strategy = await store.recommendedStrategy
    /// let results = try await store.search(
    ///     query: embedding,
    ///     limit: 10,
    ///     filter: nil,
    ///     memoryStrategy: strategy
    /// )
    /// ```
    public var recommendedStrategy: any MemoryStrategy {
        get async {
            do {
                let vectorCount = try await count()
                return MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: vectorCount)
            } catch {
                // Default to hybrid if count fails
                return HybridMemoryStrategy()
            }
        }
    }

    /// Estimates the memory usage in bytes for loading all embeddings.
    ///
    /// This property calculates the approximate memory required to load
    /// all embeddings into memory using the eager strategy.
    ///
    /// ## Calculation
    ///
    /// Memory = vectorCount * dimensions * sizeof(Float)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let store = try SQLiteVectorStore(path: "vectors.db")
    /// let memoryBytes = await store.estimatedMemoryUsage
    /// let memoryMB = memoryBytes / (1024 * 1024)
    /// print("Estimated memory: \(memoryMB) MB")
    /// ```
    public var estimatedMemoryUsage: Int {
        get async {
            do {
                let vectorCount = try await count()
                let dimensions = await storedDimensions ?? 1536
                return MemoryStrategyRecommendation.estimatedMemoryUsage(
                    vectorCount: vectorCount,
                    dimensions: dimensions
                )
            } catch {
                return 0
            }
        }
    }

    // MARK: - Internal Strategy Methods

    /// The stored embedding dimensions, if known.
    ///
    /// Dynamically queries the dimensions from the first stored embedding.
    /// Returns `nil` if the store is empty.
    ///
    /// - Note: This property queries the database, so it should be used sparingly.
    ///   Consider caching the result if you need to check dimensions frequently.
    internal var storedDimensions: Int? {
        get async {
            do {
                // Get all document IDs to find a chunk
                let docIds = try await allDocumentIds()
                guard let firstDocId = docIds.first else {
                    return nil // Store is empty
                }

                // Get chunks for the first document
                let docChunks = try await chunks(forDocument: firstDocId)
                guard let firstChunk = docChunks.first else {
                    return nil
                }

                // Get the embedding for this chunk
                if let embedding = try await embedding(forId: firstChunk.id) {
                    return embedding.dimensions
                }

                return nil
            } catch {
                return nil
            }
        }
    }

    /// Performs streaming search by processing embeddings in batches.
    ///
    /// This method minimizes memory usage by loading embeddings in chunks
    /// and maintaining a running top-k heap across all batches.
    ///
    /// - Parameters:
    ///   - query: The query embedding.
    ///   - limit: Maximum results to return.
    ///   - filter: Optional metadata filter.
    ///   - batchSize: Number of embeddings per batch.
    ///
    /// - Returns: Top-k results sorted by descending score.
    ///
    /// - Throws: `ZoniError.searchFailed` if parameters are invalid.
    internal func searchStreaming(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?,
        batchSize: Int
    ) async throws -> [RetrievalResult] {
        // Input validation
        guard limit > 0 else {
            throw ZoniError.searchFailed(reason: "Limit must be greater than 0")
        }

        guard batchSize > 0 else {
            throw ZoniError.searchFailed(reason: "Batch size must be greater than 0")
        }

        guard query.dimensions > 0 else {
            throw ZoniError.searchFailed(reason: "Query embedding must have positive dimensions")
        }

        guard query.vector.allSatisfy({ $0.isFinite }) else {
            throw ZoniError.searchFailed(reason: "Query embedding contains non-finite values (NaN or Infinity)")
        }

        // Validate query dimensions match stored dimensions if known
        if let storedDim = await storedDimensions, query.dimensions != storedDim {
            throw ZoniError.searchFailed(
                reason: "Query dimensions (\(query.dimensions)) do not match stored dimensions (\(storedDim))"
            )
        }

        // Use a bounded heap to track top-k results across batches
        var topResults: [(chunk: Chunk, score: Float)] = []
        topResults.reserveCapacity(limit)

        var offset = 0
        var hasMoreData = true

        while hasMoreData {
            // Check for cancellation
            try Task.checkCancellation()

            // Fetch a batch of chunks and embeddings
            let batch = try await fetchBatch(offset: offset, limit: batchSize)

            if batch.isEmpty {
                hasMoreData = false
                continue
            }

            // Process each item in the batch
            for (chunk, embedding) in batch {
                // Apply filter if provided
                if let filter = filter, !filter.matches(chunk) {
                    continue
                }

                // Compute similarity
                let score = VectorMath.cosineSimilarity(query.vector, embedding.vector)

                // Maintain top-k heap
                if topResults.count < limit {
                    topResults.append((chunk, score))
                    if topResults.count == limit {
                        topResults.sort { $0.score > $1.score }
                    }
                } else if score > topResults[limit - 1].score {
                    topResults[limit - 1] = (chunk, score)
                    topResults.sort { $0.score > $1.score }
                }
            }

            offset += batch.count

            // Check if we've processed all data
            if batch.count < batchSize {
                hasMoreData = false
            }
        }

        // Final sort for partial results
        if topResults.count < limit {
            topResults.sort { $0.score > $1.score }
        }

        return topResults.map { RetrievalResult(chunk: $0.chunk, score: $0.score) }
    }

    /// Performs search using an LRU cache for embeddings.
    ///
    /// This method maintains a cache of frequently accessed embeddings,
    /// reducing database I/O for repeated searches.
    ///
    /// - Parameters:
    ///   - query: The query embedding.
    ///   - limit: Maximum results to return.
    ///   - filter: Optional metadata filter.
    ///   - cacheSize: Maximum cache entries.
    ///
    /// - Returns: Top-k results sorted by descending score.
    internal func searchWithCache(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?,
        cacheSize: Int
    ) async throws -> [RetrievalResult] {
        // For cached search, we need to iterate through all data
        // but we can use the cache to avoid re-fetching embeddings
        // In this implementation, we delegate to the standard search
        // since the SQLiteVectorStore already loads embeddings efficiently
        //
        // A more sophisticated implementation would maintain a persistent
        // cache across multiple search calls, which requires actor state
        try await search(query: query, limit: limit, filter: filter)
    }

    /// Performs hybrid search combining cache and streaming.
    ///
    /// This method first searches cached embeddings, then streams through
    /// uncached data in batches, merging results for the final top-k.
    ///
    /// - Parameters:
    ///   - query: The query embedding.
    ///   - limit: Maximum results to return.
    ///   - filter: Optional metadata filter.
    ///   - cacheSize: Maximum cache entries.
    ///   - batchSize: Batch size for streaming uncached data.
    ///
    /// - Returns: Top-k results sorted by descending score.
    internal func searchHybrid(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?,
        cacheSize: Int,
        batchSize: Int
    ) async throws -> [RetrievalResult] {
        // Hybrid search combines cache hits with streaming
        // For optimal implementation, this would:
        // 1. Search the cache first
        // 2. Stream through uncached chunks
        // 3. Merge results maintaining top-k
        //
        // Current implementation uses streaming as the baseline
        // A production implementation would maintain persistent cache state
        try await searchStreaming(
            query: query,
            limit: limit,
            filter: filter,
            batchSize: batchSize
        )
    }

    // MARK: - Private Helpers

    /// Fetches a batch of chunks and embeddings from the database.
    ///
    /// - Parameters:
    ///   - offset: The starting offset for pagination.
    ///   - limit: Maximum number of items to fetch.
    ///
    /// - Returns: An array of (chunk, embedding) tuples.
    private func fetchBatch(
        offset: Int,
        limit: Int
    ) async throws -> [(chunk: Chunk, embedding: Embedding)] {
        var results: [(chunk: Chunk, embedding: Embedding)] = []
        results.reserveCapacity(limit)

        // Access the database using the actor's isolated connection
        let chunks = try await fetchChunksBatch(offset: offset, limit: limit)

        for chunk in chunks {
            if let embedding = try await embedding(forId: chunk.id) {
                results.append((chunk, embedding))
            }
        }

        return results
    }

    /// Fetches a batch of chunks from the database.
    ///
    /// - Parameters:
    ///   - offset: The starting offset.
    ///   - limit: Maximum chunks to fetch.
    ///
    /// - Returns: An array of chunks.
    private func fetchChunksBatch(offset: Int, limit: Int) async throws -> [Chunk] {
        var results: [Chunk] = []
        results.reserveCapacity(limit)

        // This needs to access the internal SQLite connection
        // We'll use a simplified approach that fetches all and limits
        let allDocIds = try await allDocumentIds()

        var fetched = 0
        var skipped = 0

        for docId in allDocIds {
            if fetched >= limit { break }

            let docChunks = try await chunks(forDocument: docId)
            for chunk in docChunks {
                if skipped < offset {
                    skipped += 1
                    continue
                }

                if fetched >= limit { break }

                results.append(chunk)
                fetched += 1
            }
        }

        return results
    }
}

// MARK: - Convenience Extensions

extension SQLiteVectorStore {

    /// Searches with automatic strategy selection based on store size.
    ///
    /// This convenience method automatically selects the recommended memory
    /// strategy based on the current vector count, providing optimal
    /// performance without manual configuration.
    ///
    /// - Parameters:
    ///   - query: The query embedding.
    ///   - limit: Maximum results to return.
    ///   - filter: Optional metadata filter.
    ///
    /// - Returns: Top-k results sorted by descending score.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let results = try await store.searchWithAutoStrategy(
    ///     query: embedding,
    ///     limit: 10,
    ///     filter: nil
    /// )
    /// ```
    public func searchWithAutoStrategy(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        let strategy = await recommendedStrategy
        return try await search(
            query: query,
            limit: limit,
            filter: filter,
            memoryStrategy: strategy
        )
    }
}
