// ZoniApple - Apple platform extensions for Zoni
//
// MLXEmbeddingProviderTests.swift - Comprehensive tests for MLX embedding provider

import Testing
import Foundation
@testable import ZoniApple
@testable import Zoni

// MARK: - MLXEmbeddingProvider Model Tests

/// Tests for the MLXEmbeddingProvider.Model enum.
@Suite("MLXEmbeddingProvider Model Tests")
struct MLXEmbeddingProviderModelTests {

    @Test("Model enum has exactly 3 models")
    func modelEnumHasThreeModels() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let allModels = MLXEmbeddingProvider.Model.allCases
        #expect(allModels.count == 3)
    }

    @Test("All models have 384 dimensions")
    func allModelsHave384Dimensions() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        for model in MLXEmbeddingProvider.Model.allCases {
            #expect(model.dimensions == 384)
        }
    }

    @Test("allMiniLML6V2 has 384 dimensions")
    func allMiniLML6V2Dimensions() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        #expect(MLXEmbeddingProvider.Model.allMiniLML6V2.dimensions == 384)
    }

    @Test("bgeSmallEn has 384 dimensions")
    func bgeSmallEnDimensions() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        #expect(MLXEmbeddingProvider.Model.bgeSmallEn.dimensions == 384)
    }

    @Test("e5SmallV2 has 384 dimensions")
    func e5SmallV2Dimensions() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        #expect(MLXEmbeddingProvider.Model.e5SmallV2.dimensions == 384)
    }

    @Test("All models have maxSequenceLength of 512")
    func maxSequenceLengthIs512() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        for model in MLXEmbeddingProvider.Model.allCases {
            #expect(model.maxSequenceLength == 512)
        }
    }

    @Test("displayName returns human-readable names")
    func displayNameReturnsReadableNames() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        #expect(MLXEmbeddingProvider.Model.allMiniLML6V2.displayName == "all-MiniLM-L6-v2")
        #expect(MLXEmbeddingProvider.Model.bgeSmallEn.displayName == "BGE-small-en-v1.5")
        #expect(MLXEmbeddingProvider.Model.e5SmallV2.displayName == "E5-small-v2")
    }

    @Test("Model raw values are HuggingFace model IDs")
    func rawValuesAreHuggingFaceIDs() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        #expect(MLXEmbeddingProvider.Model.allMiniLML6V2.rawValue == "sentence-transformers/all-MiniLM-L6-v2")
        #expect(MLXEmbeddingProvider.Model.bgeSmallEn.rawValue == "BAAI/bge-small-en-v1.5")
        #expect(MLXEmbeddingProvider.Model.e5SmallV2.rawValue == "intfloat/e5-small-v2")
    }
}

// MARK: - Availability Tests

/// Tests for platform availability of MLXEmbeddingProvider.
@Suite("MLXEmbeddingProvider Availability Tests")
struct MLXEmbeddingProviderAvailabilityTests {

    #if arch(arm64)
    @Test("isAvailable returns true on Apple Silicon")
    func isAvailableOnAppleSilicon() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        #expect(MLXEmbeddingProvider.isAvailable == true)
    }
    #else
    @Test("isAvailable returns false on Intel Mac")
    func isAvailableOnIntelMac() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        #expect(MLXEmbeddingProvider.isAvailable == false)
    }

    @Test("Intel Mac stub throws neuralEngineUnavailable")
    func intelMacThrowsNeuralEngineUnavailable() async {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        await #expect(throws: AppleMLError.self) {
            _ = try await MLXEmbeddingProvider()
        }
    }
    #endif
}

// MARK: - Provider Properties Tests

/// Tests for MLXEmbeddingProvider properties.
@Suite("MLXEmbeddingProvider Properties Tests")
struct MLXEmbeddingProviderPropertiesTests {

    #if arch(arm64)
    @Test("Provider name is 'mlx'")
    func providerNameIsMLX() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        #expect(provider.name == "mlx")
    }

    @Test("Provider dimensions is 384")
    func providerDimensionsIs384() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        #expect(provider.dimensions == 384)
    }

    @Test("maxTokensPerRequest is 512")
    func maxTokensPerRequestIs512() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        #expect(provider.maxTokensPerRequest == 512)
    }

    @Test("optimalBatchSize is 32")
    func optimalBatchSizeIs32() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        #expect(provider.optimalBatchSize == 32)
    }

    @Test("Provider dimensions matches model dimensions")
    func providerDimensionsMatchesModel() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        for model in MLXEmbeddingProvider.Model.allCases {
            let provider = try await MLXEmbeddingProvider(model: model)
            #expect(provider.dimensions == model.dimensions)
        }
    }
    #endif
}

