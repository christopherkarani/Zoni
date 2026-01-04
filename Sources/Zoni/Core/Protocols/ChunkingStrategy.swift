// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ChunkingStrategy protocol for splitting documents into smaller chunks.

import Foundation

// MARK: - ChunkingStrategy

/// A protocol for splitting documents into smaller chunks.
///
/// Implement this protocol to create custom chunking strategies
/// (character-based, sentence-based, semantic, etc.)
///
/// Chunking is a critical step in RAG pipelines that affects retrieval quality.
/// Different strategies offer trade-offs between:
/// - **Chunk size**: Smaller chunks provide more precise retrieval but less context
/// - **Overlap**: Overlapping chunks prevent context loss at boundaries
/// - **Semantic coherence**: Some strategies preserve sentence or paragraph boundaries
///
/// ## Example Implementation
/// ```swift
/// struct FixedSizeChunker: ChunkingStrategy {
///     let chunkSize: Int
///     let overlap: Int
///
///     var name: String { "fixed-size" }
///
///     func chunk(_ document: Document) async throws -> [Chunk] {
///         try await chunk(document.content, metadata: ChunkMetadata(
///             documentId: document.id,
///             index: 0,
///             source: document.metadata.source
///         ))
///     }
///
///     func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk] {
///         // Implementation here...
///     }
/// }
/// ```
///
/// ## Built-in Strategies
/// Zoni provides several built-in chunking strategies:
/// - `CharacterChunker`: Splits by character count with optional overlap
/// - `SentenceChunker`: Splits on sentence boundaries
/// - `RecursiveChunker`: Recursively splits using multiple separators
public protocol ChunkingStrategy: Sendable {

    /// The name of this chunking strategy.
    ///
    /// Used for logging, debugging, and identifying the strategy in configurations.
    /// Should be a short, descriptive identifier (e.g., "character", "sentence", "recursive").
    var name: String { get }

    /// Chunks a document into smaller pieces.
    ///
    /// This method extracts the content from the document and creates chunks
    /// with appropriate metadata linking back to the source document.
    ///
    /// - Parameter document: The document to chunk.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/chunkingFailed(reason:)`` if chunking fails.
    /// - Throws: ``ZoniError/emptyDocument`` if the document has no content.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = CharacterChunker(chunkSize: 500, overlap: 50)
    /// let chunks = try await chunker.chunk(document)
    /// for chunk in chunks {
    ///     print("Chunk \(chunk.metadata.index): \(chunk.characterCount) chars")
    /// }
    /// ```
    func chunk(_ document: Document) async throws -> [Chunk]

    /// Chunks raw text with optional metadata.
    ///
    /// Use this method when working with text that is not wrapped in a ``Document``,
    /// or when you need to provide custom base metadata for the resulting chunks.
    ///
    /// - Parameters:
    ///   - text: The text to chunk.
    ///   - metadata: Base metadata to include in each chunk. If `nil`, default
    ///     metadata with a generated document ID will be used.
    /// - Returns: An array of chunks.
    /// - Throws: ``ZoniError/chunkingFailed(reason:)`` if chunking fails.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = SentenceChunker()
    /// let metadata = ChunkMetadata(
    ///     documentId: "user-input",
    ///     index: 0,
    ///     source: "chat"
    /// )
    /// let chunks = try await chunker.chunk(userText, metadata: metadata)
    /// ```
    func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
}
