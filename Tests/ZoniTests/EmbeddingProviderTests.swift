// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// EmbeddingProviderTests.swift - Comprehensive tests for embedding providers

import Testing
import Foundation
@testable import Zoni

// MARK: - MockEmbedding Tests

@Suite("MockEmbedding Tests")
struct MockEmbeddingTests {

    // MARK: - Basic Functionality

    @Test("MockEmbedding has correct name")
    func mockEmbeddingName() {
        let mock = MockEmbedding()
        #expect(mock.name == "mock")
    }

    @Test("MockEmbedding respects configured dimensions")
    func dimensionsRespected() async throws {
        let mock = MockEmbedding(dimensions: 384)
        let embedding = try await mock.embed("test")

        #expect(embedding.dimensions == 384)
        #expect(embedding.vector.count == 384)
    }

    @Test("MockEmbedding default dimensions are 1536")
    func defaultDimensions() async throws {
        let mock = MockEmbedding()
        let embedding = try await mock.embed("test")

        #expect(embedding.dimensions == 1536)
    }

    @Test("MockEmbedding produces deterministic output")
    func deterministicOutput() async throws {
        let mock = MockEmbedding()

        let embedding1 = try await mock.embed("hello world")
        let embedding2 = try await mock.embed("hello world")

        #expect(embedding1.vector == embedding2.vector)
    }

    @Test("MockEmbedding produces different output for different texts")
    func differentTextsProduceDifferentEmbeddings() async throws {
        let mock = MockEmbedding()

        let embedding1 = try await mock.embed("hello")
        let embedding2 = try await mock.embed("world")

        #expect(embedding1.vector != embedding2.vector)
    }

    @Test("MockEmbedding sets model to 'mock'")
    func modelIsMock() async throws {
        let mock = MockEmbedding()
        let embedding = try await mock.embed("test")

        #expect(embedding.model == "mock")
    }

    // MARK: - Call Recording

    @Test("MockEmbedding records embedded texts")
    func recordsTexts() async throws {
        let mock = MockEmbedding()

        _ = try await mock.embed("text1")
        _ = try await mock.embed("text2")
        _ = try await mock.embed("text3")

        let recorded = await mock.getRecordedTexts()
        #expect(recorded == ["text1", "text2", "text3"])
    }

    @Test("MockEmbedding tracks call count")
    func tracksCallCount() async throws {
        let mock = MockEmbedding()

        _ = try await mock.embed("text1")
        _ = try await mock.embed(["text2", "text3"])

        let count = await mock.getCallCount()
        #expect(count == 3)
    }

    @Test("MockEmbedding wasEmbedded returns correct result")
    func wasEmbeddedWorks() async throws {
        let mock = MockEmbedding()

        _ = try await mock.embed("embedded text")

        #expect(await mock.wasEmbedded("embedded text") == true)
        #expect(await mock.wasEmbedded("not embedded") == false)
    }

    @Test("MockEmbedding embedCount returns correct count")
    func embedCountWorks() async throws {
        let mock = MockEmbedding()

        _ = try await mock.embed("repeated")
        _ = try await mock.embed("repeated")
        _ = try await mock.embed("once")

        #expect(await mock.embedCount(for: "repeated") == 2)
        #expect(await mock.embedCount(for: "once") == 1)
        #expect(await mock.embedCount(for: "never") == 0)
    }

    // MARK: - Custom Embeddings

    @Test("MockEmbedding returns custom embeddings when set")
    func customEmbeddings() async throws {
        let mock = MockEmbedding(dimensions: 3)
        await mock.setMockEmbedding([0.1, 0.2, 0.3], for: "special")

        let embedding = try await mock.embed("special")
        #expect(embedding.vector == [0.1, 0.2, 0.3])

        // Non-special text still gets deterministic embedding
        let other = try await mock.embed("other")
        #expect(other.vector != [0.1, 0.2, 0.3])
    }

    // MARK: - Failure Simulation

