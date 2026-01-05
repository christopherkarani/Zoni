// ZoniServer - Server-side extensions for Zoni
//
// TenantIsolationTests.swift - Tests for tenant-isolated vector store operations
//
// This file tests the TenantIsolatedVectorStore functionality including:
// - ID prefixing and stripping
// - Metadata injection and removal
// - Tenant filter enforcement
// - Concurrent operations from different tenants

import Testing
import Foundation
@testable import ZoniServer
@testable import Zoni

// MARK: - Tenant Isolation Tests

@Suite("Tenant Isolation Tests")
struct TenantIsolationTests {

    // MARK: - TenantIsolatedVectorStore Tests

    @Suite("TenantIsolatedVectorStore Tests")
    struct TenantIsolatedVectorStoreTests {

        @Test("Isolated store has correct name")
        func testIsolatedStoreName() async {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "test-tenant", tier: .standard)
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            let name = isolated.name
            #expect(name.contains("in_memory") || name.contains("InMemory"))
            #expect(name.contains("test-tenant"))
        }

        @Test("Isolated store adds tenant metadata to chunks")
        func testTenantMetadataInjection() async throws {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "metadata-tenant", tier: .standard)
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            // Create a chunk
            let chunk = Chunk(
                id: "chunk-1",
                content: "Test content",
                metadata: ChunkMetadata(documentId: "doc-1", index: 0)
            )
            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            try await isolated.add([chunk], embeddings: [embedding])

            // Query the base store directly to verify metadata was injected
            let baseResults = try await baseStore.search(
                query: embedding,
                limit: 10,
                filter: nil
            )

            #expect(baseResults.count == 1)

