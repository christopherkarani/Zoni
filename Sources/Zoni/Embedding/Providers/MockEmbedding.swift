// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MockEmbedding.swift - Mock embedding provider for testing

import Foundation

// MARK: - MockEmbedding

/// A mock embedding provider for testing without API calls.
///
/// `MockEmbedding` generates deterministic embeddings based on text content,
/// making it ideal for unit testing and development without external API costs.
///
/// Features:
/// - **Deterministic output**: Same text always produces same embedding
/// - **Call recording**: Track all texts that were embedded
/// - **Configurable responses**: Set specific embeddings for specific texts
/// - **Failure simulation**: Test error handling paths
/// - **Latency simulation**: Test timeout and performance scenarios
///
/// Example usage:
/// ```swift
/// let mock = MockEmbedding(dimensions: 384)
///
/// // Generate embedding
/// let embedding = try await mock.embed("Hello world")
///
/// // Same text produces same embedding
/// let embedding2 = try await mock.embed("Hello world")
/// assert(embedding == embedding2)
///
/// // Check what was embedded
/// let recorded = await mock.getRecordedTexts()
/// assert(recorded == ["Hello world", "Hello world"])
/// ```
public actor MockEmbedding: EmbeddingProvider {

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "mock"

    /// The number of dimensions in generated embeddings.
    public nonisolated let dimensions: Int

    /// Maximum tokens per request (high limit for testing).
    public nonisolated var maxTokensPerRequest: Int { 1000 }

    // MARK: - Internal State

    /// All texts that have been embedded, in order.
    private var recordedTexts: [String] = []

    /// Custom embeddings to return for specific texts.
    private var mockEmbeddings: [String: [Float]] = [:]

    /// Total number of embed calls made.
    private var callCount: Int = 0

    /// Whether the next embed call should fail.
    private var shouldFail: Bool = false

    /// Optional failure message.
    private var failureMessage: String = "Mock failure"

    /// Artificial latency to add to each call.
    private var latency: Duration?

    // MARK: - Initialization

    /// Creates a mock embedding provider with the specified dimensions.
    ///
    /// - Parameter dimensions: The number of dimensions for generated embeddings.
    ///   Defaults to 1536 (matching OpenAI's text-embedding-3-small).
    public init(dimensions: Int = 1536) {
        self.dimensions = dimensions
    }

    // MARK: - EmbeddingProvider Methods

    /// Generates an embedding for a single text.
    ///
    /// The embedding is deterministically generated from the text's hash,
    /// ensuring reproducible results for testing.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: A deterministic embedding based on the text content.
    /// - Throws: `ZoniError.embeddingFailed` if configured to fail.
    public func embed(_ text: String) async throws -> Embedding {
        // Apply artificial latency if configured
        if let latency = latency {
            try await Task.sleep(for: latency)
        }

        // Simulate failure if configured
        if shouldFail {
            throw ZoniError.embeddingFailed(reason: failureMessage)
        }

        // Record the text
        recordedTexts.append(text)
        callCount += 1

        // Return custom mock if configured
        if let customVector = mockEmbeddings[text] {
            return Embedding(vector: customVector, model: "mock")
        }

        // Generate deterministic embedding
        return Embedding(vector: generateDeterministic(text), model: "mock")
    }

    /// Generates embeddings for multiple texts.
    ///
    /// Each text is processed independently using the single-text embed method.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of embeddings in the same order as input texts.
    /// - Throws: `ZoniError.embeddingFailed` if configured to fail.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        var embeddings: [Embedding] = []
        embeddings.reserveCapacity(texts.count)

        for text in texts {
            let embedding = try await embed(text)
            embeddings.append(embedding)
        }

        return embeddings
    }

    // MARK: - Configuration Methods

    /// Sets specific embeddings to return for specific texts.
    ///
    /// When `embed(_:)` is called with a text that has a custom embedding,
    /// that embedding will be returned instead of the deterministic one.
    ///
    /// - Parameter embeddings: A dictionary mapping texts to their embeddings.
    public func setMockEmbeddings(_ embeddings: [String: [Float]]) {
        self.mockEmbeddings = embeddings
    }

    /// Adds a custom embedding for a specific text.
    ///
    /// - Parameters:
    ///   - vector: The embedding vector to return.
    ///   - text: The text to match.
    public func setMockEmbedding(_ vector: [Float], for text: String) {
        self.mockEmbeddings[text] = vector
    }

    /// Configures whether the next embed calls should fail.
    ///
    /// - Parameters:
    ///   - shouldFail: Whether to fail on embed calls.
    ///   - message: Optional custom error message.
    public func setFailure(_ shouldFail: Bool, message: String = "Mock failure") {
        self.shouldFail = shouldFail
        self.failureMessage = message
    }

    /// Sets artificial latency for each embed call.
    ///
    /// Useful for testing timeout handling and performance scenarios.
    ///
    /// - Parameter latency: The duration to wait before returning. Pass `nil` to disable.
    public func setLatency(_ latency: Duration?) {
        self.latency = latency
    }

    // MARK: - Inspection Methods

    /// Returns all texts that have been embedded.
    ///
    /// - Returns: An array of texts in the order they were embedded.
    public func getRecordedTexts() -> [String] {
        recordedTexts
    }

    /// Returns the total number of embed calls made.
    ///
    /// This counts individual texts, not batch calls.
    ///
    /// - Returns: The total call count.
    public func getCallCount() -> Int {
        callCount
    }

    /// Checks if a specific text was embedded.
    ///
    /// - Parameter text: The text to check for.
    /// - Returns: `true` if the text was embedded at least once.
    public func wasEmbedded(_ text: String) -> Bool {
        recordedTexts.contains(text)
    }

    /// Returns the number of times a specific text was embedded.
    ///
    /// - Parameter text: The text to count.
    /// - Returns: The number of times the text was embedded.
    public func embedCount(for text: String) -> Int {
        recordedTexts.filter { $0 == text }.count
    }

    /// Resets all state to initial values.
    ///
    /// Clears recorded texts, call count, failure configuration, and latency.
    /// Does not clear custom mock embeddings.
    public func reset() {
        recordedTexts = []
        callCount = 0
        shouldFail = false
        failureMessage = "Mock failure"
        latency = nil
    }

    /// Completely resets all state including mock embeddings.
    public func resetAll() {
        reset()
        mockEmbeddings = [:]
    }

    // MARK: - Private Methods

    /// Generates a deterministic embedding from text using its hash.
    ///
    /// This uses a simple linear congruential generator (LCG) seeded
    /// with the text's hash to produce reproducible "random" values.
    ///
    /// - Parameter text: The text to generate an embedding for.
    /// - Returns: An array of floats in the range [-1, 1].
    private func generateDeterministic(_ text: String) -> [Float] {
        // Create a seed from the text hash
        var hasher = Hasher()
        hasher.combine(text)
        let hashValue = hasher.finalize()
        let seed = UInt64(bitPattern: Int64(hashValue))

        // Use LCG for reproducible pseudo-random generation
        var state = seed

        var vector = [Float](repeating: 0, count: dimensions)

        for i in 0..<dimensions {
            // LCG: x(n+1) = (a * x(n) + c) mod m
            // Using parameters from Numerical Recipes
            state = state &* 6364136223846793005 &+ 1442695040888963407

            // Convert to float in range [-1, 1]
            let normalized = Float(state >> 33) / Float(UInt32.max)
            vector[i] = (normalized * 2.0) - 1.0
        }

        return vector
    }
}