    @Test("MockEmbedding can simulate failures")
    func failureSimulation() async throws {
        let mock = MockEmbedding()
        await mock.setFailure(true, message: "Simulated error")

        await #expect(throws: ZoniError.self) {
            _ = try await mock.embed("test")
        }
    }

    // MARK: - Reset

    @Test("MockEmbedding reset clears state")
    func resetClearsState() async throws {
        let mock = MockEmbedding()

        _ = try await mock.embed("text")
        await mock.setFailure(true)

        await mock.reset()

        let recorded = await mock.getRecordedTexts()
        let count = await mock.getCallCount()

        #expect(recorded.isEmpty)
        #expect(count == 0)

        // Should not throw after reset
        _ = try await mock.embed("after reset")
    }

    // MARK: - Batch Embedding

    @Test("MockEmbedding batch embedding preserves order")
    func batchPreservesOrder() async throws {
        let mock = MockEmbedding()
        let texts = ["a", "b", "c", "d", "e"]

        let embeddings = try await mock.embed(texts)

        #expect(embeddings.count == 5)

        // Each text should produce consistent embedding
        for (i, text) in texts.enumerated() {
            let single = try await mock.embed(text)
            #expect(embeddings[i].vector == single.vector)
        }
    }

    @Test("MockEmbedding handles empty batch")
    func emptyBatch() async throws {
        let mock = MockEmbedding()
        let embeddings = try await mock.embed([])

        #expect(embeddings.isEmpty)
    }
}

// MARK: - RateLimiter Tests

@Suite("RateLimiter Tests")
struct RateLimiterTests {

    @Test("RateLimiter allows initial burst")
    func allowsInitialBurst() async throws {
        let limiter = RateLimiter(tokensPerSecond: 10, bucketSize: 5)

        // Should be able to acquire 5 permits immediately
        for _ in 0..<5 {
            #expect(await limiter.tryAcquire(permits: 1) == true)
        }
    }

    @Test("RateLimiter rejects when exhausted")
    func rejectsWhenExhausted() async throws {
        let limiter = RateLimiter(tokensPerSecond: 100, bucketSize: 3)

        // Exhaust the bucket
        _ = await limiter.tryAcquire(permits: 3)

        // Should reject immediately
        #expect(await limiter.tryAcquire(permits: 1) == false)
    }

    @Test("RateLimiter refills over time")
    func refillsOverTime() async throws {
        let limiter = RateLimiter(tokensPerSecond: 100, bucketSize: 10)

        // Exhaust the bucket
        _ = await limiter.tryAcquire(permits: 10)

        // Wait for refill (10ms should add ~1 token at 100/sec)
        try await Task.sleep(for: .milliseconds(50))

        // Should have some tokens now
        #expect(await limiter.tryAcquire(permits: 1) == true)
    }

    @Test("RateLimiter acquire waits for tokens")
    func acquireWaits() async throws {
        let limiter = RateLimiter(tokensPerSecond: 1000, bucketSize: 1)

        // Exhaust the bucket
        try await limiter.acquire(permits: 1)

        let start = Date()
        try await limiter.acquire(permits: 1)
        let elapsed = Date().timeIntervalSince(start)

        // Should have waited approximately 1ms
        #expect(elapsed >= 0.0005)  // At least 0.5ms
    }

    @Test("RateLimiter reset refills bucket")
    func resetRefillsBucket() async throws {
        let limiter = RateLimiter(tokensPerSecond: 10, bucketSize: 5)

        // Exhaust the bucket
        _ = await limiter.tryAcquire(permits: 5)
        #expect(await limiter.tryAcquire(permits: 1) == false)

        // Reset
        await limiter.reset()

        // Should be full again
        #expect(await limiter.tryAcquire(permits: 5) == true)
    }

