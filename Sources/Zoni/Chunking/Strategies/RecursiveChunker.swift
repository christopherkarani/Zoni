// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Recursive chunking strategy using hierarchical separators (LlamaIndex-style).

import Foundation

// MARK: - RecursiveChunker

/// A chunking strategy that recursively splits text using hierarchical separators.
///
/// `RecursiveChunker` implements the LlamaIndex-style hierarchical splitting approach.
/// It tries each separator in order, preferring larger semantic boundaries (like paragraphs)
/// before falling back to smaller ones (like sentences, then words, then characters).
///
/// This strategy produces more semantically coherent chunks than fixed-size chunking
/// because it respects natural text boundaries. When a segment exceeds the target
/// chunk size, the chunker recursively splits it using the next separator in the hierarchy.
///
/// ## Separator Hierarchy
/// The default separators are ordered from largest to smallest semantic units:
/// 1. `"\n\n"` - Paragraph boundaries (double newlines)
/// 2. `"\n"` - Line boundaries
/// 3. `". "` - Sentence boundaries
/// 4. `", "` - Clause boundaries
/// 5. `" "` - Word boundaries
/// 6. `""` - Character-level splitting (fallback)
///
/// ## Example Usage
/// ```swift
/// // Default recursive chunking
/// let chunker = RecursiveChunker(chunkSize: 1000, chunkOverlap: 200)
/// let chunks = try await chunker.chunk(document)
///
/// // Custom separators for code
/// let codeChunker = RecursiveChunker(
///     separators: ["\n\n", "\n", " ", ""],
///     chunkSize: 500,
///     chunkOverlap: 50
/// )
/// let codeChunks = try await codeChunker.chunk(sourceCode, metadata: nil)
/// ```
///
/// ## Performance Considerations
/// - More separators increase processing time but improve chunk quality
/// - The empty string separator (`""`) enables character-level fallback splitting
/// - Large overlap values increase the number of chunks and embedding costs
public struct RecursiveChunker: ChunkingStrategy, Sendable {

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"recursive"` for identification in configurations and logging.
    public let name = "recursive"

    /// The ordered list of separators to try when splitting text.
    ///
    /// Separators are tried in order from first to last. Earlier separators
    /// represent larger semantic boundaries (paragraphs, sentences) while later
    /// separators represent smaller units (words, characters).
    ///
    /// An empty string (`""`) as the final separator enables character-level
    /// splitting as a fallback for text that cannot be split by other separators.
    public var separators: [String]

    /// The target maximum size for each chunk in characters.
    ///
    /// Chunks may be smaller than this size if natural boundaries occur earlier.
    /// The chunker recursively splits segments that exceed this size using
    /// progressively finer-grained separators.
    public var chunkSize: Int

    /// The number of characters to overlap between consecutive chunks.
    ///
    /// Overlap helps maintain context across chunk boundaries. A value of 0 means
    /// no overlap. The overlap should be less than `chunkSize` to ensure progress.
    public var chunkOverlap: Int

    // MARK: - Initialization

    /// Creates a new recursive chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - separators: The ordered list of separators to use. Defaults to paragraph,
    ///     line, sentence, clause, word, and character separators.
    ///   - chunkSize: The target maximum size for each chunk. Defaults to 1000.
    ///   - chunkOverlap: The number of characters to overlap. Defaults to 200.
    ///
    /// ## Validation
    /// - If `chunkSize` is less than or equal to 0, it is clamped to 1.
    /// - If `chunkOverlap` is negative, it is clamped to 0.
    /// - If `chunkOverlap` is greater than or equal to `chunkSize`, it is reduced
    ///   to `chunkSize - 1` to ensure chunking can make progress.
    public init(
        separators: [String] = ["\n\n", "\n", ". ", ", ", " ", ""],
        chunkSize: Int = 1000,
        chunkOverlap: Int = 200
    ) {
        self.separators = separators

        // Ensure chunk size is at least 1
        let validChunkSize = max(1, chunkSize)
        self.chunkSize = validChunkSize

        // Ensure overlap is non-negative and less than chunk size
        let validOverlap = max(0, min(chunkOverlap, validChunkSize - 1))
        self.chunkOverlap = validOverlap
    }

    // MARK: - Public Methods

    /// Chunks a document into segments using hierarchical separators.
    ///
    /// Extracts the content from the document and creates chunks with metadata
    /// linking back to the source document. The document's ID and source are
    /// preserved in the chunk metadata.
    ///
    /// - Parameter document: The document to chunk.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/emptyDocument`` if the document content is empty.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = RecursiveChunker(chunkSize: 500, chunkOverlap: 50)
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

    /// Chunks raw text into segments using hierarchical separators.
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
    ///
    /// ## Example
    /// ```swift
    /// let chunker = RecursiveChunker(chunkSize: 500)
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

        // Perform recursive splitting
        let segments = recursiveSplit(text: trimmedText, separators: separators)

        // Merge small segments and apply size limits
        let mergedSegments = mergeSegmentsToSize(segments)

        // Create chunks with proper metadata and overlap
        let chunks = createChunksWithOverlap(
            segments: mergedSegments,
            originalText: trimmedText,
            documentId: baseDocumentId,
            source: baseSource,
            custom: baseCustom
        )

