import Foundation
import Testing
import ZoniCore
@testable import ZoniSQLite

private func makeChunk(id: String, content: String, index: Int = 0) -> Chunk {
    Chunk(
        id: id,
        content: content,
        metadata: ChunkMetadata(
            documentId: "doc-1",
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

@Suite("SQLiteVectorStore Tests")
struct SQLiteVectorStoreTests {
    @Test("stores chunks and searchable embeddings")
    func storesChunksAndSearchableEmbeddings() async throws {
        let store = try SQLiteVectorStore(path: ":memory:", dimensions: 3)

        try await store.add(
            [
                makeChunk(id: "a", content: "refund policy", index: 0),
                makeChunk(id: "b", content: "shipping policy", index: 1),
            ],
            embeddings: [
                makeEmbedding([1, 0, 0]),
                makeEmbedding([0, 1, 0]),
            ]
        )

        #expect(try await store.count() == 2)

        let results = try await store.search(
            query: makeEmbedding([0.95, 0.05, 0]),
            limit: 1,
            filter: nil
        )

        #expect(results.count == 1)
        #expect(results.first?.chunk.id == "a")
    }

    @Test("upserts chunks with the same identifier")
    func upsertsChunksWithTheSameIdentifier() async throws {
        let store = try SQLiteVectorStore(path: ":memory:", dimensions: 3)

        try await store.add(
            [makeChunk(id: "same-id", content: "old content")],
            embeddings: [makeEmbedding([1, 0, 0])]
        )
        try await store.add(
            [makeChunk(id: "same-id", content: "new content")],
            embeddings: [makeEmbedding([0, 1, 0])]
        )

        #expect(try await store.count() == 1)

        let results = try await store.search(
            query: makeEmbedding([0, 1, 0]),
            limit: 1,
            filter: nil
        )
        #expect(results.first?.chunk.content == "new content")
    }
}