    @Test("RateLimiter factory methods create correct limiters")
    func factoryMethods() async throws {
        let openai = RateLimiter.forOpenAI()
        let cohere = RateLimiter.forCohere()
        let voyage = RateLimiter.forVoyage()
        let unlimited = RateLimiter.unlimited()

        // Just verify they can be created and used
        #expect(await openai.tryAcquire() == true)
        #expect(await cohere.tryAcquire() == true)
        #expect(await voyage.tryAcquire() == true)
        #expect(await unlimited.tryAcquire() == true)
    }
}

// MARK: - EmbeddingCache Tests

@Suite("EmbeddingCache Tests")
struct EmbeddingCacheTests {

    @Test("Cache hit returns stored embedding")
    func cacheHit() async {
        let cache = EmbeddingCache(maxSize: 100)
        let embedding = Embedding(vector: [1, 2, 3], model: "test")

        await cache.set("test text", embedding: embedding)
        let cached = await cache.get("test text")

        #expect(cached?.vector == embedding.vector)
    }

    @Test("Cache miss returns nil")
    func cacheMiss() async {
        let cache = EmbeddingCache()
        let cached = await cache.get("nonexistent")

        #expect(cached == nil)
    }

    @Test("Cache count tracks entries")
    func countTracksEntries() async {
        let cache = EmbeddingCache()

        await cache.set("a", embedding: Embedding(vector: [1], model: nil))
        await cache.set("b", embedding: Embedding(vector: [2], model: nil))

        #expect(await cache.count == 2)
    }

    @Test("Cache LRU eviction removes oldest")
    func lruEviction() async {
        let cache = EmbeddingCache(maxSize: 2)

        await cache.set("a", embedding: Embedding(vector: [1], model: nil))
        await cache.set("b", embedding: Embedding(vector: [2], model: nil))
        await cache.set("c", embedding: Embedding(vector: [3], model: nil))

        // "a" should be evicted
        #expect(await cache.get("a") == nil)
        #expect(await cache.get("b") != nil)
        #expect(await cache.get("c") != nil)
    }

    @Test("Cache LRU access updates order")
    func lruAccessUpdatesOrder() async {
        let cache = EmbeddingCache(maxSize: 2)

        await cache.set("a", embedding: Embedding(vector: [1], model: nil))
        await cache.set("b", embedding: Embedding(vector: [2], model: nil))

        // Access "a" to make it recently used
        _ = await cache.get("a")

        // Add "c" - should evict "b" (now oldest)
        await cache.set("c", embedding: Embedding(vector: [3], model: nil))

        #expect(await cache.get("a") != nil)
        #expect(await cache.get("b") == nil)
        #expect(await cache.get("c") != nil)
    }

    @Test("Cache TTL expires entries")
    func ttlExpiresEntries() async throws {
        let cache = EmbeddingCache(maxSize: 100, ttl: .milliseconds(50))

        await cache.set("test", embedding: Embedding(vector: [1], model: nil))

        // Should exist initially
        #expect(await cache.get("test") != nil)

        // Wait for expiration
        try await Task.sleep(for: .milliseconds(100))

        // Should be expired
        #expect(await cache.get("test") == nil)
    }

    @Test("Cache hit rate tracks correctly")
    func hitRateTracking() async {
        let cache = EmbeddingCache()

        await cache.set("hit", embedding: Embedding(vector: [1], model: nil))

        // 1 hit
        _ = await cache.get("hit")

        // 1 miss
        _ = await cache.get("miss")

        #expect(await cache.hitRate == 0.5)
    }

    @Test("Cache clear removes all entries")
    func clearRemovesAll() async {
        let cache = EmbeddingCache()

        await cache.set("a", embedding: Embedding(vector: [1], model: nil))
        await cache.set("b", embedding: Embedding(vector: [2], model: nil))

        await cache.clear()

        #expect(await cache.count == 0)
        #expect(await cache.get("a") == nil)
        #expect(await cache.get("b") == nil)
    }

