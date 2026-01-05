# Apple Platforms Guide

## Overview

ZoniApple provides on-device RAG capabilities using Apple's ML frameworks. All processing happens on-device with no data leaving the user's device - perfect for privacy-first applications.

**Available Embedding Providers:**
- **NLEmbeddingProvider** - Free, on-device embeddings via NaturalLanguage framework
- **SwiftEmbeddingsProvider** - Ultra-fast Model2Vec embeddings (10x faster than BERT)
- **MLXEmbeddingProvider** - GPU-accelerated embeddings on Apple Silicon
- **FoundationModelsProvider** - iOS 26+ Foundation Models integration (future)

**Memory Strategies** - Optimized for mobile memory constraints with configurable strategies

## Installation

Add Zoni to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/zoni", from: "1.0.0")
]

targets: [
    .target(
        name: "MyApp",
        dependencies: [
            "Zoni",
            "ZoniApple"
        ]
    )
]
```

## Privacy-First RAG

All processing happens on-device - no data leaves the user's device.

```swift
import Zoni
import ZoniApple

// Completely on-device pipeline
let embedding = try NLEmbeddingProvider.english()
let vectorStore = try SQLiteVectorStore(path: documentsURL.appendingPathComponent("vectors.db"))

// No API keys needed!
try await vectorStore.add(chunks: documentChunks, using: embedding)
let results = try await vectorStore.search(query: queryEmbedding, limit: 10)
```

## Embedding Providers

### NLEmbeddingProvider (Recommended for Most Use Cases)

Free, no API key required. Uses Apple's NaturalLanguage framework.

```swift
import NaturalLanguage
import ZoniApple

// Create an English embedding provider
let embedding = try NLEmbeddingProvider.english()

// Generate single embedding
let result = try await embedding.embed("Hello, world!")
print("Dimensions: \(result.dimensions)") // 512

// Batch embedding
let texts = ["First text", "Second text", "Third text"]
let embeddings = try await embedding.embed(texts)
```

**Supported Languages**: English, Spanish, French, German, Italian, Portuguese, Chinese, Japanese, Korean, Dutch, Russian, Polish, Turkish

**Factory Methods:**
```swift
let english = try NLEmbeddingProvider.english()
let spanish = try NLEmbeddingProvider.spanish()
let french = try NLEmbeddingProvider.french()
let german = try NLEmbeddingProvider.german()
// ... and more
```

**Configuration:**
- **Dimensions**: 512 (fixed)
- **Max Tokens**: 2048 characters
- **Auto Truncate**: Enabled by default
- **Optimal Batch Size**: 50

**Check Language Availability:**
```swift
// Check all available languages on device
let available = NLEmbeddingProvider.availableLanguages()

// Check specific language
if NLEmbeddingProvider.isLanguageAvailable(.japanese) {
    let provider = try NLEmbeddingProvider(language: .japanese)
}
```

### SwiftEmbeddingsProvider (Fastest Option)

Ultra-fast Model2Vec embeddings - 10x faster than traditional BERT models.

```swift
import ZoniApple

// Create with default model (balanced performance)
let embedding = try await SwiftEmbeddingsProvider.default()

// Or choose a specific model
let retrieval = try await SwiftEmbeddingsProvider.retrieval() // Best for RAG
let fast = try await SwiftEmbeddingsProvider.fast()           // Fastest

// Custom model selection
let custom = try await SwiftEmbeddingsProvider(
    model: .potionRetrieval32M,
    normalize: true
)

// Batch embedding (extremely efficient - supports 1000+ texts)
let embeddings = try await embedding.embed(texts)
```

**Available Models:**

| Model | Dimensions | Best For |
|-------|-----------|----------|
| `.potionBase2M` | 256 | Resource-constrained devices, maximum speed |
| `.potionBase4M` | 256 | Balanced speed/quality for simple tasks |
| `.potionBase8M` | 256 | General-purpose (default) |
| `.potionBase32M` | 256 | High-quality general embeddings |
| `.potionRetrieval32M` | 256 | RAG applications, semantic search |
| `.m2vBaseOutput` | 256 | Original Model2Vec base |

**Platform Requirements**: macOS 15.0+, iOS 18.0+, tvOS 18.0+, visionOS 2.0+, watchOS 11.0+

**Configuration:**
- **Dimensions**: 256
- **Max Tokens**: 512
- **Optimal Batch Size**: 1000
- **Memory**: ~50MB per model

**First Run**: Models download from HuggingFace on first use. Ensure network connectivity for initial run.

### MLXEmbeddingProvider (Apple Silicon GPU)

GPU-accelerated embeddings using MLX framework on Apple Silicon.

**Status**: Work in progress. Current implementation uses placeholder embeddings pending full MLX integration.

```swift
@available(macOS 14.0, iOS 17.0, *)
import ZoniApple

// Check if Apple Silicon is available
guard MLXEmbeddingProvider.isAvailable else {
    print("MLX requires Apple Silicon")
    return
}

// Create with default model
let embedding = try await MLXEmbeddingProvider()

// Or specify a model
let bge = try await MLXEmbeddingProvider(model: .bgeSmallEn)

