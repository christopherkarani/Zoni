# Zoni

**A Retrieval-Augmented Generation framework for Swift**

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-Linux%20%7C%20macOS%2014%2B%20%7C%20iOS%2017%2B-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Zoni is a comprehensive, production-ready RAG framework built with Swift 6.0. It provides everything you need to build intelligent document search, question-answering systems, and AI-powered applications across Linux, macOS, and iOS.

## Features

- **Document Loading** - PDF, Markdown, HTML, JSON, CSV, plain text, and web pages
- **Smart Chunking** - Recursive, semantic, markdown-aware, code-aware, sentence, and paragraph strategies
- **Multiple Embeddings** - OpenAI, Cohere, Voyage, Ollama, Apple NLEmbedding, MLX, Foundation Models
- **Vector Stores** - PostgreSQL+pgvector, SQLite, Qdrant, Pinecone, and in-memory storage
- **Advanced Retrieval** - Hybrid search, multi-query expansion, MMR diversity, reranking
- **Query Engine** - Multiple response synthesis strategies (compact, refine, tree-summarize)
- **Agent Tools** - SwiftAgents-compatible tools for RAG operations
- **Server Integration** - First-class Vapor and Hummingbird framework support
- **Multi-Tenancy** - Built-in tenant isolation and job queue system
- **Apple Native** - On-device ML with Foundation Models, NLEmbedding, MLX, and PDFKit
- **Swift 6 Concurrency** - Actor-based design with full async/await and Sendable support

## Installation

Add Zoni to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/zoni", from: "1.0.0")
]
```

## Products

Zoni provides multiple products for different use cases:

| Product | Description | Platforms |
|---------|-------------|-----------|
| **Zoni** | Core RAG library with document loading, chunking, embeddings, and vector stores | Linux, macOS, iOS, tvOS, watchOS, visionOS |
| **ZoniServer** | Multi-tenancy, job queue system, and server-side abstractions | Linux, macOS |
| **ZoniVapor** | Vapor framework integration with controllers and middleware | Linux, macOS |
| **ZoniHummingbird** | Hummingbird framework integration with routes and middleware | Linux, macOS |
| **ZoniApple** | Apple platform extensions (NLEmbedding, MLX, Foundation Models, PDFKit) | macOS 14+, iOS 17+ |
| **ZoniAgents** | SwiftAgents integration layer for agentic workflows | Linux, macOS, iOS |

## Quick Start

### Server-Side RAG (Linux/macOS)

Build a simple RAG pipeline for server-side applications:

```swift
import Zoni

// Create pipeline components
let embedding = OpenAIEmbedding(
    apiKey: "sk-...",
    model: .textEmbedding3Small
)

let vectorStore = InMemoryVectorStore()

let llm = AnthropicProvider(
    apiKey: "sk-ant-...",
    model: .claude35Sonnet
)

let chunker = RecursiveChunker(
    chunkSize: 512,
    overlap: 50
)

// Initialize the RAG pipeline
let pipeline = RAGPipeline(
    embedding: embedding,
    vectorStore: vectorStore,
    llm: llm,
    chunker: chunker
)

// Ingest documents from a directory
try await pipeline.ingest(
    directory: URL(fileURLWithPath: "documents/"),
    recursive: true
)

// Query the knowledge base
let response = try await pipeline.query("What is the refund policy?")
print(response.answer)
print("Sources:", response.sources.map(\.metadata["filename"] ?? "unknown"))
```

### iOS/macOS with Apple Intelligence

Build privacy-first, on-device RAG using Apple's frameworks:

```swift
import Zoni
import ZoniApple

// Create on-device pipeline with Apple NaturalLanguage
let embedding = NLEmbeddingProvider(language: .english)
let vectorStore = SQLiteVectorStore(url: URL(fileURLWithPath: "vectors.db"))
let chunker = MarkdownChunker(targetChunkSize: 512)

// For iOS 26+ / macOS 26+ with Apple Intelligence:
// let llm = FoundationModelsProvider()

let pipeline = RAGPipeline(
    embedding: embedding,
    vectorStore: vectorStore,
    llm: llm,  // Your LLM provider
    chunker: chunker
)

