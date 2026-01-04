// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// PerformanceTests.swift - Performance and load testing for vector stores
//
// These tests measure performance characteristics across different dataset sizes.
// Run with: swift test --filter PerformanceTests

import Testing
import Foundation
@testable import Zoni

// MARK: - Test Helpers

private func makeChunk(
    id: String,
    content: String,
    documentId: String = "perf-test-doc",
    index: Int = 0
) -> Chunk {
    Chunk(
        id: id,
        content: content,
        metadata: ChunkMetadata(
            documentId: documentId,
            index: index,
            startOffset: 0,
            endOffset: content.count,
            source: nil,
            custom: [:]
        )
    )
}

private func makeEmbedding(dimensions: Int = 1536, seed: Int = 0) -> Embedding {
    // Generate deterministic embeddings for consistent testing
    var vector = [Float](repeating: 0.0, count: dimensions)
    for i in 0..<dimensions {
        vector[i] = Float(sin(Double(i + seed) * 0.1))
    }
    // Normalize to unit length
    let magnitude = sqrt(vector.reduce(0.0) { $0 + $1 * $1 })
    return Embedding(vector: vector.map { $0 / magnitude }, model: "test")
}

/// Generate a batch of test data
private func generateTestData(count: Int, dimensions: Int = 1536) -> ([Chunk], [Embedding]) {
    var chunks: [Chunk] = []
    var embeddings: [Embedding] = []

    for i in 0..<count {
        chunks.append(makeChunk(
            id: "perf-chunk-\(i)",
            content: "Performance test content \(i)",
            documentId: "perf-doc-\(i / 100)",
            index: i % 100
        ))
        embeddings.append(makeEmbedding(dimensions: dimensions, seed: i))
    }

    return (chunks, embeddings)
}

// MARK: - InMemoryVectorStore Performance Tests

@Suite("InMemoryVectorStore Performance Tests", .tags(.performance))
struct InMemoryVectorStorePerformanceTests {

    @Test("Performance: Add 1k chunks")
    func testAdd1kChunks() async throws {
        let store = InMemoryVectorStore()
        let (chunks, embeddings) = generateTestData(count: 1_000)

        let start = Date()
        try await store.add(chunks, embeddings: embeddings)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  Added 1,000 chunks in \(String(format: "%.3f", duration))s (\(String(format: "%.0f", 1000.0/duration)) chunks/s)")

        let count = try await store.count()
        #expect(count == 1_000)
    }

    @Test("Performance: Add 10k chunks")
    func testAdd10kChunks() async throws {
        let store = InMemoryVectorStore()
        let (chunks, embeddings) = generateTestData(count: 10_000)

        let start = Date()
        try await store.add(chunks, embeddings: embeddings)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  Added 10,000 chunks in \(String(format: "%.3f", duration))s (\(String(format: "%.0f", 10000.0/duration)) chunks/s)")

        let count = try await store.count()
        #expect(count == 10_000)
    }

    @Test("Performance: Search with 1k chunks")
    func testSearch1kChunks() async throws {
        let store = InMemoryVectorStore()
        let (chunks, embeddings) = generateTestData(count: 1_000)
        try await store.add(chunks, embeddings: embeddings)

        let queryEmbedding = makeEmbedding(seed: 0)

        let start = Date()
        let results = try await store.search(query: queryEmbedding, limit: 10, filter: nil)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  Searched 1,000 chunks in \(String(format: "%.3f", duration))s")

        #expect(results.count == 10)
        #expect(results[0].chunk.id == "perf-chunk-0")
    }

    @Test("Performance: Search with 10k chunks")
    func testSearch10kChunks() async throws {
        let store = InMemoryVectorStore()
        let (chunks, embeddings) = generateTestData(count: 10_000)
        try await store.add(chunks, embeddings: embeddings)

        let queryEmbedding = makeEmbedding(seed: 0)

        let start = Date()
        let results = try await store.search(query: queryEmbedding, limit: 10, filter: nil)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  Searched 10,000 chunks in \(String(format: "%.3f", duration))s")

        #expect(results.count == 10)
    }

