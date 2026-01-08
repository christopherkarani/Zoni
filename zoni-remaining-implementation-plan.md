# Zoni Remaining Implementation Plan

## Version 1.1 & 1.2 Roadmap

**Author:** Christopher Karani  
**Date:** January 2026  
**Current Version:** 1.0.0  
**Target Versions:** 1.1.0 (4 weeks), 1.2.0 (6 weeks)

---

## Executive Summary

Zoni 1.0 is feature-complete for core RAG functionality. The remaining work focuses on:

| Version | Focus | Timeline |
|---------|-------|----------|
| **1.1.0** | Context Optimization + More Providers | 4 weeks |
| **1.2.0** | Advanced Retrieval + Evaluation | 6 weeks |

### Feature Priority Matrix

| Feature | Priority | Complexity | Value |
|---------|----------|------------|-------|
| ParentChildChunker | P0 | Medium | High (4K context) |
| HuggingFace Embeddings | P0 | Low | High |
| Evaluation Framework | P1 | High | High |
| OCR/Table Extraction | P1 | Medium | Medium |
| Graph Retrieval | P2 | High | Medium |
| Milvus/Weaviate | P2 | Medium | Medium |
| Fine-tuning Integration | P3 | High | Low |

---

## Version 1.1.0: Context Optimization & Providers

**Timeline:** 4 weeks  
**Theme:** Better context management for 4K LLMs + expanded provider support

### Week 1-2: ParentChildChunker

#### Rationale
Critical for 4K context windows (Apple Foundation Models, Claude Haiku):
- Embed **small children** for precise matching
- Retrieve **large parents** for full context
- Maximizes information per token

#### Implementation

```swift
// Sources/Zoni/Chunking/Strategies/ParentChildChunker.swift

import Foundation

/// A chunking strategy that creates hierarchical parent-child relationships.
///
/// `ParentChildChunker` is optimized for constrained context windows (4K tokens).
/// It creates small child chunks for precise embedding matches, then returns
/// the larger parent chunk for context-rich retrieval.
///
/// ## How It Works
///
/// 1. Split document into large **parent** chunks (e.g., 2000 chars)
/// 2. Split each parent into small **child** chunks (e.g., 400 chars)
/// 3. Embed only the children for precise similarity matching
/// 4. On retrieval, return the parent for richer context
///
/// ## Example
///
/// ```swift
/// let chunker = ParentChildChunker(
///     parentSize: 2000,
///     childSize: 400,
///     childOverlap: 50
/// )
///
/// let chunks = chunker.chunk(document)
/// // Returns both parents and children with relationships
///
/// // At retrieval time:
/// let parentRetriever = ParentChildRetriever(
///     childStore: childVectorStore,
///     parentStore: parentVectorStore
/// )
/// let results = try await parentRetriever.retrieve(query: "...", limit: 5)
/// // Returns parent chunks based on child matches
/// ```
public struct ParentChildChunker: ChunkingStrategy {
    
    // MARK: - Configuration
    
    /// Size of parent chunks in characters.
    public let parentSize: Int
    
    /// Size of child chunks in characters.
    public let childSize: Int
    
    /// Overlap between consecutive child chunks.
    public let childOverlap: Int
    
    /// Separator for splitting into parents (default: paragraph breaks).
    public let parentSeparator: String
    
    /// Whether to include parent chunks in the output.
    public let includeParentsInOutput: Bool
    
    // MARK: - Initialization
    
    /// Creates a new parent-child chunker.
    ///
    /// - Parameters:
    ///   - parentSize: Target size for parent chunks. Default: 2000 characters.
    ///   - childSize: Target size for child chunks. Default: 400 characters.
    ///   - childOverlap: Overlap between children. Default: 50 characters.
    ///   - parentSeparator: Separator for parent splitting. Default: "\n\n".
    ///   - includeParentsInOutput: Whether to output parent chunks. Default: true.
    public init(
        parentSize: Int = 2000,
        childSize: Int = 400,
        childOverlap: Int = 50,
        parentSeparator: String = "\n\n",
        includeParentsInOutput: Bool = true
    ) {
        precondition(parentSize > childSize, "Parent size must be larger than child size")
        precondition(childSize > childOverlap, "Child size must be larger than overlap")
        
        self.parentSize = parentSize
        self.childSize = childSize
        self.childOverlap = childOverlap
        self.parentSeparator = parentSeparator
        self.includeParentsInOutput = includeParentsInOutput
    }
    
    // MARK: - ChunkingStrategy
    
    public func chunk(_ document: Document) -> [Chunk] {
        var allChunks: [Chunk] = []
        
        // Phase 1: Create parent chunks
        let parentChunks = createParentChunks(from: document)
        
        // Phase 2: Create child chunks for each parent
        for (parentIndex, parent) in parentChunks.enumerated() {
            let children = createChildChunks(
                from: parent,
                parentIndex: parentIndex,
                document: document
            )
            
            // Add children (always)
            allChunks.append(contentsOf: children)
            
            // Add parent with child references (optional)
            if includeParentsInOutput {
                var parentWithRefs = parent
                parentWithRefs.metadata.custom["childIds"] = .array(
                    children.map { .string($0.id) }
                )
                parentWithRefs.metadata.custom["isParent"] = .bool(true)
                parentWithRefs.metadata.custom["childCount"] = .int(children.count)
                allChunks.append(parentWithRefs)
            }
        }
        
        return allChunks
    }
    
    // MARK: - Private Methods
    
    private func createParentChunks(from document: Document) -> [Chunk] {
        let text = document.content
        var chunks: [Chunk] = []
        var currentContent = ""
        var currentStart = 0
        
        let paragraphs = text.components(separatedBy: parentSeparator)
        
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let potentialContent = currentContent.isEmpty 
                ? trimmed 
                : currentContent + parentSeparator + trimmed
            
            if potentialContent.count <= parentSize {
                currentContent = potentialContent
            } else {
                // Flush current chunk
                if !currentContent.isEmpty {
                    chunks.append(createChunk(
                        content: currentContent,
                        documentId: document.id,
                        index: chunks.count,
                        startOffset: currentStart,
                        source: document.source?.description,
                        isParent: true
                    ))
                    currentStart += currentContent.count + parentSeparator.count
                }
                currentContent = trimmed
            }
        }
        
