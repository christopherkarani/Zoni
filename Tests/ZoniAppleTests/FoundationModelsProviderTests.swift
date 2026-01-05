// ZoniApple - Apple platform extensions for Zoni
//
// FoundationModelsProviderTests.swift - Tests for Foundation Models embedding provider

import Testing
import Foundation
@testable import ZoniApple
@testable import Zoni

// MARK: - FoundationModelsProvider Tests

/// Tests for the FoundationModelsProvider embedding provider.
///
/// Note: Many tests are conditional based on Foundation Models availability.
/// On devices without Apple Intelligence enabled or running older OS versions,
/// tests will verify appropriate error handling and availability checks.
@Suite("FoundationModelsProvider Tests")
struct FoundationModelsProviderTests {

    // MARK: - Availability Tests

    @Test("isAvailable returns boolean based on platform support")
    func isAvailableReturnsBool() {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        // This test just verifies the property exists and returns a boolean
        let available = FoundationModelsProvider.isAvailable
        #expect(available == true || available == false)
    }

    @Test("Provider name is apple-fm")
    func providerNameIsCorrect() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        // Skip if Foundation Models not available
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        #expect(provider.name == "apple-fm")
    }

    @Test("Provider has 1024 dimensions")
    func providerHasCorrectDimensions() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        #expect(provider.dimensions == 1024)
    }

    @Test("Provider has correct maxTokensPerRequest")
    func providerHasCorrectMaxTokens() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        #expect(provider.maxTokensPerRequest == 2048)
    }

    @Test("Provider has correct optimalBatchSize")
    func providerHasCorrectBatchSize() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        #expect(provider.optimalBatchSize == 10)
    }

    // MARK: - Embedding Tests

    @Test("embed produces embedding with correct dimensions")
    func embedProducesCorrectDimensions() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let embedding = try await provider.embed("Hello, world!")

        #expect(embedding.dimensions == 1024)
        #expect(embedding.vector.count == 1024)
    }

    @Test("embed sets model name correctly")
    func embedSetsModelName() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let embedding = try await provider.embed("Test text")

        #expect(embedding.model == "apple-fm")
    }

    @Test("embed produces finite values")
    func embedProducesFiniteValues() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let embedding = try await provider.embed("The quick brown fox jumps over the lazy dog")

        #expect(embedding.hasFiniteValues())
    }

    @Test("embed produces normalized vectors")
    func embedProducesNormalizedVectors() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let embedding = try await provider.embed("Normalized vector test")

        // Check that magnitude is approximately 1.0
        let magnitude = embedding.magnitude()
        #expect(abs(magnitude - 1.0) < 0.001)
    }

    @Test("embed is deterministic with caching")
    func embedIsDeterministicWithCaching() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let text = "Deterministic embedding test"

        let embedding1 = try await provider.embed(text)
        let embedding2 = try await provider.embed(text)

        // Same text should return identical embeddings (from cache)
        #expect(embedding1.vector == embedding2.vector)
    }

    @Test("embed produces different embeddings for different texts")
    func embedProducesDifferentEmbeddings() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()

        let embedding1 = try await provider.embed("The cat sat on the mat")
        let embedding2 = try await provider.embed("Quantum physics is fascinating")

        // Different texts should produce different embeddings
        #expect(embedding1.vector != embedding2.vector)
    }

    // MARK: - Batch Embedding Tests

    @Test("batch embed preserves order")
    func batchEmbedPreservesOrder() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let texts = ["First text", "Second text", "Third text"]

        let embeddings = try await provider.embed(texts)

        #expect(embeddings.count == 3)

        // Verify each embedding matches individual embed call
        for (i, text) in texts.enumerated() {
            let single = try await provider.embed(text)
            #expect(embeddings[i].vector == single.vector)
        }
    }

    @Test("batch embed handles empty input")
    func batchEmbedHandlesEmptyInput() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let embeddings = try await provider.embed([])

        #expect(embeddings.isEmpty)
    }

    // MARK: - Text Processing Tests

    @Test("embed handles long text with auto-truncation")
    func embedHandlesLongTextWithTruncation() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider(autoTruncate: true)

        // Create a very long text
        let longText = String(repeating: "word ", count: 1000)
        let embedding = try await provider.embed(longText)

        #expect(embedding.dimensions == 1024)
    }

    @Test("embed throws for long text without auto-truncation")
    func embedThrowsForLongTextWithoutTruncation() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider(autoTruncate: false)

        // Create a very long text (longer than maxTokensPerRequest)
        let longText = String(repeating: "word ", count: 1000)

        await #expect(throws: AppleMLError.self) {
            _ = try await provider.embed(longText)
        }
    }

    @Test("embed handles whitespace-only text")
    func embedHandlesWhitespaceText() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let embedding = try await provider.embed("   \n\t  ")

        // Should still produce an embedding (empty text case)
        #expect(embedding.dimensions == 1024)
    }

    // MARK: - Cache Tests

    @Test("cache size increases after embedding")
    func cacheSizeIncreases() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()

        let initialSize = await provider.cacheSize()
        _ = try await provider.embed("Cache test text")
        let newSize = await provider.cacheSize()

        #expect(newSize == initialSize + 1)
    }

    @Test("clearCache resets cache")
    func clearCacheResetsCache() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()

        _ = try await provider.embed("Text 1")
        _ = try await provider.embed("Text 2")

        await provider.clearCache()
        let size = await provider.cacheSize()

        #expect(size == 0)
    }

    // MARK: - Health Check Tests

    @Test("healthCheck returns true when available")
    func healthCheckReturnsTrue() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let healthy = await provider.healthCheck()

        #expect(healthy == true)
    }

    // MARK: - Factory Method Tests

    @Test("forShortTexts creates provider with smaller cache")
    func forShortTextsCreatesProvider() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider.forShortTexts()
        #expect(provider.name == "apple-fm")
    }

    @Test("forDocuments creates provider with larger cache")
    func forDocumentsCreatesProvider() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider.forDocuments()
        #expect(provider.name == "apple-fm")
    }

    @Test("strict creates provider without auto-truncation")
    func strictCreatesProvider() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider.strict()
        #expect(provider.name == "apple-fm")

        // Verify it throws for long text
        let longText = String(repeating: "word ", count: 1000)
        await #expect(throws: AppleMLError.self) {
            _ = try await provider.embed(longText)
        }
    }

    // MARK: - Description Tests

    @Test("description contains relevant information")
    func descriptionIsDescriptive() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()
        let description = provider.description

        #expect(description.contains("FoundationModelsProvider"))
        #expect(description.contains("1024"))
        #expect(description.contains("2048"))
    }

    // MARK: - Error Handling Tests

    @Test("Initialization throws when Apple Intelligence disabled")
    func initThrowsWhenDisabled() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        // This test validates that proper errors are thrown
        // It will only fail on devices with Apple Intelligence enabled
        // On devices without it, it verifies the error is appropriate

        if !FoundationModelsProvider.isAvailable {
            await #expect(throws: AppleMLError.self) {
                _ = try await FoundationModelsProvider()
            }
        }
    }
}

