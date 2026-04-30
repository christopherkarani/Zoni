# Zoni Framework Slim-Down Implementation Plan

## Overview

This plan details the step-by-step execution to reduce Zoni from 150+ public types to ~60-70, improving DX scores from 3.2/10 to 8/10.

**Target**: Production-grade RAG system focused on core functionality
**Timeline**: 6 weeks
**Approach**: Phased removal with backward compatibility considerations

---

## Phase 1: Quick Wins (Week 1)

### Day 1-2: Remove Empty/Unused Types

**Files to Delete**:
- [ ] `Sources/Zoni/Retrieval/RetrievalUtils.swift` - Empty utility enum
- [ ] `Sources/Zoni/Chunking/ChunkingUtils.swift` - Remove ChunkStatistics, ChunkValidationError

**Files to Modify**:
- [ ] `Sources/Zoni/Chunking/ChunkingUtils.swift` - Make remaining utilities internal

### Day 3-4: Make Implementation Details Internal

**Access Control Changes**:

```swift
// Sources/Zoni/Embedding/RateLimiter.swift
- public actor RateLimiter
+ internal actor RateLimiter

// Sources/Zoni/Retrieval/ParentLookup.swift
- public protocol ParentLookup
+ internal protocol ParentLookup

// Sources/Zoni/Retrieval/VectorStoreParentLookup.swift
- public actor VectorStoreParentLookup
+ internal actor VectorStoreParentLookup

// Sources/Zoni/Query/RAGPrompts.swift
- public enum RAGPrompts
+ internal enum RAGPrompts

// Sources/Zoni/Chunking/TextSplitter.swift
- public enum TextSplitter
+ internal enum TextSplitter

// Sources/Zoni/Chunking/TokenCounter.swift
- public struct TokenCounter
+ internal struct TokenCounter

// Sources/Zoni/Loading/LoadingUtils.swift
- public enum LoadingUtils
+ internal enum LoadingUtils

// Sources/Zoni/VectorStore/VectorMath.swift
- public enum VectorMath
+ internal enum VectorMath
```

### Day 5: Remove Evaluation Framework

**Files to Delete**:
- [ ] `Sources/Zoni/Evaluation/RAGEvaluator.swift` (entire file)

**Impact**: Removes 6 public types
- EvaluationItem
- EvaluationDataset
- RetrievalMetrics
- GenerationMetrics
- EvaluationResults
- RAGEvaluator

**Migration Path**: Users needing evaluation should implement their own or use a separate package.

---

## Phase 2: Core Consolidation (Week 2-3)

### Week 2, Day 1-2: Consolidate Chunking Strategies

**Remove 4 chunkers**:

```bash
# Files to delete
rm Sources/Zoni/Chunking/Strategies/SemanticChunker.swift
rm Sources/Zoni/Chunking/Strategies/CodeChunker.swift
rm Sources/Zoni/Chunking/Strategies/SentenceChunker.swift
rm Sources/Zoni/Chunking/Strategies/ParagraphChunker.swift
```

**Keep 4 chunkers**:
- RecursiveChunker (primary)
- MarkdownChunker (specialized)
- ParentChildChunker (hierarchical)
- FixedSizeChunker (simple fallback)

**Update Documentation**:
- Update README to reflect new chunking options
- Add migration note: "Use RecursiveChunker instead of Sentence/Paragraph chunkers"

### Week 2, Day 3-5: Consolidate Embedding Providers

**Remove 4 providers**:

```bash
# Files to delete
rm Sources/Zoni/Embedding/Providers/CohereEmbedding.swift
rm Sources/Zoni/Embedding/Providers/VoyageEmbedding.swift
rm Sources/Zoni/Embedding/Providers/MistralEmbedding.swift
rm Sources/Zoni/Embedding/Providers/HuggingFaceEmbedding.swift
```

**Keep 3 core providers**:
- OpenAIEmbedding (most popular)
- OllamaEmbedding (self-hosted)
- MockEmbedding (testing)

**Update Package.swift**:
```swift
// Remove unused dependencies if any
// Note: Check if HuggingFace removal affects dependencies
```

### Week 3, Day 1-2: Consolidate Vector Stores

**Remove 2 stores + factory**:

```bash
# Files to delete
rm Sources/Zoni/VectorStore/Stores/QdrantStore.swift
rm Sources/Zoni/VectorStore/Stores/PineconeStore.swift
rm Sources/Zoni/VectorStore/VectorStoreFactory.swift
```