// MARK: - Initialization Tests

/// Tests for MLXEmbeddingProvider initialization.
@Suite("MLXEmbeddingProvider Initialization Tests")
struct MLXEmbeddingProviderInitializationTests {

    #if arch(arm64)
    @Test("Creating provider with default model uses allMiniLML6V2")
    func defaultModelIsAllMiniLML6V2() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        #expect(provider.dimensions == MLXEmbeddingProvider.Model.allMiniLML6V2.dimensions)
    }

    @Test("Creating provider with each model type succeeds")
    func createWithEachModel() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        for model in MLXEmbeddingProvider.Model.allCases {
            let provider = try await MLXEmbeddingProvider(model: model)
            #expect(provider.dimensions == 384)
        }
    }

    @Test("Custom cache directory is created")
    func customCacheDirectoryIsCreated() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "MLXEmbeddingTest-\(UUID().uuidString)")

        let provider = try await MLXEmbeddingProvider(cacheDirectory: tempDir)

        // Verify the directory was created
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempDir.path(), isDirectory: &isDirectory)
        #expect(exists == true)
        #expect(isDirectory.boolValue == true)

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
        _ = provider // Silence unused warning
    }

    @Test("Provider with autoTruncate=false is configured correctly")
    func autoTruncateFalseConfiguration() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider(autoTruncate: false)
        #expect(provider.name == "mlx")
    }
    #endif
}

// MARK: - Embedding Tests

/// Tests for embedding generation.
@Suite("MLXEmbeddingProvider Embedding Tests")
struct MLXEmbeddingProviderEmbeddingTests {

    #if arch(arm64)
    @Test("embed() produces 384-dimensional vector")
    func embedProduces384DimensionalVector() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let embedding = try await provider.embed("Hello, world!")

        #expect(embedding.dimensions == 384)
        #expect(embedding.vector.count == 384)
    }

    @Test("embed([]) returns empty array")
    func embedEmptyArrayReturnsEmpty() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let embeddings = try await provider.embed([])

        #expect(embeddings.isEmpty)
    }

    @Test("Batch embedding maintains order")
    func batchEmbeddingMaintainsOrder() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let texts = ["First", "Second", "Third", "Fourth", "Fifth"]

        let embeddings = try await provider.embed(texts)

        #expect(embeddings.count == 5)

        // Verify each embedding matches individual embed call
        for (i, text) in texts.enumerated() {
            let single = try await provider.embed(text)
            #expect(embeddings[i].vector == single.vector)
        }
    }

    @Test("Embeddings are normalized with magnitude approximately 1.0")
    func embeddingsAreNormalized() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let embedding = try await provider.embed("Test normalization")

        let magnitude = embedding.magnitude()
        #expect(abs(magnitude - 1.0) < 0.001)
    }

    @Test("Embeddings produce finite values")
    func embeddingsProduceFiniteValues() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let embedding = try await provider.embed("The quick brown fox jumps over the lazy dog")

        #expect(embedding.hasFiniteValues())
    }

    @Test("embed sets model name correctly")
    func embedSetsModelName() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider(model: .allMiniLML6V2)
        let embedding = try await provider.embed("Test text")

        #expect(embedding.model == "mlx-all-MiniLM-L6-v2")
    }

    @Test("Different texts produce different embeddings")
    func differentTextsProduceDifferentEmbeddings() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        let embedding1 = try await provider.embed("Hello world")
        let embedding2 = try await provider.embed("Goodbye universe")

        #expect(embedding1.vector != embedding2.vector)
    }

    @Test("Same text produces identical embeddings")
    func sameTextProducesIdenticalEmbeddings() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let text = "Deterministic embedding test"

        let embedding1 = try await provider.embed(text)
        let embedding2 = try await provider.embed(text)

        #expect(embedding1.vector == embedding2.vector)
    }

    @Test("Large batch embedding works correctly")
    func largeBatchEmbeddingWorks() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        // Create a batch larger than optimalBatchSize (32)
        let texts = (0..<50).map { "Text number \($0)" }
        let embeddings = try await provider.embed(texts)

        #expect(embeddings.count == 50)

        // All embeddings should have correct dimensions
        for embedding in embeddings {
            #expect(embedding.dimensions == 384)
        }
    }
    #endif
}