// Ingest PDF documents
let pdfURL = Bundle.main.url(forResource: "manual", withExtension: "pdf")!
try await pipeline.ingest(from: pdfURL)

// Query with streaming
for try await event in pipeline.streamQuery("Summarize the key points") {
    switch event {
    case .retrievalStarted:
        print("Searching documents...")
    case .chunksRetrieved(let chunks):
        print("Found \(chunks.count) relevant sections")
    case .generationStarted:
        print("Generating response...")
    case .partialResponse(let delta):
        print(delta, terminator: "")
    case .completed(let response):
        print("\n\nSources: \(response.sources.count)")
    }
}
```

### Vapor Server with Multi-Tenancy

Build a production RAG API with Vapor:

```swift
import Vapor
import ZoniVapor
import ZoniServer

func configure(_ app: Application) async throws {
    // Setup multi-tenant RAG
    let tenantManager = try await TenantManager(
        postgres: PostgresConfiguration(
            host: "localhost",
            database: "zoni"
        )
    )

    app.zoni.tenantManager = tenantManager

    // Register RAG routes with JWT authentication
    try app.register(collection: ZoniController())

    // Enable streaming support
    app.middleware.use(StreamingMiddleware())
}

// Your routes support:
// POST /api/v1/documents/ingest - Ingest documents
// POST /api/v1/query - Query knowledge base
// POST /api/v1/query/stream - Streaming queries
// GET /api/v1/stats - Pipeline statistics
```

## Documentation

- [Getting Started Guide](Documentation/GettingStarted.md) - Detailed setup and basic usage
- [Server Guide](Documentation/ServerGuide.md) - Building RAG APIs with Vapor/Hummingbird
- [Apple Platforms Guide](Documentation/AppleGuide.md) - On-device ML and iOS/macOS integration
- [Advanced Retrieval](Documentation/AdvancedRetrieval.md) - Hybrid search, reranking, MMR
- [API Reference](Documentation/API/) - Complete API documentation

## Architecture

Zoni follows a modular architecture with clear protocol boundaries:

```
┌─────────────────────────────────────────────────────────┐
│                     RAGPipeline                         │
│                  (Actor-based orchestration)            │
└───────────┬─────────────┬─────────────┬────────────────┘
            │             │             │
    ┌───────▼──────┐ ┌───▼──────┐ ┌────▼─────────┐
    │ DocumentLoader│ │ Chunking │ │  Embedding   │
    │   Registry    │ │ Strategy │ │   Provider   │
    └───────┬──────┘ └───┬──────┘ └────┬─────────┘
            │             │             │
    ┌───────▼─────────────▼─────────────▼─────────┐
    │            VectorStore                       │
    │    (PostgreSQL, SQLite, Qdrant, etc.)       │
    └───────┬──────────────────────────────────────┘
            │
    ┌───────▼──────┐
    │   Retriever  │ ─────► QueryEngine ─────► LLMProvider
    │  (Strategies) │
    └──────────────┘
```

## Key Components

### Document Loading
Load documents from various sources with automatic format detection:

```swift
// Register loaders
await pipeline.registerLoader(PDFLoader())
await pipeline.registerLoader(MarkdownLoader())
await pipeline.registerLoader(WebLoader())

// Automatic loader selection by extension
try await pipeline.ingest(from: URL(string: "https://example.com/docs"))
```

### Chunking Strategies
Choose the right chunking strategy for your content:

- `FixedSizeChunker` - Simple character-based chunking
- `SentenceChunker` - Respects sentence boundaries
- `ParagraphChunker` - Splits on paragraph breaks
- `RecursiveChunker` - Hierarchical splitting (paragraphs → sentences → words)
- `MarkdownChunker` - Preserves markdown structure
- `CodeChunker` - Language-aware code splitting
- `SemanticChunker` - Embedding-based semantic boundaries

### Embedding Providers
Multiple embedding options for different needs:

```swift
// Cloud-based (high quality)
let openai = OpenAIEmbedding(apiKey: "...", model: .textEmbedding3Large)
let cohere = CohereEmbedding(apiKey: "...", model: .embedEnglishV3)
let voyage = VoyageEmbedding(apiKey: "...", model: .voyage2)