**Keep 2 stores**:
- InMemoryVectorStore (development/testing)
- SQLiteVectorStore (production single-node)

**Migration Path**:
```swift
// Before
let store = QdrantStore(url: "...", collection: "docs")

// After - implement VectorStore protocol
struct QdrantStore: VectorStore {
    // User implements
}
```

### Week 3, Day 3-4: Consolidate Retrievers

**Remove 2 retrievers + graph infrastructure**:

```bash
# Files to delete
rm Sources/Zoni/Retrieval/Retrievers/GraphRetriever.swift
rm Sources/Zoni/Retrieval/Retrievers/MultiQueryRetriever.swift
rm -rf Sources/Zoni/Retrieval/Graph/
```

**Keep 6 retrievers**:
- VectorRetriever (core)
- HybridRetriever (common strategy)
- KeywordRetriever (for hybrid)
- MMRRetriever (diversity)
- RerankerRetriever (quality)
- ParentChildRetriever (hierarchical)

### Week 3, Day 5: Consolidate Query Transformers

**Remove 4 transformers**:

```bash
# Files to delete - modify QueryTransformer.swift instead
# Remove these structs from Query/QueryTransformer.swift:
# - QueryRephraser
# - QueryDecomposer
# - ChainedTransformer
# - HyDETransformer
```

**Keep 2 transformers**:
- QueryExpander (multi-query expansion)
- QueryRewriter (merge rephraser + decomposer)

**Implementation**:
```swift
// Merge rephrasing and decomposition into QueryRewriter
public struct QueryRewriter: QueryTransformer {
    public func transform(_ query: String) async throws -> [String] {
        // Combine rephrasing and decomposition logic
    }
}
```

### Week 3, Day 5: Consolidate Synthesizers

**Remove 2 synthesizers**:

```bash
# Files to delete
rm Sources/Zoni/Query/Synthesizers/RefineSynthesizer.swift
rm Sources/Zoni/Query/Synthesizers/TreeSummarizeSynthesizer.swift
```

**Keep 1 synthesizer + protocol**:
- CompactSynthesizer (default)
- ResponseSynthesizer (protocol for custom implementations)

---

## Phase 3: Major Restructuring (Week 4-5)

### Week 4, Day 1-3: Move ZoniServer to Separate Package

**Create new repository: `zoni-server`**

```bash
# New repository structure
zoni-server/
├── Package.swift
├── Sources/
│   └── ZoniServer/
│       ├── Abstractions/
│       ├── Jobs/
│       ├── MultiTenancy/
│       ├── Pipeline/
│       ├── VectorStore/
│       └── ZoniServer.swift
└── Tests/
    └── ZoniServerTests/
```

**Move files**:
```bash
# From zoni/Sources/ZoniServer/ to zoni-server/Sources/ZoniServer/
mv Sources/ZoniServer/Abstractions/ ../zoni-server/Sources/ZoniServer/
mv Sources/ZoniServer/Jobs/ ../zoni-server/Sources/ZoniServer/
mv Sources/ZoniServer/MultiTenancy/ ../zoni-server/Sources/ZoniServer/
mv Sources/ZoniServer/Pipeline/ ../zoni-server/Sources/ZoniServer/
mv Sources/ZoniServer/VectorStore/ ../zoni-server/Sources/ZoniServer/
mv Sources/ZoniServer/ZoniServer.swift ../zoni-server/Sources/ZoniServer/
```

**Update Package.swift**:
```swift
// Remove ZoniServer target and dependencies
// Remove PostgresNIO, NIOSSL, Crypto, Logging, Vapor, JWT, Hummingbird deps
```

**Update main Package.swift**:
```swift
// Remove ZoniServer product and target
products: [
    .library(name: "Zoni", targets: ["Zoni"]),
    .library(name: "ZoniApple", targets: ["ZoniApple"]),
    .library(name: "ZoniAgents", targets: ["ZoniAgents"]),
    .library(name: "ZoniConduit", targets: ["ZoniConduit"]),
    // REMOVED: ZoniServer
]
```

### Week 4, Day 4-5: Split ZoniApple into Stable/Experimental

**Current ZoniApple** → Split into:

1. **ZoniApple** (Production Ready):
   - NLEmbeddingProvider
   - SwiftEmbeddingsProvider
   - FoundationModelsProvider
   - GPUAcceleratedInMemoryVectorStore (if stable)

2. **ZoniAppleExperimental** (New module):
   - MLXEmbeddingProvider
   - GPUVectorStore
   - MetalVectorCompute
   - MetalSimilarityCalculator
   - ComputeBackend
   - GPUAcceleratedMMRRetriever
   - VisionOCRProcessor
   - TableExtractor
   - All MemoryStrategy types

**Create new module**:
```bash
mkdir Sources/ZoniAppleExperimental
```

**Move experimental files**:
```bash
mv Sources/ZoniApple/Embedding/MLXEmbeddingProvider.swift Sources/ZoniAppleExperimental/
mv Sources/ZoniApple/VectorStore/GPUVectorStore.swift Sources/ZoniAppleExperimental/
mv Sources/ZoniApple/Metal/ Sources/ZoniAppleExperimental/
mv Sources/ZoniApple/Retrieval/GPUAcceleratedMMRRetriever.swift Sources/ZoniAppleExperimental/
mv Sources/ZoniApple/Preprocessing/ Sources/ZoniAppleExperimental/
mv Sources/ZoniApple/VectorStore/MemoryStrategy.swift Sources/ZoniAppleExperimental/
```

**Update Package.swift**:
```swift
products: [
    // ... existing products ...
    .library(name: "ZoniAppleExperimental", targets: ["ZoniAppleExperimental"]),
]

targets: [
    .target(
        name: "ZoniAppleExperimental",
        dependencies: ["Zoni", "ZoniApple"],
        path: "Sources/ZoniAppleExperimental"
    ),
]
```

### Week 5, Day 1-2: Move Tool System to ZoniAgents

**Move files**:
```bash
# Move from Zoni to ZoniAgents
mv Sources/Zoni/Tools/ToolProtocol.swift Sources/ZoniAgents/
mv Sources/Zoni/Tools/RAGSearchTool.swift Sources/ZoniAgents/
mv Sources/Zoni/Tools/RAGIngestTool.swift Sources/ZoniAgents/
mv Sources/Zoni/Tools/RAGQueryTool.swift Sources/ZoniAgents/
mv Sources/Zoni/Tools/RAGSummarizeTool.swift Sources/ZoniAgents/
mv Sources/Zoni/Tools/MultiIndexTool.swift Sources/ZoniAgents/
```

**Delete empty directory**:
```bash
rm -rf Sources/Zoni/Tools/
```

**Update imports in moved files**:
```swift
// Add to each moved file
import Zoni
```

### Week 5, Day 3-4: Merge HTMLLoader into WebLoader

**Implementation**:

```swift
// Sources/Zoni/Loading/Loaders/WebLoader.swift
public actor WebLoader {
    // ... existing code ...
    
    /// Loads a document from a URL (file or web).
    public func load(from url: URL) async throws -> Document {
        if url.scheme?.hasPrefix("http") == true {
            return try await loadFromWeb(url)
        } else {
            return try await loadFromFile(url)
        }
    }
    
    private func loadFromWeb(_ url: URL) async throws -> Document {
        // Existing web loading logic
    }
    
    private func loadFromFile(_ url: URL) async throws -> Document {
        // Use HTMLLoader internally for HTML files
        // Use TextLoader for text files
        // etc.
    }
}
```

**Delete HTMLLoader**:
```bash
rm Sources/Zoni/Loading/Loaders/HTMLLoader.swift
```

**Update LoaderRegistry**:
```swift
// Remove HTMLLoader references
// WebLoader now handles HTML files
```

### Week 5, Day 5: Remove JSONLoader and CSVLoader

**Delete files**:
```bash
rm Sources/Zoni/Loading/Loaders/JSONLoader.swift
rm Sources/Zoni/Loading/Loaders/CSVLoader.swift
```

**Update LoaderRegistry.defaultRegistry()**:
```swift
public static func defaultRegistry() async -> LoaderRegistry {
    let registry = LoaderRegistry()
    await registry.register(TextLoader())
    await registry.register(MarkdownLoader())
    // REMOVED: HTMLLoader (merged into WebLoader)
    // REMOVED: JSONLoader
    // REMOVED: CSVLoader
    await registry.register(PDFLoader())
    return registry
}
```

---