    @Test("Performance: Search with metadata filter on 10k chunks")
    func testSearchWithFilter10kChunks() async throws {
        let store = InMemoryVectorStore()
        let (chunks, embeddings) = generateTestData(count: 10_000)
        try await store.add(chunks, embeddings: embeddings)

        let queryEmbedding = makeEmbedding(seed: 0)
        let filter = MetadataFilter.equals("documentId", "perf-doc-0")

        let start = Date()
        let results = try await store.search(query: queryEmbedding, limit: 10, filter: filter)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  Filtered search on 10,000 chunks in \(String(format: "%.3f", duration))s")

        #expect(results.count == 10)
        #expect(results.allSatisfy { $0.chunk.metadata.documentId == "perf-doc-0" })
    }

    @Test("Performance: Concurrent searches on 5k chunks")
    func testConcurrentSearches() async throws {
        let store = InMemoryVectorStore()
        let (chunks, embeddings) = generateTestData(count: 5_000)
        try await store.add(chunks, embeddings: embeddings)

        let queryEmbedding = makeEmbedding(seed: 0)
        let numConcurrentSearches = 10

        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<numConcurrentSearches {
                group.addTask {
                    let _ = try? await store.search(query: queryEmbedding, limit: 10, filter: nil)
                }
            }
        }
        let duration = Date().timeIntervalSince(start)

        print("⏱️  \(numConcurrentSearches) concurrent searches on 5,000 chunks in \(String(format: "%.3f", duration))s (\(String(format: "%.2f", Double(numConcurrentSearches)/duration)) searches/s)")
    }

    @Test("Performance: Delete by filter on 10k chunks")
    func testDeleteByFilter10kChunks() async throws {
        let store = InMemoryVectorStore()
        let (chunks, embeddings) = generateTestData(count: 10_000)
        try await store.add(chunks, embeddings: embeddings)

        let filter = MetadataFilter.equals("documentId", "perf-doc-0")

        let start = Date()
        try await store.delete(filter: filter)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  Deleted by filter from 10,000 chunks in \(String(format: "%.3f", duration))s")

        let count = try await store.count()
        #expect(count == 9_900) // Should have deleted 100 chunks (perf-doc-0)
    }
}

// MARK: - SQLiteVectorStore Performance Tests

@Suite("SQLiteVectorStore Performance Tests", .tags(.performance))
struct SQLiteVectorStorePerformanceTests {

    @Test("Performance: SQLite add 1k chunks")
    func testSQLiteAdd1kChunks() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-test-\(UUID().uuidString).db")
            .path

        let store = try SQLiteVectorStore(path: tempPath, dimensions: 1536)
        let (chunks, embeddings) = generateTestData(count: 1_000)

        let start = Date()
        try await store.add(chunks, embeddings: embeddings)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  SQLite added 1,000 chunks in \(String(format: "%.3f", duration))s (\(String(format: "%.0f", 1000.0/duration)) chunks/s)")

        let count = try await store.count()
        #expect(count == 1_000)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("Performance: SQLite search 1k chunks")
    func testSQLiteSearch1kChunks() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-test-\(UUID().uuidString).db")
            .path

        let store = try SQLiteVectorStore(path: tempPath, dimensions: 1536)
        let (chunks, embeddings) = generateTestData(count: 1_000)
        try await store.add(chunks, embeddings: embeddings)

        let queryEmbedding = makeEmbedding(seed: 0)

        let start = Date()
        let results = try await store.search(query: queryEmbedding, limit: 10, filter: nil)
        let duration = Date().timeIntervalSince(start)

        print("⏱️  SQLite searched 1,000 chunks in \(String(format: "%.3f", duration))s")

        #expect(results.count == 10)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("Performance: SQLite persistence (save/load)")
    func testSQLitePersistence() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-test-\(UUID().uuidString).db")
            .path