// Generate embeddings (NOTE: Currently returns pseudo-embeddings)
let result = try await embedding.embed("Hello, world!")
print("Dimensions: \(result.dimensions)") // 384
```

**Supported Models:**

| Model | Dimensions | Description |
|-------|-----------|-------------|
| `.allMiniLML6V2` | 384 | Fast, lightweight (default) |
| `.bgeSmallEn` | 384 | Optimized for English retrieval |
| `.e5SmallV2` | 384 | Excellent zero-shot performance |

**Requirements:**
- macOS 14.0+ or iOS 17.0+
- Apple Silicon (M1/M2/M3/M4)
- 500MB-2GB GPU memory

**Model Caching**: Models are cached at `~/Library/Caches/Zoni/Models/MLX/`

```swift
// Check if model is cached
if await embedding.isModelCached() {
    print("Model ready offline")
}

// Clear cache if needed
try await embedding.clearModelCache()
```

### FoundationModelsProvider (iOS 26+)

Uses Apple's on-device Foundation Models (future - iOS 26/macOS 26).

**Status**: Future-proofing stub. Framework not yet available. Will throw `AppleMLError.frameworkNotAvailable` until iOS 26 is released.

```swift
@available(iOS 26.0, macOS 26.0, *)
import ZoniApple

// Check availability first
guard FoundationModelsProvider.isAvailable else {
    print("Foundation Models not available")
    return
}

// Create provider
let embedding = try await FoundationModelsProvider()

// Generate embeddings (when available)
let result = try await embedding.embed("Analyze this text")
print("Dimensions: \(result.dimensions)") // 1024
```

**Configuration:**
- **Dimensions**: 1024
- **Max Tokens**: 2048
- **Cache Size**: Configurable (default: 1000)

**Factory Methods:**
```swift
let short = try await FoundationModelsProvider.forShortTexts()     // Cache: 500
let docs = try await FoundationModelsProvider.forDocuments()       // Cache: 2000
let strict = try await FoundationModelsProvider.strict()           // No truncation
```

## Vector Storage on Device

### SQLiteVectorStore (Recommended)

Persistent vector storage using SQLite with memory optimization strategies.

```swift
import ZoniApple

let vectorStore = try SQLiteVectorStore(
    path: documentsURL.appendingPathComponent("vectors.db")
)

// Add documents
let chunks = try await textSplitter.split(document)
try await vectorStore.add(chunks: chunks, using: embedding)

// Search with memory strategy
let strategy = HybridMemoryStrategy(cacheSize: 5000, batchSize: 500)
let results = try await vectorStore.search(
    query: queryEmbedding,
    limit: 10,
    filter: nil,
    memoryStrategy: strategy
)
```

### Memory Strategies

Choose the right strategy based on your dataset size:

| Dataset Size | Strategy | Memory Usage | Speed |
|-------------|----------|--------------|-------|
| < 10k vectors | `EagerMemoryStrategy` | High | Fastest |
| 10k - 100k | `HybridMemoryStrategy` | Medium | Fast |
| > 100k | `StreamingMemoryStrategy` | Low | Slower |

**EagerMemoryStrategy** - Load all into memory:
```swift
let strategy = EagerMemoryStrategy()
// Best for: Desktop apps, small datasets, development
```

**StreamingMemoryStrategy** - Batch processing:
```swift
let strategy = StreamingMemoryStrategy(batchSize: 2000)
// Best for: Large datasets, memory-constrained devices
// Memory: ~6MB per 1000 vectors (1536 dims)
```

**CachedMemoryStrategy** - LRU cache:
```swift
let strategy = CachedMemoryStrategy(cacheSize: 10_000)
// Best for: Repeated queries, hot/cold access patterns
// Memory: ~60MB for 10k vectors (1536 dims)
```

**HybridMemoryStrategy** - Cache + streaming (recommended):
```swift
let strategy = HybridMemoryStrategy(
    cacheSize: 5000,
    batchSize: 500
)
// Best for: Medium datasets with mixed access patterns
```

**Auto-selection**:
```swift
import ZoniApple

// Get recommended strategy based on vector count
let count = try await vectorStore.count()
let strategy = MemoryStrategyRecommendation.recommendedStrategy(
    forVectorCount: count
)

// Estimate memory usage
let memoryBytes = MemoryStrategyRecommendation.estimatedMemoryUsage(
    vectorCount: 10_000,
    dimensions: 1536
)
print("Estimated memory: \(memoryBytes / 1024 / 1024) MB") // ~60 MB
```

### In-Memory with Persistence

For maximum speed with optional persistence:

```swift
import Zoni

let vectorStore = InMemoryVectorStore()

// Add documents
try await vectorStore.add(chunks: chunks, using: embedding)

// Save to disk
let data = try await vectorStore.export()
try data.write(to: persistenceURL)

// Load from disk
let loaded = try await InMemoryVectorStore.import(from: persistenceURL)
```

## SwiftUI Integration

### Basic RAG View

```swift
import SwiftUI
import Zoni
import ZoniApple

@Observable
class RAGViewModel {
    var answer: String = ""
    var isLoading = false
    private var embedding: NLEmbeddingProvider?
    private var vectorStore: SQLiteVectorStore?