        // Don't forget the last chunk
        if !currentContent.isEmpty {
            chunks.append(createChunk(
                content: currentContent,
                documentId: document.id,
                index: chunks.count,
                startOffset: currentStart,
                source: document.source?.description,
                isParent: true
            ))
        }
        
        return chunks
    }
    
    private func createChildChunks(
        from parent: Chunk,
        parentIndex: Int,
        document: Document
    ) -> [Chunk] {
        let text = parent.content
        var children: [Chunk] = []
        var position = 0
        
        while position < text.count {
            let endPosition = min(position + childSize, text.count)
            let startIdx = text.index(text.startIndex, offsetBy: position)
            let endIdx = text.index(text.startIndex, offsetBy: endPosition)
            
            let content = String(text[startIdx..<endIdx])
            
            let child = Chunk(
                content: content,
                metadata: ChunkMetadata(
                    documentId: document.id,
                    index: children.count,
                    startOffset: parent.metadata.startOffset + position,
                    endOffset: parent.metadata.startOffset + endPosition,
                    source: parent.metadata.source,
                    custom: [
                        "isChild": .bool(true),
                        "parentId": .string(parent.id),
                        "parentIndex": .int(parentIndex),
                        "positionInParent": .int(position)
                    ]
                )
            )
            
            children.append(child)
            position += childSize - childOverlap
            
            // Prevent infinite loop
            if position <= children.last!.metadata.startOffset - parent.metadata.startOffset {
                break
            }
        }
        
        return children
    }
    
    private func createChunk(
        content: String,
        documentId: String,
        index: Int,
        startOffset: Int,
        source: String?,
        isParent: Bool
    ) -> Chunk {
        Chunk(
            content: content,
            metadata: ChunkMetadata(
                documentId: documentId,
                index: index,
                startOffset: startOffset,
                endOffset: startOffset + content.count,
                source: source,
                custom: isParent ? ["isParent": .bool(true)] : [:]
            )
        )
    }
}

// MARK: - CustomStringConvertible

extension ParentChildChunker: CustomStringConvertible {
    public var description: String {
        "ParentChildChunker(parent: \(parentSize), child: \(childSize), overlap: \(childOverlap))"
    }
}
```

#### ParentChildRetriever

```swift
// Sources/Zoni/Retrieval/Retrievers/ParentChildRetriever.swift

import Foundation

