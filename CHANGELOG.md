# Changelog

All notable changes to Zoni will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-05

### Added

#### Core Framework (Phase 1)
- Core types: `Document`, `Chunk`, `Embedding`, `Metadata`, `RetrievalResult`
- Protocol definitions: `VectorStore`, `EmbeddingProvider`, `ChunkingStrategy`, `DocumentLoader`, `LLMProvider`, `Retriever`
- Comprehensive error handling with `ZoniError`
- `RAGConfiguration` for pipeline customization

#### Document Processing (Phase 2)
- Document loaders: `TextLoader`, `MarkdownLoader`, `HTMLLoader`, `JSONLoader`, `CSVLoader`, `PDFLoader`, `WebLoader`
- `LoaderRegistry` for automatic loader selection by file extension
- `DirectoryLoader` for batch file processing
- Chunking strategies: `FixedSizeChunker`, `SentenceChunker`, `ParagraphChunker`, `RecursiveChunker`, `SemanticChunker`, `MarkdownChunker`, `CodeChunker`
- `TokenCounter` with multiple tokenizer support

#### Embeddings (Phase 2)
- Embedding providers: `OpenAIEmbedding`, `CohereEmbedding`, `VoyageEmbedding`, `OllamaEmbedding`
- `BatchEmbedder` for efficient batch processing
- `EmbeddingCache` with LRU eviction and TTL
- `RateLimiter` for API rate limiting

#### Vector Storage (Phase 3)
- Vector stores: `InMemoryVectorStore`, `SQLiteVectorStore`, `QdrantStore`, `PineconeStore`
- `VectorStoreFactory` for configuration-driven instantiation
- SIMD-optimized vector math (cosine similarity, euclidean distance)
- Comprehensive metadata filtering

#### Retrieval (Phase 4A)
- Retrieval strategies: `VectorRetriever`, `KeywordRetriever`, `HybridRetriever`, `MultiQueryRetriever`, `MMRRetriever`, `RerankerRetriever`
- Reranking support with `Reranker` protocol

#### Query Engine (Phase 4B)
- `QueryEngine` orchestrating retrieval and generation
- Response synthesizers: `CompactSynthesizer`, `RefineSynthesizer`, `TreeSummarizeSynthesizer`
- `ContextBuilder` for context assembly
- Streaming query support with `RAGStreamEvent`

#### Server Integration (Phase 5)
- **ZoniServer**: Multi-tenancy, job queue system, server DTOs
- **ZoniVapor**: Vapor framework integration with controllers and middleware
- **ZoniHummingbird**: Hummingbird framework integration with routes
- `PgVectorStore` for PostgreSQL with pgvector
- WebSocket support for real-time streaming

#### Apple Platform Extensions (Phase 5)
- **ZoniApple**: On-device ML extensions
- `NLEmbeddingProvider` using NaturalLanguage framework
- `MLXEmbeddingProvider` for Apple Silicon GPU acceleration
- `SwiftEmbeddingsProvider` integration
- `FoundationModelsProvider` for iOS 26+ Foundation Models
- Memory optimization strategies

#### Agent Integration (Phase 5)
- **ZoniAgents**: SwiftAgents framework bridge
- RAG tools: `SearchTool`, `IngestTool`, `QueryTool`, `SummarizeTool`, `MultiIndexTool`
- Adapter implementations for seamless agent integration

#### Pipeline & Polish (Phase 6)
- `RAGPipeline` orchestrator with full ingestion and query support
- `LoaderRegistry` for automatic document loader selection
- Progress tracking with `IngestionProgress` and `QueryProgress`
- Factory methods: `.inMemory()`, `.postgres()`, `.apple()`, `.mlx()`
- Comprehensive documentation and examples
- CI/CD with GitHub Actions

### Changed
- N/A (initial release)

### Deprecated
- N/A (initial release)

### Removed
- N/A (initial release)

### Fixed
- N/A (initial release)

### Security
- All types are `Sendable` for Swift 6 concurrency safety
- Actor-based isolation for thread-safe operations
- No force unwraps in production code

## [0.5.0] - 2025-01-04 (Phase 5 - Internal)

### Added
- Server framework integrations (Vapor, Hummingbird)
- Apple platform extensions
- Multi-tenancy support
- Job queue system

## [0.4.0] - 2025-01-03 (Phase 4 - Internal)

### Added
- Query engine with streaming
- Multiple retrieval strategies
- Response synthesizers

## [0.3.0] - 2025-01-02 (Phase 3 - Internal)

### Added
- Vector store backends
- Metadata filtering
- SIMD optimizations

## [0.2.0] - 2025-01-01 (Phase 2 - Internal)

### Added
- Document loaders
- Chunking strategies
- Embedding providers

## [0.1.0] - 2024-12-30 (Phase 1 - Internal)

### Added
- Initial core types and protocols
- Error handling framework
- Configuration system