    @Test("Cache batch get returns available entries")
    func batchGet() async {
        let cache = EmbeddingCache()

        await cache.set("a", embedding: Embedding(vector: [1], model: nil))
        await cache.set("b", embedding: Embedding(vector: [2], model: nil))

        let results = await cache.get(["a", "b", "c"])

        #expect(results.count == 2)
        #expect(results["a"] != nil)
        #expect(results["b"] != nil)
        #expect(results["c"] == nil)
    }
}

// MARK: - CachedEmbeddingProvider Tests

@Suite("CachedEmbeddingProvider Tests")
struct CachedEmbeddingProviderTests {

    @Test("CachedEmbeddingProvider caches results")
    func cachesResults() async throws {
        let mock = MockEmbedding()
        let cached = CachedEmbeddingProvider(provider: mock, maxCacheSize: 100)

        // First call hits provider
        _ = try await cached.embed("test")

        // Second call should hit cache
        _ = try await cached.embed("test")

        // Mock should only have been called once
        let callCount = await mock.getCallCount()
        #expect(callCount == 1)
    }

    @Test("CachedEmbeddingProvider batch optimizes uncached")
    func batchOptimizesUncached() async throws {
        let mock = MockEmbedding()
        let cached = CachedEmbeddingProvider(provider: mock, maxCacheSize: 100)

        // Pre-cache one text
        _ = try await cached.embed("cached")
        await mock.reset()

        // Batch with mix of cached and uncached
        let embeddings = try await cached.embed(["cached", "uncached1", "uncached2"])

        #expect(embeddings.count == 3)

        // Only uncached texts should hit provider
        let recorded = await mock.getRecordedTexts()
        #expect(recorded.count == 2)
        #expect(!recorded.contains("cached"))
    }

    @Test("CachedEmbeddingProvider has correct name")
    func hasCorrectName() async {
        let mock = MockEmbedding()
        let cached = CachedEmbeddingProvider(provider: mock)

        #expect(cached.name == "cached_mock")
    }

    @Test("CachedEmbeddingProvider preserves dimensions")
    func preservesDimensions() async {
        let mock = MockEmbedding(dimensions: 512)
        let cached = CachedEmbeddingProvider(provider: mock)

        #expect(cached.dimensions == 512)
    }
}

// MARK: - BatchEmbedder Tests

@Suite("BatchEmbedder Tests")
struct BatchEmbedderTests {

    @Test("BatchEmbedder processes all texts")
    func processesAllTexts() async throws {
        let mock = MockEmbedding()
        let batcher = BatchEmbedder(provider: mock, batchSize: 2, maxConcurrency: 2)

        let texts = ["a", "b", "c", "d", "e"]
        let embeddings = try await batcher.embed(texts)

        #expect(embeddings.count == 5)
    }

    @Test("BatchEmbedder preserves order")
    func preservesOrder() async throws {
        let mock = MockEmbedding()
        let batcher = BatchEmbedder(provider: mock, batchSize: 2, maxConcurrency: 3)

        let texts = ["1", "2", "3", "4", "5", "6", "7"]
        let embeddings = try await batcher.embed(texts)

        // Verify order by re-embedding and comparing
        for (i, text) in texts.enumerated() {
            let single = try await mock.embed(text)
            #expect(embeddings[i].vector == single.vector)
        }
    }

    @Test("BatchEmbedder handles empty input")
    func handlesEmptyInput() async throws {
        let mock = MockEmbedding()
        let batcher = BatchEmbedder(provider: mock)

        let embeddings = try await batcher.embed([])

        #expect(embeddings.isEmpty)
    }

    @Test("BatchEmbedder batchCount calculates correctly")
    func batchCountCalculation() async {
        let mock = MockEmbedding()
        let batcher = BatchEmbedder(provider: mock, batchSize: 3)

        #expect(await batcher.batchCount(for: 0) == 0)
        #expect(await batcher.batchCount(for: 1) == 1)
        #expect(await batcher.batchCount(for: 3) == 1)
        #expect(await batcher.batchCount(for: 4) == 2)
        #expect(await batcher.batchCount(for: 10) == 4)
    }