            // Check that tenant metadata was added
            let storedChunk = baseResults[0].chunk
            #expect(storedChunk.metadata.custom[TenantIsolatedVectorStore.tenantMetadataKey] != nil)
            if case .string(let tenantId) = storedChunk.metadata.custom[TenantIsolatedVectorStore.tenantMetadataKey] {
                #expect(tenantId == "metadata-tenant")
            }
        }

        @Test("Isolated store prefixes chunk IDs")
        func testChunkIdPrefixing() async throws {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "prefix-tenant", tier: .standard)
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            let chunk = Chunk(
                id: "original-id",
                content: "Test content",
                metadata: ChunkMetadata(documentId: "doc-1", index: 0)
            )
            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            try await isolated.add([chunk], embeddings: [embedding])

            // Query base store to see prefixed ID
            let baseResults = try await baseStore.search(
                query: embedding,
                limit: 10,
                filter: nil
            )

            #expect(baseResults.count == 1)
            #expect(baseResults[0].chunk.id.hasPrefix("prefix-tenant_"))
            #expect(baseResults[0].chunk.id.contains("original-id"))
        }

        @Test("Isolated store strips prefixes from search results")
        func testPrefixStrippingOnSearch() async throws {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "strip-tenant", tier: .standard)
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            let chunk = Chunk(
                id: "chunk-id",
                content: "Test content",
                metadata: ChunkMetadata(documentId: "doc-1", index: 0)
            )
            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            try await isolated.add([chunk], embeddings: [embedding])

            // Search through isolated store
            let results = try await isolated.search(
                query: embedding,
                limit: 10,
                filter: nil
            )

            #expect(results.count == 1)
            // ID should be restored to original
            #expect(results[0].chunk.id == "chunk-id")
            #expect(!results[0].chunk.id.contains("strip-tenant"))
        }

        @Test("Isolated store removes tenant metadata from results")
        func testMetadataRemovalOnSearch() async throws {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "clean-tenant", tier: .standard)
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            let chunk = Chunk(
                id: "chunk-1",
                content: "Test content",
                metadata: ChunkMetadata(
                    documentId: "doc-1",
                    index: 0,
                    custom: ["userField": .string("userValue")]
                )
            )
            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            try await isolated.add([chunk], embeddings: [embedding])

            let results = try await isolated.search(
                query: embedding,
                limit: 10,
                filter: nil
            )

            #expect(results.count == 1)

            // Tenant metadata should be removed
            #expect(results[0].chunk.metadata.custom[TenantIsolatedVectorStore.tenantMetadataKey] == nil)

            // User metadata should be preserved
            #expect(results[0].chunk.metadata.custom["userField"] != nil)
        }

        @Test("Different tenants see only their own data")
        func testTenantIsolation() async throws {
            let baseStore = InMemoryVectorStore()

            let tenant1 = TenantContext(tenantId: "tenant-1", tier: .standard)
            let tenant2 = TenantContext(tenantId: "tenant-2", tier: .standard)

            let isolated1 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant1)
            let isolated2 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant2)

            // Add data for tenant 1
            let chunk1 = Chunk(
                id: "chunk-t1",
                content: "Tenant 1 content",
                metadata: ChunkMetadata(documentId: "doc-t1", index: 0)
            )
            let embedding1 = Embedding(vector: [1.0, 0.0, 0.0])
            try await isolated1.add([chunk1], embeddings: [embedding1])

            // Add data for tenant 2
            let chunk2 = Chunk(
                id: "chunk-t2",
                content: "Tenant 2 content",
                metadata: ChunkMetadata(documentId: "doc-t2", index: 0)
            )
            let embedding2 = Embedding(vector: [0.0, 1.0, 0.0])
            try await isolated2.add([chunk2], embeddings: [embedding2])

            // Tenant 1 should only see their own data
            let results1 = try await isolated1.search(
                query: Embedding(vector: [0.5, 0.5, 0.0]),
                limit: 10,
                filter: nil
            )
            #expect(results1.count == 1)
            #expect(results1[0].chunk.content == "Tenant 1 content")

            // Tenant 2 should only see their own data
            let results2 = try await isolated2.search(
                query: Embedding(vector: [0.5, 0.5, 0.0]),
                limit: 10,
                filter: nil
            )
            #expect(results2.count == 1)
            #expect(results2[0].chunk.content == "Tenant 2 content")
        }

        @Test("User filter is combined with tenant filter")
        func testCombinedFilters() async throws {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "filter-tenant", tier: .standard)
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            // Add chunks with different categories
            let chunk1 = Chunk(
                id: "chunk-a",
                content: "Category A content",
                metadata: ChunkMetadata(
                    documentId: "doc-1",
                    index: 0,
                    custom: ["category": .string("A")]
                )
            )
            let chunk2 = Chunk(
                id: "chunk-b",
                content: "Category B content",
                metadata: ChunkMetadata(
                    documentId: "doc-2",
                    index: 0,
                    custom: ["category": .string("B")]
                )
            )

            let embedding = Embedding(vector: [0.1, 0.2, 0.3])
            try await isolated.add([chunk1, chunk2], embeddings: [embedding, embedding])

            // Search with category filter
            let results = try await isolated.search(
                query: embedding,
                limit: 10,
                filter: .equals("category", .string("A"))
            )

            #expect(results.count == 1)
            #expect(results[0].chunk.content == "Category A content")
        }

        @Test("Delete by IDs respects tenant isolation")
        func testDeleteByIdsIsolation() async throws {
            let baseStore = InMemoryVectorStore()

            let tenant1 = TenantContext(tenantId: "delete-tenant-1", tier: .standard)
            let tenant2 = TenantContext(tenantId: "delete-tenant-2", tier: .standard)

            let isolated1 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant1)
            let isolated2 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant2)

            // Add same-named chunk for both tenants
            let chunk = Chunk(
                id: "same-id",
                content: "Content",
                metadata: ChunkMetadata(documentId: "doc", index: 0)
            )
            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            try await isolated1.add([chunk], embeddings: [embedding])
            try await isolated2.add([chunk], embeddings: [embedding])

            // Delete from tenant 1
            try await isolated1.delete(ids: ["same-id"])

            // Tenant 1 should have no results
            let results1 = try await isolated1.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results1.isEmpty)

            // Tenant 2 should still have their data
            let results2 = try await isolated2.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results2.count == 1)
        }

        @Test("Delete by filter respects tenant isolation")
        func testDeleteByFilterIsolation() async throws {
            let baseStore = InMemoryVectorStore()

            let tenant1 = TenantContext(tenantId: "filter-del-t1", tier: .standard)
            let tenant2 = TenantContext(tenantId: "filter-del-t2", tier: .standard)

            let isolated1 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant1)
            let isolated2 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant2)

            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            // Add chunks for both tenants with same category
            let chunk1 = Chunk(
                id: "chunk-1",
                content: "T1 Content",
                metadata: ChunkMetadata(
                    documentId: "doc-1",
                    index: 0,
                    custom: ["category": .string("shared")]
                )
            )
            let chunk2 = Chunk(
                id: "chunk-2",
                content: "T2 Content",
                metadata: ChunkMetadata(
                    documentId: "doc-2",
                    index: 0,
                    custom: ["category": .string("shared")]
                )
            )

            try await isolated1.add([chunk1], embeddings: [embedding])
            try await isolated2.add([chunk2], embeddings: [embedding])

            // Delete by filter from tenant 1
            try await isolated1.delete(filter: .equals("category", .string("shared")))

            // Tenant 1 should have no results
            let results1 = try await isolated1.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results1.isEmpty)

            // Tenant 2 should still have their data
            let results2 = try await isolated2.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results2.count == 1)
        }

        @Test("Clear only affects tenant's own data")
        func testClearIsolation() async throws {
            let baseStore = InMemoryVectorStore()

            let tenant1 = TenantContext(tenantId: "clear-tenant-1", tier: .standard)
            let tenant2 = TenantContext(tenantId: "clear-tenant-2", tier: .standard)

            let isolated1 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant1)
            let isolated2 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant2)

            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            // Add data for both tenants
            let chunk1 = Chunk(
                id: "chunk-1",
                content: "T1",
                metadata: ChunkMetadata(documentId: "doc-1", index: 0)
            )
            let chunk2 = Chunk(
                id: "chunk-2",
                content: "T2",
                metadata: ChunkMetadata(documentId: "doc-2", index: 0)
            )

            try await isolated1.add([chunk1], embeddings: [embedding])
            try await isolated2.add([chunk2], embeddings: [embedding])

            // Clear tenant 1
            try await isolated1.clear()

            // Tenant 1 should be empty
            let results1 = try await isolated1.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results1.isEmpty)

            // Tenant 2 should still have data
            let results2 = try await isolated2.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results2.count == 1)
        }

        @Test("Custom index prefix is used for ID prefixing")
        func testCustomIndexPrefix() async throws {
            let baseStore = InMemoryVectorStore()

            var config = TenantConfiguration.forTier(.standard)
            config.indexPrefix = "custom_prefix_"

            let tenant = TenantContext(
                tenantId: "custom-tenant",
                tier: .standard,
                config: config
            )
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            let chunk = Chunk(
                id: "chunk-1",
                content: "Content",
                metadata: ChunkMetadata(documentId: "doc-1", index: 0)
            )
            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            try await isolated.add([chunk], embeddings: [embedding])

            // Check base store for custom prefix
            let baseResults = try await baseStore.search(
                query: embedding,
                limit: 10,
                filter: nil
            )

            #expect(baseResults.count == 1)
            #expect(baseResults[0].chunk.id.hasPrefix("custom_prefix_"))
        }

        @Test("VectorStore extension creates isolated store")
        func testVectorStoreExtension() async {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "ext-tenant", tier: .standard)

            let isolated = baseStore.isolated(for: tenant)

            let name = isolated.name
            #expect(name.contains("ext-tenant"))
        }

        @Test("Description includes tenant info")
        func testDescription() async {
            let baseStore = InMemoryVectorStore()
            let tenant = TenantContext(tenantId: "desc-tenant", tier: .standard)
            let isolated = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)

            let description = isolated.description
            #expect(description.contains("TenantIsolatedVectorStore"))
            #expect(description.contains("desc-tenant"))
        }
    }

    // MARK: - Concurrent Operations Tests

    @Suite("Concurrent Tenant Operations")
    struct ConcurrentTenantOperationsTests {

        @Test("Concurrent adds from different tenants")
        func testConcurrentAdds() async throws {
            let baseStore = InMemoryVectorStore()

            let tenants = (0..<5).map { i in
                TenantContext(tenantId: "concurrent-tenant-\(i)", tier: .standard)
            }

            let isolatedStores = tenants.map { tenant in
                TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)
            }

            // Add chunks concurrently from all tenants
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, isolated) in isolatedStores.enumerated() {
                    group.addTask {
                        let chunk = Chunk(
                            id: "chunk-\(index)",
                            content: "Content from tenant \(index)",
                            metadata: ChunkMetadata(documentId: "doc-\(index)", index: 0)
                        )
                        let embedding = Embedding(vector: [Float(index) / 10.0, 0.5, 0.5])
                        try await isolated.add([chunk], embeddings: [embedding])
                    }
                }

                try await group.waitForAll()
            }

            // Verify each tenant sees only their own data
            for (index, isolated) in isolatedStores.enumerated() {
                let results = try await isolated.search(
                    query: Embedding(vector: [0.5, 0.5, 0.5]),
                    limit: 10,
                    filter: nil
                )

                #expect(results.count == 1)
                #expect(results[0].chunk.content == "Content from tenant \(index)")
            }
        }

        @Test("Concurrent searches from different tenants")
        func testConcurrentSearches() async throws {
            let baseStore = InMemoryVectorStore()

            let tenants = (0..<3).map { i in
                TenantContext(tenantId: "search-tenant-\(i)", tier: .standard)
            }

            let isolatedStores = tenants.map { tenant in
                TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)
            }

            // Add data for each tenant first
            for (index, isolated) in isolatedStores.enumerated() {
                let chunk = Chunk(
                    id: "chunk-\(index)",
                    content: "Content \(index)",
                    metadata: ChunkMetadata(documentId: "doc", index: 0)
                )
                let embedding = Embedding(vector: [0.1, 0.2, 0.3])
                try await isolated.add([chunk], embeddings: [embedding])
            }

            // Search concurrently
            let queryEmbedding = Embedding(vector: [0.1, 0.2, 0.3])

            let results = try await withThrowingTaskGroup(of: (Int, [RetrievalResult]).self) { group in
                for (index, isolated) in isolatedStores.enumerated() {
                    group.addTask {
                        let results = try await isolated.search(
                            query: queryEmbedding,
                            limit: 10,
                            filter: nil
                        )
                        return (index, results)
                    }
                }

                var allResults: [(Int, [RetrievalResult])] = []
                for try await result in group {
                    allResults.append(result)
                }
                return allResults
            }

            // Verify each tenant got their own results
            for (index, tenantResults) in results {
                #expect(tenantResults.count == 1)
                #expect(tenantResults[0].chunk.content == "Content \(index)")
            }
        }

        @Test("Concurrent adds and deletes maintain isolation")
        func testConcurrentAddDelete() async throws {
            let baseStore = InMemoryVectorStore()

            let tenant1 = TenantContext(tenantId: "add-del-tenant-1", tier: .standard)
            let tenant2 = TenantContext(tenantId: "add-del-tenant-2", tier: .standard)

            let isolated1 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant1)
            let isolated2 = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant2)

            let embedding = Embedding(vector: [0.1, 0.2, 0.3])

            // Add initial data
            let chunk1 = Chunk(
                id: "chunk-1",
                content: "T1 Content",
                metadata: ChunkMetadata(documentId: "doc-1", index: 0)
            )
            let chunk2 = Chunk(
                id: "chunk-2",
                content: "T2 Content",
                metadata: ChunkMetadata(documentId: "doc-2", index: 0)
            )

            try await isolated1.add([chunk1], embeddings: [embedding])
            try await isolated2.add([chunk2], embeddings: [embedding])

            // Concurrently: tenant 1 adds new chunk, tenant 2 deletes
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let newChunk = Chunk(
                        id: "chunk-new",
                        content: "New T1 Content",
                        metadata: ChunkMetadata(documentId: "doc-new", index: 0)
                    )
                    try await isolated1.add([newChunk], embeddings: [embedding])
                }

                group.addTask {
                    try await isolated2.delete(ids: ["chunk-2"])
                }

                try await group.waitForAll()
            }

            // Verify tenant 1 has 2 chunks
            let results1 = try await isolated1.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results1.count == 2)

            // Verify tenant 2 has 0 chunks
            let results2 = try await isolated2.search(
                query: embedding,
                limit: 10,
                filter: nil
            )
            #expect(results2.isEmpty)
        }
    }
}
