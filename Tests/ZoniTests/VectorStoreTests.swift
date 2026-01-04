// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// VectorStoreTests.swift - Tests for InMemoryVectorStore

import Testing
import Foundation
@testable import Zoni

// MARK: - Test Helpers

private func makeChunk(
    id: String,
    content: String,
    documentId: String = "doc-1",
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

private func makeEmbedding(_ values: [Float]) -> Embedding {
    Embedding(vector: values, model: "test")
}

// MARK: - InMemoryVectorStore Tests

@Suite("InMemoryVectorStore Tests")
struct InMemoryVectorStoreTests {

    // MARK: - Add Operations

    @Test("Add stores chunks and embeddings")
    func testAddStoresChunksAndEmbeddings() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        let count = try await store.count()
        #expect(count == 2)
    }

    @Test("Add throws on count mismatch")
    func testAddThrowsOnCountMismatch() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
        ]

        await #expect(throws: ZoniError.self) {
            try await store.add(chunks, embeddings: embeddings)
        }
    }

    @Test("Add upserts by same ID")
    func testAddUpsertsBySameId() async throws {
        let store = InMemoryVectorStore()

        // Add initial chunk
        let chunk1 = makeChunk(id: "same-id", content: "Original content")
        let embedding1 = makeEmbedding([1.0, 0.0, 0.0])
        try await store.add([chunk1], embeddings: [embedding1])

        // Add another chunk with the same ID
        let chunk2 = makeChunk(id: "same-id", content: "Updated content")
        let embedding2 = makeEmbedding([0.0, 1.0, 0.0])
        try await store.add([chunk2], embeddings: [embedding2])

        // Verify count is still 1
        let count = try await store.count()
        #expect(count == 1)

        // Verify the content was updated by searching
        let query = makeEmbedding([0.0, 1.0, 0.0])
        let results = try await store.search(query: query, limit: 1, filter: nil)
        #expect(results.count == 1)
        #expect(results[0].chunk.content == "Updated content")
    }

    // MARK: - Search Operations

    @Test("Search returns results sorted by similarity")
    func testSearchReturnsSortedBySimilarity() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
            makeChunk(id: "3", content: "Test"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),   // chunk 1
            makeEmbedding([0.0, 1.0, 0.0]),   // chunk 2
            makeEmbedding([0.5, 0.5, 0.0]),   // chunk 3
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Query closer to chunk 1
        let query = makeEmbedding([0.9, 0.1, 0.0])
        let results = try await store.search(query: query, limit: 3, filter: nil)

        #expect(results.count == 3)
        #expect(results[0].chunk.id == "1")  // Most similar to query
    }

    @Test("Search respects limit")
    func testSearchRespectsLimit() async throws {
        let store = InMemoryVectorStore()

        let chunks = (0..<5).map { makeChunk(id: "\($0)", content: "Chunk \($0)") }
        let embeddings = (0..<5).map { i in
            makeEmbedding([Float(i) / 5.0, Float(5 - i) / 5.0, 0.0])
        }

        try await store.add(chunks, embeddings: embeddings)

        let query = makeEmbedding([0.5, 0.5, 0.0])
        let results = try await store.search(query: query, limit: 2, filter: nil)

        #expect(results.count == 2)
    }

    @Test("Search with filter excludes non-matching")
    func testSearchWithFilterExcludesNonMatching() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "Doc A chunk", documentId: "doc-a"),
            makeChunk(id: "2", content: "Doc B chunk", documentId: "doc-b"),
            makeChunk(id: "3", content: "Doc A another chunk", documentId: "doc-a"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
            makeEmbedding([0.5, 0.5, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Filter by documentId
        let filter = MetadataFilter.equals("documentId", "doc-a")
        let query = makeEmbedding([0.5, 0.5, 0.0])
        let results = try await store.search(query: query, limit: 10, filter: filter)

        #expect(results.count == 2)
        for result in results {
            #expect(result.chunk.metadata.documentId == "doc-a")
        }
    }

    @Test("Search returns empty when store is empty")
    func testSearchReturnsEmptyWhenStoreEmpty() async throws {
        let store = InMemoryVectorStore()

        let query = makeEmbedding([1.0, 0.0, 0.0])
        let results = try await store.search(query: query, limit: 10, filter: nil)

        #expect(results.isEmpty)
    }

    @Test("Search handles dimension mismatch")
    func testSearchHandlesDimensionMismatch() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),  // 3 dimensions
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Query with different dimensions (5 instead of 3)
        let query = makeEmbedding([1.0, 0.0, 0.0, 0.0, 0.0])
        let results = try await store.search(query: query, limit: 10, filter: nil)

        // Should still return results (with low/zero scores due to dimension mismatch)
        #expect(results.count == 1)
        #expect(results[0].score == 0.0)  // cosineSimilarity returns 0 for dimension mismatch
    }

    // MARK: - Delete Operations

    @Test("Delete by IDs removes chunks")
    func testDeleteByIdsRemovesChunks() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "One"),
            makeChunk(id: "2", content: "Two"),
            makeChunk(id: "3", content: "Three"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
            makeEmbedding([0.0, 0.0, 1.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Delete one chunk
        try await store.delete(ids: ["2"])

        let count = try await store.count()
        #expect(count == 2)

        // Verify the deleted chunk is not searchable
        let query = makeEmbedding([0.0, 1.0, 0.0])
        let results = try await store.search(query: query, limit: 10, filter: nil)
        let ids = results.map { $0.chunk.id }
        #expect(!ids.contains("2"))
    }

    @Test("Delete by filter removes matching chunks")
    func testDeleteByFilterRemovesMatching() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "Doc A chunk 1", documentId: "doc-a"),
            makeChunk(id: "2", content: "Doc B chunk", documentId: "doc-b"),
            makeChunk(id: "3", content: "Doc A chunk 2", documentId: "doc-a"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
            makeEmbedding([0.0, 0.0, 1.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Delete all chunks from doc-a
        let filter = MetadataFilter.equals("documentId", "doc-a")
        try await store.delete(filter: filter)

        let count = try await store.count()
        #expect(count == 1)

        // Verify only doc-b remains
        let query = makeEmbedding([0.5, 0.5, 0.5])
        let results = try await store.search(query: query, limit: 10, filter: nil)
        #expect(results.count == 1)
        #expect(results[0].chunk.metadata.documentId == "doc-b")
    }

    // MARK: - Count and isEmpty

    @Test("Count returns correct number")
    func testCountReturnsCorrectNumber() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "One"),
            makeChunk(id: "2", content: "Two"),
            makeChunk(id: "3", content: "Three"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
            makeEmbedding([0.0, 0.0, 1.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        let count = try await store.count()
        #expect(count == 3)
    }

    @Test("isEmpty returns true when empty")
    func testIsEmptyReturnsTrueWhenEmpty() async throws {
        let store = InMemoryVectorStore()

        let isEmpty = try await store.isEmpty()
        #expect(isEmpty == true)
    }

    @Test("isEmpty returns false when not empty")
    func testIsEmptyReturnsFalseWhenNotEmpty() async throws {
        let store = InMemoryVectorStore()

        let chunks = [makeChunk(id: "1", content: "Hello")]
        let embeddings = [makeEmbedding([1.0, 0.0, 0.0])]

        try await store.add(chunks, embeddings: embeddings)

        let isEmpty = try await store.isEmpty()
        #expect(isEmpty == false)
    }

    // MARK: - Persistence

    @Test("Save and load restores data")
    func testSaveAndLoad() async throws {
        let store = InMemoryVectorStore()

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Save to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_vector_store_\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try await store.save(to: tempURL)

        // Create a new store and load the data
        let loadedStore = InMemoryVectorStore()
        try await loadedStore.load(from: tempURL)

        // Verify data was restored
        let count = try await loadedStore.count()
        #expect(count == 2)

        // Verify search still works
        let query = makeEmbedding([1.0, 0.0, 0.0])
        let results = try await loadedStore.search(query: query, limit: 1, filter: nil)
        #expect(results.count == 1)
        #expect(results[0].chunk.id == "1")
        #expect(results[0].chunk.content == "Hello")
    }

    // MARK: - Concurrent Access

    @Test("Concurrent adds are safe")
    func testConcurrentAddsAreSafe() async throws {
        let store = InMemoryVectorStore()

        // Add many chunks concurrently
        let chunkCount = 100

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<chunkCount {
                group.addTask {
                    let chunk = makeChunk(id: "chunk-\(i)", content: "Content \(i)")
                    let embedding = makeEmbedding([Float(i) / Float(chunkCount), 0.0, 0.0])
                    try await store.add([chunk], embeddings: [embedding])
                }
            }

            try await group.waitForAll()
        }

        let count = try await store.count()
        #expect(count == chunkCount)
    }
}