// MARK: - Convenience Extensions

extension MockEmbedding {

    /// Creates a mock provider that returns unit vectors.
    ///
    /// Useful for testing similarity calculations where normalized vectors
    /// are expected.
    ///
    /// - Parameter dimensions: The embedding dimensions.
    /// - Returns: A new mock provider.
    public static func withNormalizedOutput(dimensions: Int = 1536) -> MockEmbedding {
        MockEmbedding(dimensions: dimensions)
    }

    /// Creates a mock provider with pre-configured similar text pairs.
    ///
    /// Sets up embeddings such that the specified pairs have high cosine similarity.
    ///
    /// - Parameters:
    ///   - similarPairs: Pairs of texts that should have high similarity.
    ///   - dimensions: The embedding dimensions.
    /// - Returns: A configured mock provider.
    public static func withSimilarPairs(
        _ similarPairs: [(String, String)],
        dimensions: Int = 1536
    ) async -> MockEmbedding {
        let mock = MockEmbedding(dimensions: dimensions)

        for (text1, text2) in similarPairs {
            // Use the same vector for both texts in a pair
            let baseEmbedding = try? await mock.embed(text1)
            if let vector = baseEmbedding?.vector {
                await mock.setMockEmbedding(vector, for: text2)
            }
        }

        await mock.reset() // Clear the recorded texts from setup
        return mock
    }
}