    @Test("BatchEmbedder reports progress")
    func reportsProgress() async throws {
        let mock = MockEmbedding()
        let batcher = BatchEmbedder(provider: mock, batchSize: 2, maxConcurrency: 1)

        // Use an actor to safely collect progress calls
        actor ProgressCollector {
            var calls: [(Int, Int)] = []
            func add(_ completed: Int, _ total: Int) {
                calls.append((completed, total))
            }
            func getCalls() -> [(Int, Int)] { calls }
        }

        let collector = ProgressCollector()
        let texts = ["a", "b", "c", "d"]
        _ = try await batcher.embed(texts) { completed, total in
            Task { await collector.add(completed, total) }
        }

        // Wait a bit for async progress collection
        try await Task.sleep(for: .milliseconds(50))

        // Should have reported progress for each batch
        let progressCalls = await collector.getCalls()
        #expect(progressCalls.count == 2)
    }

    @Test("BatchEmbedder streaming yields all results")
    func streamingYieldsAllResults() async throws {
        let mock = MockEmbedding()
        let batcher = BatchEmbedder(provider: mock, batchSize: 2)

        let texts = ["a", "b", "c"]
        var received: [Int] = []

        let stream = await batcher.embedStream(texts)
        for try await (index, _) in stream {
            received.append(index)
        }

        #expect(received.sorted() == [0, 1, 2])
    }
}

// MARK: - OpenAI Model Tests

@Suite("OpenAIEmbedding Model Tests")
struct OpenAIModelTests {

    @Test("OpenAI text-embedding-3-small has 1536 dimensions")
    func smallModelDimensions() {
        #expect(OpenAIEmbedding.Model.textEmbedding3Small.dimensions == 1536)
    }

    @Test("OpenAI text-embedding-3-large has 3072 dimensions")
    func largeModelDimensions() {
        #expect(OpenAIEmbedding.Model.textEmbedding3Large.dimensions == 3072)
    }

    @Test("OpenAI text-embedding-ada-002 has 1536 dimensions")
    func adaModelDimensions() {
        #expect(OpenAIEmbedding.Model.textEmbeddingAda002.dimensions == 1536)
    }

    @Test("All OpenAI models have descriptions")
    func allModelsHaveDescriptions() {
        for model in OpenAIEmbedding.Model.allCases {
            #expect(!model.description.isEmpty)
        }
    }
}

// MARK: - Cohere Model Tests

@Suite("CohereEmbedding Model Tests")
struct CohereModelTests {

    @Test("Cohere embed-english-v3 has 1024 dimensions")
    func englishV3Dimensions() {
        #expect(CohereEmbedding.Model.embedEnglishV3.dimensions == 1024)
    }

    @Test("Cohere embed-multilingual-v3 has 1024 dimensions")
    func multilingualV3Dimensions() {
        #expect(CohereEmbedding.Model.embedMultilingualV3.dimensions == 1024)
    }

    @Test("Cohere light models have 384 dimensions")
    func lightModelDimensions() {
        #expect(CohereEmbedding.Model.embedEnglishLightV3.dimensions == 384)
        #expect(CohereEmbedding.Model.embedMultilingualLightV3.dimensions == 384)
    }

    @Test("Multilingual models are marked as multilingual")
    func multilingualFlagCorrect() {
        #expect(CohereEmbedding.Model.embedMultilingualV3.isMultilingual == true)
        #expect(CohereEmbedding.Model.embedEnglishV3.isMultilingual == false)
    }
}

// MARK: - Voyage Model Tests

@Suite("VoyageEmbedding Model Tests")
struct VoyageModelTests {

    @Test("Voyage-3 has 1024 dimensions")
    func voyage3Dimensions() {
        #expect(VoyageEmbedding.Model.voyage3.dimensions == 1024)
    }