        // Save phase
        do {
            let store = try SQLiteVectorStore(path: tempPath, dimensions: 1536)
            let (chunks, embeddings) = generateTestData(count: 5_000)

            let saveStart = Date()
            try await store.add(chunks, embeddings: embeddings)
            let saveDuration = Date().timeIntervalSince(saveStart)

            print("⏱️  SQLite saved 5,000 chunks in \(String(format: "%.3f", saveDuration))s")
        }

        // Load phase
        do {
            let loadStart = Date()
            let store = try SQLiteVectorStore(path: tempPath, dimensions: 1536)
            let loadDuration = Date().timeIntervalSince(loadStart)

            let count = try await store.count()
            #expect(count == 5_000)

            print("⏱️  SQLite loaded database with 5,000 chunks in \(String(format: "%.3f", loadDuration))s")
        }

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }
}

// MARK: - VectorMath Performance Tests

@Suite("VectorMath Performance Tests", .tags(.performance))
struct VectorMathPerformanceTests {

    @Test("Performance: Cosine similarity 1536-dim vectors")
    func testCosineSimilarityPerformance() {
        let vectorA = makeEmbedding(dimensions: 1536, seed: 1).vector
        let vectorB = makeEmbedding(dimensions: 1536, seed: 2).vector
        let iterations = 10_000

        let start = Date()
        for _ in 0..<iterations {
            _ = VectorMath.cosineSimilarity(vectorA, vectorB)
        }
        let duration = Date().timeIntervalSince(start)

        print("⏱️  \(iterations) cosine similarity computations in \(String(format: "%.3f", duration))s (\(String(format: "%.0f", Double(iterations)/duration)) ops/s)")
    }

    @Test("Performance: Euclidean distance 1536-dim vectors")
    func testEuclideanDistancePerformance() {
        let vectorA = makeEmbedding(dimensions: 1536, seed: 1).vector
        let vectorB = makeEmbedding(dimensions: 1536, seed: 2).vector
        let iterations = 10_000

        let start = Date()
        for _ in 0..<iterations {
            _ = VectorMath.euclideanDistance(vectorA, vectorB)
        }
        let duration = Date().timeIntervalSince(start)

        print("⏱️  \(iterations) Euclidean distance computations in \(String(format: "%.3f", duration))s (\(String(format: "%.0f", Double(iterations)/duration)) ops/s)")
    }

    @Test("Performance: Vector normalization 1536-dim")
    func testNormalizationPerformance() {
        let vector = makeEmbedding(dimensions: 1536, seed: 1).vector
        let iterations = 10_000

        let start = Date()
        for _ in 0..<iterations {
            _ = VectorMath.normalize(vector)
        }
        let duration = Date().timeIntervalSince(start)

        print("⏱️  \(iterations) normalizations in \(String(format: "%.3f", duration))s (\(String(format: "%.0f", Double(iterations)/duration)) ops/s)")
    }
}

// MARK: - Memory Usage Tests

@Suite("Memory Usage Tests", .tags(.performance))
struct MemoryUsageTests {

    @Test("Memory: InMemoryVectorStore with 10k chunks")
    func testInMemoryStoreMemoryUsage() async throws {
        let store = InMemoryVectorStore()

        // Measure baseline memory
        let baselineMemory = getMemoryUsage()

        // Add 10k chunks
        let (chunks, embeddings) = generateTestData(count: 10_000)
        try await store.add(chunks, embeddings: embeddings)

        // Measure memory after adding chunks
        let afterAddMemory = getMemoryUsage()
        let memoryIncreaseMB = Double(afterAddMemory - baselineMemory) / 1024 / 1024

        print("📊 Memory usage increased by ~\(String(format: "%.1f", memoryIncreaseMB)) MB for 10,000 1536-dim embeddings")

        // Expected: ~60 MB (10k * 1536 * 4 bytes ≈ 61 MB for embeddings alone)
        #expect(memoryIncreaseMB > 50.0 && memoryIncreaseMB < 150.0, "Memory usage should be reasonable")
    }

    /// Gets current memory usage in bytes (approximate)
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var performance: Self
}
