// ZoniApple - Apple platform extensions for Zoni
//
// MemoryStrategy.swift - Memory-efficient strategies for vector search in SQLiteVectorStore.
//
// This module provides configurable memory strategies for large-scale vector search:
// - EagerMemoryStrategy: Loads all embeddings upfront (best for <10k vectors)
// - StreamingMemoryStrategy: Streams in batches (best for >100k vectors)
// - CachedMemoryStrategy: LRU cache for frequent access (balanced approach)
// - HybridMemoryStrategy: Hot cache + cold streaming (best for 10k-100k vectors)

import Foundation
import Zoni

// MARK: - MemoryStrategy Protocol

/// A strategy for managing memory during vector similarity search operations.
///
/// `MemoryStrategy` abstracts the memory management approach for searching large vector stores.
/// Different strategies optimize for different dataset sizes and access patterns:
///
/// - **Eager**: Loads all vectors into memory for fastest search (small datasets)
/// - **Streaming**: Processes vectors in batches to minimize memory (large datasets)
/// - **Cached**: Maintains an LRU cache for frequently accessed vectors (mixed access)
/// - **Hybrid**: Combines caching with streaming for uncached data (medium datasets)
///
/// ## Choosing a Strategy
///
/// | Dataset Size | Recommended Strategy | Memory Usage | Search Speed |
/// |-------------|---------------------|--------------|--------------|
/// | < 10k       | Eager               | High         | Fastest      |
/// | 10k - 100k  | Hybrid              | Medium       | Fast         |
/// | > 100k      | Streaming           | Low          | Slower       |
///
/// ## Thread Safety
///
/// All strategy implementations must be `Sendable` to ensure safe concurrent use
/// across multiple tasks and actors.
///
/// ## Example Usage
///
/// ```swift
/// let store = try SQLiteVectorStore(path: "vectors.db")
/// let strategy = HybridMemoryStrategy(cacheSize: 5000, batchSize: 500)
///
/// let results = try await store.search(
///     query: queryEmbedding,
///     limit: 10,
///     filter: nil,
///     memoryStrategy: strategy
/// )
/// ```
public protocol MemoryStrategy: Sendable {
    /// A human-readable name for this memory strategy.
    ///
    /// Used for logging, debugging, and configuration display.
    var name: String { get }

    /// Performs a similarity search using this memory strategy.
    ///
    /// This method encapsulates the memory management approach for loading and
    /// processing embeddings during search. Implementations should:
    ///
    /// 1. Load embeddings according to their memory strategy
    /// 2. Apply metadata filters to reduce the search space
    /// 3. Compute similarity scores using cosine similarity
    /// 4. Return the top-k results sorted by relevance
    ///
    /// - Parameters:
    ///   - store: The SQLite vector store to search.
    ///   - query: The query embedding to find similar vectors for.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance
    ///   score in descending order (most relevant first).
    ///
    /// - Throws: `ZoniError.searchFailed` if the search operation fails.
    func search(
        in store: SQLiteVectorStore,
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult]
}

// MARK: - EagerMemoryStrategy

/// A memory strategy that loads all embeddings into memory for fastest search.
///
/// `EagerMemoryStrategy` is optimized for small to medium datasets (< 10,000 vectors)
/// where memory usage is not a concern. It provides the fastest search performance
/// by eliminating disk I/O during similarity computation.
///
/// ## Memory Characteristics
///
/// - **Initial Load**: All embeddings loaded into memory on first search
/// - **Memory Usage**: O(n * d) where n = vector count, d = dimensions
/// - **Search Complexity**: O(n * d) per query
///
/// For a dataset of 10,000 vectors with 1536 dimensions:
/// - Memory: ~60 MB (10,000 * 1536 * 4 bytes)
///
/// ## Use Cases
///
/// - Desktop applications with ample memory
/// - Development and testing environments
/// - Real-time search requirements with small datasets
/// - Datasets that fit comfortably in available RAM
///
/// ## Example
///
/// ```swift
/// let strategy = EagerMemoryStrategy()
/// let results = try await store.search(
///     query: embedding,
///     limit: 10,
///     filter: nil,
///     memoryStrategy: strategy
/// )
/// ```
public struct EagerMemoryStrategy: MemoryStrategy {

