// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// PDFLoader.swift - Loader for PDF files (Apple platforms only)

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

/// A document loader for PDF files.
///
/// `PDFLoader` extracts text content from PDF documents using PDFKit on Apple platforms.
/// On Linux or other platforms where PDFKit is not available, loading operations throw
/// an `unsupportedFileType` error.
///
/// ## Features
/// - Extract text from all pages or a specific page range
/// - Load individual pages as separate documents
/// - Preserve page metadata (page numbers, total pages)
/// - Configurable layout preservation
///
/// ## Example
/// ```swift
/// let loader = PDFLoader()
///
/// // Load entire PDF as single document
/// let document = try await loader.load(from: pdfURL)
///
/// // Load specific page range
/// let rangeLoader = PDFLoader(pageRange: 0...4)
/// let firstFivePages = try await rangeLoader.load(from: pdfURL)
///
/// // Load each page as separate document
/// let pages = try await loader.loadPages(from: pdfURL)
/// for page in pages {
///     print("Page \(page.metadata.custom["pageNumber"]?.intValue ?? 0)")
/// }
/// ```
///
/// ## Platform Support
/// - macOS: Full support via PDFKit
/// - iOS/iPadOS/tvOS/watchOS: Full support via PDFKit
/// - Linux: Not supported (throws `unsupportedFileType`)
public struct PDFLoader: DocumentLoader, Sendable {

    /// The file extensions supported by this loader.
    public static let supportedExtensions: Set<String> = ["pdf"]

    /// The page range to extract.
    ///
    /// When `nil`, all pages are extracted. Page indices are zero-based.
    /// For example, `0...2` extracts the first three pages.
    public var pageRange: ClosedRange<Int>?

    /// Whether to preserve layout formatting in the extracted text.
    ///
    /// When `true`, attempts to maintain the visual layout of text in the PDF.
    /// When `false` (default), text is extracted in reading order without layout preservation.
    public var preserveLayout: Bool

    /// Creates a new PDF loader with the specified options.
    ///
    /// - Parameters:
    ///   - pageRange: The range of pages to extract (zero-based). Pass `nil` to extract all pages.
    ///   - preserveLayout: Whether to preserve layout formatting. Defaults to `false`.
    public init(pageRange: ClosedRange<Int>? = nil, preserveLayout: Bool = false) {
        self.pageRange = pageRange
        self.preserveLayout = preserveLayout
    }

    #if canImport(PDFKit)

    /// Loads a document from a file URL.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: A document containing the extracted text content with appropriate metadata.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read,
    ///           `ZoniError.invalidData` if the data is not a valid PDF.
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
            mimeType: "application/pdf"
        )

        return try await load(from: data, metadata: metadata)
    }

    /// Loads a document from raw PDF data.
    ///
    /// - Parameters:
    ///   - data: The raw PDF data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Returns: A document containing the extracted text content.
    /// - Throws: `ZoniError.invalidData` if the data is not a valid PDF.
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        guard let pdfDocument = PDFDocument(data: data) else {
            throw ZoniError.invalidData(reason: "Unable to parse PDF document")
        }

        var finalMetadata = metadata ?? DocumentMetadata()
        if finalMetadata.mimeType == nil {
            finalMetadata.mimeType = "application/pdf"
        }

        // Extract text from pages
        let pageCount = pdfDocument.pageCount
        var textParts: [String] = []

        let startPage = pageRange?.lowerBound ?? 0
        let endPage = min(pageRange?.upperBound ?? (pageCount - 1), pageCount - 1)

        // Ensure valid range
        guard startPage <= endPage && startPage < pageCount else {
            finalMetadata.custom["pageCount"] = .int(pageCount)
            return Document(content: "", metadata: finalMetadata)
        }

        for pageIndex in startPage...endPage {
            if let page = pdfDocument.page(at: pageIndex),
               let pageText = page.string {
                textParts.append(pageText)
            }
        }

        let content = textParts.joined(separator: "\n\n")
        finalMetadata.custom["pageCount"] = .int(pageCount)

        return Document(content: content, metadata: finalMetadata)
    }

    /// Loads each page of the PDF as a separate document.
    ///
    /// This method is useful for processing PDF pages individually, such as when
    /// each page should be chunked and embedded separately.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: An array of documents, one per page.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read,
    ///           `ZoniError.invalidData` if the data is not a valid PDF.
    public func loadPages(from url: URL) async throws -> [Document] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ZoniError.loadingFailed(url: url, reason: error.localizedDescription)
        }

        let metadata = DocumentMetadata(
            source: LoadingUtils.filename(from: url),
            url: url,
            mimeType: "application/pdf"
        )

        return try await loadPages(from: data, metadata: metadata)
    }

    /// Loads each page of the PDF data as a separate document.
    ///
    /// - Parameters:
    ///   - data: The raw PDF data to load.
    ///   - metadata: Optional base metadata to attach to each page document.
    /// - Returns: An array of documents, one per page.
    /// - Throws: `ZoniError.invalidData` if the data is not a valid PDF.
    public func loadPages(from data: Data, metadata: DocumentMetadata?) async throws -> [Document] {
        guard let pdfDocument = PDFDocument(data: data) else {
            throw ZoniError.invalidData(reason: "Unable to parse PDF document")
        }

        var documents: [Document] = []
        let pageCount = pdfDocument.pageCount

        let startPage = pageRange?.lowerBound ?? 0
        let endPage = min(pageRange?.upperBound ?? (pageCount - 1), pageCount - 1)

        // Ensure valid range
        guard startPage <= endPage && startPage < pageCount else {
            return []
        }

        for pageIndex in startPage...endPage {
            if let page = pdfDocument.page(at: pageIndex) {
                var pageMetadata = metadata ?? DocumentMetadata()
                if pageMetadata.mimeType == nil {
                    pageMetadata.mimeType = "application/pdf"
                }

                // Add page-specific metadata (1-based page numbers for user display)
                pageMetadata.custom["pageNumber"] = .int(pageIndex + 1)
                pageMetadata.custom["totalPages"] = .int(pageCount)

                let content = page.string ?? ""
                documents.append(Document(content: content, metadata: pageMetadata))
            }
        }

        return documents
    }

    #else

    // MARK: - Linux Fallback (PDF not supported)

    /// Loads a document from a file URL.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Throws: `ZoniError.unsupportedFileType` as PDFKit is not available on this platform.
    public func load(from url: URL) async throws -> Document {
        throw ZoniError.unsupportedFileType("pdf (PDFKit not available on this platform)")
    }

    /// Loads a document from raw PDF data.
    ///
    /// - Parameters:
    ///   - data: The raw PDF data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Throws: `ZoniError.unsupportedFileType` as PDFKit is not available on this platform.
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        throw ZoniError.unsupportedFileType("pdf (PDFKit not available on this platform)")
    }

    /// Loads each page of the PDF as a separate document.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Throws: `ZoniError.unsupportedFileType` as PDFKit is not available on this platform.
    public func loadPages(from url: URL) async throws -> [Document] {
        throw ZoniError.unsupportedFileType("pdf (PDFKit not available on this platform)")
    }

    /// Loads each page of the PDF data as a separate document.
    ///
    /// - Parameters:
    ///   - data: The raw PDF data to load.
    ///   - metadata: Optional base metadata to attach to each page document.
    /// - Throws: `ZoniError.unsupportedFileType` as PDFKit is not available on this platform.
    public func loadPages(from data: Data, metadata: DocumentMetadata?) async throws -> [Document] {
        throw ZoniError.unsupportedFileType("pdf (PDFKit not available on this platform)")
    }

    #endif
}
