// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// EmbeddingCache.swift - LRU cache for embedding results

import Foundation

// MARK: - EmbeddingCache

/// An LRU (Least Recently Used) cache for embedding results.
///
/// `EmbeddingCache` stores embeddings keyed by their source text, reducing
/// redundant API calls for repeated content. It supports:
/// - **LRU eviction**: Oldest unused entries are evicted when capacity is reached
/// - **TTL expiration**: Optional time-to-live for cache entries
/// - **Hit tracking**: Monitor cache effectiveness with hit/miss statistics
///
/// Example usage:
/// ```swift
/// let cache = EmbeddingCache(maxSize: 10_000, ttl: .hours(24))
///
/// // Check cache before API call
/// if let cached = await cache.get("Hello world") {
///     return cached
/// }
///
/// // Cache new embedding
/// let embedding = try await provider.embed("Hello world")
/// await cache.set("Hello world", embedding: embedding)
/// ```
///
/// ## Thread Safety
/// `EmbeddingCache` is implemented as an actor, making it safe to use
/// concurrently from multiple tasks.
public actor EmbeddingCache {

    // MARK: - Types

    /// A cache entry with embedding and metadata.
    struct CacheEntry: Sendable {
        let embedding: Embedding
        let timestamp: Date
    }

    // MARK: - Properties

    /// The cached embeddings keyed by text.
    private var cache: [String: CacheEntry] = [:]

    /// The maximum number of entries to store.
    private let maxSize: Int

    /// Optional time-to-live for entries.
    private let ttl: Duration?

    /// Tracks access order for LRU eviction.
    private var accessOrder: [String] = []

    /// Number of cache hits.
    private var hits: Int = 0

    /// Number of cache misses.
    private var misses: Int = 0

    // MARK: - Initialization

    /// Creates a new embedding cache.
    ///
    /// - Parameters:
    ///   - maxSize: Maximum number of entries to store. Defaults to 10,000.
    ///   - ttl: Optional time-to-live for entries. `nil` means entries never expire.
    public init(maxSize: Int = 10_000, ttl: Duration? = nil) {
        self.maxSize = maxSize
        self.ttl = ttl
    }

    // MARK: - Cache Operations

    /// Retrieves an embedding from the cache.
    ///
    /// Returns `nil` if the text is not cached or has expired.
    /// Updates access order on hit for LRU tracking.
    ///
    /// - Parameter text: The text to look up.
    /// - Returns: The cached embedding, or `nil` if not found.
    public func get(_ text: String) -> Embedding? {
        guard let entry = cache[text] else {
            misses += 1
            return nil
        }

        // Check TTL expiration
        if let ttl = ttl {
            let age = Date().timeIntervalSince(entry.timestamp)
            if age > ttl.timeInterval {
                // Entry expired, remove it
                cache.removeValue(forKey: text)
                accessOrder.removeAll { $0 == text }
                misses += 1
                return nil
            }
        }

        // Update access order for LRU
        accessOrder.removeAll { $0 == text }
        accessOrder.append(text)

        hits += 1
        return entry.embedding
    }

    /// Stores an embedding in the cache.
    ///
    /// If the cache is at capacity, the least recently used entry is evicted.
    ///
    /// - Parameters:
    ///   - text: The text key for the embedding.
    ///   - embedding: The embedding to cache.
    public func set(_ text: String, embedding: Embedding) {
        evictIfNeeded()

        cache[text] = CacheEntry(embedding: embedding, timestamp: Date())

        // Update access order
        accessOrder.removeAll { $0 == text }
        accessOrder.append(text)
    }

    /// Removes an embedding from the cache.
    ///
    /// - Parameter text: The text key to remove.
    /// - Returns: The removed embedding, or `nil` if not found.
    @discardableResult
    public func remove(_ text: String) -> Embedding? {
        accessOrder.removeAll { $0 == text }
        return cache.removeValue(forKey: text)?.embedding
    }

    /// Clears all entries from the cache.
    public func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        hits = 0
        misses = 0
    }

    /// Removes all expired entries from the cache.
    ///
    /// This is called automatically on access, but can be called manually
    /// to proactively clean up expired entries.
    public func pruneExpired() {
        guard let ttl = ttl else { return }

        let now = Date()
        let expiredKeys = cache.filter { _, entry in
            now.timeIntervalSince(entry.timestamp) > ttl.timeInterval
        }.map { $0.key }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }

    // MARK: - Statistics

    /// The current number of entries in the cache.
    public var count: Int { cache.count }

    /// Whether the cache is empty.
    public var isEmpty: Bool { cache.isEmpty }

    /// The cache hit rate as a percentage (0.0 to 1.0).
    ///
    /// Returns 0.0 if no requests have been made.
    public var hitRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0.0 }
        return Double(hits) / Double(total)
    }

    /// The total number of cache hits.
    public var hitCount: Int { hits }

    /// The total number of cache misses.
    public var missCount: Int { misses }

    /// Resets hit/miss statistics without clearing the cache.
    public func resetStatistics() {
        hits = 0
        misses = 0
    }

    // MARK: - Batch Operations

    /// Retrieves multiple embeddings from the cache.
    ///
    /// - Parameter texts: The texts to look up.
    /// - Returns: A dictionary mapping texts to their cached embeddings.
    ///   Texts not in the cache are not included in the result.
    public func get(_ texts: [String]) -> [String: Embedding] {
        var results: [String: Embedding] = [:]
        for text in texts {
            if let embedding = get(text) {
                results[text] = embedding
            }
        }
        return results
    }

    /// Stores multiple embeddings in the cache.
    ///
    /// - Parameter embeddings: A dictionary mapping texts to embeddings.
    public func set(_ embeddings: [String: Embedding]) {
        for (text, embedding) in embeddings {
            set(text, embedding: embedding)
        }
    }

    // MARK: - Private Methods

    /// Evicts the least recently used entry if at capacity.
    private func evictIfNeeded() {
        while cache.count >= maxSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Converts Duration to TimeInterval (seconds).
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }

    /// Creates a Duration from hours.
    static func hours(_ hours: Int) -> Duration {
        .seconds(hours * 3600)
    }

    /// Creates a Duration from minutes.
    static func minutes(_ minutes: Int) -> Duration {
        .seconds(minutes * 60)
    }
}

