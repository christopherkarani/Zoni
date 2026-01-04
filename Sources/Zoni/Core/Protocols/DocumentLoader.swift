// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// DocumentLoader.swift - Protocol for loading documents from various sources

import Foundation

// MARK: - DocumentLoader Protocol

/// A protocol for loading documents from various sources.
///
/// Implement this protocol to create custom document loaders for different
/// file types (PDF, HTML, Markdown, etc.) or data sources (URLs, databases).
///
/// Conforming types must be `Sendable` to support concurrent document loading
/// operations in the RAG pipeline.
///
/// ## Example Implementation
/// ```swift
/// struct TextFileLoader: DocumentLoader {
///     static let supportedExtensions: Set<String> = ["txt"]
///
///     func load(from url: URL) async throws -> Document {
///         let data = try Data(contentsOf: url)
///         return try await load(from: data, metadata: DocumentMetadata(url: url))
///     }
///
///     func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
///         guard let content = String(data: data, encoding: .utf8) else {
///             throw ZoniError.invalidData(reason: "Unable to decode text as UTF-8")
///         }
///         return Document(content: content, metadata: metadata ?? DocumentMetadata())
///     }
/// }
/// ```
public protocol DocumentLoader: Sendable {
    /// The file extensions this loader supports (e.g., ["txt", "md"]).
    ///
    /// Extensions should be lowercase without the leading dot.
    static var supportedExtensions: Set<String> { get }

    /// Loads a document from a URL.
    ///
    /// Use this method to load documents from local file URLs or remote URLs.
    /// The implementation should handle reading the data and parsing it into
    /// a `Document` with appropriate metadata.
    ///
    /// - Parameter url: The URL to load from.
    /// - Returns: The loaded document.
    /// - Throws: `ZoniError.loadingFailed` if loading fails,
    ///           `ZoniError.unsupportedFileType` if the URL's file type is not supported.
    func load(from url: URL) async throws -> Document

    /// Loads a document from raw data.
    ///
    /// Use this method when you already have the document data in memory
    /// and want to parse it into a `Document`.
    ///
    /// - Parameters:
    ///   - data: The raw data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Returns: The loaded document.
    /// - Throws: `ZoniError.invalidData` if the data cannot be parsed.
    func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document

    /// Checks if this loader can handle the given URL.
    ///
    /// The default implementation checks if the URL's file extension
    /// is in `supportedExtensions`.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if this loader can handle the URL, `false` otherwise.
    func canLoad(_ url: URL) -> Bool
}

// MARK: - Default Implementation

extension DocumentLoader {
    /// Default implementation that checks the URL's file extension against `supportedExtensions`.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL's extension (lowercased) is in `supportedExtensions`.
    public func canLoad(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