    // MARK: - Properties

    /// The name identifier for this strategy.
    public let name = "eager"

    // MARK: - Initialization

    /// Creates a new eager memory strategy.
    ///
    /// No configuration is required as this strategy loads all data into memory.
    public init() {}

    // MARK: - MemoryStrategy Protocol

    /// Performs search by loading all embeddings into memory.
    ///
    /// This implementation:
    /// 1. Fetches all chunks and embeddings from the store
    /// 2. Applies metadata filtering in-memory
    /// 3. Computes cosine similarity for all matching chunks
    /// 4. Returns the top-k results by score
    ///
    /// - Parameters:
    ///   - store: The SQLite vector store to search.
    ///   - query: The query embedding to find similar vectors for.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///
    /// - Returns: An array of `RetrievalResult` sorted by descending relevance.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    public func search(
        in store: SQLiteVectorStore,
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Delegate to the store's native search which uses eager loading
        try await store.search(query: query, limit: limit, filter: filter)
    }
}

// MARK: - StreamingMemoryStrategy

/// A memory strategy that streams embeddings in batches for minimal memory usage.
///
/// `StreamingMemoryStrategy` is optimized for very large datasets (> 100,000 vectors)
/// where loading all embeddings into memory is impractical. It processes vectors
/// in configurable batches, trading search speed for memory efficiency.
///
/// ## Memory Characteristics
///
/// - **Memory Usage**: O(batchSize * d) where d = embedding dimensions
/// - **Search Complexity**: O(n * d) with lower memory footprint
/// - **I/O Pattern**: Sequential batch reads from SQLite
///
/// For a batch size of 1,000 with 1536 dimensions:
/// - Memory per batch: ~6 MB (1,000 * 1536 * 4 bytes)
///
/// ## Configuration
///
/// - `batchSize`: Number of embeddings to load per batch (default: 1,000)
///   - Larger batches: Better throughput, more memory
///   - Smaller batches: Lower memory, more I/O overhead
///
/// ## Use Cases
///
/// - Mobile devices with limited memory
/// - Very large vector stores (> 100k vectors)
/// - Memory-constrained server environments
/// - Batch processing scenarios
///
/// ## Example
///
/// ```swift
/// let strategy = StreamingMemoryStrategy(batchSize: 2000)
/// let results = try await store.search(
///     query: embedding,
///     limit: 10,
///     filter: nil,
///     memoryStrategy: strategy
/// )
/// ```
public struct StreamingMemoryStrategy: MemoryStrategy {

    // MARK: - Properties

    /// The name identifier for this strategy.
    public let name = "streaming"

    /// The number of embeddings to load per batch.
    ///
    /// Larger values improve throughput but increase memory usage.
    /// Default is 1,000 which provides a good balance for most use cases.
    public let batchSize: Int

    // MARK: - Initialization

    /// Creates a new streaming memory strategy with the specified batch size.
    ///
    /// - Parameter batchSize: Number of embeddings to load per batch.
    ///   Must be greater than 0. Default is 1,000.
    public init(batchSize: Int = 1000) {
        precondition(batchSize > 0, "Batch size must be greater than 0")
        self.batchSize = batchSize
    }

    // MARK: - MemoryStrategy Protocol

    /// Performs search by streaming embeddings in batches.
    ///
    /// This implementation:
    /// 1. Iterates through the store in batches of `batchSize`
    /// 2. For each batch, applies filters and computes similarities
    /// 3. Maintains a running top-k heap across all batches
    /// 4. Returns the final top-k results
    ///
    /// - Parameters:
    ///   - store: The SQLite vector store to search.
    ///   - query: The query embedding to find similar vectors for.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///
    /// - Returns: An array of `RetrievalResult` sorted by descending relevance.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    public func search(
        in store: SQLiteVectorStore,
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        try await store.searchStreaming(
            query: query,
            limit: limit,
            filter: filter,
            batchSize: batchSize
        )
    }
}

// MARK: - CachedMemoryStrategy