// MARK: - CachedEmbeddingProvider

/// An embedding provider wrapper that adds caching.
///
/// `CachedEmbeddingProvider` wraps any `EmbeddingProvider` and caches
/// its results, reducing API calls for repeated content.
///
/// Example usage:
/// ```swift
/// let openai = OpenAIEmbedding(apiKey: "...")
/// let cached = CachedEmbeddingProvider(provider: openai, maxCacheSize: 10_000)
///
/// // First call hits the API
/// let embedding1 = try await cached.embed("Hello")
///
/// // Second call returns cached result
/// let embedding2 = try await cached.embed("Hello")
/// ```
public actor CachedEmbeddingProvider: EmbeddingProvider {

    // MARK: - Properties

    /// The underlying embedding provider.
    private let wrapped: any EmbeddingProvider

    /// The cache for embeddings.
    private let cache: EmbeddingCache

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider (prefixed with "cached_").
    public nonisolated var name: String { "cached_\(wrapped.name)" }

    /// The dimensions of embeddings from the wrapped provider.
    public nonisolated var dimensions: Int { wrapped.dimensions }

    /// The max tokens per request of the wrapped provider.
    public nonisolated var maxTokensPerRequest: Int { wrapped.maxTokensPerRequest }

    // MARK: - Initialization

    /// Creates a cached provider wrapping another provider.
    ///
    /// - Parameters:
    ///   - provider: The embedding provider to wrap.
    ///   - cache: An existing cache to use.
    public init(provider: any EmbeddingProvider, cache: EmbeddingCache) {
        self.wrapped = provider
        self.cache = cache
    }

    /// Creates a cached provider with a new cache.
    ///
    /// - Parameters:
    ///   - provider: The embedding provider to wrap.
    ///   - maxCacheSize: Maximum cache entries. Defaults to 10,000.
    ///   - ttl: Optional time-to-live for cache entries.
    public init(
        provider: any EmbeddingProvider,
        maxCacheSize: Int = 10_000,
        ttl: Duration? = nil
    ) {
        self.wrapped = provider
        self.cache = EmbeddingCache(maxSize: maxCacheSize, ttl: ttl)
    }

    // MARK: - EmbeddingProvider Methods

    /// Embeds a single text, using cache when available.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: The embedding (from cache or freshly generated).
    public func embed(_ text: String) async throws -> Embedding {
        // Check cache first
        if let cached = await cache.get(text) {
            return cached
        }

        // Generate new embedding
        let embedding = try await wrapped.embed(text)

        // Cache the result
        await cache.set(text, embedding: embedding)

        return embedding
    }

    /// Embeds multiple texts, using cache when available.
    ///
    /// Only texts not in the cache are sent to the underlying provider.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: Embeddings in the same order as input texts.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }

        // Check cache for each text
        var results: [Embedding?] = Array(repeating: nil, count: texts.count)
        var uncachedIndices: [Int] = []

        for (index, text) in texts.enumerated() {
            if let cached = await cache.get(text) {
                results[index] = cached
            } else {
                uncachedIndices.append(index)
            }
        }

        // Embed uncached texts
        if !uncachedIndices.isEmpty {
            let uncachedTexts = uncachedIndices.map { texts[$0] }
            let newEmbeddings = try await wrapped.embed(uncachedTexts)

            // Store results and cache them
            for (i, index) in uncachedIndices.enumerated() {
                results[index] = newEmbeddings[i]
                await cache.set(texts[index], embedding: newEmbeddings[i])
            }
        }

        return results.compactMap { $0 }
    }

    // MARK: - Cache Access

    /// Returns the underlying cache for statistics and management.
    public func getCache() -> EmbeddingCache {
        cache
    }

    /// Clears the cache.
    public func clearCache() async {
        await cache.clear()
    }

    /// Returns the current cache hit rate.
    public func cacheHitRate() async -> Double {
        await cache.hitRate
    }
}