    @Test("Voyage-3-lite has 512 dimensions")
    func voyage3LiteDimensions() {
        #expect(VoyageEmbedding.Model.voyage3Lite.dimensions == 512)
    }

    @Test("Domain-specific models are marked correctly")
    func domainSpecificMarking() {
        #expect(VoyageEmbedding.Model.voyageCode2.isDomainSpecific == true)
        #expect(VoyageEmbedding.Model.voyageFinance2.isDomainSpecific == true)
        #expect(VoyageEmbedding.Model.voyageLaw2.isDomainSpecific == true)
        #expect(VoyageEmbedding.Model.voyage3.isDomainSpecific == false)
    }

    @Test("Domain-specific models have correct domain")
    func domainSpecificDomains() {
        #expect(VoyageEmbedding.Model.voyageCode2.domain == "code")
        #expect(VoyageEmbedding.Model.voyageFinance2.domain == "finance")
        #expect(VoyageEmbedding.Model.voyageLaw2.domain == "legal")
        #expect(VoyageEmbedding.Model.voyage3.domain == nil)
    }
}

// MARK: - Ollama Tests

@Suite("OllamaEmbedding Tests")
struct OllamaEmbeddingTests {

    @Test("OllamaEmbedding has correct name")
    func ollamaName() async {
        let ollama = OllamaEmbedding()
        #expect(ollama.name == "ollama")
    }

    @Test("OllamaEmbedding maxTokensPerRequest is 1")
    func maxTokensIsOne() {
        let ollama = OllamaEmbedding()
        #expect(ollama.maxTokensPerRequest == 1)
    }

    @Test("Known models have expected names")
    func knownModelNames() {
        #expect(OllamaEmbedding.KnownModel.nomicEmbedText == "nomic-embed-text")
        #expect(OllamaEmbedding.KnownModel.allMiniLM == "all-minilm")
        #expect(OllamaEmbedding.KnownModel.mxbaiEmbedLarge == "mxbai-embed-large")
    }
}

// MARK: - Array Chunking Tests

@Suite("Array Chunking Tests")
struct ArrayChunkingTests {

    @Test("Chunking creates correct number of chunks")
    func correctNumberOfChunks() {
        let array = [1, 2, 3, 4, 5, 6, 7]

        let chunks2 = array.chunked(into: 2)
        #expect(chunks2.count == 4)

        let chunks3 = array.chunked(into: 3)
        #expect(chunks3.count == 3)
    }

    @Test("Chunking preserves all elements")
    func preservesAllElements() {
        let array = [1, 2, 3, 4, 5]
        let chunks = array.chunked(into: 2)
        let flattened = chunks.flatMap { $0 }

        #expect(flattened == array)
    }

    @Test("Chunking handles exact division")
    func handlesExactDivision() {
        let array = [1, 2, 3, 4, 5, 6]
        let chunks = array.chunked(into: 2)

        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0.count == 2 })
    }

    @Test("Chunking handles size larger than array")
    func handlesSizeLargerThanArray() {
        let array = [1, 2, 3]
        let chunks = array.chunked(into: 10)

        #expect(chunks.count == 1)
        #expect(chunks[0] == array)
    }

    @Test("Chunking handles empty array")
    func handlesEmptyArray() {
        let array: [Int] = []
        let chunks = array.chunked(into: 3)

        #expect(chunks.isEmpty)
    }
}

// MARK: - Duration Extension Tests

@Suite("Duration Extension Tests")
struct DurationExtensionTests {

    @Test("Duration hours creates correct duration")
    func hoursCreation() {
        let duration = Duration.hours(2)
        #expect(duration.timeInterval == 7200.0)
    }

    @Test("Duration minutes creates correct duration")
    func minutesCreation() {
        let duration = Duration.minutes(5)
        #expect(duration.timeInterval == 300.0)
    }

    @Test("Duration timeInterval converts correctly")
    func timeIntervalConversion() {
        let duration = Duration.seconds(45)
        #expect(duration.timeInterval == 45.0)
    }
}
