// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Utility functions for working with chunks in RAG pipelines.

import Foundation

// MARK: - ChunkStatistics

/// Statistics computed from a collection of chunks.
///
/// `ChunkStatistics` provides aggregate metrics about chunk sizes,
/// useful for analyzing and validating chunking strategies.
///
/// Example usage:
/// ```swift
/// let chunks = chunker.chunk(document)
/// let stats = ChunkingUtils.statistics(chunks)
/// print("Average chunk size: \(stats.averageSize) characters")
/// print("Size range: \(stats.minSize) - \(stats.maxSize)")
/// ```
public struct ChunkStatistics: Sendable, Equatable {
    /// The total number of chunks.
    public let count: Int

    /// The sum of all chunk character counts.
    public let totalCharacters: Int

    /// The arithmetic mean of chunk sizes.
    public let averageSize: Double

    /// The smallest chunk size in characters.
    public let minSize: Int

    /// The largest chunk size in characters.
    public let maxSize: Int

    /// The median chunk size in characters.
    ///
    /// For an even number of chunks, this is the average of the two middle values,
    /// rounded down to an integer.
    public let medianSize: Int

    /// Creates a new chunk statistics instance.
    ///
    /// - Parameters:
    ///   - count: The total number of chunks.
    ///   - totalCharacters: The sum of all chunk character counts.
    ///   - averageSize: The arithmetic mean of chunk sizes.
    ///   - minSize: The smallest chunk size.
    ///   - maxSize: The largest chunk size.
    ///   - medianSize: The median chunk size.
    public init(
        count: Int,
        totalCharacters: Int,
        averageSize: Double,
        minSize: Int,
        maxSize: Int,
        medianSize: Int
    ) {
        self.count = count
        self.totalCharacters = totalCharacters
        self.averageSize = averageSize
        self.minSize = minSize
        self.maxSize = maxSize
        self.medianSize = medianSize
    }
}

// MARK: - ChunkValidationError

/// An error indicating that a chunk exceeds the maximum allowed size.
///
/// `ChunkValidationError` provides details about which chunk failed validation
/// and the reason for the failure.
///
/// Example usage:
/// ```swift
/// let errors = ChunkingUtils.validate(chunks, maxSize: 1000)
/// for error in errors {
///     print("Chunk \(error.chunkIndex) is invalid: \(error.reason)")
/// }
/// ```
public struct ChunkValidationError: Sendable, Error, Equatable {
    /// The zero-based index of the chunk that failed validation.
    public let chunkIndex: Int

    /// A human-readable description of why validation failed.
    public let reason: String

    /// Creates a new chunk validation error.
    ///
    /// - Parameters:
    ///   - chunkIndex: The index of the invalid chunk.
    ///   - reason: The reason for the validation failure.
    public init(chunkIndex: Int, reason: String) {
        self.chunkIndex = chunkIndex
        self.reason = reason
    }
}

// MARK: - ChunkingUtils

/// A collection of utilities for working with chunks.
///
/// `ChunkingUtils` provides static methods for computing statistics,
/// validating chunks, and managing overlap between consecutive chunks.
/// All methods are static and the enum has no stored state, making it
/// inherently `Sendable`.
///
/// Example usage:
/// ```swift
/// // Compute statistics
/// let stats = ChunkingUtils.statistics(chunks)
///
/// // Validate chunks against size limits
/// let errors = ChunkingUtils.validate(chunks, maxSize: 1000)
///
/// // Add overlap for better context continuity
/// let overlappedChunks = ChunkingUtils.addOverlap(to: chunks, overlapSize: 50, originalText: text)
/// ```
public enum ChunkingUtils: Sendable {

    // MARK: - Statistics

    /// Computes aggregate statistics for a collection of chunks.
    ///
    /// This method calculates count, total characters, average size,
    /// minimum size, maximum size, and median size across all chunks.
    ///
    /// - Parameter chunks: The chunks to analyze.
    /// - Returns: A `ChunkStatistics` instance with computed metrics.
    ///            Returns all zeros for an empty array.
    ///
    /// ## Examples
    /// ```swift
    /// let chunks = [chunk1, chunk2, chunk3]
    /// let stats = ChunkingUtils.statistics(chunks)
    /// print("Count: \(stats.count)")
    /// print("Total: \(stats.totalCharacters)")
    /// print("Average: \(stats.averageSize)")
    /// ```
    public static func statistics(_ chunks: [Chunk]) -> ChunkStatistics {
        guard !chunks.isEmpty else {
            return ChunkStatistics(
                count: 0,
                totalCharacters: 0,
                averageSize: 0.0,
                minSize: 0,
                maxSize: 0,
                medianSize: 0
            )
        }

        let sizes = chunks.map { $0.content.count }
        let total = sizes.reduce(0, +)
        let average = Double(total) / Double(sizes.count)
        let minSize = sizes.min() ?? 0
        let maxSize = sizes.max() ?? 0
        let medianSize = computeMedian(sizes)

        return ChunkStatistics(
            count: chunks.count,
            totalCharacters: total,
            averageSize: average,
            minSize: minSize,
            maxSize: maxSize,
            medianSize: medianSize
        )
    }

