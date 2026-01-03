# Phase 1: Core Foundation — Detailed Plan

## Overview

This phase establishes the foundational architecture for SwiftRAG. All subsequent phases depend on the protocols, types, and pipeline skeleton defined here.

**Duration:** 3-4 days
**Dependencies:** None
**Parallelizable:** No — must complete before any other phase

---

## Objectives

1. Create Swift Package with cross-platform support (Linux + Apple)
2. Define all core protocols
3. Define all shared types
4. Create RAGPipeline orchestrator skeleton
5. Define error types and configuration

---

## Package Structure

```
SwiftRAG/
├── Package.swift
├── Sources/
│   ├── SwiftRAG/
│   │   ├── Core/
│   │   │   ├── Protocols/
│   │   │   │   ├── DocumentLoader.swift
│   │   │   │   ├── ChunkingStrategy.swift
│   │   │   │   ├── EmbeddingProvider.swift
│   │   │   │   ├── VectorStore.swift
│   │   │   │   ├── Retriever.swift
│   │   │   │   └── LLMProvider.swift
│   │   │   ├── Types/
│   │   │   │   ├── Document.swift
│   │   │   │   ├── Chunk.swift
│   │   │   │   ├── Embedding.swift
│   │   │   │   ├── RetrievalResult.swift
│   │   │   │   ├── RAGResponse.swift
│   │   │   │   └── Metadata.swift
│   │   │   ├── Pipeline/
│   │   │   │   ├── RAGPipeline.swift
│   │   │   │   ├── IngestionPipeline.swift
│   │   │   │   └── QueryPipeline.swift
│   │   │   ├── Errors/
│   │   │   │   └── SwiftRAGError.swift
│   │   │   └── Configuration/
│   │   │       └── RAGConfiguration.swift
│   │   └── SwiftRAG.swift (public exports)
│   ├── SwiftRAGServer/
│   │   └── SwiftRAGServer.swift (placeholder)
│   └── SwiftRAGApple/
│       └── SwiftRAGApple.swift (placeholder)
├── Tests/
│   └── SwiftRAGTests/
│       └── CoreTests/
└── README.md
```

---

## Core Protocols

### DocumentLoader.swift

```swift
public protocol DocumentLoader: Sendable {
    /// Supported file extensions (e.g., ["txt", "md"])
    static var supportedExtensions: Set<String> { get }
    
    /// Load a single document from a URL
    func load(from url: URL) async throws -> Document
    
    /// Load a single document from data
    func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document
    
    /// Check if this loader can handle the given URL
    func canLoad(_ url: URL) -> Bool
}

extension DocumentLoader {
    public func canLoad(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
```

### ChunkingStrategy.swift

```swift
public protocol ChunkingStrategy: Sendable {
    /// The name of this chunking strategy
    var name: String { get }
    
    /// Chunk a document into smaller pieces
    func chunk(_ document: Document) async throws -> [Chunk]
    
    /// Chunk raw text with optional metadata
    func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
}
```

### EmbeddingProvider.swift

```swift
public protocol EmbeddingProvider: Sendable {
    /// Provider name (e.g., "openai", "cohere")
    var name: String { get }
    
    /// Embedding dimensions
    var dimensions: Int { get }
    
    /// Maximum tokens per request
    var maxTokensPerRequest: Int { get }
    
    /// Generate embedding for a single text
    func embed(_ text: String) async throws -> Embedding
    
    /// Generate embeddings for multiple texts (batch)
    func embed(_ texts: [String]) async throws -> [Embedding]
}
```

### VectorStore.swift

```swift
public protocol VectorStore: Sendable {
    /// Store name
    var name: String { get }
    
    /// Add chunks with their embeddings
    func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws
    
    /// Search for similar chunks
    func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult]
    
    /// Delete chunks by IDs
    func delete(ids: [String]) async throws
    
    /// Delete all chunks matching a filter
    func delete(filter: MetadataFilter) async throws
    
    /// Get total count of stored chunks
    func count() async throws -> Int
    
    /// Check if the store is empty
    func isEmpty() async throws -> Bool
}

public struct MetadataFilter: Sendable {
    public enum Operator: Sendable {
        case equals(String, String)
        case notEquals(String, String)
        case greaterThan(String, Double)
        case lessThan(String, Double)
        case `in`(String, [String])
        case contains(String, String)
        case and([MetadataFilter])
        case or([MetadataFilter])
    }
    
    public let conditions: [Operator]
    
    public init(_ conditions: Operator...)
    public init(_ conditions: [Operator])
}
```

