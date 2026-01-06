# Getting Started with Zoni

Zoni is a production-ready Retrieval-Augmented Generation (RAG) framework for Swift, designed for modern concurrency with Swift 6.2's strict data-race safety.

## Installation

### Swift Package Manager

Add Zoni to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/zoni", from: "1.0.0")
]

targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Zoni", package: "zoni")
        ]
    )
]
```

### Platform Requirements

- macOS 14.0+
- iOS 17.0+
- tvOS 17.0+
- watchOS 10.0+
- visionOS 1.0+
- Swift 6.0+

## Core Concepts

### The RAG Pipeline

```
Document → Chunking → Embedding → Vector Store → Retrieval → LLM Generation
```

1. **Documents** - Text content with metadata
2. **Chunks** - Smaller pieces for semantic search (default: 512 tokens with 50-token overlap)
3. **Embeddings** - Vector representations of text chunks
4. **Vector Store** - Database for similarity search (InMemory, SQLite, PostgreSQL)
5. **Retrieval** - Finding relevant chunks based on semantic similarity
6. **Generation** - LLM generates answers using retrieved context

### Key Components

- **EmbeddingProvider** - Generates vector embeddings (OpenAI, Cohere, MLX, Model2Vec)
- **VectorStore** - Stores and searches embeddings (InMemory, SQLite, pgvector)
- **ChunkingStrategy** - Splits documents into chunks (Fixed, Recursive, Semantic)
- **DocumentLoader** - Loads various file formats (TXT, MD, HTML, JSON, CSV, PDF)
- **LLMProvider** - Generates responses (OpenAI, Anthropic, custom)
- **QueryEngine** - Orchestrates retrieval and generation

## Your First Pipeline

### Basic Setup

```swift
import Zoni

// 1. Create components
let embedding = try OpenAIEmbedding(
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!
)
let vectorStore = InMemoryVectorStore()
let llm = try OpenAIProvider(
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!,
    model: "gpt-4"
)
let chunker = FixedSizeChunker(chunkSize: 512, chunkOverlap: 50)

// 2. Create pipeline
let pipeline = RAGPipeline(
    embedding: embedding,
    vectorStore: vectorStore,
    llm: llm,
    chunker: chunker
)

// 3. Ingest documents
let document = Document(
    content: "Your document content here...",
    metadata: DocumentMetadata(source: "example.txt")
)
try await pipeline.ingest(document)

// 4. Query
let response = try await pipeline.query("What is this document about?")
print("Answer: \(response.answer)")
print("Sources: \(response.sources.count)")
for source in response.sources {
    print("  - \(source.chunk.metadata.source ?? "unknown") (score: \(source.score))")
}
```

## Ingesting Documents

### From Files

```swift
// Register document loaders
await pipeline.registerLoader(TextLoader())
await pipeline.registerLoader(MarkdownLoader())
await pipeline.registerLoader(HTMLLoader())
await pipeline.registerLoader(PDFLoader())

// Single file
try await pipeline.ingest(from: URL(fileURLWithPath: "/path/to/file.pdf"))

// Directory (recursive by default)
try await pipeline.ingest(
    directory: URL(fileURLWithPath: "/path/to/docs/"),
    recursive: true
)
```

### Supported Formats

- `.txt`, `.text` - Plain text (TextLoader)
- `.md`, `.markdown` - Markdown (MarkdownLoader)
- `.html`, `.htm` - HTML (HTMLLoader)
- `.json` - JSON (JSONLoader)
- `.csv`, `.tsv` - CSV/TSV (CSVLoader)
- `.pdf` - PDF documents (PDFLoader)

### Custom Document Metadata

```swift
let document = Document(
    content: "Swift is a powerful programming language.",
    metadata: DocumentMetadata(
        source: "swift-guide.txt",
        title: "Swift Programming Guide",
        author: "Apple Inc.",
        createdAt: Date(),
        customFields: [
            "category": "programming",
            "language": "swift",
            "version": "6.0"
        ]
    )
)