## Phase 4: Polish & Swift 6.2 Features (Week 6)

### Day 1-2: Swift 6.2 Improvements

**Use `some` instead of `any`**:

```swift
// Before
public func observed(by observer: any AgentObserver) -> ObservedAgent

// After
public func observed(by observer: some AgentObserver) -> some AgentRuntime
```

**Parameter packs for variadic APIs**:

```swift
// Before
public func handoffs(_ targets: [any AgentRuntime]) -> Builder

// After
public func handoffs<each T: AgentRuntime>(_ targets: repeat each T) -> Builder
```

### Day 3: Improve Naming Consistency

**Standardize naming**:

```swift
// Before (inconsistent)
public actor OpenAIEmbedding
public actor OllamaEmbedding
public actor CohereEmbedding  // Being removed

// After (consistent)
// Already consistent, but verify all remaining types follow pattern
```

**Rename if needed**:
```swift
// Consider renaming for clarity
public actor NLEmbeddingProvider -> NLEmbedder
public actor SwiftEmbeddingsProvider -> SwiftEmbedder
```

### Day 4: Documentation Updates

**Update README.md**:
- [ ] Update feature list to reflect removed features
- [ ] Update installation instructions (remove ZoniServer references)
- [ ] Update quick start examples
- [ ] Add "Migration from 0.1.0" section

**Update API documentation**:
- [ ] Remove documentation for deleted types
- [ ] Add deprecation notices where applicable
- [ ] Update architecture diagrams

### Day 5: Testing & Validation

**Run full test suite**:
```bash
swift test
```

**Verify build**:
```bash
swift build
```

**Check for breaking changes**:
```bash
# Build examples
swift build --package-path Examples/AgentWithRAG
swift build --package-path Examples/iOSDocumentQA
swift build --package-path Examples/ServerRAG
```

---

## Migration Guide

### For Users of Removed Types

**JSONLoader**:
```swift
// Before
let loader = JSONLoader(contentKeyPath: "text")
let doc = try await loader.load(from: url)

// After - implement DocumentLoader
struct JSONLoader: DocumentLoader {
    static let supportedExtensions = ["json"]
    
    func load(from url: URL) async throws -> Document {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        // Extract content as needed
        return Document(content: extractedContent, metadata: metadata)
    }
}
```

**SemanticChunker**:
```swift
// Before
let chunker = SemanticChunker(embeddingProvider: embedder)

// After - use RecursiveChunker
let chunker = RecursiveChunker(
    separators: ["\n\n", "\n", ". ", " "],
    chunkSize: 1000,
    chunkOverlap: 200
)
```

**GraphRetriever**:
```swift
// Before
let graph = ChunkGraph(similarityThreshold: 0.8)
let retriever = GraphRetriever(graph: graph, ...)

// After - use MMRRetriever for diversity
let retriever = MMRRetriever(
    baseRetriever: vectorRetriever,
    lambda: 0.5
)
```

**QdrantStore/PineconeStore**:
```swift
// Before
let store = QdrantStore(url: "...", collection: "docs")

// After - implement VectorStore protocol
struct QdrantStore: VectorStore {
    // Implement required methods
}
```

---

## Rollback Plan

If critical issues arise:

1. **Week 1-2 changes**: Can be reverted via git
2. **Week 3 changes**: Can be reverted via git
3. **Week 4-5 changes**: 
   - ZoniServer can be restored from separate repo
   - Experimental features can be restored from backup
4. **Always maintain**: Working branch with all changes for easy rollback

---

## Success Metrics

**Quantitative**:
- [ ] Public types reduced from 150+ to 60-70
- [ ] Build time reduced by 20%
- [ ] Test suite passes 100%
- [ ] Examples build successfully

**Qualitative**:
- [ ] API feels focused and clear
- [ ] Documentation is concise
- [ ] New users can understand the framework in < 30 minutes
- [ ] Agents can discover correct APIs from autocomplete

---

## Post-Implementation

**Version bump**: 0.1.0 → 0.2.0 (breaking changes)

**Release notes**:
- Highlight removed features and migration paths
- Emphasize improved focus and simplicity
- Thank contributors and users for feedback

**Future roadmap**:
- Monitor usage of remaining features
- Consider further consolidation based on usage data
- Add new features only if they serve core RAG use cases

---

*This plan is designed for incremental execution with rollback capabilities at each phase.*
