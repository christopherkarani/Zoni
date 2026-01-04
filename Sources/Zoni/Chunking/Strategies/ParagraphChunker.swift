// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Paragraph-based chunking strategy for splitting documents by paragraph boundaries.

import Foundation

// MARK: - ParagraphChunker

/// A chunking strategy that splits text by paragraph boundaries.
///
/// `ParagraphChunker` groups consecutive paragraphs into chunks, respecting both
/// paragraph count and size limits. This strategy preserves semantic coherence
/// by keeping paragraphs intact and supports overlap for context continuity.
///
/// Paragraphs are identified using `TextSplitter.splitParagraphs()`, which splits
/// on blank lines (double newlines or more).
///
/// ## Configuration Options
/// - **maxParagraphsPerChunk**: Maximum number of paragraphs in each chunk
/// - **maxChunkSize**: Maximum character count for each chunk
/// - **overlapParagraphs**: Number of paragraphs to repeat at chunk boundaries
/// - **preserveShortParagraphs**: Whether to keep short paragraphs separate
///
/// ## Example Usage
/// ```swift
/// // Basic paragraph chunking
/// let chunker = ParagraphChunker()
/// let chunks = try await chunker.chunk(document)
///
/// // Custom configuration
/// let customChunker = ParagraphChunker(
///     maxParagraphsPerChunk: 5,
///     maxChunkSize: 3000,
///     overlapParagraphs: 2,
///     preserveShortParagraphs: false
/// )
/// let customChunks = try await customChunker.chunk(document)
/// ```
///
/// ## Performance Considerations
/// - Paragraph detection uses regex-based splitting which is efficient for most texts
/// - Large documents with many short paragraphs may produce many chunks
/// - The overlap feature increases total chunk count and embedding costs
public struct ParagraphChunker: ChunkingStrategy, Sendable {

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"paragraph"` for identification in configurations and logging.
    public let name = "paragraph"

    /// The maximum number of paragraphs to include in each chunk.
    ///
    /// Chunks will contain up to this many paragraphs, unless the combined
    /// size exceeds `maxChunkSize`. Defaults to 3.
    public var maxParagraphsPerChunk: Int

    /// The maximum character count for each chunk.
    ///
    /// If adding another paragraph would exceed this limit, a new chunk
    /// is started instead. Defaults to 2000.
    public var maxChunkSize: Int

    /// The number of paragraphs to overlap between consecutive chunks.
    ///
    /// Overlap helps maintain context across chunk boundaries. For example,
    /// with an overlap of 1, the last paragraph of chunk N will also appear
    /// as the first paragraph of chunk N+1. Defaults to 1.
    public var overlapParagraphs: Int

    /// Whether to preserve short paragraphs as separate entities.
    ///
    /// When `true`, short paragraphs are kept as-is during chunking.
    /// When `false`, short paragraphs may be merged with adjacent paragraphs
    /// to form larger chunks. Defaults to `true`.
    public var preserveShortParagraphs: Bool

    // MARK: - Initialization

    /// Creates a new paragraph chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - maxParagraphsPerChunk: Maximum paragraphs per chunk. Defaults to 3.
    ///   - maxChunkSize: Maximum character count per chunk. Defaults to 2000.
    ///   - overlapParagraphs: Number of paragraphs to overlap. Defaults to 1.
    ///   - preserveShortParagraphs: Whether to keep short paragraphs separate. Defaults to `true`.
    ///
    /// ## Validation
    /// - If `maxParagraphsPerChunk` is less than 1, it is clamped to 1.
    /// - If `maxChunkSize` is less than 1, it is clamped to 1.
    /// - If `overlapParagraphs` is negative, it is clamped to 0.
    /// - If `overlapParagraphs` is greater than or equal to `maxParagraphsPerChunk`,
    ///   it is reduced to `maxParagraphsPerChunk - 1` to ensure progress.
    public init(
        maxParagraphsPerChunk: Int = 3,
        maxChunkSize: Int = 2000,
        overlapParagraphs: Int = 1,
        preserveShortParagraphs: Bool = true
    ) {
        // Ensure maxParagraphsPerChunk is at least 1
        let validMaxParagraphs = max(1, maxParagraphsPerChunk)
        self.maxParagraphsPerChunk = validMaxParagraphs

        // Ensure maxChunkSize is at least 1
        self.maxChunkSize = max(1, maxChunkSize)

        // Ensure overlap is non-negative and less than maxParagraphsPerChunk
        let validOverlap = max(0, min(overlapParagraphs, validMaxParagraphs - 1))
        self.overlapParagraphs = validOverlap

        self.preserveShortParagraphs = preserveShortParagraphs
    }

    // MARK: - Public Methods

    /// Chunks a document into paragraph-based segments.
    ///
    /// Extracts the content from the document and creates chunks with metadata
    /// linking back to the source document. The document's ID and source are
    /// preserved in the chunk metadata.
    ///
    /// - Parameter document: The document to chunk.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/emptyDocument`` if the document content is empty.
    /// - Throws: ``ZoniError/chunkingFailed(reason:)`` if chunking fails.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = ParagraphChunker(maxParagraphsPerChunk: 3)
    /// let chunks = try await chunker.chunk(document)
    /// for chunk in chunks {
    ///     print("Chunk \(chunk.metadata.index): \(chunk.characterCount) chars")
    /// }
    /// ```
    public func chunk(_ document: Document) async throws -> [Chunk] {
        let baseMetadata = ChunkMetadata(
            documentId: document.id,
            index: 0,
            source: document.metadata.source
        )

        return try await chunk(document.content, metadata: baseMetadata)
    }

