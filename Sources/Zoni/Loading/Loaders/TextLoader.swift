// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// TextLoader.swift - Loader for plain text documents

import Foundation

/// A document loader for plain text files.
///
/// `TextLoader` supports loading `.txt` and `.text` files with automatic
/// encoding detection. It handles various text encodings including UTF-8,
/// UTF-16, and ISO Latin-1.
///
/// ## Example
/// ```swift
/// let loader = TextLoader()
///
/// // Load from file URL
/// let document = try await loader.load(from: fileURL)
///
/// // Load from raw data
/// let doc = try await loader.load(from: data, metadata: nil)
/// ```
public struct TextLoader: DocumentLoader, Sendable {

    /// The file extensions supported by this loader.
    public static let supportedExtensions: Set<String> = ["txt", "text"]

    /// Creates a new text loader.
    public init() {}

    /// Loads a document from a file URL.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: A document containing the text content with appropriate metadata.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read.
    public func load(from url: URL) async throws -> Document {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ZoniError.loadingFailed(url: url, reason: error.localizedDescription)
        }

        var metadata = DocumentMetadata(
            source: LoadingUtils.filename(from: url),
            url: url,
            mimeType: "text/plain"
        )

        return try await load(from: data, metadata: metadata)
    }

    /// Loads a document from raw data.
    ///
    /// The encoding is automatically detected from BOM markers or validated as UTF-8.
    ///
    /// - Parameters:
    ///   - data: The raw data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Returns: A document containing the decoded text content.
    /// - Throws: `ZoniError.invalidData` if the data cannot be decoded as text.
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        let encoding = LoadingUtils.detectEncoding(data)

        // Strip BOM if present
        var processedData = data
        if encoding == .utf8 && data.count >= 3 {
            let prefix = Array(data.prefix(3))
            if prefix == [0xEF, 0xBB, 0xBF] {
                processedData = data.dropFirst(3)
            }
        } else if (encoding == .utf16LittleEndian || encoding == .utf16BigEndian) && data.count >= 2 {
            processedData = data.dropFirst(2)
        }

        guard let content = String(data: processedData, encoding: encoding) else {
            throw ZoniError.invalidData(reason: "Unable to decode text with detected encoding")
        }

        var finalMetadata = metadata ?? DocumentMetadata()
        if finalMetadata.mimeType == nil {
            finalMetadata.mimeType = "text/plain"
        }

        return Document(content: content, metadata: finalMetadata)
    }
}
