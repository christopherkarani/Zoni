// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// BatchEmbedder.swift - Efficient batch embedding with concurrency control

import Foundation

// MARK: - BatchEmbedder

/// Handles efficient batch embedding of large text collections.
///
/// `BatchEmbedder` optimizes embedding operations for large datasets by:
/// - Chunking texts into provider-optimal batch sizes
/// - Processing multiple batches concurrently (with limits)
/// - Maintaining result order despite concurrent processing
/// - Supporting progress tracking and streaming results
///
/// Example usage:
/// ```swift
/// let openai = OpenAIEmbedding(apiKey: "...")
/// let batcher = BatchEmbedder(provider: openai, maxConcurrency: 5)
///
/// // Embed 10,000 texts efficiently
/// let embeddings = try await batcher.embed(largeTextArray)
///
/// // Or stream results as they complete
/// for try await (index, embedding) in batcher.embedStream(largeTextArray) {
///     print("Completed \(index)")
/// }
/// ```
///
/// ## Concurrency Control
/// The `maxConcurrency` parameter limits how many batches are processed
/// simultaneously, balancing throughput against resource usage and rate limits.
public actor BatchEmbedder {

    // MARK: - Properties

    /// The underlying embedding provider.
    private let provider: any EmbeddingProvider

    /// The batch size for chunking texts.
    private let batchSize: Int

    /// Maximum number of concurrent batch requests.
    private let maxConcurrency: Int

    // MARK: - Initialization

    /// Creates a batch embedder for a provider.
    ///
    /// - Parameters:
    ///   - provider: The embedding provider to use.
    ///   - batchSize: Texts per batch. Defaults to provider's `optimalBatchSize`.
    ///   - maxConcurrency: Maximum concurrent batches. Defaults to 3.
    public init(
        provider: any EmbeddingProvider,
        batchSize: Int? = nil,
        maxConcurrency: Int = 3
    ) {
        self.provider = provider
        self.batchSize = batchSize ?? provider.optimalBatchSize
        self.maxConcurrency = max(1, maxConcurrency)
    }

    // MARK: - Batch Embedding

    /// Embeds a large collection of texts efficiently.
    ///
    /// Texts are chunked into batches and processed concurrently,
    /// respecting the `maxConcurrency` limit. Results are returned
    /// in the same order as input texts.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: Embeddings in the same order as input texts.
    /// - Throws: `ZoniError.embeddingFailed` if any batch fails.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }

        // Chunk into batches
        let batches = texts.chunked(into: batchSize)

        // Process with bounded concurrency
        return try await withThrowingTaskGroup(of: (Int, [Embedding]).self) { group in
            var results: [(Int, [Embedding])] = []
            results.reserveCapacity(batches.count)

            var batchIterator = batches.enumerated().makeIterator()
            var inFlight = 0

            // Start initial concurrent tasks
            while inFlight < maxConcurrency, let (index, batch) = batchIterator.next() {
                group.addTask(priority: .high) {
                    let embeddings = try await self.provider.embed(batch)
                    return (index, embeddings)
                }
                inFlight += 1
            }

            // Process results and schedule new tasks
            while let result = try await group.next() {
                results.append(result)
                inFlight -= 1

                // Schedule next batch if available
                if let (index, batch) = batchIterator.next() {
                    group.addTask(priority: .high) {
                        let embeddings = try await self.provider.embed(batch)
                        return (index, embeddings)
                    }
                    inFlight += 1
                }
            }

            // Sort by batch index and flatten
            return results
                .sorted { $0.0 < $1.0 }
                .flatMap { $0.1 }
        }
    }

    /// Embeds texts with progress callback.
    ///
    /// - Parameters:
    ///   - texts: The texts to embed.
    ///   - progress: Called after each batch completes with (completed, total) counts.
    /// - Returns: Embeddings in the same order as input texts.
    public func embed(
        _ texts: [String],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }

        let batches = texts.chunked(into: batchSize)
        let totalBatches = batches.count
        var completedBatches = 0

        return try await withThrowingTaskGroup(of: (Int, [Embedding]).self) { group in
            var results: [(Int, [Embedding])] = []
            results.reserveCapacity(batches.count)

            var batchIterator = batches.enumerated().makeIterator()
            var inFlight = 0

            while inFlight < maxConcurrency, let (index, batch) = batchIterator.next() {
                group.addTask(priority: .high) {
                    let embeddings = try await self.provider.embed(batch)
                    return (index, embeddings)
                }
                inFlight += 1
            }

            while let result = try await group.next() {
                results.append(result)
                inFlight -= 1
                completedBatches += 1
                progress(completedBatches, totalBatches)

                if let (index, batch) = batchIterator.next() {
                    group.addTask(priority: .high) {
                        let embeddings = try await self.provider.embed(batch)
                        return (index, embeddings)
                    }
                    inFlight += 1
                }
            }

            return results
                .sorted { $0.0 < $1.0 }
                .flatMap { $0.1 }
        }
    }

    // MARK: - Streaming

    /// Streams embeddings as they complete.
    ///
    /// Unlike `embed(_:)`, results may arrive out of order as batches
    /// complete at different times. Each result includes its original
    /// index for reordering if needed.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An async stream of (index, embedding) tuples.
    public func embedStream(
        _ texts: [String]
    ) -> AsyncThrowingStream<(index: Int, embedding: Embedding), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let batches = texts.chunked(into: batchSize)
                    var globalIndexOffset = 0

                    for batch in batches {
                        let embeddings = try await provider.embed(batch)

                        for (localIndex, embedding) in embeddings.enumerated() {
                            continuation.yield((
                                index: globalIndexOffset + localIndex,
                                embedding: embedding
                            ))
                        }

                        globalIndexOffset += batch.count
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Streams embeddings with concurrent batch processing.
    ///
    /// Batches are processed concurrently (respecting `maxConcurrency`),
    /// with results yielded as soon as they complete. Results include
    /// their original index for client-side reordering.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An async stream of (index, embedding) tuples.
    public func embedStreamConcurrent(
        _ texts: [String]
    ) -> AsyncThrowingStream<(index: Int, embedding: Embedding), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let batches = texts.chunked(into: batchSize)

                    try await withThrowingTaskGroup(of: [(Int, Embedding)].self) { group in
                        var batchIterator = batches.enumerated().makeIterator()
                        var inFlight = 0
                        var indexOffset = 0
                        var offsets: [Int: Int] = [:]  // batch index -> global offset

                        // Track offsets for each batch
                        for (batchIndex, batch) in batches.enumerated() {
                            offsets[batchIndex] = indexOffset
                            indexOffset += batch.count
                        }

                        // Start initial tasks
                        while inFlight < maxConcurrency, let (batchIndex, batch) = batchIterator.next() {
                            guard let offset = offsets[batchIndex] else {
                                continuation.finish(throwing: ZoniError.embeddingFailed(
                                    reason: "Batch offset not found for index \(batchIndex)"
                                ))
                                return
                            }
                            group.addTask(priority: .high) {
                                let embeddings = try await self.provider.embed(batch)
                                return embeddings.enumerated().map { (offset + $0.offset, $0.element) }
                            }
                            inFlight += 1
                        }

                        // Process and yield results
                        while let batchResults = try await group.next() {
                            for (index, embedding) in batchResults {
                                continuation.yield((index: index, embedding: embedding))
                            }
                            inFlight -= 1

                            if let (batchIndex, batch) = batchIterator.next() {
                                guard let offset = offsets[batchIndex] else {
                                    continuation.finish(throwing: ZoniError.embeddingFailed(
                                        reason: "Batch offset not found for index \(batchIndex)"
                                    ))
                                    return
                                }
                                group.addTask(priority: .high) {
                                    let embeddings = try await self.provider.embed(batch)
                                    return embeddings.enumerated().map { (offset + $0.offset, $0.element) }
                                }
                                inFlight += 1
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Statistics

    /// Calculates the number of batches for a given text count.
    ///
    /// - Parameter textCount: The number of texts to embed.
    /// - Returns: The number of batches that will be created.
    public func batchCount(for textCount: Int) -> Int {
        guard textCount > 0 else { return 0 }
        return (textCount + batchSize - 1) / batchSize
    }

    /// The configured batch size.
    public var configuredBatchSize: Int { batchSize }

    /// The configured maximum concurrency.
    public var configuredMaxConcurrency: Int { maxConcurrency }
}

// MARK: - Array Chunking Extension

extension Array {
    /// Splits the array into chunks of the specified size.
    ///
    /// - Parameter size: The maximum size of each chunk.
    /// - Returns: An array of chunks.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
