# Phase 2C: Embedding Providers — Plan & Prompt

## Plan Overview

**Duration:** 4-5 days
**Dependencies:** Phase 1 (Core Foundation)
**Parallelizable With:** Phase 2A, Phase 2B

### Objectives
1. Implement cloud embedding providers (OpenAI, Cohere, Voyage)
2. Implement self-hosted embedding (Ollama)
3. Add batching, rate limiting, and caching
4. Mock provider for testing

### Directory Structure
```
Sources/Zoni/Embedding/
├── Providers/
│   ├── OpenAIEmbedding.swift
│   ├── CohereEmbedding.swift
│   ├── VoyageEmbedding.swift
│   ├── OllamaEmbedding.swift
│   └── MockEmbedding.swift
├── EmbeddingCache.swift
├── BatchEmbedder.swift
└── RateLimiter.swift
```

---

# Phase 2C Prompt: Embedding Providers

You are implementing **Embedding Providers** for Zoni — integrations with various embedding APIs.

## Context

Embeddings convert text to vectors for similarity search. Different providers offer different trade-offs:
- **OpenAI:** Easy, good quality, widely used
- **Cohere:** Good multilingual support
- **Voyage:** Optimized for retrieval
- **Ollama:** Self-hosted, free, private

## Implementation Requirements

### 1. OpenAIEmbedding.swift

```swift
import AsyncHTTPClient

public actor OpenAIEmbedding: EmbeddingProvider {
    public let name = "openai"
    
    private let apiKey: String
    private let model: Model
    private let httpClient: HTTPClient
    private let rateLimiter: RateLimiter
    
    public enum Model: String, Sendable {
        case textEmbedding3Small = "text-embedding-3-small"  // 1536 dims, cheap
        case textEmbedding3Large = "text-embedding-3-large"  // 3072 dims, better
        case textEmbeddingAda002 = "text-embedding-ada-002"  // 1536 dims, legacy
    }
    
    public var dimensions: Int {
        switch model {
        case .textEmbedding3Small, .textEmbeddingAda002: return 1536
        case .textEmbedding3Large: return 3072
        }
    }
    
    public var maxTokensPerRequest: Int { 8191 }
    
    public init(
        apiKey: String,
        model: Model = .textEmbedding3Small,
        httpClient: HTTPClient? = nil
    )
    
    public func embed(_ text: String) async throws -> Embedding {
        return try await embed([text])[0]
    }
    
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        try await rateLimiter.acquire(permits: texts.count)
        
        var request = HTTPClientRequest(url: "https://api.openai.com/v1/embeddings")
        request.method = .POST
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.headers.add(name: "Content-Type", value: "application/json")
        
        let body = OpenAIEmbeddingRequest(model: model.rawValue, input: texts)
        request.body = .bytes(try JSONEncoder().encode(body))
        
        let response = try await httpClient.execute(request, timeout: .seconds(60))
        
        guard response.status == .ok else {
            let error = try? await parseError(response)
            throw ZoniError.embeddingFailed(reason: error ?? "HTTP \(response.status.code)")
        }
        
        let data = try await response.body.collect(upTo: 50 * 1024 * 1024)
        let result = try JSONDecoder().decode(OpenAIEmbeddingResponse.self, from: data)
        
        return result.data
            .sorted { $0.index < $1.index }
            .map { Embedding(vector: $0.embedding, model: model.rawValue) }
    }
}

// Request/Response types
struct OpenAIEmbeddingRequest: Codable {
    let model: String
    let input: [String]
}

struct OpenAIEmbeddingResponse: Codable {
    let data: [EmbeddingData]
    let usage: Usage
    
    struct EmbeddingData: Codable {
        let embedding: [Float]
        let index: Int
    }
    
    struct Usage: Codable {
        let promptTokens: Int
        let totalTokens: Int
    }
}
```

### 2. CohereEmbedding.swift

```swift
public actor CohereEmbedding: EmbeddingProvider {
    public let name = "cohere"
    
    private let apiKey: String
    private let model: Model
    private let inputType: InputType
    private let httpClient: HTTPClient
    
    public enum Model: String, Sendable {
        case embedEnglishV3 = "embed-english-v3.0"       // 1024 dims
        case embedMultilingualV3 = "embed-multilingual-v3.0"  // 1024 dims
        case embedEnglishLightV3 = "embed-english-light-v3.0" // 384 dims
    }
    
    public enum InputType: String, Sendable {
        case searchDocument = "search_document"
        case searchQuery = "search_query"
        case classification = "classification"
        case clustering = "clustering"
    }
    
    public var dimensions: Int {
        switch model {
        case .embedEnglishV3, .embedMultilingualV3: return 1024
        case .embedEnglishLightV3: return 384
        }
    }
    
    public var maxTokensPerRequest: Int { 96 }  // Max texts per batch
    
    public init(
        apiKey: String,
        model: Model = .embedEnglishV3,
        inputType: InputType = .searchDocument
    )
    
    public func embed(_ text: String) async throws -> Embedding
    public func embed(_ texts: [String]) async throws -> [Embedding]
    
    /// Embed for query (uses searchQuery input type)
    public func embedQuery(_ text: String) async throws -> Embedding
}
```

