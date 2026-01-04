// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Fixed-size chunking strategy for splitting documents into uniform segments.

import Foundation

// MARK: - FixedSizeChunker

/// A chunking strategy that splits text into fixed-size segments.
///
/// `FixedSizeChunker` divides text into chunks of a specified size, with optional
/// overlap between consecutive chunks. This is one of the simplest and most commonly
/// used chunking strategies in RAG systems.
///
/// The chunker supports two modes of operation:
/// - **Character-based**: Splits by character count (default)
/// - **Token-based**: Splits by approximate token count using a `TokenCounter`
///
/// ## Overlap
/// Overlap ensures that context is not lost at chunk boundaries. For example, if a
/// sentence spans two chunks, the overlap allows both chunks to contain the full
/// sentence, improving retrieval quality.
///
/// ## Example Usage
/// ```swift
/// // Character-based chunking with overlap
/// let chunker = FixedSizeChunker(chunkSize: 1000, chunkOverlap: 200)
/// let chunks = try await chunker.chunk(document)
///
/// // Token-based chunking
/// let tokenChunker = FixedSizeChunker(
///     chunkSize: 256,
///     chunkOverlap: 50,
///     useTokens: true,
///     tokenCounter: TokenCounter(model: .cl100k)
/// )
/// let tokenChunks = try await tokenChunker.chunk(document)
/// ```
///
/// ## Performance Considerations
/// - Character-based chunking is faster as it does not require token estimation
/// - Token-based chunking provides more accurate size control for LLM context windows
/// - Large overlaps increase the number of chunks and embedding costs
public struct FixedSizeChunker: ChunkingStrategy, Sendable {

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"fixed_size"` for identification in configurations and logging.
    public let name = "fixed_size"

    /// The target size for each chunk.
    ///
    /// When `useTokens` is `false`, this represents the number of characters.
    /// When `useTokens` is `true`, this represents the number of tokens.
    public var chunkSize: Int

    /// The number of characters or tokens to overlap between consecutive chunks.
    ///
    /// Overlap helps maintain context across chunk boundaries. A value of 0 means
    /// no overlap. The overlap should be less than `chunkSize` to ensure progress.
    public var chunkOverlap: Int

    /// Whether to use token-based chunking instead of character-based.
    ///
    /// When `true`, the `tokenCounter` is used to estimate token counts.
    /// When `false`, character counts are used directly.
    public var useTokens: Bool

    /// The token counter to use for token-based chunking.
    ///
    /// Only used when `useTokens` is `true`. If `nil` when `useTokens` is `true`,
    /// a default `TokenCounter` with the `.simple` model is used.
    public var tokenCounter: TokenCounter?

    // MARK: - Initialization

    /// Creates a new fixed-size chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - chunkSize: The target size for each chunk (characters or tokens). Defaults to 1000.
    ///   - chunkOverlap: The number of characters/tokens to overlap. Defaults to 200.
    ///   - useTokens: Whether to use token-based chunking. Defaults to `false`.
    ///   - tokenCounter: The token counter for token-based chunking. Defaults to `nil`.
    ///
    /// ## Validation
    /// - If `chunkSize` is less than or equal to 0, it is clamped to 1.
    /// - If `chunkOverlap` is negative, it is clamped to 0.
    /// - If `chunkOverlap` is greater than or equal to `chunkSize`, it is reduced
    ///   to `chunkSize - 1` to ensure chunking can make progress.
    public init(
        chunkSize: Int = 1000,
        chunkOverlap: Int = 200,
        useTokens: Bool = false,
        tokenCounter: TokenCounter? = nil
    ) {
        // Ensure chunk size is at least 1
        let validChunkSize = max(1, chunkSize)
        self.chunkSize = validChunkSize

        // Ensure overlap is non-negative and less than chunk size
        let validOverlap = max(0, min(chunkOverlap, validChunkSize - 1))
        self.chunkOverlap = validOverlap

        self.useTokens = useTokens
        self.tokenCounter = tokenCounter
    }

    // MARK: - Public Methods

    /// Chunks a document into fixed-size segments.
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
    /// let chunker = FixedSizeChunker(chunkSize: 500, chunkOverlap: 50)
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

    /// Chunks raw text into fixed-size segments with optional metadata.
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
    /// let chunker = FixedSizeChunker(chunkSize: 500)
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

        // Perform chunking based on mode
        if useTokens {
            return try await chunkByTokens(
                text: trimmedText,
                documentId: baseDocumentId,
                source: baseSource,
                custom: baseCustom
            )
        } else {
            return chunkByCharacters(
                text: trimmedText,
                documentId: baseDocumentId,
                source: baseSource,
                custom: baseCustom
            )
        }
    }

    // MARK: - Private Methods

    /// Chunks text by character count.
    ///
    /// - Parameters:
    ///   - text: The text to chunk.
    ///   - documentId: The document ID to use in chunk metadata.
    ///   - source: The source to use in chunk metadata.
    ///   - custom: Custom metadata to include in each chunk.
    /// - Returns: An array of chunks.
    private func chunkByCharacters(
        text: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var startIndex = text.startIndex
        var chunkIndex = 0

        while startIndex < text.endIndex {
            // Calculate end index for this chunk
            let remainingDistance = text.distance(from: startIndex, to: text.endIndex)
            let chunkLength = min(chunkSize, remainingDistance)
            let endIndex = text.index(startIndex, offsetBy: chunkLength)

            // Extract chunk content
            let chunkContent = String(text[startIndex..<endIndex])
            let startOffset = text.distance(from: text.startIndex, to: startIndex)
            let endOffset = text.distance(from: text.startIndex, to: endIndex)

            // Create chunk with metadata
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

            // Calculate next start position with overlap
            let stride = chunkSize - chunkOverlap
            let nextStartOffset = startOffset + stride

            // Check if we've processed all text
            if endIndex >= text.endIndex {
                break
            }

            // Move to next position, ensuring we make progress
            if nextStartOffset >= text.count {
                break
            }

            startIndex = text.index(text.startIndex, offsetBy: nextStartOffset)
            chunkIndex += 1
        }

        return chunks
    }

    /// Chunks text by token count using the configured token counter.
    ///
    /// - Parameters:
    ///   - text: The text to chunk.
    ///   - documentId: The document ID to use in chunk metadata.
    ///   - source: The source to use in chunk metadata.
    ///   - custom: Custom metadata to include in each chunk.
    /// - Returns: An array of chunks.
    private func chunkByTokens(
        text: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) async throws -> [Chunk] {
        let counter = tokenCounter ?? TokenCounter(model: .simple)

        // Convert token limits to approximate character limits
        let targetCharCount = counter.estimateCharacters(forTokens: chunkSize)
        let overlapCharCount = counter.estimateCharacters(forTokens: chunkOverlap)

        var chunks: [Chunk] = []
        var startIndex = text.startIndex
        var chunkIndex = 0

        while startIndex < text.endIndex {
            // Start with the estimated character count
            var endIndex = text.index(
                startIndex,
                offsetBy: targetCharCount,
                limitedBy: text.endIndex
            ) ?? text.endIndex

            // Refine to stay within token limit
            var chunkContent = String(text[startIndex..<endIndex])
            var tokenCount = counter.count(chunkContent)

            // If over the token limit, reduce the chunk size
            while tokenCount > chunkSize && endIndex > startIndex {
                // Reduce by a character at a time near the boundary
                endIndex = text.index(before: endIndex)
                chunkContent = String(text[startIndex..<endIndex])
                tokenCount = counter.count(chunkContent)
            }

            // If under the token limit and not at end, try to expand
            if tokenCount < chunkSize && endIndex < text.endIndex {
                while tokenCount < chunkSize && endIndex < text.endIndex {
                    let nextEndIndex = text.index(after: endIndex)
                    let testContent = String(text[startIndex..<nextEndIndex])
                    let testTokenCount = counter.count(testContent)

                    if testTokenCount <= chunkSize {
                        endIndex = nextEndIndex
                        chunkContent = testContent
                        tokenCount = testTokenCount
                    } else {
                        break
                    }
                }
            }

            // Ensure we have content
            if chunkContent.isEmpty {
                break
            }

            let startOffset = text.distance(from: text.startIndex, to: startIndex)
            let endOffset = text.distance(from: text.startIndex, to: endIndex)

            // Create chunk with metadata
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

            // Calculate next start position with overlap
            let currentLength = text.distance(from: startIndex, to: endIndex)
            let strideChars = currentLength - overlapCharCount

            // Check if we've processed all text
            if endIndex >= text.endIndex {
                break
            }

            // Ensure we make progress
            let actualStride = max(1, strideChars)
            let nextStartOffset = startOffset + actualStride

            if nextStartOffset >= text.count {
                break
            }

            startIndex = text.index(text.startIndex, offsetBy: nextStartOffset)
            chunkIndex += 1
        }

        return chunks
    }
}

// MARK: - CustomStringConvertible

extension FixedSizeChunker: CustomStringConvertible {
    public var description: String {
        let mode = useTokens ? "tokens" : "characters"
        return "FixedSizeChunker(size: \(chunkSize) \(mode), overlap: \(chunkOverlap))"
    }
}