/// A retriever that matches on child chunks but returns parent chunks.
///
/// This retriever is designed to work with `ParentChildChunker` to provide
/// precise matching (via children) with rich context (via parents).
///
/// ## Architecture
///
/// ```
/// Query → Embed → Search Children → Map to Parents → Return Parents
/// ```
///
/// ## Example
///
/// ```swift
/// let retriever = ParentChildRetriever(
///     embeddingProvider: openAI,
///     childStore: childVectorStore,
///     parentLookup: parentLookup  // id -> Chunk
/// )
///
/// let results = try await retriever.retrieve(
///     query: "What are Swift actors?",
///     limit: 3
/// )
/// // Returns up to 3 parent chunks based on best child matches
/// ```
public actor ParentChildRetriever: Retriever {
    
    // MARK: - Properties
    
    public nonisolated let name = "parent-child"
    
    private let embeddingProvider: any EmbeddingProvider
    private let childStore: any VectorStore
    private let parentLookup: ParentLookup
    
    /// How many children to fetch per desired parent.
    private let childMultiplier: Int
    
    /// Aggregation method for multiple child matches to same parent.
    public enum ScoreAggregation: Sendable {
        case max       // Use highest child score
        case average   // Average all child scores
        case sum       // Sum all child scores (rewards multiple matches)
    }
    
    private let aggregation: ScoreAggregation
    
    // MARK: - Parent Lookup Protocol
    
    /// Protocol for looking up parent chunks by ID.
    public protocol ParentLookup: Sendable {
        func parent(forId id: String) async throws -> Chunk?
    }
    
    // MARK: - Initialization
    
    /// Creates a new parent-child retriever.
    ///
    /// - Parameters:
    ///   - embeddingProvider: Provider for query embeddings.
    ///   - childStore: Vector store containing child chunk embeddings.
    ///   - parentLookup: Lookup mechanism for parent chunks.
    ///   - childMultiplier: How many children to fetch per parent. Default: 3.
    ///   - aggregation: How to aggregate multiple child scores. Default: `.max`.
    public init(
        embeddingProvider: any EmbeddingProvider,
        childStore: any VectorStore,
        parentLookup: ParentLookup,
        childMultiplier: Int = 3,
        aggregation: ScoreAggregation = .max
    ) {
        self.embeddingProvider = embeddingProvider
        self.childStore = childStore
        self.parentLookup = parentLookup
        self.childMultiplier = childMultiplier
        self.aggregation = aggregation
    }
    
    // MARK: - Retriever Protocol
    
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // 1. Embed the query
        let queryEmbedding = try await embeddingProvider.embed(query)
        
        // 2. Search children (fetch more to account for multiple children per parent)
        let childLimit = limit * childMultiplier
        let childFilter = combineFilter(filter, with: .equals("isChild", .bool(true)))
        
        let childResults = try await childStore.search(
            query: queryEmbedding,
            limit: childLimit,
            filter: childFilter
        )
        
        // 3. Group by parent and aggregate scores
        var parentScores: [String: (score: Float, children: [RetrievalResult])] = [:]
        
        for child in childResults {
            guard let parentId = child.metadata["parentId"]?.stringValue else {
                continue
            }
            
            if var existing = parentScores[parentId] {
                existing.children.append(child)
                existing.score = aggregateScore(existing.score, child.score)
                parentScores[parentId] = existing
            } else {
                parentScores[parentId] = (score: child.score, children: [child])
            }
        }
        
        // 4. Sort by aggregated score and limit
        let sortedParentIds = parentScores
            .sorted { $0.value.score > $1.value.score }
            .prefix(limit)
            .map { $0.key }
        
        // 5. Fetch parent chunks
        var results: [RetrievalResult] = []
        
        for parentId in sortedParentIds {
            guard let parentChunk = try await parentLookup.parent(forId: parentId),
                  let scoreData = parentScores[parentId] else {
                continue
            }
            
            // Add child match info to metadata
            var metadata = parentChunk.metadata.custom
            metadata["matchedChildren"] = .int(scoreData.children.count)
            metadata["bestChildScore"] = .double(Double(scoreData.children.map(\.score).max() ?? 0))
            
            results.append(RetrievalResult(
                chunk: parentChunk,
                score: scoreData.score,
                metadata: metadata
            ))
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func aggregateScore(_ existing: Float, _ new: Float) -> Float {
        switch aggregation {
        case .max:
            return max(existing, new)
        case .average:
            // Note: This is a running average approximation
            return (existing + new) / 2
        case .sum:
            return existing + new
        }
    }
    
    private func combineFilter(_ base: MetadataFilter?, with additional: MetadataFilter) -> MetadataFilter {
        if let base = base {
            return .and([base, additional])
        }
        return additional
    }
}

// MARK: - Vector Store Parent Lookup

/// A parent lookup backed by a vector store.
public actor VectorStoreParentLookup: ParentChildRetriever.ParentLookup {
    private let store: any VectorStore
    private var cache: [String: Chunk] = [:]
    
    public init(store: any VectorStore) {
        self.store = store
    }
    
    public func parent(forId id: String) async throws -> Chunk? {
        if let cached = cache[id] {
            return cached
        }
        
        // Search by ID filter
        let results = try await store.search(
            query: Embedding(vector: [], model: nil), // Dummy, not used with ID filter
            limit: 1,
            filter: .equals("id", .string(id))
        )
        
        if let result = results.first {
            cache[id] = result.chunk
            return result.chunk
        }
        
        return nil
    }
    
    public func preloadParents(_ ids: [String]) async throws {
        // Bulk load for efficiency
        for id in ids where cache[id] == nil {
            _ = try await parent(forId: id)
        }
    }
}
```

#### Tests

```swift
// Tests/ZoniTests/ParentChildChunkerTests.swift

import XCTest
@testable import Zoni

final class ParentChildChunkerTests: XCTestCase {
    
    func testBasicChunking() {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )
        
        let document = Document(
            content: String(repeating: "Hello world. ", count: 50), // ~650 chars
            metadata: DocumentMetadata()
        )
        
        let chunks = chunker.chunk(document)
        
        // Should have both parents and children
        let parents = chunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
        let children = chunks.filter { $0.metadata.custom["isChild"]?.boolValue == true }
        
        XCTAssertGreaterThan(parents.count, 0, "Should have parent chunks")
        XCTAssertGreaterThan(children.count, parents.count, "Should have more children than parents")
        
        // Each child should reference a parent
        for child in children {
            XCTAssertNotNil(child.metadata.custom["parentId"], "Child should have parentId")
        }
    }
    
    func testParentChildRelationships() {
        let chunker = ParentChildChunker(
            parentSize: 100,
            childSize: 30,
            childOverlap: 5
        )
        
        let document = Document(
            content: "First paragraph content here.\n\nSecond paragraph content here.",
            metadata: DocumentMetadata()
        )
        
        let chunks = chunker.chunk(document)
        let parents = chunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
        
        for parent in parents {
            if let childIds = parent.metadata.custom["childIds"]?.arrayValue {
                XCTAssertGreaterThan(childIds.count, 0, "Parent should have children")
            }
        }
    }
    
    func testChildOverlap() {
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 100,
            childOverlap: 20
        )
        
        let document = Document(
            content: String(repeating: "x", count: 300),
            metadata: DocumentMetadata()
        )
        
        let chunks = chunker.chunk(document)
        let children = chunks.filter { $0.metadata.custom["isChild"]?.boolValue == true }
        
        // With 300 chars, 100 child size, 20 overlap:
        // positions: 0, 80, 160, 240 = 4 children
        XCTAssertEqual(children.count, 4, "Should have correct number of overlapping children")
    }
}
```

---

### Week 2-3: Additional Embedding Providers

#### HuggingFace Inference API

```swift
// Sources/Zoni/Embedding/Providers/HuggingFaceEmbedding.swift

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Embedding provider using HuggingFace Inference API.
///
/// Supports any embedding model hosted on HuggingFace Hub:
/// - `sentence-transformers/all-MiniLM-L6-v2` (384 dims)
/// - `BAAI/bge-large-en-v1.5` (1024 dims)
/// - `intfloat/multilingual-e5-large` (1024 dims)
///
/// ## Example
///
/// ```swift
/// let embedding = HuggingFaceEmbedding(
///     apiKey: "hf_...",
///     model: "sentence-transformers/all-MiniLM-L6-v2"
/// )
///
/// let vector = try await embedding.embed("Hello world")
/// ```
public actor HuggingFaceEmbedding: EmbeddingProvider {
    
    // MARK: - Properties
    
    public nonisolated let name = "huggingface"
    public nonisolated let dimensions: Int
    public nonisolated var maxTokensPerRequest: Int { 512 }
    public nonisolated var optimalBatchSize: Int { 32 }
    
    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let session: URLSession
    
    // MARK: - Common Models
    
    public enum Model: String, Sendable {
        case miniLM = "sentence-transformers/all-MiniLM-L6-v2"
        case bgeLargeEN = "BAAI/bge-large-en-v1.5"
        case bgeBaseEN = "BAAI/bge-base-en-v1.5"
        case e5Large = "intfloat/e5-large-v2"
        case multilingualE5 = "intfloat/multilingual-e5-large"
        case jina = "jinaai/jina-embeddings-v2-base-en"
        
        public var dimensions: Int {
            switch self {
            case .miniLM: return 384
            case .bgeLargeEN, .e5Large, .multilingualE5: return 1024
            case .bgeBaseEN: return 768
            case .jina: return 768
            }
        }
    }
    
    // MARK: - Initialization
    
    /// Creates a HuggingFace embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: HuggingFace API key.
    ///   - model: Model enum for common models.
    public init(apiKey: String, model: Model) {
        self.apiKey = apiKey
        self.model = model.rawValue
        self.dimensions = model.dimensions
        self.baseURL = URL(string: "https://api-inference.huggingface.co/pipeline/feature-extraction/\(model.rawValue)")!
        self.session = URLSession.shared
    }
    
    /// Creates a HuggingFace embedding provider with a custom model.
    ///
    /// - Parameters:
    ///   - apiKey: HuggingFace API key.
    ///   - modelId: Full model ID (e.g., "username/model-name").
    ///   - dimensions: Output embedding dimensions.
    public init(apiKey: String, modelId: String, dimensions: Int) {
        self.apiKey = apiKey
        self.model = modelId
        self.dimensions = dimensions
        self.baseURL = URL(string: "https://api-inference.huggingface.co/pipeline/feature-extraction/\(modelId)")!
        self.session = URLSession.shared
    }
    
    // MARK: - EmbeddingProvider
    
    public func embed(_ text: String) async throws -> Embedding {
        let embeddings = try await embed([text])
        guard let first = embeddings.first else {
            throw ZoniError.embeddingFailed(reason: "No embedding returned")
        }
        return first
    }
    
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "inputs": texts,
            "options": ["wait_for_model": true]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoniError.embeddingFailed(reason: "Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ZoniError.embeddingFailed(
                reason: "HuggingFace API error (\(httpResponse.statusCode)): \(errorMessage)"
            )
        }
        
        // Parse response - HF returns [[Float]] for batch
        let decoded = try JSONDecoder().decode([[Float]].self, from: data)
        
        return decoded.map { vector in
            Embedding(vector: vector, model: model)
        }
    }
}
```

#### Mistral Embeddings

```swift
// Sources/Zoni/Embedding/Providers/MistralEmbedding.swift

