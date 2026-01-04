# Zoni Test Suite

This directory contains comprehensive tests for the Zoni RAG framework, including unit tests, integration tests, and performance tests.

## Test Categories

### Unit Tests
Core functionality tests that run quickly without external dependencies.

**Run all unit tests:**
```bash
swift test
```

**Run specific test suites:**
```bash
swift test --filter VectorStoreTests
swift test --filter VectorMathTests
swift test --filter MetadataFilterMatchingTests
```

### Integration Tests
Tests that require actual cloud service credentials. These are disabled by default and must be enabled via environment variables.

**Setup for Qdrant:**
```bash
export QDRANT_URL="https://your-cluster.qdrant.io"
export QDRANT_API_KEY="your-api-key"
export QDRANT_COLLECTION="zoni_integration_test"
```

**Setup for Pinecone:**
```bash
export PINECONE_API_KEY="your-api-key"
export PINECONE_INDEX_HOST="your-index-abc123.svc.us-east1-gcp.pinecone.io"
export PINECONE_NAMESPACE="test"  # optional
```

**Setup for PostgreSQL (pgvector):**
```bash
export PG_CONNECTION_STRING="postgres://user:pass@localhost:5432/testdb"
export PG_TABLE_NAME="zoni_test_chunks"  # optional
```

**Run integration tests:**
```bash
# Run all integration tests (only enabled ones will execute)
swift test --filter IntegrationTests

# Run specific service integration tests
swift test --filter QdrantIntegrationTests
swift test --filter PineconeIntegrationTests
swift test --filter PgVectorIntegrationTests
```

### Performance Tests
Tests that measure performance characteristics across different dataset sizes.

**Run performance tests:**
```bash
swift test --filter PerformanceTests
```

**Run specific performance suites:**
```bash
swift test --filter InMemoryVectorStorePerformanceTests
swift test --filter SQLiteVectorStorePerformanceTests
swift test --filter VectorMathPerformanceTests
```

## Test Organization

```
Tests/ZoniTests/
├── README.md                          # This file
├── ZoniTests.swift                    # End-to-end workflow tests
├── VectorStoreTests.swift             # InMemoryVectorStore unit tests
├── VectorMathTests.swift              # SIMD vector math tests
├── MetadataFilterMatchingTests.swift  # Metadata filtering tests
├── IntegrationTests.swift             # Cloud service integration tests
├── PerformanceTests.swift             # Performance & load tests
├── ChunkingTests.swift                # Text chunking tests
├── LoadingTests.swift                 # Document loading tests
└── EmbeddingProviderTests.swift       # Embedding provider tests
```

## Writing New Tests

### Unit Tests
Use the Swift Testing framework with the `@Test` attribute:

```swift
@Test("Description of what this test does")
func testFeature() async throws {
    // Arrange
    let store = InMemoryVectorStore()

    // Act
    try await store.add(chunks, embeddings: embeddings)

    // Assert
    #expect(await store.count() == 1)
}
```

### Integration Tests
Tag tests with `.integration` and check for required environment variables:

```swift
@Suite("My Integration Tests", .tags(.integration))
struct MyIntegrationTests {
    @Test("Integration test")
    func testIntegration() async throws {
        try #require(shouldRunIntegrationTests(for: "myservice"),
                     "Skipping: MYSERVICE_KEY not set")
        // Test code here
    }
}
```

### Performance Tests
Tag tests with `.performance` and include timing measurements:

```swift
@Suite("My Performance Tests", .tags(.performance))
struct MyPerformanceTests {
    @Test("Performance test")
    func testPerformance() async throws {
        let start = Date()
        // Operation to measure
        let duration = Date().timeIntervalSince(start)
        print("⏱️  Operation took \(duration)s")
    }
}
```

## Continuous Integration

The test suite runs automatically on pull requests. Integration tests are skipped in CI unless credentials are configured as secrets.

To run the full test suite locally including integration tests:

```bash
# Set up all environment variables
source .env.test  # if you have a test environment file

# Run all tests
swift test
```

## Test Coverage

To generate a test coverage report:

```bash
swift test --enable-code-coverage
```

## Troubleshooting

### Integration tests not running
- Ensure environment variables are set correctly
- Verify network connectivity to cloud services
- Check that your API keys have appropriate permissions

### Performance tests slow
- Performance tests intentionally use large datasets
- Run them separately: `swift test --filter PerformanceTests`
- Consider running on a dedicated machine for consistent results

### Memory tests failing
- Memory usage tests are approximate and may vary by platform
- They verify memory is within reasonable bounds, not exact values
- Run on a quiet system for more reliable results

## Best Practices

1. **Keep unit tests fast** - Unit tests should complete in milliseconds
2. **Make integration tests idempotent** - Clean up test data before and after
3. **Use deterministic data** - Use seeds for reproducible test data
4. **Document test requirements** - Note any special setup or credentials needed
5. **Tag appropriately** - Use `.integration` and `.performance` tags correctly