    // MARK: - Validation

    /// Validates that all chunks are within the specified maximum size.
    ///
    /// This method checks each chunk's character count against the maximum
    /// allowed size and returns validation errors for any chunks that exceed it.
    ///
    /// - Parameters:
    ///   - chunks: The chunks to validate.
    ///   - maxSize: The maximum allowed character count per chunk.
    /// - Returns: An array of validation errors for chunks exceeding the limit.
    ///            Returns an empty array if all chunks are valid.
    ///            Errors are returned in chunk order.
    ///
    /// ## Examples
    /// ```swift
    /// let errors = ChunkingUtils.validate(chunks, maxSize: 500)
    /// if errors.isEmpty {
    ///     print("All chunks are valid")
    /// } else {
    ///     for error in errors {
    ///         print("Invalid chunk at index \(error.chunkIndex): \(error.reason)")
    ///     }
    /// }
    /// ```
    public static func validate(_ chunks: [Chunk], maxSize: Int) -> [ChunkValidationError] {
        var errors: [ChunkValidationError] = []

        for (index, chunk) in chunks.enumerated() {
            let characterCount = chunk.content.count
            if characterCount > maxSize {
                let error = ChunkValidationError(
                    chunkIndex: index,
                    reason: "Chunk exceeds maximum size of \(maxSize) characters (actual: \(characterCount))"
                )
                errors.append(error)
            }
        }

        return errors
    }

    // MARK: - Overlap Management

    /// Adds overlapping content from previous chunks to subsequent chunks.
    ///
    /// This method prepends content from the end of the previous chunk to the
    /// beginning of each subsequent chunk. Overlap improves context continuity
    /// across chunk boundaries, which can enhance retrieval quality in RAG systems.
    ///
    /// - Parameters:
    ///   - chunks: The chunks to add overlap to.
    ///   - overlapSize: The number of characters to overlap from the previous chunk.
    ///   - originalText: The original text from which chunks were created.
    /// - Returns: An array of chunks with overlap added. The first chunk is unchanged.
    ///
    /// ## Behavior
    /// - Empty input returns an empty array
    /// - Single chunk is returned unchanged
    /// - Zero overlap size returns chunks unchanged
    /// - Overlap size larger than available content is handled gracefully
    /// - Document IDs and metadata are preserved
    ///
    /// ## Examples
    /// ```swift
    /// let overlapped = ChunkingUtils.addOverlap(
    ///     to: chunks,
    ///     overlapSize: 50,
    ///     originalText: originalDocument
    /// )
    /// ```
    public static func addOverlap(
        to chunks: [Chunk],
        overlapSize: Int,
        originalText: String
    ) -> [Chunk] {
        guard !chunks.isEmpty else { return [] }
        guard chunks.count > 1 else { return chunks }
        guard overlapSize > 0 else { return chunks }

        var result: [Chunk] = []

        // First chunk is unchanged
        result.append(chunks[0])

        // Add overlap to subsequent chunks
        for index in 1..<chunks.count {
            let currentChunk = chunks[index]
            let previousChunk = chunks[index - 1]

            // Get overlap content from the end of the previous chunk
            let previousContent = previousChunk.content
            let overlapLength = min(overlapSize, previousContent.count)
            let overlapStartIndex = previousContent.index(
                previousContent.endIndex,
                offsetBy: -overlapLength
            )
            let overlapContent = String(previousContent[overlapStartIndex...])

            // Create new chunk with overlap prepended
            let newContent = overlapContent + currentChunk.content
            let newChunk = Chunk(
                id: currentChunk.id,
                content: newContent,
                metadata: ChunkMetadata(
                    documentId: currentChunk.metadata.documentId,
                    index: currentChunk.metadata.index,
                    startOffset: max(0, currentChunk.metadata.startOffset - overlapLength),
                    endOffset: currentChunk.metadata.endOffset,
                    source: currentChunk.metadata.source,
                    custom: currentChunk.metadata.custom
                ),
                embedding: currentChunk.embedding
            )

            result.append(newChunk)
        }

        return result
    }