    /// Chunks raw text into paragraph-based segments with optional metadata.
    ///
    /// Use this method when working with text that is not wrapped in a `Document`,
    /// or when you need to provide custom base metadata for the resulting chunks.
    ///
    /// - Parameters:
    ///   - text: The text to chunk.
    ///   - metadata: Base metadata to include in each chunk. If `nil`, a new
    ///     document ID is generated and used for all chunks.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/emptyDocument`` if the text is empty or whitespace-only.
    /// - Throws: ``ZoniError/chunkingFailed(reason:)`` if chunking fails.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = ParagraphChunker()
    /// let chunks = try await chunker.chunk(longText, metadata: nil)
    /// ```
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk] {
        // Validate input
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ZoniError.emptyDocument
        }

        // Prepare base metadata
        let baseDocumentId = metadata?.documentId ?? UUID().uuidString
        let baseSource = metadata?.source
        let baseCustom = metadata?.custom ?? [:]

        // Split text into paragraphs
        let paragraphs = TextSplitter.splitParagraphs(text)

        guard !paragraphs.isEmpty else {
            throw ZoniError.emptyDocument
        }

        // Process paragraphs based on preserveShortParagraphs setting
        let processedParagraphs: [String]
        if preserveShortParagraphs {
            processedParagraphs = paragraphs
        } else {
            // Merge short paragraphs (less than 50 characters) with adjacent ones
            processedParagraphs = mergeShortParagraphs(paragraphs)
        }

        // Build chunks from paragraphs
        return buildChunks(
            from: processedParagraphs,
            originalText: text,
            documentId: baseDocumentId,
            source: baseSource,
            custom: baseCustom
        )
    }

    // MARK: - Private Methods

    /// Merges short paragraphs with their neighbors.
    ///
    /// - Parameter paragraphs: The paragraphs to potentially merge.
    /// - Returns: An array of paragraphs with short ones merged.
    private func mergeShortParagraphs(_ paragraphs: [String]) -> [String] {
        let shortThreshold = 50

        var result: [String] = []
        var accumulator = ""

        for paragraph in paragraphs {
            if accumulator.isEmpty {
                accumulator = paragraph
            } else if paragraph.count < shortThreshold || accumulator.count < shortThreshold {
                // Merge short paragraphs
                accumulator = accumulator + "\n\n" + paragraph
            } else {
                // Current paragraph is not short, finalize accumulator and start new
                result.append(accumulator)
                accumulator = paragraph
            }
        }

        // Add any remaining content
        if !accumulator.isEmpty {
            result.append(accumulator)
        }

        return result
    }

    /// Builds chunks from an array of paragraphs.
    ///
    /// - Parameters:
    ///   - paragraphs: The paragraphs to chunk.
    ///   - originalText: The original text for offset calculation.
    ///   - documentId: The document ID for chunk metadata.
    ///   - source: The source for chunk metadata.
    ///   - custom: Custom metadata to include in each chunk.
    /// - Returns: An array of chunks.
    private func buildChunks(
        from paragraphs: [String],
        originalText: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var paragraphIndex = 0
        var chunkIndex = 0

        while paragraphIndex < paragraphs.count {
            var currentParagraphs: [String] = []
            var currentSize = 0
            var paragraphsInChunk = 0
            var startParagraphIndex = paragraphIndex

            // Collect paragraphs for this chunk
            while paragraphIndex < paragraphs.count &&
                  paragraphsInChunk < maxParagraphsPerChunk {
                let paragraph = paragraphs[paragraphIndex]
                let paragraphSize = paragraph.count

                // Check if adding this paragraph would exceed size limit
                // (unless this is the first paragraph in the chunk)
                let separatorSize = currentParagraphs.isEmpty ? 0 : 2 // "\n\n"
                let newSize = currentSize + separatorSize + paragraphSize

                if !currentParagraphs.isEmpty && newSize > maxChunkSize {
                    // Would exceed size limit, stop here
                    break
                }

                currentParagraphs.append(paragraph)
                currentSize = newSize
                paragraphsInChunk += 1
                paragraphIndex += 1
            }

            // Create chunk content by joining paragraphs
            let chunkContent = currentParagraphs.joined(separator: "\n\n")

            // Calculate offsets in original text
            let (startOffset, endOffset) = calculateOffsets(
                for: currentParagraphs,
                startingAt: startParagraphIndex,
                in: paragraphs,
                originalText: originalText
            )

            // Create chunk metadata
            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: chunkIndex,
                startOffset: startOffset,
                endOffset: endOffset,
                source: source,
                custom: custom
            )

            let chunk = Chunk(content: chunkContent, metadata: chunkMetadata)
            chunks.append(chunk)
            chunkIndex += 1

            // Apply overlap for next chunk
            if paragraphIndex < paragraphs.count && overlapParagraphs > 0 {
                let overlapCount = min(overlapParagraphs, paragraphsInChunk)
                paragraphIndex -= overlapCount
            }

            // Ensure we make progress
            if paragraphIndex <= startParagraphIndex && paragraphIndex < paragraphs.count {
                paragraphIndex = startParagraphIndex + 1
            }
        }

        return chunks
    }

    /// Calculates the character offsets for a set of paragraphs in the original text.
    ///
    /// - Parameters:
    ///   - paragraphs: The paragraphs in the current chunk.
    ///   - startParagraphIndex: The index of the first paragraph in the chunk.
    ///   - allParagraphs: All paragraphs from the document.
    ///   - originalText: The original text.
    /// - Returns: A tuple of (startOffset, endOffset).
    private func calculateOffsets(
        for paragraphs: [String],
        startingAt startParagraphIndex: Int,
        in allParagraphs: [String],
        originalText: String
    ) -> (Int, Int) {
        guard let firstParagraph = paragraphs.first,
              let lastParagraph = paragraphs.last else {
            return (0, 0)
        }

        // Find the start offset by locating the first paragraph in the original text
        var searchStartIndex = originalText.startIndex

        // Skip to the approximate position by accounting for previous paragraphs
        for i in 0..<startParagraphIndex {
            if let range = originalText.range(of: allParagraphs[i], range: searchStartIndex..<originalText.endIndex) {
                searchStartIndex = range.upperBound
            }
        }

        // Find the first paragraph's position
        guard let firstRange = originalText.range(of: firstParagraph, range: searchStartIndex..<originalText.endIndex) else {
            return (0, 0)
        }

        let startOffset = originalText.distance(from: originalText.startIndex, to: firstRange.lowerBound)

        // Find the last paragraph's position
        let lastSearchStart = firstRange.lowerBound
        guard let lastRange = originalText.range(of: lastParagraph, range: lastSearchStart..<originalText.endIndex) else {
            let endOffset = originalText.distance(from: originalText.startIndex, to: firstRange.upperBound)
            return (startOffset, endOffset)
        }

        let endOffset = originalText.distance(from: originalText.startIndex, to: lastRange.upperBound)

        return (startOffset, endOffset)
    }
}

// MARK: - CustomStringConvertible

extension ParagraphChunker: CustomStringConvertible {
    public var description: String {
        "ParagraphChunker(maxParagraphs: \(maxParagraphsPerChunk), maxSize: \(maxChunkSize), overlap: \(overlapParagraphs))"
    }
}