    func setup() async throws {
        embedding = try NLEmbeddingProvider.english()
        vectorStore = try SQLiteVectorStore(
            path: FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("vectors.db")
        )
    }

    func query(_ question: String) async throws {
        guard let embedding = embedding,
              let vectorStore = vectorStore else { return }

        isLoading = true
        defer { isLoading = false }

        let queryEmbedding = try await embedding.embed(question)
        let results = try await vectorStore.search(
            query: queryEmbedding,
            limit: 5
        )

        // Format results as answer
        answer = results.map(\.chunk.content).joined(separator: "\n\n")
    }
}

struct ContentView: View {
    @State private var viewModel = RAGViewModel()
    @State private var question = ""

    var body: some View {
        VStack {
            TextField("Ask a question...", text: $question)
                .textFieldStyle(.roundedBorder)
                .padding()

            Button("Search") {
                Task {
                    try? await viewModel.query(question)
                }
            }
            .disabled(viewModel.isLoading || question.isEmpty)

            if viewModel.isLoading {
                ProgressView()
            } else {
                ScrollView {
                    Text(viewModel.answer)
                        .padding()
                }
            }
        }
        .task {
            try? await viewModel.setup()
        }
    }
}
```

### Document Picker Integration

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf, .plainText, .text]
        )
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            urls.first.map(onPick)
        }
    }
}
```

## Error Handling

All ZoniApple providers use the `AppleMLError` type:

```swift
import ZoniApple

do {
    let embedding = try NLEmbeddingProvider(language: .japanese)
    let result = try await embedding.embed(longText)
} catch AppleMLError.modelNotAvailable(let name, let reason) {
    print("Model \(name) unavailable: \(reason)")
} catch AppleMLError.contextLengthExceeded(let length, let max) {
    print("Text too long: \(length) > \(max)")
} catch AppleMLError.languageNotSupported(let lang) {
    print("Language \(lang) not supported")
} catch AppleMLError.frameworkNotAvailable(let framework, let minOS) {
    print("\(framework) requires \(minOS)")
} catch AppleMLError.invalidEmbedding(let reason) {
    print("Embedding failed: \(reason)")
} catch {
    print("Unexpected error: \(error)")
}
```

**Common Error Types:**
- `modelNotAvailable` - Model not on device
- `frameworkNotAvailable` - OS version too old
- `languageNotSupported` - Language not supported
- `contextLengthExceeded` - Text too long
- `neuralEngineUnavailable` - Not on Apple Silicon
- `invalidEmbedding` - Embedding generation failed

## Platform Requirements

| Feature | iOS | macOS | tvOS | watchOS | visionOS |
|---------|-----|-------|------|---------|----------|
| NLEmbedding | 17.0+ | 14.0+ | 17.0+ | 10.0+ | 1.0+ |
| SwiftEmbeddings | 18.0+ | 15.0+ | 18.0+ | 11.0+ | 2.0+ |
| MLX | 17.0+ (arm64) | 14.0+ (arm64) | - | - | - |
| Foundation Models | 26.0+ | 26.0+ | - | - | - |
| SQLite Vector Store | 17.0+ | 14.0+ | 17.0+ | 10.0+ | 1.0+ |

## Performance Tips

### 1. Choose the Right Provider

- **SwiftEmbeddingsProvider**: Best throughput (1000+ texts/sec)
- **NLEmbeddingProvider**: Best compatibility across platforms
- **MLXEmbeddingProvider**: Best for GPU workloads (when complete)

### 2. Optimize Batch Sizes

```swift
// SwiftEmbeddings can handle very large batches
let swift = try await SwiftEmbeddingsProvider.retrieval()
let embeddings = try await swift.embed(Array(repeating: "text", count: 5000))

// NLEmbedding processes sequentially - use smaller batches
let nl = try NLEmbeddingProvider.english()
for batch in texts.chunked(into: 50) {
    let embeddings = try await nl.embed(batch)
    // Process batch
}
```

### 3. Use Appropriate Memory Strategies

```swift
// For 100k vectors, use streaming to minimize memory
let bigStore = try SQLiteVectorStore(path: bigDBPath)
let strategy = StreamingMemoryStrategy(batchSize: 1000)
let results = try await bigStore.search(
    query: query,
    limit: 10,
    memoryStrategy: strategy
)

// For 5k vectors, use eager loading for speed
let smallStore = try SQLiteVectorStore(path: smallDBPath)
let eagerStrategy = EagerMemoryStrategy()
let results = try await smallStore.search(
    query: query,
    limit: 10,
    memoryStrategy: eagerStrategy
)
```

## Next Steps

- [Getting Started Guide](GettingStarted.md) - Core Zoni concepts
- [Server Guide](ServerGuide.md) - Deploy RAG systems to servers
- [API Reference](https://zoni.dev/docs) - Complete API documentation

## Resources

- **Source Code**: [github.com/christopherkarani/zoni](https://github.com/christopherkarani/zoni)
- **Examples**: See `/Examples/ZoniApple/` in the repository
- **Issues**: Report bugs and request features on GitHub