### 3. VoyageEmbedding.swift

Voyage AI — specifically optimized for retrieval.

```swift
public actor VoyageEmbedding: EmbeddingProvider {
    public let name = "voyage"
    
    private let apiKey: String
    private let model: Model
    private let httpClient: HTTPClient
    
    public enum Model: String, Sendable {
        case voyage2 = "voyage-2"                    // 1024 dims, general
        case voyage3 = "voyage-3"                    // 1024 dims, improved
        case voyage3Lite = "voyage-3-lite"           // 512 dims, fast
        case voyageFinance2 = "voyage-finance-2"     // Finance-specific
        case voyageCode2 = "voyage-code-2"           // Code-specific
    }
    
    public var dimensions: Int {
        switch model {
        case .voyage3Lite: return 512
        default: return 1024
        }
    }
    
    public var maxTokensPerRequest: Int { 128 }
    
    public init(apiKey: String, model: Model = .voyage2)
    
    public func embed(_ text: String) async throws -> Embedding
    public func embed(_ texts: [String]) async throws -> [Embedding]
}
```

### 4. OllamaEmbedding.swift

Self-hosted embeddings via Ollama.

```swift
public actor OllamaEmbedding: EmbeddingProvider {
    public let name = "ollama"
    
    private let baseURL: URL
    private let model: String
    private let httpClient: HTTPClient
    
    /// Common Ollama embedding models
    public enum KnownModel {
        public static let nomicEmbedText = "nomic-embed-text"     // 768 dims
        public static let allMiniLM = "all-minilm"                // 384 dims
        public static let mxbaiEmbedLarge = "mxbai-embed-large"   // 1024 dims
    }
    
    private var _dimensions: Int?
    public var dimensions: Int {
        get async {
            if let dims = _dimensions { return dims }
            // Query model info to get dimensions
            let dims = try? await queryModelDimensions()
            _dimensions = dims
            return dims ?? 768  // Default fallback
        }
    }
    
    public var maxTokensPerRequest: Int { 1 }  // Ollama processes one at a time
    
    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = KnownModel.nomicEmbedText
    )
    
    public func embed(_ text: String) async throws -> Embedding {
        var request = HTTPClientRequest(url: "\(baseURL)/api/embeddings")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        
        let body = OllamaEmbeddingRequest(model: model, prompt: text)
        request.body = .bytes(try JSONEncoder().encode(body))
        
        let response = try await httpClient.execute(request, timeout: .seconds(120))
        let data = try await response.body.collect(upTo: 10 * 1024 * 1024)
        let result = try JSONDecoder().decode(OllamaEmbeddingResponse.self, from: data)
        
        return Embedding(vector: result.embedding, model: model)
    }
    
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        // Ollama doesn't support batch, process sequentially
        var embeddings: [Embedding] = []
        for text in texts {
            embeddings.append(try await embed(text))
        }
        return embeddings
    }
    
    /// Check if Ollama is running and model is available
    public func checkAvailability() async throws -> Bool
    
    /// Pull model if not available
    public func pullModel() async throws
}

struct OllamaEmbeddingRequest: Codable {
    let model: String
    let prompt: String
}

struct OllamaEmbeddingResponse: Codable {
    let embedding: [Float]
}
```

### 5. MockEmbedding.swift

For testing without API calls.

```swift
public actor MockEmbedding: EmbeddingProvider {
    public let name = "mock"
    public let dimensions: Int
    public var maxTokensPerRequest: Int { 1000 }
    
    private var recordedTexts: [String] = []
    private var mockEmbeddings: [String: [Float]]?
    
    public init(dimensions: Int = 1536)
    
    /// Set specific embeddings to return for specific texts
    public func setMockEmbeddings(_ embeddings: [String: [Float]])
    
    public func embed(_ text: String) async throws -> Embedding {
        recordedTexts.append(text)
        
        if let mock = mockEmbeddings?[text] {
            return Embedding(vector: mock, model: "mock")
        }
        
        // Generate deterministic random embedding based on text hash
        return Embedding(vector: generateDeterministic(text), model: "mock")
    }
    
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        return try await texts.asyncMap { try await embed($0) }
    }
    
    /// Get all texts that were embedded
    public func getRecordedTexts() -> [String] {
        recordedTexts
    }
    
    public func reset() {
        recordedTexts = []
    }
    
    private func generateDeterministic(_ text: String) -> [Float] {
        var hasher = Hasher()
        hasher.combine(text)
        let seed = hasher.finalize()
        
        var rng = RandomNumberGenerator(seed: UInt64(bitPattern: Int64(seed)))
        return (0..<dimensions).map { _ in Float.random(in: -1...1, using: &rng) }
    }
}
```

### 6. EmbeddingCache.swift

Cache embeddings to avoid redundant API calls.

