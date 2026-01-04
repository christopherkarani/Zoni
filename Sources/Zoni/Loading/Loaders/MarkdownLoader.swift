// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MarkdownLoader.swift - Loader for Markdown documents with frontmatter support

import Foundation

/// A document loader for Markdown files with YAML frontmatter support.
///
/// `MarkdownLoader` supports loading `.md` and `.markdown` files. It can optionally
/// extract YAML frontmatter from the beginning of documents and populate document
/// metadata with the extracted values.
///
/// ## Frontmatter Format
/// ```markdown
/// ---
/// title: My Document
/// author: John Doe
/// date: 2024-01-01
/// ---
///
/// # Content here
/// ```
///
/// ## Example
/// ```swift
/// let loader = MarkdownLoader()
///
/// // Load from file URL
/// let document = try await loader.load(from: fileURL)
///
/// // Load without frontmatter extraction
/// let loader2 = MarkdownLoader(extractFrontmatter: false)
/// ```
public struct MarkdownLoader: DocumentLoader, Sendable {

    /// The file extensions supported by this loader.
    public static let supportedExtensions: Set<String> = ["md", "markdown"]

    /// Whether to extract and parse YAML frontmatter.
    public var extractFrontmatter: Bool

    /// Creates a new Markdown loader.
    ///
    /// - Parameter extractFrontmatter: Whether to extract YAML frontmatter. Defaults to `true`.
    public init(extractFrontmatter: Bool = true) {
        self.extractFrontmatter = extractFrontmatter
    }

    /// Loads a document from a file URL.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: A document containing the Markdown content with appropriate metadata.
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
            mimeType: "text/markdown"
        )

        return try await load(from: data, metadata: metadata)
    }

    /// Loads a document from raw data.
    ///
    /// - Parameters:
    ///   - data: The raw data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Returns: A document containing the Markdown content.
    /// - Throws: `ZoniError.invalidData` if the data cannot be decoded.
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        let encoding = LoadingUtils.detectEncoding(data)

        guard let content = String(data: data, encoding: encoding) else {
            throw ZoniError.invalidData(reason: "Unable to decode Markdown content")
        }

        var finalMetadata = metadata ?? DocumentMetadata()
        if finalMetadata.mimeType == nil {
            finalMetadata.mimeType = "text/markdown"
        }

        var body = content

        if extractFrontmatter {
            let (frontmatter, extractedBody) = parseFrontmatter(content)

            body = extractedBody

            // Apply frontmatter to metadata
            if let title = frontmatter["title"] {
                finalMetadata.title = title
            }
            if let author = frontmatter["author"] {
                finalMetadata.author = author
            }
            // Store other frontmatter values as custom metadata
            for (key, value) in frontmatter where key != "title" && key != "author" {
                finalMetadata.custom[key] = .string(value)
            }
        }

        return Document(content: body, metadata: finalMetadata)
    }

    /// Parses YAML frontmatter from Markdown content.
    ///
    /// Frontmatter must be at the beginning of the content, enclosed by `---` delimiters.
    ///
    /// - Parameter content: The raw Markdown content.
    /// - Returns: A tuple containing the parsed frontmatter dictionary and the remaining body content.
    private func parseFrontmatter(_ content: String) -> (frontmatter: [String: String], body: String) {
        let lines = content.components(separatedBy: .newlines)

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], content)
        }

        var frontmatterLines: [String] = []
        var endIndex = 1

        for i in 1..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
            frontmatterLines.append(line)
        }

        // If no closing delimiter found, treat as no frontmatter
        if endIndex == 1 && !frontmatterLines.isEmpty {
            return ([:], content)
        }

        // Parse simple YAML key: value pairs
        var frontmatter: [String: String] = [:]
        for line in frontmatterLines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                    frontmatter[key] = value
                }
            }
        }

        // Reconstruct body (skip frontmatter lines)
        let bodyLines = Array(lines.dropFirst(endIndex + 1))
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (frontmatter, body)
    }
}