        return chunks
    }

    // MARK: - Private Methods

    /// Recursively splits text using the separator hierarchy.
    ///
    /// Tries each separator in order, preferring larger semantic boundaries.
    /// If a segment exceeds the chunk size, it is recursively split using
    /// the next separator in the hierarchy.
    ///
    /// - Parameters:
    ///   - text: The text to split.
    ///   - separators: The remaining separators to try.
    /// - Returns: An array of text segments.
    private func recursiveSplit(text: String, separators: [String]) -> [String] {
        guard !text.isEmpty else { return [] }

        // If text fits within chunk size, return it as-is
        if text.count <= chunkSize {
            return [text]
        }

        // If no separators left, split by character
        guard !separators.isEmpty else {
            return splitByCharacter(text)
        }

        let currentSeparator = separators[0]
        let remainingSeparators = Array(separators.dropFirst())

        // Handle empty separator (character-level splitting)
        if currentSeparator.isEmpty {
            return splitByCharacter(text)
        }

        // Try to split by the current separator
        let parts = TextSplitter.split(text, separators: [currentSeparator])

        // If no split occurred, try the next separator
        if parts.count <= 1 {
            return recursiveSplit(text: text, separators: remainingSeparators)
        }

        // Process each part, recursively splitting if needed
        var result: [String] = []
        for part in parts {
            if part.count <= chunkSize {
                result.append(part)
            } else {
                // Recursively split using remaining separators
                let subParts = recursiveSplit(text: part, separators: remainingSeparators)
                result.append(contentsOf: subParts)
            }
        }

        return result
    }

    /// Splits text by character when no other separators work.
    ///
    /// - Parameter text: The text to split.
    /// - Returns: An array of character-level segments.
    private func splitByCharacter(_ text: String) -> [String] {
        guard text.count > chunkSize else { return [text] }

        var segments: [String] = []
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            let remainingDistance = text.distance(from: startIndex, to: text.endIndex)
            let segmentLength = min(chunkSize, remainingDistance)
            let endIndex = text.index(startIndex, offsetBy: segmentLength)

            let segment = String(text[startIndex..<endIndex])
            segments.append(segment)

            // Move to next position (no overlap at this stage)
            if endIndex >= text.endIndex {
                break
            }
            startIndex = endIndex
        }

        return segments
    }

    /// Merges small consecutive segments to approach the target chunk size.
    ///
    /// This prevents creating too many tiny chunks when text has many natural
    /// boundaries close together.
    ///
    /// - Parameter segments: The segments to merge.
    /// - Returns: Merged segments that respect the chunk size limit.
    private func mergeSegmentsToSize(_ segments: [String]) -> [String] {
        guard !segments.isEmpty else { return [] }

        var result: [String] = []
        var currentChunk = ""

        for segment in segments {
            let potentialChunk = currentChunk.isEmpty ? segment : currentChunk + " " + segment

            if potentialChunk.count <= chunkSize {
                currentChunk = potentialChunk
            } else {
                // Current chunk is as large as it can get
                if !currentChunk.isEmpty {
                    result.append(currentChunk)
                }
                // Start new chunk with current segment
                currentChunk = segment

                // If single segment exceeds size, it will be handled as-is
                if segment.count > chunkSize {
                    result.append(segment)
                    currentChunk = ""
                }
            }
        }

        // Add remaining content
        if !currentChunk.isEmpty {
            result.append(currentChunk)
        }

        return result
    }

    /// Creates chunks with proper metadata and overlap between consecutive chunks.
    ///
    /// - Parameters:
    ///   - segments: The text segments to convert to chunks.
    ///   - originalText: The original text for offset calculations.
    ///   - documentId: The document ID for chunk metadata.
    ///   - source: The source for chunk metadata.
    ///   - custom: Custom metadata to include.
    /// - Returns: An array of chunks with accurate position metadata.
    private func createChunksWithOverlap(
        segments: [String],
        originalText: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        guard !segments.isEmpty else { return [] }

        var chunks: [Chunk] = []
        var searchStartOffset = 0

        for (index, segment) in segments.enumerated() {
            // Find the segment in the original text starting from the last found position
            let searchStartIndex = originalText.index(
                originalText.startIndex,
                offsetBy: min(searchStartOffset, originalText.count),
                limitedBy: originalText.endIndex
            ) ?? originalText.endIndex

            let searchSubstring = originalText[searchStartIndex...]

            // Find offset in original text
            var startOffset = searchStartOffset
            var endOffset = searchStartOffset + segment.count

            if let range = searchSubstring.range(of: segment) {
                startOffset = originalText.distance(from: originalText.startIndex, to: range.lowerBound)
                endOffset = originalText.distance(from: originalText.startIndex, to: range.upperBound)
                searchStartOffset = endOffset
            } else {
                // If exact match not found, use sequential positioning
                searchStartOffset = endOffset
            }

            // Apply overlap from previous chunk
            var chunkContent = segment
            var adjustedStartOffset = startOffset

            if index > 0 && chunkOverlap > 0 && startOffset > 0 {
                let overlapStartOffset = max(0, startOffset - chunkOverlap)
                let overlapStartIndex = originalText.index(
                    originalText.startIndex,
                    offsetBy: overlapStartOffset
                )
                let contentEndIndex = originalText.index(
                    originalText.startIndex,
                    offsetBy: min(endOffset, originalText.count)
                )

                chunkContent = String(originalText[overlapStartIndex..<contentEndIndex])
                adjustedStartOffset = overlapStartOffset
            }

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: index,
                startOffset: adjustedStartOffset,
                endOffset: endOffset,
                source: source,
                custom: custom
            )

            let chunk = Chunk(content: chunkContent, metadata: chunkMetadata)
            chunks.append(chunk)
        }

        return chunks
    }
}

// MARK: - CustomStringConvertible

extension RecursiveChunker: CustomStringConvertible {
    public var description: String {
        let separatorCount = separators.count
        return "RecursiveChunker(size: \(chunkSize), overlap: \(chunkOverlap), separators: \(separatorCount))"
    }
}