    /// Removes overlapping content from the start of chunks.
    ///
    /// This method detects and removes duplicate content at chunk boundaries
    /// that was added by `addOverlap`. It looks for common content between
    /// the end of one chunk and the start of the next.
    ///
    /// - Parameter chunks: The chunks to remove overlap from.
    /// - Returns: An array of chunks with overlap removed. The first chunk is unchanged.
    ///
    /// ## Behavior
    /// - Empty input returns an empty array
    /// - Single chunk is returned unchanged
    /// - Chunks with no actual overlap are returned unchanged
    /// - Document IDs and metadata are preserved
    ///
    /// ## Examples
    /// ```swift
    /// let cleaned = ChunkingUtils.removeOverlap(overlappedChunks)
    /// ```
    public static func removeOverlap(_ chunks: [Chunk]) -> [Chunk] {
        guard !chunks.isEmpty else { return [] }
        guard chunks.count > 1 else { return chunks }

        var result: [Chunk] = []

        // First chunk is unchanged
        result.append(chunks[0])

        // Remove overlap from subsequent chunks
        for index in 1..<chunks.count {
            let currentChunk = chunks[index]
            let previousChunk = chunks[index - 1]

            // Find overlap by comparing end of previous chunk with start of current chunk
            let overlapLength = findOverlapLength(
                previousContent: previousChunk.content,
                currentContent: currentChunk.content
            )

            if overlapLength > 0 {
                // Remove overlap from current chunk
                let newContent = String(currentChunk.content.dropFirst(overlapLength))
                let newChunk = Chunk(
                    id: currentChunk.id,
                    content: newContent,
                    metadata: ChunkMetadata(
                        documentId: currentChunk.metadata.documentId,
                        index: currentChunk.metadata.index,
                        startOffset: currentChunk.metadata.startOffset + overlapLength,
                        endOffset: currentChunk.metadata.endOffset,
                        source: currentChunk.metadata.source,
                        custom: currentChunk.metadata.custom
                    ),
                    embedding: currentChunk.embedding
                )
                result.append(newChunk)
            } else {
                result.append(currentChunk)
            }
        }

        return result
    }

    // MARK: - Private Methods

    /// Computes the median of an array of integers.
    ///
    /// - Parameter values: The values to compute the median of.
    /// - Returns: The median value. For even counts, returns the average of
    ///            the two middle values rounded down.
    private static func computeMedian(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            // Even number of elements: average of two middle values
            let midIndex = count / 2
            return (sorted[midIndex - 1] + sorted[midIndex]) / 2
        } else {
            // Odd number of elements: middle value
            return sorted[count / 2]
        }
    }

    /// Finds the length of overlapping content between two strings.
    ///
    /// Compares the end of the previous content with the start of the current
    /// content to find the longest matching overlap.
    ///
    /// - Parameters:
    ///   - previousContent: The content of the previous chunk.
    ///   - currentContent: The content of the current chunk.
    /// - Returns: The number of characters that overlap, or 0 if no overlap.
    private static func findOverlapLength(
        previousContent: String,
        currentContent: String
    ) -> Int {
        guard !previousContent.isEmpty, !currentContent.isEmpty else { return 0 }

        // Start with the maximum possible overlap and work down
        let maxOverlap = min(previousContent.count, currentContent.count)

        for length in stride(from: maxOverlap, through: 1, by: -1) {
            // Get the end of the previous chunk
            let prevStartIndex = previousContent.index(
                previousContent.endIndex,
                offsetBy: -length
            )
            let prevSuffix = String(previousContent[prevStartIndex...])

            // Get the start of the current chunk
            let currentEndIndex = currentContent.index(
                currentContent.startIndex,
                offsetBy: length
            )
            let currentPrefix = String(currentContent[..<currentEndIndex])

            if prevSuffix == currentPrefix {
                return length
            }
        }

        return 0
    }
}

// MARK: - CustomStringConvertible

extension ChunkStatistics: CustomStringConvertible {
    public var description: String {
        "ChunkStatistics(count: \(count), total: \(totalCharacters), avg: \(averageSize), min: \(minSize), max: \(maxSize), median: \(medianSize))"
    }
}

extension ChunkValidationError: CustomStringConvertible {
    public var description: String {
        "ChunkValidationError(chunk: \(chunkIndex), reason: \(reason))"
    }
}