```swift
public actor EmbeddingCache {
    private var cache: [String: CacheEntry] = [:]
    private let maxSize: Int
    private let ttl: Duration?
    
    struct CacheEntry {
        let embedding: Embedding
        let timestamp: Date
    }
    
    public init(maxSize: Int = 10000, ttl: Duration? = nil)
    
    public func get(_ text: String) -> Embedding?
    public func set(_ text: String, embedding: Embedding)
    public func clear()
    
    /// Wrap an embedding provider with caching
    public func cached(_ provider: any EmbeddingProvider) -> CachedEmbeddingProvider
    
    // LRU eviction
    private func evictIfNeeded()
}

public actor CachedEmbeddingProvider: EmbeddingProvider {
    private let wrapped: any EmbeddingProvider
    private let cache: EmbeddingCache
    
    public var name: String { "cached_\(wrapped.name)" }
    public var dimensions: Int { wrapped.dimensions }
    public var maxTokensPerRequest: Int { wrapped.maxTokensPerRequest }
    
    public func embed(_ text: String) async throws -> Embedding {
        if let cached = await cache.get(text) {
            return cached
        }
        let embedding = try await wrapped.embed(text)
        await cache.set(text, embedding: embedding)
        return embedding
    }
    
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        // Check cache first, only embed uncached texts
        var results: [Embedding?] = texts.map { await cache.get($0) }
        let uncachedIndices = results.indices.filter { results[$0] == nil }
        let uncachedTexts = uncachedIndices.map { texts[$0] }
        
        if !uncachedTexts.isEmpty {
            let newEmbeddings = try await wrapped.embed(uncachedTexts)
            for (index, embedding) in zip(uncachedIndices, newEmbeddings) {
                results[index] = embedding
                await cache.set(texts[index], embedding: embedding)
            }
        }
        
        return results.compactMap { $0 }
    }
}
```

### 7. BatchEmbedder.swift

Handle batch processing with chunking.

```swift
public actor BatchEmbedder {
    private let provider: any EmbeddingProvider
    private let batchSize: Int
    private let maxConcurrency: Int
    
    public init(
        provider: any EmbeddingProvider,
        batchSize: Int? = nil,  // nil = use provider max
        maxConcurrency: Int = 3
    )
    
    /// Embed large number of texts efficiently
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        let batches = texts.chunked(into: batchSize ?? provider.maxTokensPerRequest)
        
        return try await withThrowingTaskGroup(of: (Int, [Embedding]).self) { group in
            var results: [(Int, [Embedding])] = []
            var batchIndex = 0
            
            for batch in batches {
                let index = batchIndex
                group.addTask {
                    let embeddings = try await self.provider.embed(batch)
                    return (index, embeddings)
                }
                batchIndex += 1
                
                // Limit concurrency
                if group.count >= maxConcurrency {
                    if let result = try await group.next() {
                        results.append(result)
                    }
                }
            }
            
            // Collect remaining
            for try await result in group {
                results.append(result)
            }
            
            return results
                .sorted { $0.0 < $1.0 }
                .flatMap { $0.1 }
        }
    }
    
    /// Stream embeddings as they complete
    public func embedStream(_ texts: [String]) -> AsyncThrowingStream<(Int, Embedding), Error>
}
```

### 8. RateLimiter.swift

Token bucket rate limiting.

```swift
public actor RateLimiter {
    private let tokensPerSecond: Double
    private let bucketSize: Int
    private var tokens: Double
    private var lastRefill: Date
    
    public init(tokensPerSecond: Double, bucketSize: Int? = nil) {
        self.tokensPerSecond = tokensPerSecond
        self.bucketSize = bucketSize ?? Int(tokensPerSecond * 2)
        self.tokens = Double(self.bucketSize)
        self.lastRefill = Date()
    }
    
    /// Acquire permits, waiting if necessary
    public func acquire(permits: Int = 1) async throws {
        refill()
        
        while tokens < Double(permits) {
            let waitTime = (Double(permits) - tokens) / tokensPerSecond
            try await Task.sleep(for: .seconds(waitTime))
            refill()
        }
        
        tokens -= Double(permits)
    }
    
    /// Try to acquire without waiting
    public func tryAcquire(permits: Int = 1) -> Bool {
        refill()
        if tokens >= Double(permits) {
            tokens -= Double(permits)
            return true
        }
        return false
    }
    
    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        tokens = min(Double(bucketSize), tokens + elapsed * tokensPerSecond)
        lastRefill = now
    }
    
    /// Create rate limiter for common providers
    public static func forOpenAI() -> RateLimiter {
        RateLimiter(tokensPerSecond: 3000, bucketSize: 10000)  // 3000 RPM
    }
    
    public static func forCohere() -> RateLimiter {
        RateLimiter(tokensPerSecond: 100, bucketSize: 1000)
    }
}
```

## Tests

### EmbeddingTests.swift
- Test OpenAI embedding dimensions
- Test batch processing
- Test caching behavior
- Test rate limiting delays
- Test mock deterministic output

## Code Standards

- All providers are actors (thread-safe)
- Never log API keys
- Handle rate limit errors gracefully
- Support cancellation

## Verification

```bash
swift build
swift test --filter Embedding
```
