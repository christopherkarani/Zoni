# Zoni

**A Retrieval-Augmented Generation framework for Swift**

[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-Linux%20%7C%20macOS%2014%2B%20%7C%20iOS%2017%2B-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Zoni is a comprehensive RAG framework built with Swift 6.1. It provides document search, question-answering, and AI application building blocks across Linux, macOS, and iOS.

## Features

- **Document Loading** - PDF, Markdown, JSON, CSV, plain text, plus optional HTML and web-page loading
- **Smart Chunking** - Recursive, semantic, markdown-aware, code-aware, sentence, and paragraph strategies
- **Multiple Embeddings** - Mock/local core embeddings, optional OpenAI/Cohere/Voyage/Ollama integrations, Apple NLEmbedding, MLX, Foundation Models
- **Vector Stores** - In-memory, plus optional Qdrant, Pinecone, PostgreSQL+pgvector, and SQLite integrations
- **Advanced Retrieval** - Hybrid search, multi-query expansion, MMR diversity, reranking
- **Query Engine** - Multiple response synthesis strategies (compact, refine, tree-summarize)
- **Agent Tools** - SwiftAgents-compatible tools for RAG operations
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
| **ZoniCore** | Lightweight contracts, value types, configuration, errors, and metadata filtering for custom integrations | Linux, macOS, iOS, tvOS, watchOS, visionOS |
| **Zoni** | Core RAG library with document loading, chunking, embeddings, and vector stores | Linux, macOS, iOS, tvOS, watchOS, visionOS |
| **ZoniServer** | Multi-tenancy, job queue system, and server-side abstractions | Linux, macOS |
| **ZoniApple** | Apple platform extensions (NLEmbedding, MLX, Foundation Models, PDFKit) | macOS 14+, iOS 17+ |
| **ZoniAgents** | SwiftAgents integration layer for agentic workflows | Linux, macOS, iOS |

## Optional Integration Packages

Heavier storage and framework integrations live outside the root package so core users do not resolve those dependencies by default:

| Integration | Path | Adds |
|-------------|------|------|
| **ZoniServerPostgres** | `Integrations/ZoniServerPostgres` | PostgreSQL/pgvector vector store and RAG pipeline factory |
| **ZoniSQLite** | `Integrations/ZoniSQLite` | SQLite vector store for embedded persistence |
| **ZoniSQLiteApple** | `Integrations/ZoniSQLite` | Apple SQLite memory strategies and on-device pipeline factories |
| **ZoniConduit** | `Integrations/ZoniConduit` | Conduit inference adapter for `LLMProvider` |
| **ZoniHTTP** | `Integrations/ZoniHTTP` | HTTP embedding providers, HTML/web loaders, Qdrant/Pinecone stores, and Cohere reranking |

## Build and Test

Use these commands as the local baseline before opening a PR:

```bash
# Build the package
swift build

# Run the core test suite without external services
swift test --filter ZoniTests

# Run integration tests that require local or hosted vector stores
ZONI_RUN_INTEGRATION_TESTS=1 swift test --filter IntegrationTests
```

The example projects are standalone Swift packages:

```bash
(cd Examples/AgentWithRAG && swift build)
(cd Examples/ServerRAG && swift build)
(cd Examples/iOSDocumentQA && swift build)
```

## Quick Start

### Server-Side RAG (Linux/macOS)

Build a simple RAG pipeline for server-side applications:

```swift
import Zoni
import ZoniHTTP

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
import ZoniSQLite

// Create on-device pipeline with Apple NaturalLanguage
let embedding = NLEmbeddingProvider(language: .english)
let vectorStore = try SQLiteVectorStore(url: URL(fileURLWithPath: "vectors.db"))
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

## Documentation

- [Getting Started Guide](Documentation/GettingStarted.md) - Detailed setup and basic usage
- [Server Guide](Documentation/ServerGuide.md) - Building RAG APIs with ZoniServer
- [Apple Platforms Guide](Documentation/AppleGuide.md) - On-device ML and iOS/macOS integration
- Advanced retrieval examples are covered in the sections below.

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
    │      (In-memory, optional integrations)      │
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
import ZoniHTTP

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
import ZoniHTTP

// Cloud-based (high quality)
let openai = OpenAIEmbedding(apiKey: "...", model: .textEmbedding3Large)
let cohere = CohereEmbedding(apiKey: "...", model: .embedEnglishV3)
let voyage = VoyageEmbedding(apiKey: "...", model: .voyage2)

// Self-hosted (privacy)
let ollama = OllamaEmbedding(baseURL: "http://localhost:11434", model: "nomic-embed-text")

// On-device (Apple platforms)
let apple = NLEmbeddingProvider(language: .english)  // Free, private
let mlx = try MLXEmbeddingProvider(modelPath: "...")  // GPU-accelerated (⚠️ Experimental - see docs)
let swift = try SwiftEmbeddingsProvider(model: .model2VecBase)  // Ultra-fast
```

> **Note**: `MLXEmbeddingProvider` is experimental and not recommended for production use. See [AppleGuide.md](Documentation/AppleGuide.md) for details.

### Vector Stores
Flexible storage backends:

```swift
import ZoniHTTP

// In-memory (development/testing)
let memory = InMemoryVectorStore()

// SQLite (single-node, embedded; requires import ZoniSQLite)
let sqlite = try SQLiteVectorStore(url: URL(fileURLWithPath: "vectors.db"))

// PostgreSQL with pgvector (production, multi-tenant; requires import ZoniServerPostgres)
let postgres = try await PgVectorStore(
    configuration: PostgresConfiguration(host: "localhost", database: "zoni")
)

// Managed services (requires ZoniHTTP)
let qdrant = QdrantStore(url: "http://localhost:6333", collection: "docs")
let pinecone = PineconeStore(apiKey: "...", index: "zoni-index")
```

### Advanced Retrieval
Combine multiple retrieval strategies:

```swift
import ZoniHTTP

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

- **Swift 6.1+** (Swift 6 language mode enabled)
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
- **Server RAG API** - Multi-tenant RAG API
- **Agent Workflows** - Using ZoniAgents for complex workflows

## Testing

Zoni includes comprehensive test coverage:

```bash
# Run core tests that do not require external services
swift test --filter ZoniTests

# Run specific product suites
swift test --filter ZoniServerTests
swift test --filter ZoniAppleTests

# Run integration tests that require Qdrant/Pinecone configuration
ZONI_RUN_INTEGRATION_TESTS=1 swift test --filter IntegrationTests

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

Built with Swift 6.1 and powered by:
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) - HTML parsing in the optional `ZoniHTTP` package
- [AsyncHTTPClient](https://github.com/swift-server/async-http-client) - HTTP networking in the optional `ZoniHTTP` package
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) - SQLite interface for the optional `ZoniSQLite` package
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - GPU-accelerated ML
- [swift-embeddings](https://github.com/jkrukowski/swift-embeddings) - Fast Model2Vec

---

**Questions?** Open an [issue](../../issues) or start a [discussion](../../discussions).

**Looking for enterprise support?** Contact [chris@example.com](mailto:chris@example.com).