import Foundation

/// Embedding provider using Mistral AI API.
///
/// Supports Mistral's embedding models:
/// - `mistral-embed` (1024 dimensions)
///
/// ## Example
///
/// ```swift
/// let embedding = MistralEmbedding(apiKey: "...")
/// let vector = try await embedding.embed("Hello world")
/// ```
public actor MistralEmbedding: EmbeddingProvider {
    
    // MARK: - Properties
    
    public nonisolated let name = "mistral"
    public nonisolated let dimensions: Int = 1024
    public nonisolated var maxTokensPerRequest: Int { 8192 }
    public nonisolated var optimalBatchSize: Int { 32 }
    
    private let apiKey: String
    private let model: String
    private let baseURL: URL
    
    // MARK: - Initialization
    
    public init(
        apiKey: String,
        model: String = "mistral-embed"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = URL(string: "https://api.mistral.ai/v1/embeddings")!
    }
    
    // MARK: - EmbeddingProvider
    
    public func embed(_ text: String) async throws -> Embedding {
        let embeddings = try await embed([text])
        guard let first = embeddings.first else {
            throw ZoniError.embeddingFailed(reason: "No embedding returned")
        }
        return first
    }
    
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "input": texts
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ZoniError.embeddingFailed(reason: "Mistral API error")
        }
        
        struct MistralResponse: Decodable {
            struct EmbeddingData: Decodable {
                let embedding: [Float]
                let index: Int
            }
            let data: [EmbeddingData]
        }
        
        let decoded = try JSONDecoder().decode(MistralResponse.self, from: data)
        
        // Sort by index to maintain order
        let sorted = decoded.data.sorted { $0.index < $1.index }
        
        return sorted.map { item in
            Embedding(vector: item.embedding, model: model)
        }
    }
}
```

---

### Week 3-4: Document Preprocessing

#### OCR Integration (Vision Framework)

```swift
// Sources/ZoniApple/Preprocessing/OCRProcessor.swift

#if canImport(Vision)
import Vision
import Foundation