### Retriever.swift

```swift
public protocol Retriever: Sendable {
    /// Retriever name
    var name: String { get }
    
    /// Retrieve relevant chunks for a query
    func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult]
}
```

### LLMProvider.swift

```swift
public protocol LLMProvider: Sendable {
    /// Provider name
    var name: String { get }
    
    /// Model identifier
    var model: String { get }
    
    /// Maximum context tokens
    var maxContextTokens: Int { get }
    
    /// Generate a response
    func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String
    
    /// Stream a response
    func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error>
}

public struct LLMOptions: Sendable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var stopSequences: [String]?
    
    public init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stopSequences: [String]? = nil
    )
    
    public static let `default` = LLMOptions()
}
```

---

## Core Types

### Document.swift

```swift
public struct Document: Sendable, Identifiable, Codable {
    public let id: String
    public let content: String
    public let metadata: DocumentMetadata
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        content: String,
        metadata: DocumentMetadata = DocumentMetadata()
    )
    
    public var wordCount: Int { get }
    public var characterCount: Int { get }
}

public struct DocumentMetadata: Sendable, Codable {
    public var source: String?
    public var title: String?
    public var author: String?
    public var url: URL?
    public var mimeType: String?
    public var custom: [String: MetadataValue]
    
    public init(
        source: String? = nil,
        title: String? = nil,
        author: String? = nil,
        url: URL? = nil,
        mimeType: String? = nil,
        custom: [String: MetadataValue] = [:]
    )
    
    public subscript(key: String) -> MetadataValue? {
        get { custom[key] }
        set { custom[key] = newValue }
    }
}
```

### Chunk.swift

```swift
public struct Chunk: Sendable, Identifiable, Codable {
    public let id: String
    public let content: String
    public let metadata: ChunkMetadata
    public let embedding: Embedding?
    
    public init(
        id: String = UUID().uuidString,
        content: String,
        metadata: ChunkMetadata,
        embedding: Embedding? = nil
    )
    
    public func withEmbedding(_ embedding: Embedding) -> Chunk
}

public struct ChunkMetadata: Sendable, Codable {
    public var documentId: String
    public var index: Int
    public var startOffset: Int
    public var endOffset: Int
    public var source: String?
    public var custom: [String: MetadataValue]
    
    public init(
        documentId: String,
        index: Int,
        startOffset: Int = 0,
        endOffset: Int = 0,
        source: String? = nil,
        custom: [String: MetadataValue] = [:]
    )
}
```

### Embedding.swift

```swift
public struct Embedding: Sendable, Codable {
    public let vector: [Float]
    public let model: String?
    public let dimensions: Int
    
    public init(vector: [Float], model: String? = nil) {
        self.vector = vector
        self.model = model
        self.dimensions = vector.count
    }
    
    /// Cosine similarity with another embedding
    public func cosineSimilarity(to other: Embedding) -> Float
    
    /// Euclidean distance to another embedding
    public func euclideanDistance(to other: Embedding) -> Float
    
    /// Dot product with another embedding
    public func dotProduct(with other: Embedding) -> Float
}
```

### RetrievalResult.swift

```swift
public struct RetrievalResult: Sendable, Identifiable {
    public let id: String
    public let chunk: Chunk
    public let score: Float
    public let metadata: [String: MetadataValue]
    
    public init(
        chunk: Chunk,
        score: Float,
        metadata: [String: MetadataValue] = [:]
    )
}

extension RetrievalResult: Comparable {
    public static func < (lhs: RetrievalResult, rhs: RetrievalResult) -> Bool {
        lhs.score < rhs.score
    }
}
```

### RAGResponse.swift

```swift
public struct RAGResponse: Sendable {
    public let answer: String
    public let sources: [RetrievalResult]
    public let metadata: RAGResponseMetadata
    
    public init(
        answer: String,
        sources: [RetrievalResult],
        metadata: RAGResponseMetadata = RAGResponseMetadata()
    )
}

public struct RAGResponseMetadata: Sendable {
    public var queryTime: Duration?
    public var retrievalTime: Duration?
    public var generationTime: Duration?
    public var totalTime: Duration?
    public var tokensUsed: Int?
    public var model: String?
    
    public init()
}
```