/// A memory strategy using an LRU cache for frequently accessed embeddings.
///
/// `CachedMemoryStrategy` maintains a Least Recently Used (LRU) cache of embeddings,
/// providing fast access to frequently queried vectors while evicting stale entries.
/// This strategy is ideal for workloads with temporal locality.
///
/// ## Memory Characteristics
///
/// - **Memory Usage**: O(cacheSize * d) where d = embedding dimensions
/// - **Cache Hits**: O(1) lookup, O(d) similarity computation
/// - **Cache Misses**: O(1) database lookup per miss
///
/// For a cache size of 10,000 with 1536 dimensions:
/// - Cache memory: ~60 MB (10,000 * 1536 * 4 bytes)
///
/// ## Configuration
///
/// - `cacheSize`: Maximum number of embeddings to cache (default: 10,000)
///   - Larger cache: More hits, more memory
///   - Smaller cache: Fewer hits, less memory
///
/// ## Cache Behavior
///
/// - **Eviction Policy**: Least Recently Used (LRU)
/// - **Population**: On-demand as vectors are accessed
/// - **Invalidation**: Automatic on store modifications (via actor isolation)
///
/// ## Use Cases
///
/// - Applications with repeated queries over similar data
/// - Search systems with hot/cold access patterns
/// - Interactive applications needing consistent latency
///
/// ## Example
///
/// ```swift
/// let strategy = CachedMemoryStrategy(cacheSize: 5000)
/// let results = try await store.search(
///     query: embedding,
///     limit: 10,
///     filter: nil,
///     memoryStrategy: strategy
/// )
/// ```
public struct CachedMemoryStrategy: MemoryStrategy {

    // MARK: - Properties

    /// The name identifier for this strategy.
    public let name = "cached"

    /// The maximum number of embeddings to keep in the LRU cache.
    public let cacheSize: Int

    // MARK: - Initialization

    /// Creates a new cached memory strategy with the specified cache size.
    ///
    /// - Parameter cacheSize: Maximum embeddings to cache.
    ///   Must be greater than 0. Default is 10,000.
    public init(cacheSize: Int = 10_000) {
        precondition(cacheSize > 0, "Cache size must be greater than 0")
        self.cacheSize = cacheSize
    }

    // MARK: - MemoryStrategy Protocol

    /// Performs search using the LRU cache.
    ///
    /// This implementation:
    /// 1. Checks the cache for each required embedding
    /// 2. Fetches cache misses from the database
    /// 3. Updates the cache with newly fetched embeddings
    /// 4. Computes similarities and returns top-k results
    ///
    /// - Parameters:
    ///   - store: The SQLite vector store to search.
    ///   - query: The query embedding to find similar vectors for.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///
    /// - Returns: An array of `RetrievalResult` sorted by descending relevance.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    public func search(
        in store: SQLiteVectorStore,
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        try await store.searchWithCache(
            query: query,
            limit: limit,
            filter: filter,
            cacheSize: cacheSize
        )
    }
}

// MARK: - HybridMemoryStrategy

/// A memory strategy combining LRU caching with streaming for uncached data.
///
/// `HybridMemoryStrategy` provides an optimal balance between memory usage and search
/// performance by maintaining a hot cache for frequently accessed vectors while
/// streaming cold (uncached) vectors in batches. This is the recommended strategy
/// for medium-sized datasets (10,000 - 100,000 vectors).
///
/// ## Memory Characteristics
///
/// - **Cache Memory**: O(cacheSize * d) for hot data
/// - **Streaming Memory**: O(batchSize * d) for cold data
/// - **Total Memory**: O((cacheSize + batchSize) * d)
///
/// ## Search Algorithm
///
/// 1. Search the hot cache first (cached embeddings)
/// 2. Stream through uncached data in batches
/// 3. Merge results maintaining top-k across both sources
/// 4. Update cache with newly accessed embeddings
///
/// ## Configuration
///
/// - `cacheSize`: Number of embeddings in the hot cache (default: 10,000)
/// - `batchSize`: Batch size for streaming cold data (default: 1,000)
///
/// ## Use Cases
///
/// - Medium-sized datasets (10k - 100k vectors)
/// - Applications with mixed hot/cold access patterns
/// - Systems requiring predictable memory bounds
/// - Real-time search with large datasets
///
/// ## Example
///
/// ```swift
/// let strategy = HybridMemoryStrategy(cacheSize: 5000, batchSize: 500)
/// let results = try await store.search(
///     query: embedding,
///     limit: 10,
///     filter: nil,
///     memoryStrategy: strategy
/// )
/// ```
public struct HybridMemoryStrategy: MemoryStrategy {

