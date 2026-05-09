// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Document types for representing content in the RAG pipeline.

import Foundation

// MARK: - DocumentMetadata

/// Metadata associated with a document in the RAG system.
///
/// `DocumentMetadata` provides a structured way to store common document
/// properties along with custom key-value pairs for application-specific needs.
///
/// Example usage:
/// ```swift
/// var metadata = DocumentMetadata(
///     source: "wikipedia",
///     title: "Swift Programming Language",
///     url: URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")
/// )
///
/// // Add custom metadata
/// metadata["category"] = "programming"
/// metadata["lastUpdated"] = "2024-01-15"
/// ```
public struct DocumentMetadata: Sendable, Codable, Equatable {
    /// The source of the document (e.g., "wikipedia", "local-file", "api").
    public var source: String?

    /// The title of the document.
    public var title: String?

    /// The author of the document.
    public var author: String?

    /// The URL where the document can be accessed.
    public var url: URL?

    /// The MIME type of the document content (e.g., "text/plain", "application/pdf").
    public var mimeType: String?

    /// Custom metadata key-value pairs for application-specific needs.
    public var custom: [String: MetadataValue]

    /// Creates new document metadata with the specified properties.
    ///
    /// - Parameters:
    ///   - source: The source of the document.
    ///   - title: The title of the document.
    ///   - author: The author of the document.
    ///   - url: The URL where the document can be accessed.
    ///   - mimeType: The MIME type of the document content.
    ///   - custom: Custom metadata key-value pairs.
    public init(
        source: String? = nil,
        title: String? = nil,
        author: String? = nil,
        url: URL? = nil,
        mimeType: String? = nil,
        custom: [String: MetadataValue] = [:]
    ) {
        self.source = source
        self.title = title
        self.author = author
        self.url = url
        self.mimeType = mimeType
        self.custom = custom
    }

    /// Accesses custom metadata values by key.
    ///
    /// - Parameter key: The key for the custom metadata value.
    /// - Returns: The metadata value if it exists, `nil` otherwise.
    public subscript(key: String) -> MetadataValue? {
        get { custom[key] }
        set { custom[key] = newValue }
    }
}

// MARK: - Document

/// A document containing text content and associated metadata.
///
/// `Document` is the primary unit of content in the RAG system. Documents
/// can be indexed, chunked, embedded, and retrieved based on semantic similarity.
///
/// Example usage:
/// ```swift
/// let document = Document(
///     content: "Swift is a powerful and intuitive programming language...",
///     metadata: DocumentMetadata(
///         source: "documentation",
///         title: "Swift Overview"
///     )
/// )
///
/// print("Word count: \(document.wordCount)")
/// print("Character count: \(document.characterCount)")
/// ```
public struct Document: Sendable, Identifiable, Codable, Equatable {
    /// The unique identifier for this document.
    public let id: String

    /// The text content of the document.
    public let content: String

    /// Metadata associated with this document.
    public let metadata: DocumentMetadata

    /// The date and time when this document was created.
    public let createdAt: Date

    /// Creates a new document with the specified properties.
    ///
    /// - Parameters:
    ///   - id: The unique identifier for this document. Defaults to a new UUID string.
    ///   - content: The text content of the document.
    ///   - metadata: Metadata associated with this document. Defaults to empty metadata.
    ///   - createdAt: The creation timestamp. Defaults to the current date and time.
    public init(
        id: String = UUID().uuidString,
        content: String,
        metadata: DocumentMetadata = DocumentMetadata(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }

    /// The number of words in the document content.
    ///
    /// Words are determined by splitting on whitespace and newline characters.
    public var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// The number of characters in the document content.
    public var characterCount: Int {
        content.count
    }
}

// MARK: - Document CustomStringConvertible

extension Document: CustomStringConvertible {
    public var description: String {
        let title = metadata.title ?? "Untitled"
        let preview = content.prefix(50)
        let suffix = content.count > 50 ? "..." : ""
        return "Document(id: \(id), title: \"\(title)\", content: \"\(preview)\(suffix)\")"
    }
}
