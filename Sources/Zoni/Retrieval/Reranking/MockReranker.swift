// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MockReranker.swift - Mock reranker for testing

import Foundation

// MARK: - MockReranker

/// A mock reranker for testing without external API calls.
///
/// `MockReranker` provides configurable reranking behavior for unit testing
/// and development. It can return specific scores for chunks, record calls,
/// and simulate failures.
///
/// Example usage:
/// ```swift
/// let reranker = MockReranker()
///
/// // Configure mock scores
/// await reranker.setMockScore(0.9, for: "chunk-1")
/// await reranker.setMockScore(0.5, for: "chunk-2")
///
/// // Rerank results
/// let reranked = try await reranker.rerank(query: "test", results: results)
///
/// // Verify calls
/// let calls = await reranker.getRecordedCalls()
/// ```
public actor MockReranker: Reranker {

    // MARK: - Properties

    /// The name of this reranker.
    public nonisolated let name = "mock"

    /// Mock scores to return for specific chunk IDs.
    private var mockScores: [String: Float] = [:]

    /// Recorded rerank calls for test assertions.
    private var recordedCalls: [(query: String, resultCount: Int)] = []

    /// Whether rerank calls should fail.
    private var shouldFail: Bool = false

    /// Custom failure message.
    private var failureMessage: String = "Mock reranker failure"

    // MARK: - Initialization

    /// Creates a new mock reranker.
    public init() {}

    // MARK: - Reranker Protocol

    /// Reranks results using configured mock scores.
    ///
    /// If a chunk has a configured mock score, that score is used.
    /// Otherwise, results are returned with descending scores based on position.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - results: The results to rerank.
    /// - Returns: Results reordered by mock scores.
    /// - Throws: `ZoniError.retrievalFailed` if configured to fail.
    public func rerank(query: String, results: [RetrievalResult]) async throws -> [RetrievalResult] {
        // Record the call
        recordedCalls.append((query: query, resultCount: results.count))

        // Simulate failure if configured
        if shouldFail {
            throw ZoniError.retrievalFailed(reason: failureMessage)
        }

        // Apply mock scores
        var scoredResults = results.map { result -> RetrievalResult in
            let score: Float
            if let mockScore = mockScores[result.id] {
                score = mockScore
            } else {
                // Default: decreasing score based on original position
                let index = results.firstIndex(where: { $0.id == result.id }) ?? 0
                score = 1.0 - Float(index) * 0.1
            }
            return RetrievalResult(chunk: result.chunk, score: score, metadata: result.metadata)
        }

        // Sort by score descending
        scoredResults.sort { $0.score > $1.score }

        return scoredResults
    }

    // MARK: - Configuration Methods

    /// Sets a mock score to return for a specific chunk ID.
    ///
    /// - Parameters:
    ///   - score: The score to return (0.0 to 1.0).
    ///   - chunkId: The chunk ID to match.
    public func setMockScore(_ score: Float, for chunkId: String) {
        mockScores[chunkId] = score
    }

    /// Sets multiple mock scores at once.
    ///
    /// - Parameter scores: Dictionary mapping chunk IDs to scores.
    public func setMockScores(_ scores: [String: Float]) {
        mockScores = scores
    }

    /// Configures whether rerank calls should fail.
    ///
    /// - Parameters:
    ///   - shouldFail: Whether to fail on rerank calls.
    ///   - message: Custom failure message.
    public func setFailure(_ shouldFail: Bool, message: String = "Mock reranker failure") {
        self.shouldFail = shouldFail
        self.failureMessage = message
    }

    // MARK: - Inspection Methods

    /// Returns all recorded rerank calls.
    ///
    /// - Returns: Array of (query, resultCount) tuples.
    public func getRecordedCalls() -> [(query: String, resultCount: Int)] {
        recordedCalls
    }

    /// Returns the total number of rerank calls made.
    public func getCallCount() -> Int {
        recordedCalls.count
    }

    // MARK: - Reset

    /// Resets all state to initial values.
    ///
    /// Clears recorded calls, failure configuration, but preserves mock scores.
    public func reset() {
        recordedCalls = []
        shouldFail = false
        failureMessage = "Mock reranker failure"
    }

    /// Completely resets all state including mock scores.
    public func resetAll() {
        reset()
        mockScores = [:]
    }
}
