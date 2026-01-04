// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// IntegrationTests.swift - Integration tests for cloud vector stores
//
// These tests require actual cloud service credentials and are disabled by default.
// To enable them, set the appropriate environment variables:
//
// For Qdrant:
//   - QDRANT_URL: The Qdrant server URL (e.g., "https://your-cluster.qdrant.io")
//   - QDRANT_API_KEY: Your Qdrant API key
//   - QDRANT_COLLECTION: Test collection name (will be created if it doesn't exist)
//
// For Pinecone:
//   - PINECONE_API_KEY: Your Pinecone API key
//   - PINECONE_INDEX_HOST: Your index host URL
//   - PINECONE_NAMESPACE: Test namespace (optional)
//
// For PostgreSQL (pgvector):
//   - PG_CONNECTION_STRING: PostgreSQL connection string (e.g., "postgres://user:pass@localhost:5432/db")
//   - PG_TABLE_NAME: Test table name (optional, defaults to "zoni_test_chunks")

import Testing
import Foundation
@testable import Zoni

#if canImport(ZoniServer)
@testable import ZoniServer
#endif

// MARK: - Test Configuration

/// Helper to check if integration tests should run for a given service
private func shouldRunIntegrationTests(for service: String) -> Bool {
    switch service {
    case "qdrant":
        return ProcessInfo.processInfo.environment["QDRANT_URL"] != nil &&
               ProcessInfo.processInfo.environment["QDRANT_API_KEY"] != nil
    case "pinecone":
        return ProcessInfo.processInfo.environment["PINECONE_API_KEY"] != nil &&
               ProcessInfo.processInfo.environment["PINECONE_INDEX_HOST"] != nil
    case "pgvector":
        return ProcessInfo.processInfo.environment["PG_CONNECTION_STRING"] != nil
    default:
        return false
    }
}

// MARK: - Test Helpers

private func makeChunk(
    id: String,
    content: String,
    documentId: String = "integration-test-doc",
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
            source: "integration-test",
            custom: ["test_type": .string("integration")]
        )
    )
}

private func makeEmbedding(dimensions: Int = 1536, seed: Int = 0) -> Embedding {
    // Generate deterministic but varied embeddings for testing
    var vector = [Float](repeating: 0.0, count: dimensions)
    for i in 0..<dimensions {
        vector[i] = Float(sin(Double(i + seed) * 0.1))
    }
    // Normalize to unit length for cosine similarity
    let magnitude = sqrt(vector.reduce(0.0) { $0 + $1 * $1 })
    return Embedding(vector: vector.map { $0 / magnitude }, model: "test")
}

// MARK: - Qdrant Integration Tests

@Suite("Qdrant Integration Tests", .tags(.integration))
struct QdrantIntegrationTests {

    @Test("Qdrant: Add, search, and delete chunks")
    func testQdrantBasicOperations() async throws {
        try #require(shouldRunIntegrationTests(for: "qdrant"), "Skipping: QDRANT_URL or QDRANT_API_KEY not set")

        let url = ProcessInfo.processInfo.environment["QDRANT_URL"]!
        let apiKey = ProcessInfo.processInfo.environment["QDRANT_API_KEY"]!
        let collectionName = ProcessInfo.processInfo.environment["QDRANT_COLLECTION"] ?? "zoni_integration_test"

        let store = QdrantStore(
            baseURL: URL(string: url)!,
            collectionName: collectionName,
            apiKey: apiKey
        )

        // Ensure collection exists
        try await store.ensureCollection(dimensions: 1536)

        // Clean up any previous test data
        let initialCount = try await store.count()
        if initialCount > 0 {
            let filter = MetadataFilter.equals("source", "integration-test")
            try await store.delete(filter: filter)
        }

        // Add test chunks
        let chunks = [
            makeChunk(id: "qdrant-test-1", content: "Test content 1"),
            makeChunk(id: "qdrant-test-2", content: "Test content 2"),
            makeChunk(id: "qdrant-test-3", content: "Test content 3")
        ]
        let embeddings = [
            makeEmbedding(seed: 1),
            makeEmbedding(seed: 2),
            makeEmbedding(seed: 3)
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Wait a bit for eventual consistency
        try await Task.sleep(for: .seconds(1))

        // Search for similar chunks
        let queryEmbedding = makeEmbedding(seed: 1)
        let results = try await store.search(query: queryEmbedding, limit: 3, filter: nil)

        #expect(results.count > 0, "Should find at least one result")
        #expect(results[0].chunk.id == "qdrant-test-1", "Most similar should be the matching chunk")

        // Test metadata filtering
        let filteredResults = try await store.search(
            query: queryEmbedding,
            limit: 10,
            filter: .equals("source", "integration-test")
        )
        #expect(filteredResults.count == 3, "Should find all test chunks with filter")

        // Clean up
        try await store.delete(ids: chunks.map { $0.id })

        // Verify deletion
        try await Task.sleep(for: .seconds(1))
        let afterDelete = try await store.search(query: queryEmbedding, limit: 10, filter: .equals("source", "integration-test"))
        #expect(afterDelete.isEmpty, "Chunks should be deleted")
    }

    @Test("Qdrant: Network error handling")
    func testQdrantNetworkErrorHandling() async throws {
        try #require(shouldRunIntegrationTests(for: "qdrant"), "Skipping: QDRANT_URL or QDRANT_API_KEY not set")

        // Create store with invalid configuration
        let store = QdrantStore(
            baseURL: URL(string: "https://invalid-qdrant-server-that-does-not-exist.example.com")!,
            collectionName: "test",
            apiKey: "invalid-key"
        )

        let chunk = makeChunk(id: "error-test", content: "Test")
        let embedding = makeEmbedding()

        // Should fail with network/connection error
        do {
            try await store.add([chunk], embeddings: [embedding])
            Issue.record("Expected network error but operation succeeded")
        } catch {
            // Expected - verify it's a reasonable error
            #expect(error is ZoniError)
        }
    }
}

// MARK: - Pinecone Integration Tests

@Suite("Pinecone Integration Tests", .tags(.integration))
struct PineconeIntegrationTests {