/// OCR processor using Apple's Vision framework.
///
/// Extracts text from images within documents (PDFs, images).
///
/// ## Example
///
/// ```swift
/// let ocr = VisionOCRProcessor(languages: [.english, .spanish])
/// let text = try await ocr.extractText(from: imageURL)
/// ```
@available(macOS 10.15, iOS 13.0, *)
public actor VisionOCRProcessor {
    
    // MARK: - Properties
    
    private let languages: [String]
    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let usesLanguageCorrection: Bool
    
    // MARK: - Initialization
    
    public init(
        languages: [String] = ["en-US"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true
    ) {
        self.languages = languages
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
    }
    
    // MARK: - Public Methods
    
    /// Extracts text from an image file.
    public func extractText(from imageURL: URL) async throws -> String {
        guard let image = loadImage(from: imageURL) else {
            throw ZoniError.loadingFailed(reason: "Failed to load image")
        }
        
        return try await extractText(from: image)
    }
    
    /// Extracts text from a CGImage.
    public func extractText(from image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = recognitionLevel
            request.usesLanguageCorrection = usesLanguageCorrection
            request.recognitionLanguages = languages
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Extracts text from all pages of a PDF.
    public func extractTextFromPDF(at url: URL) async throws -> [String] {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw ZoniError.loadingFailed(reason: "Failed to open PDF")
        }
        
        var pageTexts: [String] = []
        
        for pageIndex in 1...document.numberOfPages {
            guard let page = document.page(at: pageIndex) else { continue }
            
            if let image = renderPDFPage(page) {
                let text = try await extractText(from: image)
                pageTexts.append(text)
            }
        }
        
        return pageTexts
    }
    
    // MARK: - Private Methods
    
    private func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
    
    private func renderPDFPage(_ page: CGPDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let pageRect = page.getBoxRect(.mediaBox)
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        
        return context.makeImage()
    }
}
#endif
```

#### Table Extraction

```swift
// Sources/ZoniApple/Preprocessing/TableExtractor.swift

#if canImport(Vision)
import Vision
import Foundation

/// Extracts tables from document images using Vision framework.
@available(macOS 13.0, iOS 16.0, *)
public actor TableExtractor {
    
    // MARK: - Types
    
    public struct ExtractedTable: Sendable {
        public let rows: [[String]]
        public let boundingBox: CGRect
        public let confidence: Float
        
        public var markdown: String {
            guard let firstRow = rows.first, !firstRow.isEmpty else {
                return ""
            }
            
            var lines: [String] = []
            
            // Header
            lines.append("| " + firstRow.joined(separator: " | ") + " |")
            lines.append("| " + firstRow.map { _ in "---" }.joined(separator: " | ") + " |")
            
            // Body
            for row in rows.dropFirst() {
                lines.append("| " + row.joined(separator: " | ") + " |")
            }
            
            return lines.joined(separator: "\n")
        }
        
        public var csv: String {
            rows.map { row in
                row.map { cell in
                    // Escape quotes and wrap in quotes if contains comma
                    let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
                    return cell.contains(",") ? "\"\(escaped)\"" : escaped
                }.joined(separator: ",")
            }.joined(separator: "\n")
        }
    }
    
    // MARK: - Public Methods
    
    public func extractTables(from image: CGImage) async throws -> [ExtractedTable] {
        // Use Vision's document detection for table regions
        let observations = try await detectDocumentRegions(in: image)
        
        var tables: [ExtractedTable] = []
        
        for observation in observations {
            if let table = try await extractTableFromRegion(observation, in: image) {
                tables.append(table)
            }
        }
        
        return tables
    }
    
    // MARK: - Private Methods
    
    private func detectDocumentRegions(in image: CGImage) async throws -> [VNRectangleObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let observations = request.results as? [VNRectangleObservation] ?? []
                continuation.resume(returning: observations)
            }
            
            request.minimumAspectRatio = 0.1
            request.maximumAspectRatio = 10.0
            request.minimumSize = 0.1
            request.maximumObservations = 10
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func extractTableFromRegion(
        _ region: VNRectangleObservation,
        in image: CGImage
    ) async throws -> ExtractedTable? {
        // Crop image to region
        let bounds = region.boundingBox
        let x = Int(bounds.minX * CGFloat(image.width))
        let y = Int((1 - bounds.maxY) * CGFloat(image.height))
        let width = Int(bounds.width * CGFloat(image.width))
        let height = Int(bounds.height * CGFloat(image.height))
        
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else {
            return nil
        }
        
        // Extract text with positions
        let textObservations = try await recognizeText(in: cropped)
        
        // Group into rows based on Y position
        let rows = groupIntoRows(textObservations)
        
        guard !rows.isEmpty else { return nil }
        
        return ExtractedTable(
            rows: rows,
            boundingBox: bounds,
            confidence: region.confidence
        )
    }
    
    private func recognizeText(in image: CGImage) async throws -> [(String, CGRect)] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let results = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { observation -> (String, CGRect)? in
                        guard let text = observation.topCandidates(1).first?.string else {
                            return nil
                        }
                        return (text, observation.boundingBox)
                    }
                
                continuation.resume(returning: results)
            }
            
            request.recognitionLevel = .accurate
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func groupIntoRows(_ observations: [(String, CGRect)]) -> [[String]] {
        guard !observations.isEmpty else { return [] }
        
        // Sort by Y (top to bottom), then X (left to right)
        let sorted = observations.sorted { a, b in
            let yDiff = abs(a.1.midY - b.1.midY)
            if yDiff < 0.02 { // Same row threshold
                return a.1.minX < b.1.minX
            }
            return a.1.midY > b.1.midY // Vision coordinates are bottom-up
        }
        
        var rows: [[String]] = []
        var currentRow: [String] = []
        var lastY: CGFloat = sorted.first!.1.midY
        
        for (text, rect) in sorted {
            if abs(rect.midY - lastY) > 0.02 {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                }
                currentRow = [text]
            } else {
                currentRow.append(text)
            }
            lastY = rect.midY
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
}
#endif
```

---

## Version 1.2.0: Advanced Retrieval & Evaluation

**Timeline:** 6 weeks (after 1.1.0)  
**Theme:** Graph retrieval, distributed stores, and quality metrics

### Week 1-2: Graph-Based Retrieval

```swift
// Sources/Zoni/Retrieval/Retrievers/GraphRetriever.swift

import Foundation

/// A retriever that uses graph relationships between chunks.
///
/// `GraphRetriever` builds a knowledge graph from chunk relationships
/// and traverses it during retrieval for contextually connected results.
///
/// ## Graph Construction
///
/// Chunks are connected via:
/// - **Sequential edges**: Adjacent chunks in same document
/// - **Semantic edges**: High similarity between chunks
/// - **Reference edges**: Explicit references (citations, links)
///
/// ## Example
///
/// ```swift
/// let graph = ChunkGraph()
/// await graph.addDocument(chunks, embeddings: embeddings)
///
/// let retriever = GraphRetriever(
///     graph: graph,
///     embeddingProvider: embedding,
///     hops: 2  // Traverse up to 2 edges
/// )
///
/// let results = try await retriever.retrieve(query: "...", limit: 10)
/// ```
public actor GraphRetriever: Retriever {
    
    // MARK: - Properties
    
    public nonisolated let name = "graph"
    
    private let graph: ChunkGraph
    private let embeddingProvider: any EmbeddingProvider
    private let vectorStore: any VectorStore
    private let hops: Int
    private let edgeWeightThreshold: Float
    
    // MARK: - Initialization
    
    public init(
        graph: ChunkGraph,
        embeddingProvider: any EmbeddingProvider,
        vectorStore: any VectorStore,
        hops: Int = 2,
        edgeWeightThreshold: Float = 0.7
    ) {
        self.graph = graph
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
        self.hops = hops
        self.edgeWeightThreshold = edgeWeightThreshold
    }
    
    // MARK: - Retriever Protocol
    
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // 1. Get initial seed results via vector search
        let queryEmbedding = try await embeddingProvider.embed(query)
        let seedLimit = max(3, limit / 2)
        
        let seedResults = try await vectorStore.search(
            query: queryEmbedding,
            limit: seedLimit,
            filter: filter
        )
        
        // 2. Expand via graph traversal
        var visited: Set<String> = []
        var expanded: [String: Float] = [:] // id -> score
        
        for seed in seedResults {
            expanded[seed.id] = seed.score
            visited.insert(seed.id)
        }
        
        // BFS expansion
        var frontier = seedResults.map { $0.id }
        
        for hop in 0..<hops {
            var nextFrontier: [String] = []
            let decayFactor = Float(1.0 / Double(hop + 2))
            
            for nodeId in frontier {
                let neighbors = await graph.neighbors(of: nodeId)
                
                for neighbor in neighbors {
                    guard !visited.contains(neighbor.targetId) else { continue }
                    guard neighbor.weight >= edgeWeightThreshold else { continue }
                    
                    visited.insert(neighbor.targetId)
                    nextFrontier.append(neighbor.targetId)
                    
                    // Propagate score with decay
                    let parentScore = expanded[nodeId] ?? 0
                    let propagatedScore = parentScore * neighbor.weight * decayFactor
                    
                    expanded[neighbor.targetId] = max(
                        expanded[neighbor.targetId] ?? 0,
                        propagatedScore
                    )
                }
            }
            
            frontier = nextFrontier
        }
        
        // 3. Fetch chunks and build results
        let topIds = expanded
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
        
        var results: [RetrievalResult] = []
        
        for id in topIds {
            if let chunk = await graph.chunk(forId: id) {
                results.append(RetrievalResult(
                    chunk: chunk,
                    score: expanded[id] ?? 0,
                    metadata: [:]
                ))
            }
        }
        
        return results
    }
}