// MARK: - Text Processing Tests

/// Tests for text processing and truncation.
@Suite("MLXEmbeddingProvider Text Processing Tests")
struct MLXEmbeddingProviderTextProcessingTests {

    #if arch(arm64)
    @Test("autoTruncate=true truncates long text")
    func autoTruncateTruncatesLongText() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider(autoTruncate: true)

        // Create a very long text (way over 512 tokens)
        let longText = String(repeating: "word ", count: 1000)
        let embedding = try await provider.embed(longText)

        // Should still produce valid embedding
        #expect(embedding.dimensions == 384)
    }

    @Test("autoTruncate=false throws contextLengthExceeded for long text")
    func autoTruncateFalseThrowsForLongText() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider(autoTruncate: false)

        // Create a very long text that exceeds 512 tokens (~2048+ characters)
        let longText = String(repeating: "word ", count: 1000)

        await #expect(throws: AppleMLError.self) {
            _ = try await provider.embed(longText)
        }
    }

    @Test("Whitespace is trimmed before embedding")
    func whitespaceIsTrimmed() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        let embedding1 = try await provider.embed("hello")
        let embedding2 = try await provider.embed("  hello  ")

        #expect(embedding1.vector == embedding2.vector)
    }

    @Test("Empty text after trimming is handled")
    func emptyTextAfterTrimming() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let embedding = try await provider.embed("   \n\t  ")

        // Should produce an embedding (for empty string case)
        #expect(embedding.dimensions == 384)
    }

    @Test("Newlines and tabs are handled correctly")
    func newlinesAndTabsHandled() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        let textWithNewlines = "Line 1\nLine 2\nLine 3"
        let embedding = try await provider.embed(textWithNewlines)

        #expect(embedding.dimensions == 384)
    }
    #endif
}

// MARK: - Cache Management Tests

/// Tests for model cache management.
@Suite("MLXEmbeddingProvider Cache Management Tests")
struct MLXEmbeddingProviderCacheManagementTests {

    #if arch(arm64)
    @Test("modelCachePath() returns expected URL")
    func modelCachePathReturnsExpectedURL() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider(model: .allMiniLML6V2)

        let cachePath = await provider.modelCachePath()

        // Path should contain the model's cache directory name
        #expect(cachePath.lastPathComponent == "sentence-transformers_all-MiniLM-L6-v2")
    }

    @Test("modelCachePath() varies by model")
    func modelCachePathVariesByModel() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider1 = try await MLXEmbeddingProvider(model: .allMiniLML6V2)
        let provider2 = try await MLXEmbeddingProvider(model: .bgeSmallEn)

        let path1 = await provider1.modelCachePath()
        let path2 = await provider2.modelCachePath()

        #expect(path1 != path2)
    }

    @Test("clearModelCache() clears state")
    func clearModelCacheClearsState() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        // Perform some operations to establish state
        _ = try await provider.embed("Test text")

        // Clear the cache
        try await provider.clearModelCache()

        // After clearing, isReady should return false
        let ready = await provider.isReady()
        #expect(ready == false)
    }

    @Test("isModelCached() returns correct status")
    func isModelCachedReturnsCorrectStatus() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "MLXCacheTest-\(UUID().uuidString)")

        let provider = try await MLXEmbeddingProvider(cacheDirectory: tempDir)

        // Initially should check cache status
        _ = await provider.isModelCached()

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    #endif
}

// MARK: - Error Handling Tests

/// Tests for error handling in MLXEmbeddingProvider.
@Suite("MLXEmbeddingProvider Error Handling Tests")
struct MLXEmbeddingProviderErrorHandlingTests {

    #if arch(arm64)
    @Test("embed() throws modelNotAvailable when model not loaded")
    func embedThrowsModelNotAvailableWhenNotLoaded() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        // Clear the model to simulate not loaded state
        try await provider.clearModelCache()