// Self-hosted (privacy)
let ollama = OllamaEmbedding(baseURL: "http://localhost:11434", model: "nomic-embed-text")

// On-device (Apple platforms)
let apple = NLEmbeddingProvider(language: .english)  // Free, private
let mlx = try MLXEmbeddingProvider(modelPath: "...")  // GPU-accelerated
let swift = try SwiftEmbeddingsProvider(model: .model2VecBase)  // Ultra-fast
```

### Vector Stores
Flexible storage backends:

```swift
// In-memory (development/testing)
let memory = InMemoryVectorStore()

// SQLite (single-node, embedded)
let sqlite = SQLiteVectorStore(url: URL(fileURLWithPath: "vectors.db"))

// PostgreSQL with pgvector (production, multi-tenant)
let postgres = try await PgVectorStore(
    configuration: PostgresConfiguration(host: "localhost", database: "zoni")
)

// Managed services
let qdrant = QdrantStore(url: "http://localhost:6333", collection: "docs")
let pinecone = PineconeStore(apiKey: "...", index: "zoni-index")
```

### Advanced Retrieval
Combine multiple retrieval strategies:

```swift
// Hybrid search (keyword + semantic)
let hybrid = HybridRetriever(
    vectorRetriever: vectorRetriever,
    keywordRetriever: keywordRetriever,
    alpha: 0.7  // Weight toward semantic
)

// Multi-query expansion
let multiQuery = MultiQueryRetriever(
    baseRetriever: vectorRetriever,
    llm: llm,
    numQueries: 3
)

// MMR for diversity
let mmr = MMRRetriever(
    baseRetriever: vectorRetriever,
    lambda: 0.5  // Balance relevance vs. diversity
)

// Reranking
let reranker = RerankerRetriever(
    baseRetriever: vectorRetriever,
    reranker: CohereReranker(apiKey: "...")
)
```

## Requirements

- **Swift 6.0+** (Swift 6 language mode enabled)
- **Platforms:**
  - Linux (Ubuntu 20.04+)
  - macOS 14.0+
  - iOS 17.0+
  - tvOS 17.0+
  - watchOS 10.0+
  - visionOS 1.0+
- **Apple Extensions (ZoniApple):**
  - Foundation Models: iOS 26.0+, macOS 26.0+ (requires Apple Intelligence)
  - MLX: macOS 14.0+, iOS 17.0+ (Apple Silicon only)
  - Swift Embeddings: macOS 15.0+, iOS 18.0+

## Examples

Check out the [Examples](Examples/) directory for complete sample projects:

- **CLI RAG Tool** - Command-line document search
- **iOS Knowledge Base** - SwiftUI app with on-device RAG
- **Vapor API Server** - Multi-tenant RAG API
- **Hummingbird Microservice** - Lightweight RAG service
- **Agent Workflows** - Using ZoniAgents for complex workflows

## Testing

Zoni includes comprehensive test coverage:

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter ZoniTests
swift test --filter ZoniServerTests
swift test --filter ZoniAppleTests

# Run with coverage (macOS/Linux)
swift test --enable-code-coverage
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Roadmap

- [ ] Support for more embedding providers (HuggingFace, Mistral, etc.)
- [ ] Document preprocessing pipelines (OCR, table extraction)
- [ ] Graph-based retrieval strategies
- [ ] Distributed vector stores (Milvus, Weaviate)
- [ ] Fine-tuning integration
- [ ] Evaluation framework for RAG quality metrics

## License

Zoni is released under the MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Built with Swift 6.0 and powered by:
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) - HTML parsing
- [AsyncHTTPClient](https://github.com/swift-server/async-http-client) - HTTP networking
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) - SQLite interface
- [PostgresNIO](https://github.com/vapor/postgres-nio) - PostgreSQL driver
- [Vapor](https://github.com/vapor/vapor) - Web framework
- [Hummingbird](https://github.com/hummingbird-project/hummingbird) - Swift HTTP server
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - GPU-accelerated ML
- [swift-embeddings](https://github.com/jkrukowski/swift-embeddings) - Fast Model2Vec

---

**Questions?** Open an [issue](../../issues) or start a [discussion](../../discussions).

**Looking for enterprise support?** Contact [chris@example.com](mailto:chris@example.com).