    // MARK: - Properties

    /// The name identifier for this strategy.
    public let name = "hybrid"

    /// The maximum number of embeddings to keep in the hot cache.
    public let cacheSize: Int

    /// The batch size for streaming uncached embeddings.
    public let batchSize: Int

    // MARK: - Initialization

    /// Creates a new hybrid memory strategy with the specified configuration.
    ///
    /// - Parameters:
    ///   - cacheSize: Maximum embeddings in the hot cache.
    ///     Must be greater than 0. Default is 10,000.
    ///   - batchSize: Batch size for streaming cold data.
    ///     Must be greater than 0. Default is 1,000.
    public init(cacheSize: Int = 10_000, batchSize: Int = 1000) {
        precondition(cacheSize > 0, "Cache size must be greater than 0")
        precondition(batchSize > 0, "Batch size must be greater than 0")
        self.cacheSize = cacheSize
        self.batchSize = batchSize
    }

    // MARK: - MemoryStrategy Protocol

    /// Performs search using the hybrid cache + streaming approach.
    ///
    /// This implementation:
    /// 1. Searches the hot cache for matching embeddings
    /// 2. Streams through uncached data in batches
    /// 3. Maintains a unified top-k heap across both sources
    /// 4. Updates the cache with frequently accessed embeddings
    ///
    /// - Parameters:
    ///   - store: The SQLite vector store to search.
    ///   - query: The query embedding to find similar vectors for.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///
    /// - Returns: An array of `RetrievalResult` sorted by descending relevance.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    public func search(
        in store: SQLiteVectorStore,
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        try await store.searchHybrid(
            query: query,
            limit: limit,
            filter: filter,
            cacheSize: cacheSize,
            batchSize: batchSize
        )
    }
}

// MARK: - MemoryStrategyRecommendation

/// Provides automatic strategy selection based on store characteristics.
///
/// This utility analyzes the vector store size and recommends an appropriate
/// memory strategy based on empirical thresholds.
public enum MemoryStrategyRecommendation {

    /// Threshold below which eager loading is recommended.
    ///
    /// For datasets smaller than this, memory usage is acceptable
    /// and eager loading provides the best search performance.
    public static let eagerThreshold = 10_000

    /// Threshold above which streaming is recommended.
    ///
    /// For datasets larger than this, memory constraints typically
    /// make streaming necessary despite slower search performance.
    public static let streamingThreshold = 100_000

    /// Returns the recommended memory strategy for the given vector count.
    ///
    /// - Parameter vectorCount: The number of vectors in the store.
    /// - Returns: The recommended `MemoryStrategy` for optimal performance.
    ///
    /// ## Recommendation Logic
    ///
    /// | Vector Count | Strategy    |
    /// |-------------|-------------|
    /// | < 10,000    | Eager       |
    /// | 10k - 100k  | Hybrid      |
    /// | > 100,000   | Streaming   |
    public static func recommendedStrategy(forVectorCount vectorCount: Int) -> any MemoryStrategy {
        if vectorCount < eagerThreshold {
            return EagerMemoryStrategy()
        } else if vectorCount < streamingThreshold {
            return HybridMemoryStrategy()
        } else {
            return StreamingMemoryStrategy()
        }
    }

    /// Estimates the memory usage in bytes for the given parameters.
    ///
    /// - Parameters:
    ///   - vectorCount: The number of vectors.
    ///   - dimensions: The embedding dimensions (e.g., 1536 for OpenAI).
    ///
    /// - Returns: Estimated memory usage in bytes for eager loading.
    ///
    /// ## Calculation
    ///
    /// Memory = vectorCount * dimensions * sizeof(Float)
    ///
    /// For example, 10,000 vectors with 1536 dimensions:
    /// - 10,000 * 1536 * 4 bytes = 61,440,000 bytes (~60 MB)
    public static func estimatedMemoryUsage(
        vectorCount: Int,
        dimensions: Int
    ) -> Int {
        vectorCount * dimensions * MemoryLayout<Float>.size
    }
}
