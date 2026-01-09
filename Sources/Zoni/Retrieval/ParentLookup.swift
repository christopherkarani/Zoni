// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ParentLookup.swift - Protocol for resolving parent chunks from child chunk IDs.

// MARK: - ParentLookup

/// A protocol for resolving parent chunks from child chunk references.
///
/// `ParentLookup` provides a unified interface for fetching parent chunks by ID,
/// enabling the ``ParentChildRetriever`` to return rich context after matching
/// against child chunks. This abstraction allows different storage backends to
/// be used for parent chunk retrieval.
///
/// ## Use Case
///
/// In parent-child retrieval, child chunks are used for precise semantic matching
/// due to their smaller size, but the full parent chunk is returned to provide
/// richer context. The `ParentLookup` protocol abstracts the mechanism for
/// finding parent chunks given their IDs.
///
/// ## Thread Safety
///
/// Conforming types must be `Sendable` to ensure safe concurrent access from
/// multiple retrieval tasks. Consider using an `actor` for implementations
/// that maintain mutable state such as caches.
///
/// ## Example Implementation
///
/// ```swift
/// actor SimpleParentLookup: ParentLookup {
///     private var parentChunks: [String: Chunk]
///
///     init(parents: [Chunk]) {
///         self.parentChunks = Dictionary(uniqueKeysWithValues: parents.map { ($0.id, $0) })
///     }
///
///     func parent(forId id: String) async throws -> Chunk? {
///         parentChunks[id]
///     }
/// }
/// ```
///
/// ## See Also
///
/// - ``VectorStoreParentLookup``: A production-ready implementation with LRU caching.
/// - ``ParentChildRetriever``: The retriever that uses this protocol.
/// - ``ParentChildChunker``: The chunker that creates parent-child hierarchies.
public protocol ParentLookup: Sendable {
    /// Retrieves a parent chunk by its unique identifier.
    ///
    /// This method is called by ``ParentChildRetriever`` to fetch the full parent
    /// chunk after child chunks have been matched during similarity search.
    ///
    /// - Parameter id: The unique identifier of the parent chunk to retrieve.
    /// - Returns: The parent chunk if found, or `nil` if no chunk exists with the given ID.
    /// - Throws: An error if the lookup operation fails (e.g., network or database issues).
    ///
    /// ## Performance Considerations
    ///
    /// Implementations should optimize for repeated lookups of the same parent ID,
    /// as multiple child chunks may reference the same parent. Consider using
    /// caching strategies like LRU caches for better performance.
    func parent(forId id: String) async throws -> Chunk?
}
