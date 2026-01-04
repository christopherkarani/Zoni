// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Sentence-based chunking strategy for splitting documents at sentence boundaries.

import Foundation

// MARK: - SentenceChunker

/// A chunking strategy that splits text at sentence boundaries.
///
/// `SentenceChunker` uses linguistic sentence detection to create semantically coherent
/// chunks while respecting configurable size constraints. This approach preserves sentence
/// integrity, which typically leads to better retrieval quality compared to fixed-size
/// character-based chunking.
///
/// The chunker groups sentences together until reaching the target size, then starts
/// a new chunk. Optional sentence overlap ensures context is not lost at chunk boundaries.
///
/// ## Size Constraints
/// - **targetSize**: The ideal chunk size in characters (default: 1000)
/// - **minSize**: Minimum chunk size; smaller chunks are merged with neighbors (default: 100)
/// - **maxSize**: Maximum chunk size; enforced even if it means splitting mid-sentence (default: 2000)
///
/// ## Overlap
/// The `overlapSentences` parameter controls how many sentences from the end of one
/// chunk are repeated at the beginning of the next. This maintains context across
/// chunk boundaries at the cost of increased total content.
///
/// ## Example Usage
/// ```swift
/// // Basic sentence chunking
/// let chunker = SentenceChunker()
/// let chunks = try await chunker.chunk(document)
///
/// // Custom configuration with overlap
/// let customChunker = SentenceChunker(
///     targetSize: 500,
///     minSize: 50,
///     maxSize: 1000,
///     overlapSentences: 2
/// )
/// let overlappingChunks = try await customChunker.chunk(document)
/// ```
///
/// ## Performance Considerations
/// - Sentence detection adds overhead compared to fixed-size chunking
/// - Larger `overlapSentences` values increase the number of chunks
/// - Very long sentences may require splitting to respect `maxSize`
public struct SentenceChunker: ChunkingStrategy, Sendable {

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"sentence"` for identification in configurations and logging.
    public let name = "sentence"

    /// The target size for each chunk in characters.
    ///
    /// The chunker will group sentences together until this approximate size is reached.
    /// Individual chunks may be larger or smaller depending on sentence boundaries.
    public var targetSize: Int

    /// The minimum size for a chunk in characters.
    ///
    /// Chunks smaller than this threshold will be merged with adjacent chunks
    /// when possible. This prevents creating very short chunks that may not
    /// provide enough context for meaningful embedding.
    public var minSize: Int

    /// The maximum size for a chunk in characters.
    ///
    /// This is a hard limit. If a single sentence exceeds this size, it will
    /// be split to respect this constraint.
    public var maxSize: Int

    /// The number of sentences to overlap between consecutive chunks.
    ///
    /// When set to a value greater than 0, the last N sentences of each chunk
    /// are repeated at the beginning of the next chunk. This ensures context
    /// continuity across chunk boundaries.
    public var overlapSentences: Int

    // MARK: - Initialization

    /// Creates a new sentence-based chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - targetSize: The target chunk size in characters. Defaults to 1000.
    ///   - minSize: The minimum chunk size in characters. Defaults to 100.
    ///   - maxSize: The maximum chunk size in characters. Defaults to 2000.
    ///   - overlapSentences: The number of sentences to overlap. Defaults to 1.
    ///
    /// ## Validation
    /// - If `targetSize` is less than 1, it is clamped to 1.
    /// - If `minSize` is less than 0, it is clamped to 0.
    /// - If `minSize` is greater than `targetSize`, it is set to `targetSize`.
    /// - If `maxSize` is less than `targetSize`, it is set to `targetSize`.
    /// - If `overlapSentences` is negative, it is clamped to 0.
    public init(
        targetSize: Int = 1000,
        minSize: Int = 100,
        maxSize: Int = 2000,
        overlapSentences: Int = 1
    ) {
        // Ensure target size is at least 1
        let validTargetSize = max(1, targetSize)
        self.targetSize = validTargetSize

        // Ensure min size is valid and not greater than target
        let validMinSize = max(0, min(minSize, validTargetSize))
        self.minSize = validMinSize

        // Ensure max size is at least as large as target
        let validMaxSize = max(validTargetSize, maxSize)
        self.maxSize = validMaxSize

        // Ensure overlap is non-negative
        self.overlapSentences = max(0, overlapSentences)
    }

    // MARK: - Public Methods

    /// Chunks a document into sentence-based segments.
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
    /// let chunker = SentenceChunker(targetSize: 500, overlapSentences: 1)
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

    /// Chunks raw text into sentence-based segments with optional metadata.
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
    /// let chunker = SentenceChunker(targetSize: 500)
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

        // Split text into sentences
        let sentences = TextSplitter.splitSentences(trimmedText)

        // Handle edge case: no sentences found (text has no sentence terminators)
        guard !sentences.isEmpty else {
            // Treat the entire text as one chunk if it meets size constraints
            return try createSingleChunk(
                from: trimmedText,
                documentId: baseDocumentId,
                source: baseSource,
                custom: baseCustom
            )
        }

        // Group sentences into chunks
        return createChunks(
            from: sentences,
            originalText: trimmedText,
            documentId: baseDocumentId,
            source: baseSource,
            custom: baseCustom
        )
    }

    // MARK: - Private Methods

    /// Creates a single chunk from the given text.
    ///
    /// Used when the text has no sentence terminators and must be treated as a single unit.
    private func createSingleChunk(
        from text: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) throws -> [Chunk] {
        // If text exceeds maxSize, split it (fallback to character-based splitting)
        if text.count > maxSize {
            return splitLongText(
                text,
                startOffset: 0,
                documentId: documentId,
                source: source,
                custom: custom,
                startingIndex: 0
            )
        }

        let chunkMetadata = ChunkMetadata(
            documentId: documentId,
            index: 0,
            startOffset: 0,
            endOffset: text.count,
            source: source,
            custom: custom
        )

        return [Chunk(content: text, metadata: chunkMetadata)]
    }

    /// Groups sentences into chunks respecting size constraints.
    private func createChunks(
        from sentences: [String],
        originalText: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var currentSentences: [String] = []
        var currentSize = 0
        var chunkIndex = 0

        // Track offsets in the original text
        var sentenceOffsets: [(start: Int, end: Int)] = []
        var searchStartOffset = 0

        // Calculate offsets for each sentence in the original text
        for sentence in sentences {
            if let range = originalText.range(
                of: sentence,
                range: originalText.index(originalText.startIndex, offsetBy: searchStartOffset)..<originalText.endIndex
            ) {
                let start = originalText.distance(from: originalText.startIndex, to: range.lowerBound)
                let end = originalText.distance(from: originalText.startIndex, to: range.upperBound)
                sentenceOffsets.append((start: start, end: end))
                searchStartOffset = end
            } else {
                // Fallback: use approximate offset
                sentenceOffsets.append((start: searchStartOffset, end: searchStartOffset + sentence.count))
                searchStartOffset += sentence.count
            }
        }

        var currentStartSentenceIndex = 0

        for (sentenceIndex, sentence) in sentences.enumerated() {
            let sentenceSize = sentence.count

            // Check if adding this sentence would exceed target size
            let separatorSize = currentSentences.isEmpty ? 0 : 1 // Space separator
            let projectedSize = currentSize + separatorSize + sentenceSize

            if projectedSize > targetSize && !currentSentences.isEmpty {
                // Create chunk from current sentences
                let chunk = createChunkFromSentences(
                    currentSentences,
                    sentenceOffsets: sentenceOffsets,
                    startSentenceIndex: currentStartSentenceIndex,
                    endSentenceIndex: sentenceIndex - 1,
                    chunkIndex: chunkIndex,
                    documentId: documentId,
                    source: source,
                    custom: custom
                )

                // Check if chunk is too large and needs splitting
                if chunk.content.count > maxSize {
                    let splitChunks = splitLongChunk(
                        chunk,
                        startingIndex: chunkIndex,
                        documentId: documentId,
                        source: source,
                        custom: custom
                    )
                    chunks.append(contentsOf: splitChunks)
                    chunkIndex += splitChunks.count
                } else {
                    chunks.append(chunk)
                    chunkIndex += 1
                }

                // Apply overlap: keep last N sentences
                let overlapStart = max(0, currentSentences.count - overlapSentences)
                currentSentences = Array(currentSentences.suffix(from: overlapStart))
                currentSize = currentSentences.joined(separator: " ").count
                currentStartSentenceIndex = sentenceIndex - (currentSentences.count)
            }

            // Handle sentences that exceed maxSize individually
            if sentenceSize > maxSize {
                // First, flush current accumulated sentences if any
                if !currentSentences.isEmpty {
                    let chunk = createChunkFromSentences(
                        currentSentences,
                        sentenceOffsets: sentenceOffsets,
                        startSentenceIndex: currentStartSentenceIndex,
                        endSentenceIndex: sentenceIndex - 1,
                        chunkIndex: chunkIndex,
                        documentId: documentId,
                        source: source,
                        custom: custom
                    )
                    chunks.append(chunk)
                    chunkIndex += 1
                    currentSentences = []
                    currentSize = 0
                }

                // Split the long sentence
                let offset = sentenceOffsets[sentenceIndex]
                let splitChunks = splitLongText(
                    sentence,
                    startOffset: offset.start,
                    documentId: documentId,
                    source: source,
                    custom: custom,
                    startingIndex: chunkIndex
                )
                chunks.append(contentsOf: splitChunks)
                chunkIndex += splitChunks.count
                currentStartSentenceIndex = sentenceIndex + 1
            } else {
                // Add sentence to current accumulator
                currentSentences.append(sentence)
                currentSize = currentSentences.joined(separator: " ").count
            }
        }

        // Handle remaining sentences
        if !currentSentences.isEmpty {
            let chunk = createChunkFromSentences(
                currentSentences,
                sentenceOffsets: sentenceOffsets,
                startSentenceIndex: currentStartSentenceIndex,
                endSentenceIndex: sentences.count - 1,
                chunkIndex: chunkIndex,
                documentId: documentId,
                source: source,
                custom: custom
            )

            // Check if final chunk is too small and should be merged with previous
            if chunk.content.count < minSize && !chunks.isEmpty {
                let previousChunk = chunks.removeLast()
                let mergedContent = previousChunk.content + " " + chunk.content
                let mergedMetadata = ChunkMetadata(
                    documentId: documentId,
                    index: previousChunk.metadata.index,
                    startOffset: previousChunk.metadata.startOffset,
                    endOffset: chunk.metadata.endOffset,
                    source: source,
                    custom: custom
                )

                // Check if merged chunk exceeds maxSize
                if mergedContent.count > maxSize {
                    // Can't merge, keep both
                    chunks.append(previousChunk)
                    chunks.append(chunk)
                } else {
                    chunks.append(Chunk(content: mergedContent, metadata: mergedMetadata))
                }
            } else if chunk.content.count > maxSize {
                // Split oversized final chunk
                let splitChunks = splitLongChunk(
                    chunk,
                    startingIndex: chunkIndex,
                    documentId: documentId,
                    source: source,
                    custom: custom
                )
                chunks.append(contentsOf: splitChunks)
            } else {
                chunks.append(chunk)
            }
        }

        return chunks
    }

    /// Creates a chunk from a collection of sentences.
    private func createChunkFromSentences(
        _ sentences: [String],
        sentenceOffsets: [(start: Int, end: Int)],
        startSentenceIndex: Int,
        endSentenceIndex: Int,
        chunkIndex: Int,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> Chunk {
        let content = sentences.joined(separator: " ")

        // Calculate offsets from the original text
        let validStartIndex = max(0, min(startSentenceIndex, sentenceOffsets.count - 1))
        let validEndIndex = max(0, min(endSentenceIndex, sentenceOffsets.count - 1))

        let startOffset = sentenceOffsets[validStartIndex].start
        let endOffset = sentenceOffsets[validEndIndex].end

        let chunkMetadata = ChunkMetadata(
            documentId: documentId,
            index: chunkIndex,
            startOffset: startOffset,
            endOffset: endOffset,
            source: source,
            custom: custom
        )

        return Chunk(content: content, metadata: chunkMetadata)
    }

    /// Splits a chunk that exceeds maxSize into smaller pieces.
    private func splitLongChunk(
        _ chunk: Chunk,
        startingIndex: Int,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        return splitLongText(
            chunk.content,
            startOffset: chunk.metadata.startOffset,
            documentId: documentId,
            source: source,
            custom: custom,
            startingIndex: startingIndex
        )
    }

    /// Splits text that exceeds maxSize into chunks of at most maxSize characters.
    private func splitLongText(
        _ text: String,
        startOffset: Int,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue],
        startingIndex: Int
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var currentIndex = text.startIndex
        var chunkIndex = startingIndex
        var localOffset = 0

        while currentIndex < text.endIndex {
            let remainingDistance = text.distance(from: currentIndex, to: text.endIndex)
            let chunkLength = min(maxSize, remainingDistance)
            let endIndex = text.index(currentIndex, offsetBy: chunkLength)

            let chunkContent = String(text[currentIndex..<endIndex])
            let chunkStartOffset = startOffset + localOffset
            let chunkEndOffset = chunkStartOffset + chunkContent.count

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: chunkIndex,
                startOffset: chunkStartOffset,
                endOffset: chunkEndOffset,
                source: source,
                custom: custom
            )

            chunks.append(Chunk(content: chunkContent, metadata: chunkMetadata))

            localOffset += chunkLength
            currentIndex = endIndex
            chunkIndex += 1
        }

        return chunks
    }
}

// MARK: - CustomStringConvertible

extension SentenceChunker: CustomStringConvertible {
    public var description: String {
        "SentenceChunker(target: \(targetSize), min: \(minSize), max: \(maxSize), overlap: \(overlapSentences) sentences)"
    }
}