try await pipeline.ingest(document)
```

## Querying

### Basic Query

```swift
let response = try await pipeline.query("What is Swift?")
print(response.answer)
```

### With Options

```swift
let options = QueryOptions(
    retrievalLimit: 10,
    systemPrompt: "You are a Swift programming expert. Be concise and cite sources.",
    temperature: 0.7,
    maxContextTokens: 8000
)

let response = try await pipeline.query(
    "How does async/await work in Swift?",
    options: options
)
```

### With Metadata Filtering

```swift
// Only retrieve chunks from programming-related documents
let filter = MetadataFilter.equals("category", "programming")
let options = QueryOptions(
    retrievalLimit: 5,
    filter: filter
)

let response = try await pipeline.query("Explain Swift concurrency", options: options)
```

### Streaming Responses

Stream responses for real-time display:

```swift
for try await event in pipeline.streamQuery("What is Swift?") {
    switch event {
    case .retrievalStarted:
        print("Searching knowledge base...")

    case .retrievalComplete(let sources):
        print("Found \(sources.count) relevant sources")

    case .generationStarted:
        print("Generating answer...\n")

    case .generationChunk(let text):
        print(text, terminator: "")

    case .generationComplete(let fullAnswer):
        print("\n\n[Generation complete]")

    case .complete(let response):
        print("Total sources used: \(response.sources.count)")
        if let duration = response.metadata.totalTime {
            print("Completed in: \(duration)")
        }

    case .error(let error):
        print("Error: \(error)")
    }
}
```

## Configuration

### Custom RAG Configuration

```swift
let config = RAGConfiguration(
    defaultChunkSize: 1024,
    defaultChunkOverlap: 100,
    embeddingBatchSize: 50,
    cacheEmbeddings: true,
    defaultRetrievalLimit: 10,
    similarityThreshold: 0.7,
    defaultSystemPrompt: "You are a helpful assistant. Always cite your sources.",
    maxContextTokens: 8000,
    responseMaxTokens: 2000,
    enableLogging: true,
    logLevel: .info
)

let pipeline = RAGPipeline(
    embedding: embedding,
    vectorStore: vectorStore,
    llm: llm,
    chunker: chunker,
    configuration: config
)
```

### Configuration Options

- **defaultChunkSize**: Chunk size in tokens/characters (default: 512)
- **defaultChunkOverlap**: Overlap between chunks (default: 50)
- **embeddingBatchSize**: Batch size for embedding operations (default: 100)
- **cacheEmbeddings**: Enable embedding caching (default: true)
- **defaultRetrievalLimit**: Default number of chunks to retrieve (default: 5)
- **similarityThreshold**: Minimum similarity score (default: nil)
- **defaultSystemPrompt**: Default LLM system prompt
- **maxContextTokens**: Max context window size (default: 4000)
- **responseMaxTokens**: Max response length (default: nil)
- **enableLogging**: Enable logging (default: true)
- **logLevel**: Logging verbosity (.none, .error, .warning, .info, .debug)

## Vector Stores

### In-Memory Store

Fast, volatile storage for development:

```swift
let vectorStore = InMemoryVectorStore()
```

### SQLite Store

Persistent storage for single-user applications:

```swift
let vectorStore = try SQLiteVectorStore(
    path: "/path/to/database.sqlite"
)
```

### PostgreSQL Store (with pgvector)

Production-ready vector store with advanced filtering:

```swift
let vectorStore = try await PostgresVectorStore(
    host: "localhost",
    port: 5432,
    database: "zoni",
    username: "user",
    password: "password",
    dimensions: 1536
)
```

## Embedding Providers

### OpenAI Embeddings

```swift
let embedding = try OpenAIEmbedding(
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!,
    model: "text-embedding-3-small"  // 1536 dimensions
)
```

### Cohere Embeddings

```swift
let embedding = try CohereEmbedding(
    apiKey: ProcessInfo.processInfo.environment["COHERE_API_KEY"]!,
    model: "embed-english-v3.0"
)
```

### Local Embeddings (Apple Platforms)

For privacy-focused applications:

```swift
import ZoniApple