// MARK: - ChunkGraph

/// A graph structure for chunk relationships.
public actor ChunkGraph {
    
    // MARK: - Types
    
    public enum EdgeType: String, Sendable, Codable {
        case sequential  // Adjacent in document
        case semantic    // High similarity
        case reference   // Explicit reference
    }
    
    public struct Edge: Sendable {
        public let targetId: String
        public let type: EdgeType
        public let weight: Float
    }
    
    private struct Node {
        var chunk: Chunk
        var embedding: Embedding?
        var edges: [Edge]
    }
    
    // MARK: - Properties
    
    private var nodes: [String: Node] = [:]
    private let similarityThreshold: Float
    
    // MARK: - Initialization
    
    public init(similarityThreshold: Float = 0.8) {
        self.similarityThreshold = similarityThreshold
    }
    
    // MARK: - Graph Construction
    
    public func addChunks(_ chunks: [Chunk], embeddings: [Embedding]) async {
        // Add nodes
        for (chunk, embedding) in zip(chunks, embeddings) {
            nodes[chunk.id] = Node(
                chunk: chunk,
                embedding: embedding,
                edges: []
            )
        }
        
        // Build sequential edges (same document, adjacent index)
        let byDocument = Dictionary(grouping: chunks) { $0.metadata.documentId }
        
        for (_, docChunks) in byDocument {
            let sorted = docChunks.sorted { $0.metadata.index < $1.metadata.index }
            
            for i in 0..<sorted.count - 1 {
                let current = sorted[i]
                let next = sorted[i + 1]
                
                addEdge(from: current.id, to: next.id, type: .sequential, weight: 1.0)
                addEdge(from: next.id, to: current.id, type: .sequential, weight: 1.0)
            }
        }
        
        // Build semantic edges (high similarity between chunks)
        let chunkIds = chunks.map { $0.id }
        
        for i in 0..<chunks.count {
            for j in (i + 1)..<chunks.count {
                let similarity = cosineSimilarity(
                    embeddings[i].vector,
                    embeddings[j].vector
                )
                
                if similarity >= similarityThreshold {
                    addEdge(from: chunkIds[i], to: chunkIds[j], type: .semantic, weight: similarity)
                    addEdge(from: chunkIds[j], to: chunkIds[i], type: .semantic, weight: similarity)
                }
            }
        }
    }
    
    public func neighbors(of nodeId: String) -> [Edge] {
        nodes[nodeId]?.edges ?? []
    }
    
    public func chunk(forId id: String) -> Chunk? {
        nodes[id]?.chunk
    }
    
    // MARK: - Private Methods
    
    private func addEdge(from sourceId: String, to targetId: String, type: EdgeType, weight: Float) {
        guard var node = nodes[sourceId] else { return }
        
        // Avoid duplicates
        if !node.edges.contains(where: { $0.targetId == targetId && $0.type == type }) {
            node.edges.append(Edge(targetId: targetId, type: type, weight: weight))
            nodes[sourceId] = node
        }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
```

---

### Week 3-4: Distributed Vector Stores

#### Milvus Store

```swift
// Sources/Zoni/VectorStore/Stores/MilvusStore.swift

import Foundation

/// Vector store using Milvus distributed vector database.
///
/// Milvus supports:
/// - Billion-scale vectors
/// - GPU acceleration
/// - Multiple index types (IVF, HNSW, etc.)
///
/// ## Example
///
/// ```swift
/// let milvus = try await MilvusStore(
///     host: "localhost",
///     port: 19530,
///     collection: "documents",
///     dimensions: 1536
/// )
/// ```
public actor MilvusStore: VectorStore {
    
    // MARK: - Properties
    
    public nonisolated let name = "milvus"
    
    private let host: String
    private let port: Int
    private let collection: String
    private let dimensions: Int
    private let indexType: IndexType
    
    // MARK: - Index Types
    
    public enum IndexType: String, Sendable {
        case flat = "FLAT"
        case ivfFlat = "IVF_FLAT"
        case ivfSQ8 = "IVF_SQ8"
        case ivfPQ = "IVF_PQ"
        case hnsw = "HNSW"
        case diskANN = "DISKANN"
    }
    
    // MARK: - Initialization
    
    public init(
        host: String = "localhost",
        port: Int = 19530,
        collection: String,
        dimensions: Int,
        indexType: IndexType = .hnsw
    ) async throws {
        self.host = host
        self.port = port
        self.collection = collection
        self.dimensions = dimensions
        self.indexType = indexType
        
        try await createCollectionIfNeeded()
    }
    
    // MARK: - VectorStore Protocol
    
    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        guard !chunks.isEmpty else { return }
        
        let url = URL(string: "http://\(host):\(port)/v1/vector/insert")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let records = zip(chunks, embeddings).map { chunk, embedding in
            [
                "id": chunk.id,
                "vector": embedding.vector,
                "content": chunk.content,
                "document_id": chunk.metadata.documentId,
                "metadata": try? JSONEncoder().encode(chunk.metadata)
            ] as [String: Any]
        }
        
        let body: [String: Any] = [
            "collectionName": collection,
            "data": records
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ZoniError.insertionFailed(reason: "Milvus insert failed")
        }
    }
    
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        let url = URL(string: "http://\(host):\(port)/v1/vector/search")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "collectionName": collection,
            "vector": query.vector,
            "topK": limit,
            "outputFields": ["id", "content", "document_id", "metadata"]
        ]
        
        if let filter = filter {
            body["filter"] = buildMilvusFilter(filter)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct MilvusResponse: Decodable {
            struct Result: Decodable {
                let id: String
                let distance: Float
                let content: String
                let document_id: String
            }
            let data: [Result]
        }
        
        let decoded = try JSONDecoder().decode(MilvusResponse.self, from: data)
        
        return decoded.data.map { result in
            RetrievalResult(
                chunk: Chunk(
                    id: result.id,
                    content: result.content,
                    metadata: ChunkMetadata(
                        documentId: result.document_id,
                        index: 0
                    )
                ),
                score: 1.0 - result.distance, // Convert distance to similarity
                metadata: [:]
            )
        }
    }
    
    public func delete(ids: [String]) async throws {
        let url = URL(string: "http://\(host):\(port)/v1/vector/delete")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "collectionName": collection,
            "ids": ids
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ZoniError.deletionFailed(reason: "Milvus delete failed")
        }
    }
    
    public func delete(filter: MetadataFilter) async throws {
        // Milvus supports filter-based deletion
        let url = URL(string: "http://\(host):\(port)/v1/vector/delete")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "collectionName": collection,
            "filter": buildMilvusFilter(filter)
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, _) = try await URLSession.shared.data(for: request)
    }
    
    public func count() async throws -> Int {
        let url = URL(string: "http://\(host):\(port)/v1/vector/count")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["collectionName": collection]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct CountResponse: Decodable {
            let data: Int
        }
        
        let decoded = try JSONDecoder().decode(CountResponse.self, from: data)
        return decoded.data
    }
    
    // MARK: - Private Methods
    
    private func createCollectionIfNeeded() async throws {
        // Check if collection exists, create if not
        let url = URL(string: "http://\(host):\(port)/v1/vector/collections/create")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "collectionName": collection,
            "dimension": dimensions,
            "metricType": "COSINE",
            "indexParams": [
                "index_type": indexType.rawValue,
                "params": indexType == .hnsw ? ["M": 16, "efConstruction": 256] : [:]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Ignore errors (collection may already exist)
        _ = try? await URLSession.shared.data(for: request)
    }
    
    private func buildMilvusFilter(_ filter: MetadataFilter) -> String {
        switch filter {
        case .equals(let key, let value):
            return "\(key) == \(formatValue(value))"
        case .notEquals(let key, let value):
            return "\(key) != \(formatValue(value))"
        case .contains(let key, let value):
            return "\(key) like '%\(value)%'"
        case .greaterThan(let key, let value):
            return "\(key) > \(formatValue(value))"
        case .lessThan(let key, let value):
            return "\(key) < \(formatValue(value))"
        case .and(let filters):
            return filters.map { buildMilvusFilter($0) }.joined(separator: " && ")
        case .or(let filters):
            return filters.map { buildMilvusFilter($0) }.joined(separator: " || ")
        case .not(let inner):
            return "!(\(buildMilvusFilter(inner)))"
        default:
            return ""
        }
    }
    
    private func formatValue(_ value: MetadataValue) -> String {
        switch value {
        case .string(let s): return "'\(s)'"
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        default: return "''"
        }
    }
}
```

---

### Week 5-6: Evaluation Framework

```swift
// Sources/Zoni/Evaluation/RAGEvaluator.swift

