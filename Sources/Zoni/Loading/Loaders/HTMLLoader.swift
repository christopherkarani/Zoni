// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// HTMLLoader.swift - Loader for HTML files using SwiftSoup

import Foundation
import SwiftSoup

/// A document loader for HTML files with CSS selector-based extraction.
///
/// `HTMLLoader` uses SwiftSoup to parse HTML documents and extract clean text content.
/// It supports CSS selectors for targeted content extraction and automatic exclusion
/// of non-content elements like navigation, scripts, and styles.
///
/// ## Features
/// - Extracts clean text content from HTML documents
/// - CSS selectors for targeted content extraction (e.g., `article`, `main`)
/// - Automatic exclusion of navigation, scripts, styles, and other non-content elements
/// - Meta tag extraction for title, description, author, and Open Graph tags
/// - Graceful handling of malformed HTML
///
/// ## Example
/// ```swift
/// // Basic usage - extracts all body content
/// let loader = HTMLLoader()
/// let document = try await loader.load(from: htmlURL)
///
/// // Extract only article content
/// let articleLoader = HTMLLoader(contentSelectors: ["article", "main"])
///
/// // Custom exclusion selectors
/// let customLoader = HTMLLoader(
///     excludeSelectors: ["nav", "footer", ".ads", ".sidebar"]
/// )
/// ```
public struct HTMLLoader: DocumentLoader, Sendable {

    /// The file extensions supported by this loader.
    public static let supportedExtensions: Set<String> = ["html", "htm"]

    /// CSS selectors for main content extraction.
    ///
    /// When specified, only content matching these selectors will be extracted.
    /// Multiple selectors are processed in order, and their content is concatenated.
    ///
    /// Example values: `["article"]`, `["main", ".content"]`, `[".post-body"]`
    public var contentSelectors: [String]?

    /// CSS selectors for elements to exclude from content extraction.
    ///
    /// Elements matching these selectors are removed from the document before
    /// content extraction. By default, common non-content elements are excluded.
    public var excludeSelectors: [String]

    /// Whether to extract `<meta>` tags as document metadata.
    ///
    /// When `true`, the following metadata is extracted:
    /// - `<title>` tag content to `metadata.title`
    /// - `<meta name="author">` to `metadata.author`
    /// - `<meta name="description">` to `metadata.custom["description"]`
    /// - `<meta property="og:*">` tags to `metadata.custom`
    /// - Other named meta tags to `metadata.custom`
    public var extractMetaTags: Bool

    /// Creates a new HTML loader with the specified configuration.
    ///
    /// - Parameters:
    ///   - contentSelectors: CSS selectors for main content. Pass `nil` to extract
    ///     entire body content. Defaults to `nil`.
    ///   - excludeSelectors: CSS selectors for elements to exclude. Defaults to common
    ///     non-content elements: `nav`, `footer`, `header`, `script`, `style`, `aside`.
    ///   - extractMetaTags: Whether to extract meta tags. Defaults to `true`.
    public init(
        contentSelectors: [String]? = nil,
        excludeSelectors: [String] = ["nav", "footer", "header", "script", "style", "aside"],
        extractMetaTags: Bool = true
    ) {
        self.contentSelectors = contentSelectors
        self.excludeSelectors = excludeSelectors
        self.extractMetaTags = extractMetaTags
    }

    /// Loads a document from a file URL.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: A document containing the extracted text content with appropriate metadata.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read.
    public func load(from url: URL) async throws -> Document {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ZoniError.loadingFailed(url: url, reason: error.localizedDescription)
        }

        let metadata = DocumentMetadata(
            source: LoadingUtils.filename(from: url),
            url: url,
            mimeType: "text/html"
        )

        return try await load(from: data, metadata: metadata)
    }

    /// Loads a document from raw HTML data.
    ///
    /// - Parameters:
    ///   - data: The raw HTML data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Returns: A document containing the extracted text content.
    /// - Throws: `ZoniError.invalidData` if the data cannot be decoded as UTF-8.
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        guard let html = String(data: data, encoding: .utf8) else {
            throw ZoniError.invalidData(reason: "Unable to decode HTML as UTF-8")
        }

        let doc: SwiftSoup.Document
        do {
            doc = try SwiftSoup.parse(html)
        } catch {
            throw ZoniError.invalidData(reason: "Unable to parse HTML: \(error.localizedDescription)")
        }

        // Build metadata
        var finalMetadata = metadata ?? DocumentMetadata()
        if finalMetadata.mimeType == nil {
            finalMetadata.mimeType = "text/html"
        }

        // Extract meta tags before removing elements
        if extractMetaTags {
            extractMetadataFromDocument(doc, into: &finalMetadata)
        }

        // Remove excluded elements
        for selector in excludeSelectors {
            do {
                try doc.select(selector).remove()
            } catch {
                // Ignore selector errors - continue processing
            }
        }

        // Extract content
        let content: String
        if let selectors = contentSelectors, !selectors.isEmpty {
            var parts: [String] = []
            for selector in selectors {
                do {
                    let elements = try doc.select(selector)
                    for element in elements {
                        if let text = try? element.text(), !text.isEmpty {
                            parts.append(text)
                        }
                    }
                } catch {
                    // Ignore selector errors - continue processing
                }
            }
            content = parts.joined(separator: " ")
        } else {
            content = (try? doc.body()?.text()) ?? ""
        }

        return Document(content: content, metadata: finalMetadata)
    }

    // MARK: - Private Helpers

    /// Extracts metadata from the HTML document.
    ///
    /// - Parameters:
    ///   - doc: The parsed SwiftSoup document.
    ///   - metadata: The metadata structure to populate.
    private func extractMetadataFromDocument(_ doc: SwiftSoup.Document, into metadata: inout DocumentMetadata) {
        // Extract <title>
        if let title = try? doc.title(), !title.isEmpty {
            metadata.title = title
        }

        // Extract <meta> tags
        guard let metaTags = try? doc.select("meta") else {
            return
        }

        for meta in metaTags {
            let name = try? meta.attr("name")
            let property = try? meta.attr("property")
            let content = try? meta.attr("content")

            // Handle name attribute (e.g., <meta name="description" content="...">)
            if let name = name, !name.isEmpty, let content = content, !content.isEmpty {
                switch name.lowercased() {
                case "description":
                    metadata.custom["description"] = .string(content)
                case "author":
                    metadata.author = content
                default:
                    metadata.custom[name] = .string(content)
                }
            }

            // Handle property attribute (e.g., <meta property="og:title" content="...">)
            if let property = property, !property.isEmpty, let content = content, !content.isEmpty {
                metadata.custom[property] = .string(content)
            }
        }
    }
}