### Metadata.swift

```swift
public enum MetadataValue: Sendable, Codable, Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MetadataValue])
    case dictionary([String: MetadataValue])
    
    public var stringValue: String? { get }
    public var intValue: Int? { get }
    public var doubleValue: Double? { get }
    public var boolValue: Bool? { get }
    
    public var description: String { get }
}

extension MetadataValue: ExpressibleByStringLiteral { }
extension MetadataValue: ExpressibleByIntegerLiteral { }
extension MetadataValue: ExpressibleByFloatLiteral { }
extension MetadataValue: ExpressibleByBooleanLiteral { }
extension MetadataValue: ExpressibleByArrayLiteral { }
extension MetadataValue: ExpressibleByDictionaryLiteral { }
```

---

## Pipeline

### RAGPipeline.swift

```swift
public actor RAGPipeline {
    public let configuration: RAGConfiguration
    
    private let embeddingProvider: any EmbeddingProvider
    private let vectorStore: any VectorStore
    private let retriever: any Retriever
    private let llmProvider: any LLMProvider
    private let chunker: any ChunkingStrategy
    
    public init(
        embedding: any EmbeddingProvider,
        vectorStore: any VectorStore,
        llm: any LLMProvider,
        chunker: any ChunkingStrategy = DefaultChunker(),
        configuration: RAGConfiguration = .default
    )
    
    // MARK: - Ingestion
    
    /// Ingest a single document
    public func ingest(_ document: Document) async throws
    
    /// Ingest multiple documents
    public func ingest(_ documents: [Document]) async throws
    
    /// Ingest from a URL (auto-detect loader)
    public func ingest(from url: URL) async throws
    
    /// Ingest from a directory
    public func ingest(directory: URL, recursive: Bool = true) async throws
    
    // MARK: - Query
    
    /// Query the knowledge base
    public func query(_ question: String, options: QueryOptions = .default) async throws -> RAGResponse
    
    /// Stream a query response
    public func streamQuery(_ question: String, options: QueryOptions = .default) -> AsyncThrowingStream<RAGStreamEvent, Error>
    
    // MARK: - Retrieval Only
    
    /// Retrieve relevant chunks without generation
    public func retrieve(_ query: String, limit: Int = 5, filter: MetadataFilter? = nil) async throws -> [RetrievalResult]
    
    // MARK: - Management
    
    /// Get statistics about the index
    public func statistics() async throws -> RAGStatistics
    
    /// Clear all documents
    public func clear() async throws
}

public struct QueryOptions: Sendable {
    public var retrievalLimit: Int
    public var includeMetadata: Bool
    public var systemPrompt: String?
    public var temperature: Double?
    public var filter: MetadataFilter?
    
    public init(
        retrievalLimit: Int = 5,
        includeMetadata: Bool = true,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        filter: MetadataFilter? = nil
    )
    
    public static let `default` = QueryOptions()
}

public enum RAGStreamEvent: Sendable {
    case retrievalStarted
    case retrievalComplete([RetrievalResult])
    case generationStarted
    case generationChunk(String)
    case generationComplete(String)
    case complete(RAGResponse)
    case error(Error)
}

public struct RAGStatistics: Sendable {
    public let documentCount: Int
    public let chunkCount: Int
    public let embeddingDimensions: Int
    public let vectorStoreName: String
    public let embeddingProviderName: String
}
```

---

## Errors

### SwiftRAGError.swift

```swift
public enum SwiftRAGError: Error, Sendable, LocalizedError {
    // Loading errors
    case unsupportedFileType(String)
    case loadingFailed(url: URL, reason: String)
    case invalidData(reason: String)
    
    // Chunking errors
    case chunkingFailed(reason: String)
    case emptyDocument
    
    // Embedding errors
    case embeddingFailed(reason: String)
    case embeddingDimensionMismatch(expected: Int, got: Int)
    case embeddingProviderUnavailable(name: String)
    case rateLimited(retryAfter: Duration?)
    
    // Vector store errors
    case vectorStoreUnavailable(name: String)
    case vectorStoreConnectionFailed(reason: String)
    case indexNotFound(name: String)
    case insertionFailed(reason: String)
    case searchFailed(reason: String)
    
    // Retrieval errors
    case retrievalFailed(reason: String)
    case noResultsFound
    
    // Generation errors
    case generationFailed(reason: String)
    case llmProviderUnavailable(name: String)
    case contextTooLong(tokens: Int, limit: Int)
    
    // Configuration errors
    case invalidConfiguration(reason: String)
    case missingRequiredComponent(String)
    
    public var errorDescription: String? { get }
    public var recoverySuggestion: String? { get }
}
```

