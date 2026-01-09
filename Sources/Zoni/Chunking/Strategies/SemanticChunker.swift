// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Semantic chunking strategy that uses embeddings to find natural breakpoints.

import Foundation

// MARK: - SemanticChunker

/// A chunking strategy that uses semantic similarity to find natural breakpoints.
///
/// `SemanticChunker` analyzes the semantic content of text using embeddings
/// to identify where topic shifts occur. It splits text into sentences, computes
/// embeddings for sliding windows of sentences, and identifies breakpoints where
/// the semantic similarity between adjacent windows drops below a threshold.
///
/// This approach produces chunks that are more semantically coherent than
/// fixed-size chunking, improving retrieval quality in RAG systems.
///
/// ## Algorithm
/// 1. Split text into sentences using `TextSplitter.splitSentences()`
/// 2. Create sliding windows of `windowSize` consecutive sentences
/// 3. Compute embeddings for each window using the provided `EmbeddingProvider`
/// 4. Calculate cosine similarity between adjacent window embeddings
/// 5. Identify breakpoints where similarity drops below `similarityThreshold`
/// 6. Group sentences between breakpoints into chunks
/// 7. Merge small chunks to meet `targetChunkSize` when possible
///
/// ## Example Usage
/// ```swift
/// let embedder = OpenAIEmbeddingProvider(apiKey: "...")
/// let chunker = SemanticChunker(
///     embeddingProvider: embedder,
///     targetChunkSize: 1000,
///     similarityThreshold: 0.5,
///     windowSize: 3
/// )
///
/// let document = Document(content: longText)
/// let chunks = try await chunker.chunk(document)
/// ```
///
/// ## Performance Considerations
/// - Semantic chunking requires embedding calls, which may be slow or costly
/// - Larger `windowSize` values provide more context but increase compute cost
/// - Consider caching embeddings when processing similar documents repeatedly
///
/// ## Thread Safety
/// `SemanticChunker` is an actor to ensure safe concurrent access to the
/// embedding provider reference.
public actor SemanticChunker: ChunkingStrategy {

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"semantic"` for identification in configurations and logging.
    public nonisolated let name = "semantic"

    /// The embedding provider used to generate vector representations.
    private let embeddingProvider: any EmbeddingProvider

    /// The calculator used for vector math (e.g. Metal-accelerated).
    private let similarityCalculator: SimilarityCalculator?

    /// The target size for each chunk in characters.
    ///
    /// Chunks may be smaller or larger than this target depending on
    /// where semantic breakpoints occur. Small chunks are merged together
    /// to approach this target.
    public let targetChunkSize: Int

    /// The similarity threshold for detecting semantic breakpoints.
    ///
    /// When the cosine similarity between adjacent sentence windows falls
    /// below this threshold, a breakpoint is created. Values typically
    /// range from 0.3 to 0.7, with lower values creating fewer, larger chunks.
    public let similarityThreshold: Float

    /// The number of sentences in each sliding window for embedding.
    ///
    /// Larger windows provide more context for similarity comparison but
    /// require more computation. A value of 3-5 is typical.
    public let windowSize: Int

    // MARK: - Initialization

    /// Creates a new semantic chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - embeddingProvider: The provider used to generate embeddings for text windows.
    ///   - targetChunkSize: The target size for each chunk in characters. Defaults to 1000.
    ///   - similarityThreshold: The threshold below which a breakpoint is created. Defaults to 0.5.
    ///   - windowSize: The number of sentences in each sliding window. Defaults to 3.
    public init(
        embeddingProvider: any EmbeddingProvider,
        targetChunkSize: Int = 1000,
        similarityThreshold: Float = 0.5,
        windowSize: Int = 3,
        similarityCalculator: SimilarityCalculator? = nil
    ) {
        self.embeddingProvider = embeddingProvider
        self.targetChunkSize = max(1, targetChunkSize)
        self.similarityThreshold = max(0.0, min(1.0, similarityThreshold))
        self.windowSize = max(1, windowSize)
        self.similarityCalculator = similarityCalculator
    }

    // MARK: - Public Methods

    /// Chunks a document into semantically coherent segments.
    ///
    /// Extracts the content from the document and creates chunks with metadata
    /// linking back to the source document. Semantic breakpoints are detected
    /// using embedding similarity between sliding windows of sentences.
    ///
    /// - Parameter document: The document to chunk.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/emptyDocument`` if the document content is empty.
    /// - Throws: ``ZoniError/embeddingFailed(reason:)`` if embedding generation fails.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = SemanticChunker(embeddingProvider: embedder)
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

    /// Chunks raw text into semantically coherent segments with optional metadata.
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
    /// - Throws: ``ZoniError/embeddingFailed(reason:)`` if embedding generation fails.
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

        // Handle edge cases
        guard !sentences.isEmpty else {
            throw ZoniError.emptyDocument
        }

        // If we have fewer sentences than window size, return as single chunk
        if sentences.count <= windowSize {
            let chunkMetadata = ChunkMetadata(
                documentId: baseDocumentId,
                index: 0,
                startOffset: 0,
                endOffset: trimmedText.count,
                source: baseSource,
                custom: baseCustom
            )
            return [Chunk(content: trimmedText, metadata: chunkMetadata)]
        }

        // Find semantic breakpoints
        let breakpoints = try await findSemanticBreakpoints(sentences: sentences)

        // Create chunks based on breakpoints
        let chunks = createChunksFromBreakpoints(
            sentences: sentences,
            breakpoints: breakpoints,
            originalText: trimmedText,
            documentId: baseDocumentId,
            source: baseSource,
            custom: baseCustom
        )

        return chunks
    }

    // MARK: - Private Methods

    /// Finds semantic breakpoints in the sentence list.
    ///
    /// - Parameter sentences: The sentences to analyze.
    /// - Returns: An array of sentence indices where breakpoints should occur.
    /// - Throws: ``ZoniError/embeddingFailed(reason:)`` if embedding generation fails.
    private func findSemanticBreakpoints(sentences: [String]) async throws -> [Int] {
        // Create sliding windows of sentences
        let windows = createSlidingWindows(sentences: sentences)

        guard windows.count >= 2 else {
            return []
        }

        // Generate embeddings for all windows in batch
        let windowTexts = windows.map { $0.joined(separator: " ") }
        let embeddings: [Embedding]

        do {
            embeddings = try await embeddingProvider.embed(windowTexts)
        } catch {
            throw ZoniError.embeddingFailed(reason: "Failed to generate embeddings: \(error.localizedDescription)")
        }

        // Calculate similarity between adjacent windows
        var breakpoints: [Int] = []
        let similarities: [Float]

        if let calculator = similarityCalculator, !embeddings.isEmpty {
            let flatVectors = embeddings.flatMap { $0.vector }
            let dimensions = embeddings[0].dimensions
            similarities = try await calculator.adjacentCosineSimilarity(vectors: flatVectors, dimensions: dimensions)
        } else {
            // CPU Fallback
            var computed: [Float] = []
            computed.reserveCapacity(embeddings.count - 1)
            for i in 0..<(embeddings.count - 1) {
                let score = cosineSimilarity(embeddings[i].vector, embeddings[i + 1].vector)
                computed.append(score)
            }
            similarities = computed
        }

        // Identify breakpoints from similarities
        for (i, similarity) in similarities.enumerated() {
            // If similarity drops below threshold, mark as breakpoint
            if similarity < similarityThreshold {
                // The breakpoint occurs after sentence at index (i + windowSize - 1)
                // This is the center of the current window pair logic
                let breakpointIndex = i + windowSize / 2
                if breakpointIndex > 0 && breakpointIndex < sentences.count - 1 {
                    breakpoints.append(breakpointIndex)
                }
            }
        }

        return breakpoints
    }

    /// Creates sliding windows of sentences for embedding.
    ///
    /// - Parameter sentences: The sentences to create windows from.
    /// - Returns: An array of sentence arrays, each representing a window.
    private func createSlidingWindows(sentences: [String]) -> [[String]] {
        guard sentences.count >= windowSize else {
            return [sentences]
        }

        var windows: [[String]] = []

        for i in 0...(sentences.count - windowSize) {
            let window = Array(sentences[i..<(i + windowSize)])
            windows.append(window)
        }

        return windows
    }

    /// Creates chunks based on the identified breakpoints.
    ///
    /// - Parameters:
    ///   - sentences: The original sentences.
    ///   - breakpoints: The indices where chunks should be split.
    ///   - originalText: The original text for offset calculation.
    ///   - documentId: The document ID for metadata.
    ///   - source: The source for metadata.
    ///   - custom: Custom metadata attributes.
    /// - Returns: An array of chunks.
    private func createChunksFromBreakpoints(
        sentences: [String],
        breakpoints: [Int],
        originalText: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var currentSentenceStart = 0
        var chunkIndex = 0

        // Sort breakpoints to ensure proper ordering
        let sortedBreakpoints = breakpoints.sorted()

        // Add final sentence index as implicit breakpoint
        var allBreakpoints = sortedBreakpoints
        allBreakpoints.append(sentences.count)

        for breakpoint in allBreakpoints {
            // Collect sentences for this chunk
            let chunkSentences = Array(sentences[currentSentenceStart..<breakpoint])

            guard !chunkSentences.isEmpty else {
                currentSentenceStart = breakpoint
                continue
            }

            let chunkContent = chunkSentences.joined(separator: " ")

            // Calculate offsets in original text
            let (startOffset, endOffset) = calculateOffsets(
                chunkContent: chunkContent,
                originalText: originalText,
                searchStart: chunks.last?.metadata.endOffset ?? 0
            )

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: chunkIndex,
                startOffset: startOffset,
                endOffset: endOffset,
                source: source,
                custom: custom
            )

            chunks.append(Chunk(content: chunkContent, metadata: chunkMetadata))

            currentSentenceStart = breakpoint
            chunkIndex += 1
        }

        // Merge small chunks if needed
        return mergeSmallChunks(chunks, documentId: documentId, source: source, custom: custom)
    }

    /// Calculates the start and end offsets for a chunk within the original text.
    ///
    /// - Parameters:
    ///   - chunkContent: The content of the chunk.
    ///   - originalText: The original text.
    ///   - searchStart: The offset to start searching from.
    /// - Returns: A tuple containing the start and end offsets.
    private func calculateOffsets(
        chunkContent: String,
        originalText: String,
        searchStart: Int
    ) -> (Int, Int) {
        // Find the first sentence of the chunk in the original text
        let firstSentence = chunkContent.split(separator: ".").first.map { String($0) } ?? chunkContent
        let searchRange = originalText.index(originalText.startIndex, offsetBy: min(searchStart, originalText.count))..<originalText.endIndex

        if let range = originalText.range(of: firstSentence.prefix(50), range: searchRange) {
            let startOffset = originalText.distance(from: originalText.startIndex, to: range.lowerBound)
            let endOffset = startOffset + chunkContent.count
            return (startOffset, min(endOffset, originalText.count))
        }

        // Fallback to sequential offsets
        let endOffset = searchStart + chunkContent.count
        return (searchStart, min(endOffset, originalText.count))
    }

    /// Merges chunks that are smaller than the target size.
    ///
    /// - Parameters:
    ///   - chunks: The chunks to potentially merge.
    ///   - documentId: The document ID for metadata.
    ///   - source: The source for metadata.
    ///   - custom: Custom metadata attributes.
    /// - Returns: An array of merged chunks.
    private func mergeSmallChunks(
        _ chunks: [Chunk],
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        guard !chunks.isEmpty else { return [] }

        var mergedChunks: [Chunk] = []
        var accumulator = ""
        var accumulatorStartOffset = 0
        var currentIndex = 0

        for chunk in chunks {
            if accumulator.isEmpty {
                accumulator = chunk.content
                accumulatorStartOffset = chunk.metadata.startOffset
            } else {
                accumulator = accumulator + " " + chunk.content
            }

            // Check if accumulated content meets target size
            if accumulator.count >= targetChunkSize {
                let metadata = ChunkMetadata(
                    documentId: documentId,
                    index: currentIndex,
                    startOffset: accumulatorStartOffset,
                    endOffset: accumulatorStartOffset + accumulator.count,
                    source: source,
                    custom: custom
                )
                mergedChunks.append(Chunk(content: accumulator, metadata: metadata))
                accumulator = ""
                currentIndex += 1
            }
        }

        // Handle remaining accumulated content
        if !accumulator.isEmpty {
            if mergedChunks.isEmpty {
                // If no chunks met the target, add what we have
                let metadata = ChunkMetadata(
                    documentId: documentId,
                    index: currentIndex,
                    startOffset: accumulatorStartOffset,
                    endOffset: accumulatorStartOffset + accumulator.count,
                    source: source,
                    custom: custom
                )
                mergedChunks.append(Chunk(content: accumulator, metadata: metadata))
            } else {
                // Merge with the last chunk
                let last = mergedChunks.removeLast()
                let mergedContent = last.content + " " + accumulator
                let metadata = ChunkMetadata(
                    documentId: documentId,
                    index: last.metadata.index,
                    startOffset: last.metadata.startOffset,
                    endOffset: last.metadata.startOffset + mergedContent.count,
                    source: source,
                    custom: custom
                )
                mergedChunks.append(Chunk(content: mergedContent, metadata: metadata))
            }
        }

        return mergedChunks
    }

    /// Computes the cosine similarity between two vectors.
    ///
    /// - Parameters:
    ///   - a: The first vector.
    ///   - b: The second vector.
    /// - Returns: The cosine similarity value in the range [-1, 1].
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else {
            return 0.0
        }

        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        let magnitudeProduct = magnitudeA.squareRoot() * magnitudeB.squareRoot()

        guard magnitudeProduct > 0 else {
            return 0.0
        }

        return dotProduct / magnitudeProduct
    }
}

// MARK: - CustomStringConvertible

extension SemanticChunker: CustomStringConvertible {
    public nonisolated var description: String {
        "SemanticChunker(targetSize: \(targetChunkSize), threshold: \(similarityThreshold), windowSize: \(windowSize), accelerated: \(similarityCalculator != nil))"
    }
}