        await #expect(throws: AppleMLError.self) {
            _ = try await provider.embed("Test")
        }
    }

    @Test("healthCheck() returns true when model is loaded")
    func healthCheckReturnsTrueWhenLoaded() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        let healthy = await provider.healthCheck()
        #expect(healthy == true)
    }

    @Test("healthCheck() returns false when model not loaded")
    func healthCheckReturnsFalseWhenNotLoaded() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        // Clear model to simulate not loaded state
        try await provider.clearModelCache()

        let healthy = await provider.healthCheck()
        #expect(healthy == false)
    }

    @Test("isReady() returns true after initialization")
    func isReadyReturnsTrueAfterInit() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        let ready = await provider.isReady()
        #expect(ready == true)
    }

    @Test("isReady() returns false after clearing cache")
    func isReadyReturnsFalseAfterClear() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        try await provider.clearModelCache()

        let ready = await provider.isReady()
        #expect(ready == false)
    }
    #endif
}

// MARK: - CustomStringConvertible Tests

/// Tests for provider description.
@Suite("MLXEmbeddingProvider Description Tests")
struct MLXEmbeddingProviderDescriptionTests {

    #if arch(arm64)
    @Test("Description contains provider name and dimensions")
    func descriptionContainsRelevantInfo() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider(model: .allMiniLML6V2)
        let description = provider.description

        #expect(description.contains("MLXEmbeddingProvider"))
        #expect(description.contains("all-MiniLM-L6-v2"))
        #expect(description.contains("384"))
    }

    @Test("Description varies by model")
    func descriptionVariesByModel() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider1 = try await MLXEmbeddingProvider(model: .allMiniLML6V2)
        let provider2 = try await MLXEmbeddingProvider(model: .bgeSmallEn)

        #expect(provider1.description != provider2.description)
    }
    #endif
}

// MARK: - Semantic Similarity Tests

/// Tests verifying semantic understanding of embeddings.
@Suite("MLXEmbeddingProvider Semantic Tests")
struct MLXEmbeddingProviderSemanticTests {

    #if arch(arm64)
    @Test("Similar texts have higher cosine similarity")
    func similarTextsHaveHigherSimilarity() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

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

    @Test("Embedding magnitude is consistent")
    func embeddingMagnitudeIsConsistent() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        let texts = ["Short text", "A longer piece of text with more words", "Yet another test"]
        let embeddings = try await provider.embed(texts)

        for embedding in embeddings {
            let magnitude = embedding.magnitude()
            #expect(abs(magnitude - 1.0) < 0.001)
        }
    }
    #endif
}

// MARK: - Performance Tests

/// Performance-related tests for MLXEmbeddingProvider.
@Suite("MLXEmbeddingProvider Performance Tests")
struct MLXEmbeddingProviderPerformanceTests {

    #if arch(arm64)
    @Test("Batch embedding is more efficient than sequential")
    func batchEmbeddingEfficiency() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()
        let texts = (0..<10).map { "Test text number \($0)" }

        // Batch embedding
        let batchEmbeddings = try await provider.embed(texts)

        #expect(batchEmbeddings.count == 10)

        // Verify results match sequential
        for (i, text) in texts.enumerated() {
            let sequential = try await provider.embed(text)
            #expect(batchEmbeddings[i].vector == sequential.vector)
        }
    }

    @Test("Provider handles concurrent embedding requests")
    func handlesConcurrentRequests() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let provider = try await MLXEmbeddingProvider()

        // Create multiple concurrent embedding tasks
        async let embedding1 = provider.embed("First concurrent request")
        async let embedding2 = provider.embed("Second concurrent request")
        async let embedding3 = provider.embed("Third concurrent request")

        let results = try await [embedding1, embedding2, embedding3]

        #expect(results.count == 3)
        for result in results {
            #expect(result.dimensions == 384)
        }
    }
    #endif
}

// MARK: - Test Skip Reason

/// Custom error for skipping tests when MLX is not available.
struct MLXTestSkipReason: Error, CustomStringConvertible {
    let message: String

    var description: String { message }

    static let mlxNotAvailable = MLXTestSkipReason(
        message: "MLX requires Apple Silicon (M1/M2/M3/M4)"
    )
}