import Foundation

/// Framework for evaluating RAG pipeline quality.
///
/// Measures:
/// - **Retrieval Quality**: Precision, recall, MRR, NDCG
/// - **Generation Quality**: Faithfulness, relevance, coherence
/// - **End-to-End**: Answer correctness, latency
///
/// ## Example
///
/// ```swift
/// let evaluator = RAGEvaluator(pipeline: pipeline)
///
/// let dataset = EvaluationDataset(items: [
///     EvaluationItem(
///         query: "What is Swift concurrency?",
///         expectedChunks: ["chunk-1", "chunk-2"],
///         groundTruth: "Swift concurrency uses async/await..."
///     )
/// ])
///
/// let results = try await evaluator.evaluate(dataset)
/// print("Retrieval Precision: \(results.retrievalMetrics.precision)")
/// print("Answer Faithfulness: \(results.generationMetrics.faithfulness)")
/// ```
public actor RAGEvaluator {
    
    // MARK: - Types
    
    public struct EvaluationItem: Sendable {
        public let query: String
        public let expectedChunkIds: [String]?
        public let groundTruthAnswer: String?
        public let relevantDocumentIds: [String]?
        
        public init(
            query: String,
            expectedChunkIds: [String]? = nil,
            groundTruthAnswer: String? = nil,
            relevantDocumentIds: [String]? = nil
        ) {
            self.query = query
            self.expectedChunkIds = expectedChunkIds
            self.groundTruthAnswer = groundTruthAnswer
            self.relevantDocumentIds = relevantDocumentIds
        }
    }
    
    public struct EvaluationDataset: Sendable {
        public let items: [EvaluationItem]
        public let name: String
        
        public init(items: [EvaluationItem], name: String = "default") {
            self.items = items
            self.name = name
        }
    }
    
    public struct RetrievalMetrics: Sendable {
        public let precision: Float      // Relevant retrieved / Total retrieved
        public let recall: Float         // Relevant retrieved / Total relevant
        public let f1Score: Float        // Harmonic mean of P and R
        public let mrr: Float            // Mean Reciprocal Rank
        public let ndcg: Float           // Normalized Discounted Cumulative Gain
        public let averageLatencyMs: Double
    }
    
    public struct GenerationMetrics: Sendable {
        public let faithfulness: Float   // Answer grounded in context
        public let relevance: Float      // Answer addresses query
        public let coherence: Float      // Answer is well-structured
        public let averageLatencyMs: Double
    }
    
    public struct EvaluationResults: Sendable {
        public let retrievalMetrics: RetrievalMetrics
        public let generationMetrics: GenerationMetrics
        public let itemResults: [ItemResult]
        public let timestamp: Date
        
        public struct ItemResult: Sendable {
            public let query: String
            public let retrievedChunkIds: [String]
            public let generatedAnswer: String
            public let precision: Float
            public let recall: Float
            public let faithfulness: Float?
            public let retrievalLatencyMs: Double
            public let generationLatencyMs: Double
        }
    }
    
    // MARK: - Properties
    
    private let pipeline: RAGPipeline
    private let llmJudge: (any LLMProvider)?
    
    // MARK: - Initialization
    
    public init(
        pipeline: RAGPipeline,
        llmJudge: (any LLMProvider)? = nil
    ) {
        self.pipeline = pipeline
        self.llmJudge = llmJudge
    }
    
    // MARK: - Evaluation
    
    public func evaluate(_ dataset: EvaluationDataset) async throws -> EvaluationResults {
        var itemResults: [EvaluationResults.ItemResult] = []
        
        for item in dataset.items {
            let result = try await evaluateItem(item)
            itemResults.append(result)
        }
        
        // Aggregate metrics
        let retrievalMetrics = aggregateRetrievalMetrics(itemResults)
        let generationMetrics = aggregateGenerationMetrics(itemResults)
        
        return EvaluationResults(
            retrievalMetrics: retrievalMetrics,
            generationMetrics: generationMetrics,
            itemResults: itemResults,
            timestamp: Date()
        )
    }
    
    // MARK: - Private Methods
    
    private func evaluateItem(_ item: EvaluationItem) async throws -> EvaluationResults.ItemResult {
        // Retrieval
        let retrievalStart = ContinuousClock.now
        let retrievalResults = try await pipeline.retrieve(item.query, limit: 10)
        let retrievalLatency = (ContinuousClock.now - retrievalStart).milliseconds
        
        let retrievedIds = retrievalResults.map { $0.chunk.id }
        
        // Calculate retrieval metrics
        let (precision, recall) = calculatePrecisionRecall(
            retrieved: Set(retrievedIds),
            relevant: Set(item.expectedChunkIds ?? [])
        )
        
        // Generation
        let generationStart = ContinuousClock.now
        let response = try await pipeline.query(item.query)
        let generationLatency = (ContinuousClock.now - generationStart).milliseconds
        
        // Calculate faithfulness (if LLM judge available)
        var faithfulness: Float? = nil
        if let judge = llmJudge, let groundTruth = item.groundTruthAnswer {
            faithfulness = try await calculateFaithfulness(
                answer: response.answer,
                context: retrievalResults.map { $0.chunk.content }.joined(separator: "\n"),
                groundTruth: groundTruth,
                judge: judge
            )
        }
        
        return EvaluationResults.ItemResult(
            query: item.query,
            retrievedChunkIds: retrievedIds,
            generatedAnswer: response.answer,
            precision: precision,
            recall: recall,
            faithfulness: faithfulness,
            retrievalLatencyMs: Double(retrievalLatency),
            generationLatencyMs: Double(generationLatency)
        )
    }
    
    private func calculatePrecisionRecall(
        retrieved: Set<String>,
        relevant: Set<String>
    ) -> (precision: Float, recall: Float) {
        guard !retrieved.isEmpty else { return (0, 0) }
        guard !relevant.isEmpty else { return (1, 1) } // No expected = all correct
        
        let intersection = retrieved.intersection(relevant)
        let precision = Float(intersection.count) / Float(retrieved.count)
        let recall = Float(intersection.count) / Float(relevant.count)
        
        return (precision, recall)
    }
    
    private func calculateFaithfulness(
        answer: String,
        context: String,
        groundTruth: String,
        judge: any LLMProvider
    ) async throws -> Float {
        let prompt = """
        You are evaluating the faithfulness of an AI-generated answer.
        
        Context (retrieved documents):
        \(context.prefix(2000))
        
        Generated Answer:
        \(answer)
        
        Ground Truth Answer:
        \(groundTruth)
        
        Rate the faithfulness of the generated answer on a scale of 0.0 to 1.0:
        - 1.0: Answer is fully grounded in the context and matches ground truth
        - 0.5: Answer is partially grounded but has some unsupported claims
        - 0.0: Answer contains hallucinations or contradicts the context
        
        Respond with only a number between 0.0 and 1.0.
        """
        
        let response = try await judge.generate(prompt: prompt)
        return Float(response.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.5
    }
    
    private func aggregateRetrievalMetrics(
        _ results: [EvaluationResults.ItemResult]
    ) -> RetrievalMetrics {
        let count = Float(results.count)
        
        let avgPrecision = results.map { $0.precision }.reduce(0, +) / count
        let avgRecall = results.map { $0.recall }.reduce(0, +) / count
        let f1 = (avgPrecision + avgRecall) > 0
            ? 2 * avgPrecision * avgRecall / (avgPrecision + avgRecall)
            : 0
        
        let avgLatency = results.map { $0.retrievalLatencyMs }.reduce(0, +) / Double(count)
        
        return RetrievalMetrics(
            precision: avgPrecision,
            recall: avgRecall,
            f1Score: f1,
            mrr: 0, // TODO: Calculate MRR
            ndcg: 0, // TODO: Calculate NDCG
            averageLatencyMs: avgLatency
        )
    }
    
    private func aggregateGenerationMetrics(
        _ results: [EvaluationResults.ItemResult]
    ) -> GenerationMetrics {
        let faithfulnessScores = results.compactMap { $0.faithfulness }
        let avgFaithfulness = faithfulnessScores.isEmpty
            ? 0
            : faithfulnessScores.reduce(0, +) / Float(faithfulnessScores.count)
        
        let avgLatency = results.map { $0.generationLatencyMs }.reduce(0, +) / Double(results.count)
        
        return GenerationMetrics(
            faithfulness: avgFaithfulness,
            relevance: 0, // TODO: Calculate relevance
            coherence: 0, // TODO: Calculate coherence
            averageLatencyMs: avgLatency
        )
    }
}

// MARK: - Duration Extension

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = self.components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
```

---

## Summary Timeline

| Week | Version | Deliverable |
|------|---------|-------------|
| 1-2 | 1.1.0 | ParentChildChunker + ParentChildRetriever |
| 2-3 | 1.1.0 | HuggingFace + Mistral embedding providers |
| 3-4 | 1.1.0 | OCR + Table extraction (ZoniApple) |
| 5-6 | 1.2.0 | GraphRetriever + ChunkGraph |
| 7-8 | 1.2.0 | MilvusStore + WeaviateStore |
| 9-10 | 1.2.0 | RAGEvaluator framework |

---

## Testing Requirements

Each feature requires:
1. **Unit tests** (80%+ coverage)
2. **Integration tests** with real/mock services
3. **Performance benchmarks**
4. **Documentation** with examples

---

## Dependencies to Add

```swift
// Package.swift additions

// For Milvus (gRPC)
.package(url: "https://github.com/grpc/grpc-swift.git", from: "1.0.0"),

// For Weaviate (GraphQL)
.package(url: "https://github.com/nerdsupremacist/GraphQL.git", from: "2.0.0"),
```

---

## Migration Notes

### From 1.0.0 to 1.1.0
- No breaking changes
- New chunkers are additive
- New providers are additive

### From 1.1.0 to 1.2.0
- No breaking changes
- New stores require external services
- Evaluation framework is optional

---

This plan extends Zoni to handle:
- ✅ Context-constrained LLMs (4K windows)
- ✅ More embedding providers
- ✅ Document preprocessing
- ✅ Graph-based retrieval
- ✅ Distributed vector stores
- ✅ Quality evaluation