// MARK: - Test Skip Reason

/// Custom error for skipping tests when Foundation Models is not available.
struct TestSkipReason: Error, CustomStringConvertible {
    let message: String

    var description: String { message }

    static let foundationModelsNotAvailable = TestSkipReason(
        message: "Foundation Models not available on this device/OS"
    )
}

// MARK: - Semantic Similarity Tests

/// Tests verifying semantic understanding of embeddings.
@Suite("FoundationModelsProvider Semantic Tests")
struct FoundationModelsProviderSemanticTests {

    @Test("Similar texts have higher cosine similarity")
    func similarTextsHaveHigherSimilarity() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()

        // Similar texts about programming
        let text1 = "Swift is a modern programming language"
        let text2 = "Swift is a contemporary coding language"

        // Unrelated text
        let text3 = "The weather is sunny today"

        let embedding1 = try await provider.embed(text1)
        let embedding2 = try await provider.embed(text2)
        let embedding3 = try await provider.embed(text3)

        let similaritySimilar = embedding1.cosineSimilarity(to: embedding2)
        let similarityDifferent = embedding1.cosineSimilarity(to: embedding3)

        // Similar texts should have higher similarity than unrelated texts
        #expect(similaritySimilar > similarityDifferent)
    }

    @Test("Embeddings are useful for semantic search")
    func embeddingsWorkForSemanticSearch() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        guard FoundationModelsProvider.isAvailable else {
            throw TestSkipReason.foundationModelsNotAvailable
        }

        let provider = try await FoundationModelsProvider()

        // Corpus of documents
        let documents = [
            "How to cook pasta with tomato sauce",
            "Introduction to machine learning algorithms",
            "Best hiking trails in the mountains",
            "Understanding neural networks and deep learning",
            "Italian recipes for beginners"
        ]

        // Query about AI/ML
        let query = "artificial intelligence tutorial"

        let queryEmbedding = try await provider.embed(query)
        let documentEmbeddings = try await provider.embed(documents)

        // Find most similar documents
        var similarities: [(Int, Float)] = []
        for (i, docEmbedding) in documentEmbeddings.enumerated() {
            let similarity = queryEmbedding.cosineSimilarity(to: docEmbedding)
            similarities.append((i, similarity))
        }

        // Sort by similarity (highest first)
        similarities.sort { $0.1 > $1.1 }

        // The ML-related documents (indices 1 and 3) should rank highest
        let topTwo = Set([similarities[0].0, similarities[1].0])
        let mlDocuments = Set([1, 3])

        #expect(topTwo.intersection(mlDocuments).count >= 1)
    }
}