// Model2Vec (fast, efficient)
let embedding = Model2VecEmbedding(
    modelPath: "/path/to/model2vec.onnx"
)

// MLX (GPU-accelerated on Apple Silicon)
let embedding = MLXEmbedding(
    modelPath: "/path/to/mlx-model"
)
```

## LLM Providers

### OpenAI

```swift
let llm = try OpenAIProvider(
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!,
    model: "gpt-4-turbo"
)
```

### Anthropic

```swift
let llm = try AnthropicProvider(
    apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]!,
    model: "claude-3-opus-20240229"
)
```

### Custom LLM Provider

Implement the `LLMProvider` protocol for custom models:

```swift
struct CustomLLM: LLMProvider {
    let name = "CustomLLM"
    let model = "custom-model-v1"
    let maxContextTokens = 8000

    func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String {
        // Your implementation
    }

    func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error> {
        // Your streaming implementation
    }
}
```

## Chunking Strategies

### Fixed-Size Chunking

Simple, predictable chunks:

```swift
let chunker = FixedSizeChunker(
    chunkSize: 512,
    chunkOverlap: 50
)
```

### Recursive Character Chunking

Splits at natural boundaries (paragraphs, sentences):

```swift
let chunker = RecursiveChunker(
    chunkSize: 512,
    chunkOverlap: 50,
    separators: ["\n\n", "\n", ".", " "]
)
```

### Semantic Chunking

Groups semantically related content:

```swift
let chunker = SemanticChunker(
    embedding: embedding,
    bufferSize: 1,
    breakpointPercentileThreshold: 95
)
```

## Pipeline Statistics

Monitor your pipeline:

```swift
let stats = try await pipeline.statistics()
print("Documents: \(stats.documentCount)")
print("Chunks: \(stats.chunkCount)")
print("Embedding dimensions: \(stats.embeddingDimensions)")
print("Vector store: \(stats.vectorStoreName)")
print("Embedding provider: \(stats.embeddingProviderName)")
```

## Management Operations

### Clear All Data

```swift
try await pipeline.clear()
```

### Retrieval-Only Mode

Retrieve relevant chunks without LLM generation:

```swift
let results = try await pipeline.retrieve(
    "Swift concurrency",
    limit: 10,
    filter: nil
)

for result in results {
    print("Score: \(result.score)")
    print("Content: \(result.chunk.content)")
    print("Source: \(result.chunk.metadata.source ?? "unknown")")
}
```

## Error Handling

Zoni uses the `ZoniError` enum for all errors:

```swift
do {
    try await pipeline.ingest(from: fileURL)
} catch ZoniError.unsupportedFileType(let ext) {
    print("Unsupported file type: .\(ext)")
} catch ZoniError.loadingFailed(let url, let reason) {
    print("Failed to load \(url): \(reason)")
} catch ZoniError.embeddingFailed(let reason) {
    print("Embedding failed: \(reason)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Next Steps

- **[Server Deployment Guide](ServerGuide.md)** - Deploy Zoni as a server with Vapor or Hummingbird
- **[Apple Platforms Guide](AppleGuide.md)** - Use Zoni in iOS, macOS, and visionOS apps
- **[Advanced Topics](Advanced.md)** - Custom retrievers, query engines, and synthesis strategies

## Examples

Check out the `/Examples` directory for:

- Basic RAG pipeline
- Streaming chat interface
- Document search system
- Multi-tenant server deployment
- iOS app with local embeddings

## Community

- GitHub: [https://github.com/christopherkarani/zoni](https://github.com/christopherkarani/zoni)
- Issues: [https://github.com/christopherkarani/zoni/issues](https://github.com/christopherkarani/zoni/issues)
- Discussions: [https://github.com/christopherkarani/zoni/discussions](https://github.com/christopherkarani/zoni/discussions)

## License

Zoni is released under the MIT License. See LICENSE for details.
