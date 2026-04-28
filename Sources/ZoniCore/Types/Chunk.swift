// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Chunk types for representing document segments in RAG pipelines.

import Foundation

// MARK: - ChunkMetadata

/// Metadata associated with a document chunk.
///
/// `ChunkMetadata` tracks the origin and position of a chunk within its source
/// document, along with any custom metadata attributes.
///
/// Example usage:
/// ```swift
/// let metadata = ChunkMetadata(
///     documentId: "doc-123",
///     index: 0,
///     startOffset: 0,
///     endOffset: 500,
///     source: "documents/guide.txt",
///     custom: ["author": "Jane Doe", "section": "Introduction"]
/// )
/// ```
public struct ChunkMetadata: Sendable, Codable, Equatable {
    /// The unique identifier of the source document this chunk belongs to.
    public var documentId: String

    /// The zero-based index of this chunk within the document.
    ///
    /// Chunks from the same document are numbered sequentially starting from 0.
    public var index: Int

    /// The character offset where this chunk starts within the source document.
    public var startOffset: Int

    /// The character offset where this chunk ends within the source document.
    public var endOffset: Int

    /// An optional source identifier such as a file path or URL.
    public var source: String?

    /// Custom metadata attributes for this chunk.
    ///
    /// Use this dictionary to store application-specific metadata that
    /// can be used for filtering or display purposes.
    public var custom: [String: MetadataValue]

    /// Creates a new chunk metadata instance.
    ///
    /// - Parameters:
    ///   - documentId: The unique identifier of the source document.
    ///   - index: The zero-based index of this chunk within the document.
    ///   - startOffset: The character offset where this chunk starts. Defaults to 0.
    ///   - endOffset: The character offset where this chunk ends. Defaults to 0.
    ///   - source: An optional source identifier (e.g., file path).
    ///   - custom: Custom metadata attributes. Defaults to an empty dictionary.
    public init(
        documentId: String,
        index: Int,
        startOffset: Int = 0,
        endOffset: Int = 0,
        source: String? = nil,
        custom: [String: MetadataValue] = [:]
    ) {
        self.documentId = documentId
        self.index = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.source = source
        self.custom = custom
    }
}

// MARK: - Chunk

/// A segment of text from a document, optionally with an embedding vector.
///
/// Chunks are the fundamental unit of retrieval in RAG systems. Documents are
/// split into chunks which are then embedded and stored in vector databases
/// for similarity search.
///
/// Example usage:
/// ```swift
/// let chunk = Chunk(
///     content: "Swift is a powerful programming language...",
///     metadata: ChunkMetadata(documentId: "doc-1", index: 0)
/// )
///
/// // Add embedding after processing
/// let embeddedChunk = chunk.withEmbedding(embedding)
/// ```
public struct Chunk: Sendable, Identifiable, Codable, Equatable {
    /// The unique identifier for this chunk.
    public let id: String

    /// The text content of this chunk.
    public let content: String

    /// Metadata describing the chunk's origin and attributes.
    public let metadata: ChunkMetadata

    /// The vector embedding for this chunk, if computed.
    ///
    /// This is `nil` until the chunk has been processed by an embedding service.
    public let embedding: Embedding?

    /// Creates a new chunk.
    ///
    /// - Parameters:
    ///   - id: The unique identifier. Defaults to a new UUID string.
    ///   - content: The text content of the chunk.
    ///   - metadata: Metadata describing the chunk's origin.
    ///   - embedding: An optional pre-computed embedding vector.
    public init(
        id: String = UUID().uuidString,
        content: String,
        metadata: ChunkMetadata,
        embedding: Embedding? = nil
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.embedding = embedding
    }

    /// Creates a new chunk with the given embedding attached.
    ///
    /// This method returns a copy of the chunk with the embedding set,
    /// preserving all other properties.
    ///
    /// - Parameter embedding: The embedding vector to attach.
    /// - Returns: A new chunk instance with the embedding.
    public func withEmbedding(_ embedding: Embedding) -> Chunk {
        Chunk(
            id: self.id,
            content: self.content,
            metadata: self.metadata,
            embedding: embedding
        )
    }

    /// The number of characters in this chunk's content.
    public var characterCount: Int {
        content.count
    }

    /// The approximate number of words in this chunk's content.
    ///
    /// Words are counted by splitting on whitespace and newlines.
    public var wordCount: Int {
        content.split { $0.isWhitespace || $0.isNewline }.count
    }
}

// MARK: - Chunk Hashable

extension Chunk: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ChunkMetadata Hashable

extension ChunkMetadata: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(documentId)
        hasher.combine(index)
        hasher.combine(startOffset)
        hasher.combine(endOffset)
        hasher.combine(source)
        hasher.combine(custom)
    }
}

// MARK: - CustomStringConvertible

extension Chunk: CustomStringConvertible {
    public var description: String {
        let preview = content.prefix(50)
        let truncated = content.count > 50 ? "..." : ""
        return "Chunk(id: \(id), content: \"\(preview)\(truncated)\", index: \(metadata.index))"
    }
}

extension ChunkMetadata: CustomStringConvertible {
    public var description: String {
        var parts = ["documentId: \(documentId)", "index: \(index)"]
        if startOffset != 0 || endOffset != 0 {
            parts.append("range: \(startOffset)..<\(endOffset)")
        }
        if let source = source {
            parts.append("source: \(source)")
        }
        if !custom.isEmpty {
            parts.append("custom: \(custom.count) keys")
        }
        return "ChunkMetadata(\(parts.joined(separator: ", ")))"
    }
}