---

## Configuration

### RAGConfiguration.swift

```swift
public struct RAGConfiguration: Sendable {
    // Chunking
    public var defaultChunkSize: Int
    public var defaultChunkOverlap: Int
    
    // Embedding
    public var embeddingBatchSize: Int
    public var cacheEmbeddings: Bool
    
    // Retrieval
    public var defaultRetrievalLimit: Int
    public var similarityThreshold: Float?
    
    // Generation
    public var defaultSystemPrompt: String
    public var maxContextTokens: Int
    public var responseMaxTokens: Int?
    
    // Performance
    public var enableLogging: Bool
    public var logLevel: LogLevel
    
    public enum LogLevel: Int, Sendable {
        case none = 0
        case error = 1
        case warning = 2
        case info = 3
        case debug = 4
    }
    
    public init(...)
    
    public static let `default` = RAGConfiguration(
        defaultChunkSize: 512,
        defaultChunkOverlap: 50,
        embeddingBatchSize: 100,
        cacheEmbeddings: true,
        defaultRetrievalLimit: 5,
        similarityThreshold: nil,
        defaultSystemPrompt: "You are a helpful assistant. Answer questions based on the provided context.",
        maxContextTokens: 4000,
        responseMaxTokens: nil,
        enableLogging: true,
        logLevel: .info
    )
}
```

---

## Testing

### CoreTests.swift

```swift
import XCTest
@testable import SwiftRAG

final class CoreTests: XCTestCase {
    func testDocumentCreation() {
        let doc = Document(content: "Test content", metadata: DocumentMetadata(title: "Test"))
        XCTAssertFalse(doc.id.isEmpty)
        XCTAssertEqual(doc.content, "Test content")
        XCTAssertEqual(doc.metadata.title, "Test")
    }
    
    func testChunkCreation() {
        let chunk = Chunk(
            content: "Test chunk",
            metadata: ChunkMetadata(documentId: "doc-1", index: 0)
        )
        XCTAssertEqual(chunk.metadata.index, 0)
    }
    
    func testEmbeddingCosineSimilarity() {
        let e1 = Embedding(vector: [1.0, 0.0, 0.0])
        let e2 = Embedding(vector: [1.0, 0.0, 0.0])
        let e3 = Embedding(vector: [0.0, 1.0, 0.0])
        
        XCTAssertEqual(e1.cosineSimilarity(to: e2), 1.0, accuracy: 0.001)
        XCTAssertEqual(e1.cosineSimilarity(to: e3), 0.0, accuracy: 0.001)
    }
    
    func testMetadataValueLiterals() {
        let string: MetadataValue = "test"
        let int: MetadataValue = 42
        let double: MetadataValue = 3.14
        let bool: MetadataValue = true
        
        XCTAssertEqual(string.stringValue, "test")
        XCTAssertEqual(int.intValue, 42)
        XCTAssertEqual(double.doubleValue, 3.14)
        XCTAssertEqual(bool.boolValue, true)
    }
    
    func testMetadataFilter() {
        let filter = MetadataFilter(
            .equals("type", "document"),
            .greaterThan("score", 0.5)
        )
        XCTAssertEqual(filter.conditions.count, 2)
    }
}
```

---

## Acceptance Criteria

- [ ] `swift build` succeeds on both Linux and macOS
- [ ] All protocols are defined with clear contracts
- [ ] All types are `Sendable` and `Codable` where appropriate
- [ ] RAGPipeline compiles (methods can be unimplemented stubs)
- [ ] Error types cover all failure modes
- [ ] Tests pass for all types
- [ ] No external dependencies in core module

---

## Notes

1. **Cross-platform first** — No Apple-specific imports in core
2. **Protocol-oriented** — Everything through protocols for testability
3. **Actor-based pipeline** — Thread-safe by design
4. **Streaming support** — Built in from the start
5. **Metadata flexibility** — Support arbitrary key-value metadata