    @Test("Pinecone: Add, search, and delete chunks")
    func testPineconeBasicOperations() async throws {
        try #require(shouldRunIntegrationTests(for: "pinecone"), "Skipping: PINECONE_API_KEY or PINECONE_INDEX_HOST not set")

        let apiKey = ProcessInfo.processInfo.environment["PINECONE_API_KEY"]!
        let indexHost = ProcessInfo.processInfo.environment["PINECONE_INDEX_HOST"]!
        let namespace = ProcessInfo.processInfo.environment["PINECONE_NAMESPACE"]

        let store = PineconeStore(
            apiKey: apiKey,
            indexHost: indexHost,
            namespace: namespace
        )

        // Clean up any previous test data
        let initialFilter = MetadataFilter.equals("source", "integration-test")
        try? await store.delete(filter: initialFilter)

        // Add test chunks
        let chunks = [
            makeChunk(id: "pinecone-test-1", content: "Test content 1"),
            makeChunk(id: "pinecone-test-2", content: "Test content 2"),
            makeChunk(id: "pinecone-test-3", content: "Test content 3")
        ]
        let embeddings = [
            makeEmbedding(seed: 1),
            makeEmbedding(seed: 2),
            makeEmbedding(seed: 3)
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Wait for eventual consistency
        try await Task.sleep(for: .seconds(2))

        // Search for similar chunks
        let queryEmbedding = makeEmbedding(seed: 1)
        let results = try await store.search(query: queryEmbedding, limit: 3, filter: nil)

        #expect(results.count > 0, "Should find at least one result")
        #expect(results[0].chunk.id == "pinecone-test-1", "Most similar should be the matching chunk")

        // Test metadata filtering
        let filteredResults = try await store.search(
            query: queryEmbedding,
            limit: 10,
            filter: .equals("source", "integration-test")
        )
        #expect(filteredResults.count == 3, "Should find all test chunks with filter")

        // Clean up
        try await store.delete(ids: chunks.map { $0.id })

        // Verify deletion (with eventual consistency delay)
        try await Task.sleep(for: .seconds(2))
        let afterDelete = try await store.search(query: queryEmbedding, limit: 10, filter: .equals("source", "integration-test"))
        #expect(afterDelete.isEmpty, "Chunks should be deleted")
    }
}

// MARK: - PgVector Integration Tests

#if canImport(ZoniServer)
@Suite("PgVector Integration Tests", .tags(.integration))
struct PgVectorIntegrationTests {

    @Test("PgVector: Add, search, and delete chunks")
    func testPgVectorBasicOperations() async throws {
        try #require(shouldRunIntegrationTests(for: "pgvector"), "Skipping: PG_CONNECTION_STRING not set")

        let connectionString = ProcessInfo.processInfo.environment["PG_CONNECTION_STRING"]!
        let tableName = ProcessInfo.processInfo.environment["PG_TABLE_NAME"] ?? "zoni_test_chunks"

        let config = PgVectorStore.Configuration(
            tableName: tableName,
            dimensions: 1536,
            indexType: .ivfFlat
        )

        let store = try await PgVectorStore.connect(
            connectionString: connectionString,
            configuration: config
        )

        // Clean up any previous test data
        let initialFilter = MetadataFilter.equals("source", "integration-test")
        try? await store.delete(filter: initialFilter)

        // Add test chunks
        let chunks = [
            makeChunk(id: "pg-test-1", content: "Test content 1"),
            makeChunk(id: "pg-test-2", content: "Test content 2"),
            makeChunk(id: "pg-test-3", content: "Test content 3")
        ]
        let embeddings = [
            makeEmbedding(seed: 1),
            makeEmbedding(seed: 2),
            makeEmbedding(seed: 3)
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Search for similar chunks
        let queryEmbedding = makeEmbedding(seed: 1)
        let results = try await store.search(query: queryEmbedding, limit: 3, filter: nil)

        #expect(results.count > 0, "Should find at least one result")
        #expect(results[0].chunk.id == "pg-test-1", "Most similar should be the matching chunk")

        // Test metadata filtering
        let filteredResults = try await store.search(
            query: queryEmbedding,
            limit: 10,
            filter: .equals("source", "integration-test")
        )
        #expect(filteredResults.count == 3, "Should find all test chunks with filter")

        // Test count
        let count = try await store.count()
        #expect(count >= 3, "Should have at least 3 chunks")

        // Clean up
        try await store.delete(ids: chunks.map { $0.id })

        // Verify deletion
        let afterDelete = try await store.search(query: queryEmbedding, limit: 10, filter: .equals("source", "integration-test"))
        #expect(afterDelete.isEmpty, "Chunks should be deleted")

        // Close connection
        try await store.close()
    }
}
#endif

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}
