// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// VectorStoreParentLookup.swift - Parent chunk lookup with LRU caching.

import Foundation

// MARK: - VectorStoreParentLookup

/// A ``ParentLookup`` implementation that retrieves parent chunks from a preloaded cache
/// or an ``InMemoryVectorStore``.
///
/// `VectorStoreParentLookup` provides efficient parent chunk retrieval using an LRU
/// (Least Recently Used) cache. It can be initialized with preloaded parent chunks
/// or connected to an ``InMemoryVectorStore`` for dynamic lookups.
///
/// ## Initialization Options
///
/// There are two ways to use this lookup:
///
/// 1. **With preloaded chunks** (recommended): Pass parent chunks directly during
///    initialization. This is the most efficient approach.
///
/// 2. **With InMemoryVectorStore**: Connect to a store containing parent chunks.
///    The lookup will scan the store to find parents by ID.
///
/// ## LRU Cache Behavior
///
/// The cache maintains a maximum size (default: 100 entries). When the cache is full
/// and a new entry needs to be added, the least recently used entry is evicted.
/// Access order is updated on both reads and writes.
///
/// ## Example Usage
///
/// ```swift
/// // Option 1: Initialize with preloaded parent chunks (recommended)
/// let parentChunks = allChunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
/// let parentLookup = VectorStoreParentLookup(parents: parentChunks)
///
/// // Option 2: Connect to an InMemoryVectorStore
/// let parentStore = InMemoryVectorStore()
/// try await parentStore.add(parentChunks, embeddings: parentEmbeddings)
/// let parentLookup = VectorStoreParentLookup(
///     vectorStore: parentStore,
///     cacheSize: 200
/// )
///
/// // Retrieve individual parents
/// if let parent = try await parentLookup.parent(forId: "parent-1") {
///     print("Found parent: \(parent.content)")
/// }
///
/// // Use with ParentChildRetriever
/// let retriever = ParentChildRetriever(
///     embeddingProvider: embedder,
///     childStore: childStore,
///     parentLookup: parentLookup
/// )
/// ```
///
/// ## Performance Characteristics
///
/// - **Cache hit**: O(1) lookup and O(1) LRU update
/// - **Cache miss with preloaded data**: O(1) lookup
/// - **Cache miss with vector store**: O(n) scan of store
///
/// ## Thread Safety
///
/// This type is implemented as an `actor`, ensuring safe concurrent access from
/// multiple tasks. All cache mutations and store queries are serialized.
///
/// ## See Also
///
/// - ``ParentLookup``: The protocol this type conforms to.
/// - ``ParentChildRetriever``: The retriever that uses this lookup.
/// - ``InMemoryVectorStore``: A vector store that works with this lookup.
public actor VectorStoreParentLookup: ParentLookup {

    // MARK: - Properties

    /// Optional vector store for dynamic lookups.
    private let vectorStore: (any VectorStore)?

    /// Maximum number of entries in the LRU cache.
    private let cacheSize: Int

    /// LRU cache storage: maps chunk ID to the cached chunk.
    private var cache: [String: Chunk] = [:]

    /// LRU access order: chunk IDs ordered by most recent access (head = most recent).
    private var accessOrder: [String] = []

    /// Preloaded parent chunks indexed by ID for O(1) lookup.
    private var preloadedParents: [String: Chunk] = [:]

    // MARK: - Initialization

    /// Creates a new parent lookup with preloaded parent chunks.
    ///
    /// This is the recommended initialization method as it provides O(1) lookups
    /// without requiring vector store queries.
    ///
    /// - Parameters:
    ///   - parents: The parent chunks to make available for lookup.
    ///   - cacheSize: Maximum number of parent chunks in the LRU cache. Defaults to 100.
    ///
    /// ## Example
    /// ```swift
    /// let parentChunks = allChunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
    /// let lookup = VectorStoreParentLookup(parents: parentChunks)
    /// ```
    public init(parents: [Chunk], cacheSize: Int = 100) {
        self.vectorStore = nil
        self.cacheSize = max(0, cacheSize)
        self.preloadedParents = Dictionary(uniqueKeysWithValues: parents.map { ($0.id, $0) })
    }

    /// Creates a new parent lookup backed by a vector store.
    ///
    /// Use this initializer when parent chunks are stored in a vector store
    /// and need to be fetched dynamically. For better performance with
    /// ``InMemoryVectorStore``, consider using ``init(parents:cacheSize:)`` instead.
    ///
    /// - Parameters:
    ///   - vectorStore: The vector store containing parent chunks.
    ///   - cacheSize: Maximum number of parent chunks to cache. Defaults to 100.
    ///
    /// ## Example
    /// ```swift
    /// let lookup = VectorStoreParentLookup(
    ///     vectorStore: myVectorStore,
    ///     cacheSize: 200
    /// )
    /// ```
    public init(vectorStore: any VectorStore, cacheSize: Int = 100) {
        self.vectorStore = vectorStore
        self.cacheSize = max(0, cacheSize)
    }

    // MARK: - ParentLookup Protocol

    /// Retrieves a parent chunk by its unique identifier.
    ///
    /// This method checks for the parent chunk in the following order:
    /// 1. LRU cache (fastest)
    /// 2. Preloaded parents dictionary (if initialized with chunks)
    /// 3. Vector store query (if initialized with a store)
    ///
    /// Found chunks are cached for subsequent lookups.
    ///
    /// - Parameter id: The unique identifier of the parent chunk.
    /// - Returns: The parent chunk if found, or `nil` if not found.
    /// - Throws: ``ZoniError/retrievalFailed(reason:)`` if the vector store query fails.
    ///
    /// ## Example
    /// ```swift
    /// if let parent = try await lookup.parent(forId: "parent-123") {
    ///     print("Content: \(parent.content)")
    /// } else {
    ///     print("Parent not found")
    /// }
    /// ```
    public func parent(forId id: String) async throws -> Chunk? {
        // Check cache first (fastest path)
        if let cached = cache[id] {
            updateAccessOrder(for: id)
            return cached
        }

        // Check preloaded parents (O(1) lookup)
        if let preloaded = preloadedParents[id] {
            cacheChunk(preloaded)
            return preloaded
        }

        // Fall back to vector store if available
        guard vectorStore != nil else {
            return nil
        }

        // Cache miss - fetch from vector store
        let chunk = try await fetchFromStore(id: id)

        // Cache the result if found
        if let chunk = chunk {
            cacheChunk(chunk)
        }

        return chunk
    }

    // MARK: - Batch Operations

    /// Preloads multiple parent chunks into the cache.
    ///
    /// This method fetches all requested parent chunks in a single batch operation,
    /// which is more efficient than individual lookups. Use this when you know
    /// which parent IDs will be needed.
    ///
    /// - Parameter ids: The IDs of parent chunks to preload.
    /// - Throws: ``ZoniError/retrievalFailed(reason:)`` if the batch fetch fails.
    ///
    /// ## Performance
    ///
    /// Batch preloading is most efficient when using ``init(parents:cacheSize:)``
    /// as it simply moves chunks from the preloaded dictionary to the LRU cache.
    /// When using a vector store, it performs a single batch fetch.
    ///
    /// ## Example
    /// ```swift
    /// // Preload parents before retrieval
    /// let parentIds = childResults.compactMap { result in
    ///     result.chunk.metadata.custom["parentId"]?.stringValue
    /// }
    /// try await parentLookup.preload(ids: Array(Set(parentIds)))
    /// ```
    public func preload(ids: [String]) async throws {
        guard !ids.isEmpty else { return }

        // Filter out already cached IDs
        let uncachedIds = ids.filter { cache[$0] == nil }
        guard !uncachedIds.isEmpty else { return }

        // First, check preloaded parents
        var remainingIds: [String] = []
        for id in uncachedIds {
            if let preloaded = preloadedParents[id] {
                cacheChunk(preloaded)
            } else {
                remainingIds.append(id)
            }
        }

        // If any IDs still need fetching and we have a vector store, fetch them
        guard !remainingIds.isEmpty, vectorStore != nil else { return }

        // Fetch remaining chunks from vector store
        let chunks = try await fetchBatchFromStore(ids: remainingIds)

        // Cache all fetched chunks
        for chunk in chunks {
            cacheChunk(chunk)
        }
    }

    /// Clears the parent chunk cache.
    ///
    /// Use this method to free memory or force fresh lookups from the vector store.
    /// This does not clear preloaded parents; use ``clearAll()`` for that.
    ///
    /// ## Example
    /// ```swift
    /// // Clear cache when parent chunks have been updated
    /// await parentLookup.clearCache()
    /// ```
    public func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    /// Clears both the LRU cache and preloaded parents.
    ///
    /// Use this method when the parent chunk data has been completely refreshed
    /// and you want to start with a clean slate.
    ///
    /// ## Example
    /// ```swift
    /// // Clear everything and reload
    /// await parentLookup.clearAll()
    /// await parentLookup.addParents(newParentChunks)
    /// ```
    public func clearAll() {
        cache.removeAll()
        accessOrder.removeAll()
        preloadedParents.removeAll()
    }

    /// Adds parent chunks to the preloaded parents dictionary.
    ///
    /// Use this method to dynamically add parent chunks after initialization.
    /// Existing parents with the same ID will be replaced.
    ///
    /// - Parameter parents: The parent chunks to add.
    ///
    /// ## Example
    /// ```swift
    /// // Add new parents after processing more documents
    /// let newParents = newChunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
    /// await parentLookup.addParents(newParents)
    /// ```
    public func addParents(_ parents: [Chunk]) {
        for parent in parents {
            preloadedParents[parent.id] = parent
        }
    }

    /// Returns the current number of cached parent chunks.
    ///
    /// This is useful for monitoring cache utilization and debugging.
    ///
    /// - Returns: The number of chunks currently in the cache.
    public var cachedCount: Int {
        cache.count
    }

    /// Returns the total number of preloaded parent chunks.
    ///
    /// This is useful for monitoring and debugging.
    ///
    /// - Returns: The number of preloaded parent chunks.
    public var preloadedCount: Int {
        preloadedParents.count
    }

    // MARK: - Private Methods

    /// Fetches a single chunk from the vector store by ID.
    ///
    /// This method uses the InMemoryVectorStore's `allChunks()` method if available,
    /// otherwise falls back to searching with a filter.
    ///
    /// - Parameter id: The chunk ID to fetch.
    /// - Returns: The chunk if found, or `nil` if not found.
    /// - Throws: ``ZoniError/retrievalFailed(reason:)`` on query failure.
    private func fetchFromStore(id: String) async throws -> Chunk? {
        guard let store = vectorStore else { return nil }

        // Try to use InMemoryVectorStore's efficient allChunks() method
        if let inMemoryStore = store as? InMemoryVectorStore {
            let allChunks = await inMemoryStore.allChunks()
            return allChunks.first { $0.id == id }
        }

        // For other stores, we cannot efficiently fetch by ID without an embedding
        // The caller should use preloaded parents instead
        throw ZoniError.retrievalFailed(
            reason: "Cannot fetch parent chunk '\(id)' by ID from vector store '\(store.name)'. " +
                    "Use VectorStoreParentLookup(parents:) to preload parent chunks instead."
        )
    }

    /// Fetches multiple chunks from the vector store by their IDs.
    ///
    /// - Parameter ids: The chunk IDs to fetch.
    /// - Returns: An array of found chunks (may be fewer than requested if some IDs don't exist).
    /// - Throws: ``ZoniError/retrievalFailed(reason:)`` on query failure.
    private func fetchBatchFromStore(ids: [String]) async throws -> [Chunk] {
        guard !ids.isEmpty else { return [] }
        guard let store = vectorStore else { return [] }

        // Try to use InMemoryVectorStore's efficient allChunks() method
        if let inMemoryStore = store as? InMemoryVectorStore {
            let idSet = Set(ids)
            let allChunks = await inMemoryStore.allChunks()
            return allChunks.filter { idSet.contains($0.id) }
        }

        // For other stores, we cannot efficiently fetch by ID without an embedding
        throw ZoniError.retrievalFailed(
            reason: "Cannot batch fetch parent chunks by ID from vector store '\(store.name)'. " +
                    "Use VectorStoreParentLookup(parents:) to preload parent chunks instead."
        )
    }

    /// Adds a chunk to the cache, evicting the LRU entry if necessary.
    ///
    /// - Parameter chunk: The chunk to cache.
    private func cacheChunk(_ chunk: Chunk) {
        let id = chunk.id

        // If already in cache, just update access order
        if cache[id] != nil {
            updateAccessOrder(for: id)
            return
        }

        // Evict LRU entry if cache is full
        if cacheSize > 0, cache.count >= cacheSize {
            evictLRU()
        }

        // Add to cache and access order
        cache[id] = chunk
        accessOrder.insert(id, at: 0)
    }

    /// Updates the access order for a cache entry (moves to most recent).
    ///
    /// - Parameter id: The chunk ID that was accessed.
    private func updateAccessOrder(for id: String) {
        if let index = accessOrder.firstIndex(of: id) {
            accessOrder.remove(at: index)
            accessOrder.insert(id, at: 0)
        }
    }

    /// Evicts the least recently used cache entry.
    private func evictLRU() {
        guard let lruId = accessOrder.popLast() else { return }
        cache.removeValue(forKey: lruId)
    }
}

// MARK: - CustomStringConvertible

extension VectorStoreParentLookup: CustomStringConvertible {
    /// A textual representation of the lookup for debugging.
    nonisolated public var description: String {
        "VectorStoreParentLookup(cacheSize: \(cacheSize))"
    }
}
