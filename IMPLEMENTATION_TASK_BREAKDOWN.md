# Zoni v1.1-v1.2 Implementation Task Breakdown

**Project:** Zoni RAG Framework
**Version:** 1.0.0 → 1.1.0 → 1.2.0
**Language:** Swift 6.0
**Date:** 2026-01-07
**Author:** Task Decomposition Expert

---

## Executive Summary

This document provides a comprehensive, execution-ready breakdown of all tasks required to implement Zoni v1.1 and v1.2 features. The implementation follows TDD principles, leverages ChromaDB for development testing, and maintains strict Swift 6 actor-based concurrency patterns.

### ChromaDB Integration Strategy

**CRITICAL**: While Zoni implements its own vector stores (PostgreSQL, SQLite, Qdrant, Pinecone), ChromaDB should be used during development for:

1. **Test Fixture Storage** - Store test embeddings and expected results
2. **Development Validation** - Quick semantic search validation during implementation
3. **Integration Testing** - Cross-reference retrieval results between implementations
4. **Benchmark Baselines** - Store performance baseline data
5. **Documentation Examples** - Semantic search over implementation specs

**ChromaDB Usage Pattern:**
```swift
// Example: Storing test vectors for ParentChildRetriever validation
let testCollection = "parent_child_test_fixtures"
await chromaDB.addDocuments(
    collection: testCollection,
    documents: testChunks.map { $0.content },
    embeddings: testEmbeddings,
    metadata: testMetadata
)
```

---

## Priority Matrix

| Feature | Priority | Complexity | Value | Dependencies | Test Files |
|---------|----------|------------|-------|--------------|------------|
| ParentChildChunker | P0 | Medium | High | ChunkingStrategy protocol | `Tests/ZoniTests/Chunking/ParentChildChunkerTests.swift` |
| ParentChildRetriever | P0 | Medium-High | High | ParentChildChunker, VectorStore | `Tests/ZoniTests/Retrieval/ParentChildRetrieverTests.swift` |
| HuggingFaceEmbedding | P0 | Low | High | EmbeddingProvider protocol | `Tests/ZoniTests/Embedding/HuggingFaceEmbeddingTests.swift` |
| MistralEmbedding | P0 | Low | High | EmbeddingProvider protocol | `Tests/ZoniTests/Embedding/MistralEmbeddingTests.swift` |
| VisionOCRProcessor | P1 | Medium | Medium | None | `Tests/ZoniAppleTests/Preprocessing/OCRProcessorTests.swift` |
| TableExtractor | P1 | Medium | Medium | VisionOCRProcessor | `Tests/ZoniAppleTests/Preprocessing/TableExtractorTests.swift` |
| ChunkGraph | P2 | High | Medium | None | `Tests/ZoniTests/Retrieval/ChunkGraphTests.swift` |
| GraphRetriever | P2 | High | Medium | ChunkGraph | `Tests/ZoniTests/Retrieval/GraphRetrieverTests.swift` |
| RAGEvaluator | P2 | High | High | RAGPipeline, LLMProvider | `Tests/ZoniTests/Evaluation/RAGEvaluatorTests.swift` |

---

## Phase 1: Foundation Setup (Week 0)

### Task 1.1: Project Structure Preparation
**Priority:** P0
**Estimated Time:** 2 hours
**Complexity:** Low

**Sub-tasks:**
1. Create directory structure for new components
2. Update Package.swift if needed (no new dependencies for P0 features)
3. Set up ChromaDB collection for test fixtures
4. Create test data directory structure

**Deliverables:**
- `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Chunking/Strategies/`
- `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Retrieval/Retrievers/`
- `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Embedding/Providers/`
- `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Fixtures/`

**ChromaDB Setup:**
```swift
// Test fixture collections
let collections = [
    "parent_child_test_vectors",
    "embedding_provider_benchmarks",
    "retrieval_expected_results",
    "graph_test_fixtures"
]
```

**Success Criteria:**
- [ ] All directories created
- [ ] ChromaDB collections initialized
- [ ] Test fixture structure documented

---

## Phase 2: P0 Features - Context Optimization (Weeks 1-3)

### Task 2.1: ParentChildChunker Implementation
**Priority:** P0
**Estimated Time:** 2 days
**Complexity:** Medium
**Dependencies:** ChunkingStrategy protocol

#### Sub-task 2.1.1: Test Design (TDD Red Phase)
**Estimated Time:** 4 hours
**Owner:** `test-specialist` agent

**Test Cases to Implement:**
1. **Basic Chunking** (`testBasicParentChildSplit`)
   - Input: 650 character document
   - Parent size: 200, Child size: 50, Overlap: 10
   - Expected: 3-4 parents, 12+ children
   - Assertion: All children reference valid parent IDs

2. **Relationship Integrity** (`testParentChildRelationships`)
   - Verify bidirectional references
   - Parent's childIds array matches actual children
   - Child's parentId points to existing parent

3. **Overlap Validation** (`testChildOverlapCorrectness`)
   - Verify overlap windows contain expected shared content
   - Check position offsets are sequential with proper overlap

4. **Edge Cases** (`testEdgeCases`)
   - Empty document
   - Single sentence (smaller than child size)
   - Exact chunk size multiples
   - Unicode and emoji handling

5. **Metadata Preservation** (`testMetadataPreservation`)
   - Document ID propagation
   - Custom metadata inheritance
   - Source attribution

**ChromaDB Integration:**
```swift
// Store expected results for cross-validation
let expectedChunks = await chromaDB.query(
    collection: "parent_child_expected_results",
    query: testDocument.content,
    limit: 100
)
```

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Chunking/ParentChildChunkerTests.swift`

**Success Criteria:**
- [ ] All tests compile
- [ ] All tests fail (Red phase)
- [ ] Test coverage plan documented

#### Sub-task 2.1.2: Protocol Conformance (TDD Green Phase)
**Estimated Time:** 6 hours
**Owner:** `implementer` agent

**Implementation Steps:**
1. Create struct conforming to `ChunkingStrategy`
2. Implement `chunk(_ document: Document) -> [Chunk]`
3. Add parent chunk creation logic
4. Add child chunk creation logic with overlap
5. Build metadata relationships

**Key Algorithms:**
```swift
// Parent creation: Greedy paragraph aggregation up to parentSize
func createParentChunks(from document: Document) -> [Chunk] {
    var chunks: [Chunk] = []
    var currentContent = ""
    let paragraphs = text.components(separatedBy: parentSeparator)

    for paragraph in paragraphs {
        let potential = currentContent + parentSeparator + paragraph
        if potential.count <= parentSize {
            currentContent = potential
        } else {
            // Flush current, start new
            chunks.append(createChunk(currentContent, ...))
            currentContent = paragraph
        }
    }
    return chunks
}

// Child creation: Sliding window with overlap
func createChildChunks(from parent: Chunk) -> [Chunk] {
    var position = 0
    var children: [Chunk] = []

    while position < parent.content.count {
        let end = min(position + childSize, parent.content.count)
        let content = String(parent.content[position..<end])
        children.append(createChild(content, parentId: parent.id, ...))
        position += (childSize - childOverlap)
    }
    return children
}
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Chunking/Strategies/ParentChildChunker.swift`

**Success Criteria:**
- [ ] All tests pass (Green phase)
- [ ] No force unwraps (`!`)
- [ ] Proper error handling
- [ ] Actor isolation respected

#### Sub-task 2.1.3: Refactor & Optimize
**Estimated Time:** 2 hours
**Owner:** `code-reviewer` agent

**Refactoring Tasks:**
1. Extract magic numbers to constants
2. Add comprehensive DocC documentation
3. Optimize string operations for large documents
4. Add performance benchmarks

**Performance Targets:**
- 10MB document: <1 second
- 100K chunks: <5 seconds

**Success Criteria:**
- [ ] Code review approved
- [ ] Performance benchmarks meet targets
- [ ] DocC examples compile

---

### Task 2.2: ParentChildRetriever Implementation
**Priority:** P0
**Estimated Time:** 3 days
**Complexity:** Medium-High
**Dependencies:** ParentChildChunker, VectorStore, EmbeddingProvider

#### Sub-task 2.2.1: ParentLookup Protocol Design
**Estimated Time:** 2 hours
**Owner:** `protocol-architect` agent

**Protocol Definition:**
```swift
public protocol ParentLookup: Sendable {
    func parent(forId id: String) async throws -> Chunk?
    func parents(forIds ids: [String]) async throws -> [String: Chunk]
}
```

**Implementations Needed:**
1. `VectorStoreParentLookup` - Uses existing vector store with ID filter
2. `CachingParentLookup` - Wrapper with LRU cache
3. `InMemoryParentLookup` - Dictionary-based for testing

**ChromaDB Test Strategy:**
```swift
// Validate lookup implementation against ChromaDB
let chromaParent = await chromaDB.getDocument(
    collection: "parent_chunks",
    id: childChunk.parentId
)
let ourParent = try await lookup.parent(forId: childChunk.parentId)
XCTAssertEqual(chromaParent.content, ourParent?.content)
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Retrieval/ParentLookup.swift`

**Success Criteria:**
- [ ] Protocol is Sendable
- [ ] Actor isolation safe
- [ ] Batch lookup supported

#### Sub-task 2.2.2: Test Design (TDD Red Phase)
**Estimated Time:** 6 hours
**Owner:** `test-specialist` agent

**Test Cases:**
1. **Basic Retrieval** (`testBasicParentRetrieval`)
   - Query: "Swift actors"
   - Mock: 5 child matches → 3 unique parents
   - Expected: Return 3 parent chunks sorted by score

2. **Score Aggregation** (`testScoreAggregationStrategies`)
   - Test `.max` - Takes highest child score
   - Test `.average` - Averages all child scores
   - Test `.sum` - Sums child scores (rewards multiple matches)

3. **Deduplication** (`testParentDeduplication`)
   - Multiple children from same parent
   - Verify parent returned only once
   - Score reflects aggregation method

4. **Filter Integration** (`testMetadataFiltering`)
   - Apply filter on child search
   - Verify parent lookup respects document filters

5. **Edge Cases** (`testEdgeCases`)
   - No children match
   - Parent not found in lookup
   - Limit < number of parents

**Mock Setup:**
```swift
let mockEmbedding = MockEmbeddingProvider(
    responses: ["query": [0.1, 0.2, 0.3, ...]]
)

let mockStore = MockVectorStore(
    searchResults: [
        child1: 0.95, // parent A
        child2: 0.92, // parent A
        child3: 0.88, // parent B
    ]
)

let mockLookup = InMemoryParentLookup(
    parents: [parentA, parentB]
)
```

**ChromaDB Validation:**
```swift
// Store expected retrieval results
await chromaDB.addDocuments(
    collection: "parent_child_expected_retrievals",
    documents: expectedResults.map { $0.chunk.content },
    metadata: [
        "query": query,
        "aggregation": "max",
        "expected_score": score
    ]
)
```

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Retrieval/ParentChildRetrieverTests.swift`

**Success Criteria:**
- [ ] All test scenarios covered
- [ ] Tests fail (Red phase)
- [ ] Mock implementations ready

#### Sub-task 2.2.3: Actor Implementation (TDD Green Phase)
**Estimated Time:** 8 hours
**Owner:** `implementer` agent

**Implementation Algorithm:**
```swift
public actor ParentChildRetriever: Retriever {
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // 1. Embed query
        let queryEmbedding = try await embeddingProvider.embed(query)

        // 2. Search children (fetch more for parent aggregation)
        let childLimit = limit * childMultiplier
        let childFilter = combineFilter(filter, isChild: true)
        let childResults = try await childStore.search(
            query: queryEmbedding,
            limit: childLimit,
            filter: childFilter
        )

        // 3. Group by parent and aggregate scores
        var parentScores: [String: (score: Float, children: [Result])] = [:]
        for child in childResults {
            let parentId = child.metadata["parentId"]!.stringValue
            if var existing = parentScores[parentId] {
                existing.children.append(child)
                existing.score = aggregateScore(existing.score, child.score)
                parentScores[parentId] = existing
            } else {
                parentScores[parentId] = (child.score, [child])
            }
        }

        // 4. Sort and limit
        let topParentIds = parentScores
            .sorted { $0.value.score > $1.value.score }
            .prefix(limit)
            .map { $0.key }

        // 5. Batch fetch parents
        let parents = try await parentLookup.parents(forIds: topParentIds)

        // 6. Build results with enriched metadata
        return topParentIds.compactMap { id in
            guard let parent = parents[id],
                  let scoreData = parentScores[id] else { return nil }

            var metadata = parent.metadata.custom
            metadata["matchedChildren"] = .int(scoreData.children.count)
            metadata["bestChildScore"] = .double(scoreData.children.max(\.score))

            return RetrievalResult(
                chunk: parent,
                score: scoreData.score,
                metadata: metadata
            )
        }
    }
}
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Retrieval/Retrievers/ParentChildRetriever.swift`

**Success Criteria:**
- [ ] All tests pass (Green phase)
- [ ] Actor isolation maintained
- [ ] Batch operations where possible

#### Sub-task 2.2.4: VectorStoreParentLookup Implementation
**Estimated Time:** 4 hours
**Owner:** `implementer` agent

**Implementation:**
```swift
public actor VectorStoreParentLookup: ParentLookup {
    private let store: any VectorStore
    private var cache: [String: Chunk] = [:]
    private let cacheSize: Int

    public func parent(forId id: String) async throws -> Chunk? {
        if let cached = cache[id] { return cached }

        // Search with ID filter (avoid vector search)
        let results = try await store.search(
            query: Embedding(vector: [], model: nil), // Dummy
            limit: 1,
            filter: .equals("id", .string(id))
        )

        if let result = results.first {
            cache[id] = result.chunk
            evictIfNeeded()
            return result.chunk
        }
        return nil
    }

    public func parents(forIds ids: [String]) async throws -> [String: Chunk] {
        var result: [String: Chunk] = [:]
        var missingIds: [String] = []

        // Check cache first
        for id in ids {
            if let cached = cache[id] {
                result[id] = cached
            } else {
                missingIds.append(id)
            }
        }

        // Batch fetch missing
        if !missingIds.isEmpty {
            let filter = MetadataFilter.or(
                missingIds.map { .equals("id", .string($0)) }
            )
            let fetched = try await store.search(
                query: Embedding(vector: [], model: nil),
                limit: missingIds.count,
                filter: filter
            )
            for chunk in fetched.map(\.chunk) {
                result[chunk.id] = chunk
                cache[chunk.id] = chunk
            }
        }

        return result
    }
}
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Retrieval/VectorStoreParentLookup.swift`

**Success Criteria:**
- [ ] LRU cache working
- [ ] Batch fetch optimized
- [ ] Cache eviction tested

---

### Task 2.3: HuggingFace Embedding Provider
**Priority:** P0
**Estimated Time:** 2 days
**Complexity:** Low
**Dependencies:** EmbeddingProvider protocol

#### Sub-task 2.3.1: Test Design (TDD Red Phase)
**Estimated Time:** 3 hours
**Owner:** `test-specialist` agent

**Test Cases:**
1. **Single Embedding** (`testSingleTextEmbedding`)
   - Input: "Hello world"
   - Model: MiniLM (384 dims)
   - Verify: Vector length = 384

2. **Batch Embedding** (`testBatchEmbedding`)
   - Input: 32 texts
   - Verify: Order preserved
   - Verify: All vectors correct dimension

3. **Model Variants** (`testDifferentModels`)
   - Test MiniLM (384d)
   - Test BGE-large (1024d)
   - Test E5 (1024d)

4. **Error Handling** (`testErrorHandling`)
   - Invalid API key
   - Rate limiting
   - Network timeout
   - Model not loaded (wait_for_model)

5. **Empty Input** (`testEmptyInput`)
   - Empty string
   - Empty array

**ChromaDB Benchmark Storage:**
```swift
// Store embedding benchmarks for comparison
await chromaDB.addDocuments(
    collection: "embedding_benchmarks",
    documents: testTexts,
    embeddings: huggingfaceResults,
    metadata: [
        "provider": "huggingface",
        "model": "all-MiniLM-L6-v2",
        "timestamp": Date().iso8601,
        "latency_ms": latency
    ]
)
```

**Mock HuggingFace API:**
```swift
class MockHuggingFaceAPI: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api-inference.huggingface.co"
    }

    override func startLoading() {
        let response = [[Float]](
            repeating: Array(repeating: 0.1, count: 384),
            count: requestBatchSize
        )
        // Return mock JSON
    }
}
```

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Embedding/HuggingFaceEmbeddingTests.swift`

**Success Criteria:**
- [ ] All tests compile
- [ ] Tests fail (Red phase)
- [ ] Mock API ready

#### Sub-task 2.3.2: Implementation (TDD Green Phase)
**Estimated Time:** 4 hours
**Owner:** `implementer` agent

**Implementation:**
```swift
public actor HuggingFaceEmbedding: EmbeddingProvider {
    public nonisolated let name = "huggingface"
    public nonisolated let dimensions: Int
    public nonisolated var maxTokensPerRequest: Int { 512 }
    public nonisolated var optimalBatchSize: Int { 32 }

    private let apiKey: String
    private let model: String
    private let baseURL: URL

    public enum Model: String, Sendable {
        case miniLM = "sentence-transformers/all-MiniLM-L6-v2"
        case bgeLargeEN = "BAAI/bge-large-en-v1.5"
        case bgeBaseEN = "BAAI/bge-base-en-v1.5"

        public var dimensions: Int {
            switch self {
            case .miniLM: return 384
            case .bgeLargeEN: return 1024
            case .bgeBaseEN: return 768
            }
        }
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let error = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ZoniError.embeddingFailed(
                reason: "HuggingFace API error: \(error)"
            )
        }

        let vectors = try JSONDecoder().decode([[Float]].self, from: data)
        return vectors.map { Embedding(vector: $0, model: model) }
    }
}
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Embedding/Providers/HuggingFaceEmbedding.swift`

**Success Criteria:**
- [ ] All tests pass
- [ ] Proper error handling
- [ ] Rate limiting handled

---

### Task 2.4: Mistral Embedding Provider
**Priority:** P0
**Estimated Time:** 1.5 days
**Complexity:** Low
**Dependencies:** EmbeddingProvider protocol

**Similar structure to Task 2.3 with Mistral-specific API:**

#### Sub-task 2.4.1: Test Design
**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Embedding/MistralEmbeddingTests.swift`

#### Sub-task 2.4.2: Implementation
**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Embedding/Providers/MistralEmbedding.swift`

**Key Differences from HuggingFace:**
- API endpoint: `https://api.mistral.ai/v1/embeddings`
- Response format: `{ "data": [{"embedding": [...], "index": 0}] }`
- Must sort by index to preserve order
- Model: `mistral-embed` (1024 dimensions)

**Success Criteria:**
- [ ] All tests pass
- [ ] Index sorting verified
- [ ] Integration test with real API (optional, env-gated)

---

## Phase 3: P1 Features - Document Preprocessing (Weeks 3-4)

### Task 3.1: VisionOCRProcessor
**Priority:** P1
**Estimated Time:** 2 days
**Complexity:** Medium
**Target:** ZoniApple module

#### Sub-task 3.1.1: Test Design (TDD Red Phase)
**Estimated Time:** 4 hours
**Owner:** `test-specialist` agent

**Test Cases:**
1. **Basic Image OCR** (`testBasicImageOCR`)
   - Input: PNG with printed text
   - Expected: Extracted text matches expected
   - Languages: English

2. **PDF OCR** (`testPDFPageOCR`)
   - Input: 3-page PDF
   - Expected: Array of 3 text strings
   - Verify: Page order preserved

3. **Multi-Language** (`testMultiLanguageOCR`)
   - Input: Spanish text image
   - Languages: ["es-ES"]
   - Verify: Accented characters correct

4. **Low Quality Image** (`testLowQualityImage`)
   - Input: Blurry, low-res image
   - Recognition level: .fast vs .accurate
   - Verify: Graceful degradation

5. **Empty Image** (`testEmptyImage`)
   - Input: Blank white image
   - Expected: Empty string (no error)

**Test Fixtures:**
- `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniAppleTests/Fixtures/test_document.png`
- `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniAppleTests/Fixtures/test_document.pdf`

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniAppleTests/Preprocessing/OCRProcessorTests.swift`

**Success Criteria:**
- [ ] Tests run on macOS/iOS only (`@available`)
- [ ] Test fixtures committed
- [ ] Tests fail (Red phase)

#### Sub-task 3.1.2: Implementation (TDD Green Phase)
**Estimated Time:** 6 hours
**Owner:** `implementer` agent

**Implementation:**
```swift
#if canImport(Vision)
import Vision
import Foundation

@available(macOS 10.15, iOS 13.0, *)
public actor VisionOCRProcessor {
    private let languages: [String]
    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let usesLanguageCorrection: Bool

    public init(
        languages: [String] = ["en-US"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true
    ) {
        self.languages = languages
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func extractText(from imageURL: URL) async throws -> String {
        guard let cgImage = loadCGImage(from: imageURL) else {
            throw ZoniError.loadingFailed(reason: "Failed to load image")
        }
        return try await extractText(from: cgImage)
    }

    public func extractText(from cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = recognitionLevel
            request.usesLanguageCorrection = usesLanguageCorrection
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func extractTextFromPDF(at url: URL) async throws -> [String] {
        guard let pdfDocument = CGPDFDocument(url as CFURL) else {
            throw ZoniError.loadingFailed(reason: "Failed to open PDF")
        }

        var pageTexts: [String] = []
        for pageNum in 1...pdfDocument.numberOfPages {
            guard let page = pdfDocument.page(at: pageNum),
                  let cgImage = renderPDFPage(page) else { continue }

            let text = try await extractText(from: cgImage)
            pageTexts.append(text)
        }
        return pageTexts
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
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)

        return context.makeImage()
    }
}
#endif
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/ZoniApple/Preprocessing/OCRProcessor.swift`

**Success Criteria:**
- [ ] All tests pass
- [ ] Works on macOS 10.15+, iOS 13+
- [ ] Proper async/await continuation

---

### Task 3.2: TableExtractor
**Priority:** P1
**Estimated Time:** 2.5 days
**Complexity:** Medium
**Dependencies:** VisionOCRProcessor (for text recognition)
**Target:** ZoniApple module

#### Sub-task 3.2.1: Test Design (TDD Red Phase)
**Estimated Time:** 4 hours
**Owner:** `test-specialist` agent

**Test Cases:**
1. **Simple Table** (`testSimpleTableExtraction`)
   - Input: Image with 3x3 table
   - Expected: ExtractedTable with 3 rows, 3 columns
   - Verify: Markdown format correct

2. **CSV Output** (`testCSVOutput`)
   - Same table input
   - Verify: CSV format with proper escaping
   - Test: Cells with commas and quotes

3. **Multiple Tables** (`testMultipleTablesInImage`)
   - Input: Image with 2 tables
   - Expected: Array of 2 ExtractedTable objects
   - Verify: Bounding boxes don't overlap

4. **Complex Table** (`testComplexTable`)
   - Input: Table with merged cells, headers
   - Expected: Best-effort extraction
   - Verify: Header row identified

5. **No Tables** (`testImageWithoutTables`)
   - Input: Plain text image
   - Expected: Empty array (no crash)

**Test Fixtures:**
- `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniAppleTests/Fixtures/simple_table.png`
- `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniAppleTests/Fixtures/complex_table.png`

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniAppleTests/Preprocessing/TableExtractorTests.swift`

**Success Criteria:**
- [ ] Tests compile (macOS 13+, iOS 16+)
- [ ] Test fixtures include ground truth tables
- [ ] Tests fail (Red phase)

#### Sub-task 3.2.2: Implementation (TDD Green Phase)
**Estimated Time:** 8 hours
**Owner:** `implementer` agent

**Implementation Strategy:**
1. Use `VNDetectRectanglesRequest` to find table regions
2. Crop image to each rectangle
3. Use `VNRecognizeTextRequest` to extract text with positions
4. Group text by Y-coordinate into rows
5. Sort within rows by X-coordinate into columns
6. Output as `ExtractedTable` struct

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/ZoniApple/Preprocessing/TableExtractor.swift`

**Success Criteria:**
- [ ] Basic tables extracted correctly
- [ ] Markdown and CSV formats working
- [ ] Handles edge cases gracefully

---

## Phase 4: P2 Features - Advanced Retrieval (Weeks 5-8)

### Task 4.1: ChunkGraph Implementation
**Priority:** P2
**Estimated Time:** 3 days
**Complexity:** High

#### Sub-task 4.1.1: Graph Data Structure Design
**Estimated Time:** 4 hours
**Owner:** `protocol-architect` agent

**Design Decisions:**
1. **Node Storage:** Dictionary `[String: Node]` for O(1) lookup
2. **Edge Types:** Sequential, Semantic, Reference (enum)
3. **Edge Weights:** Float 0.0-1.0
4. **Thread Safety:** Actor isolation

**ChromaDB Integration for Graph Validation:**
```swift
// Store graph structure for validation
await chromaDB.addDocuments(
    collection: "chunk_graph_edges",
    documents: edges.map { "\($0.source) -> \($0.target)" },
    metadata: [
        "edge_type": edgeType.rawValue,
        "weight": weight,
        "graph_id": graphId
    ]
)
```

**Protocol:**
```swift
public actor ChunkGraph {
    public enum EdgeType: String, Sendable {
        case sequential  // Same document, adjacent chunks
        case semantic    // High embedding similarity
        case reference   // Explicit cross-reference
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

    private var nodes: [String: Node] = [:]
    private let similarityThreshold: Float
}
```

**Success Criteria:**
- [ ] Protocol design reviewed
- [ ] Actor-safe design validated
- [ ] Edge type semantics documented

#### Sub-task 4.1.2: Test Design (TDD Red Phase)
**Estimated Time:** 6 hours
**Owner:** `test-specialist` agent

**Test Cases:**
1. **Graph Construction** (`testGraphConstruction`)
   - Add 10 chunks from same document
   - Verify: 9 sequential edges created
   - Verify: No duplicate edges

2. **Semantic Edge Creation** (`testSemanticEdges`)
   - Add chunks with known similar embeddings
   - Threshold: 0.8
   - Verify: Edges created for similarity > 0.8
   - Verify: Bidirectional edges

3. **Neighbor Retrieval** (`testNeighborRetrieval`)
   - Query: neighbors of chunk X
   - Expected: All connected chunks
   - Verify: Sorted by weight

4. **Graph Persistence** (future)
   - Save graph to disk
   - Load graph from disk
   - Verify: Structure preserved

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Retrieval/ChunkGraphTests.swift`

**Success Criteria:**
- [ ] Tests compile
- [ ] Tests fail (Red phase)
- [ ] Mock embeddings ready

#### Sub-task 4.1.3: Implementation (TDD Green Phase)
**Estimated Time:** 10 hours
**Owner:** `implementer` agent

**Key Algorithms:**
```swift
public func addChunks(_ chunks: [Chunk], embeddings: [Embedding]) async {
    // 1. Add nodes
    for (chunk, embedding) in zip(chunks, embeddings) {
        nodes[chunk.id] = Node(chunk: chunk, embedding: embedding, edges: [])
    }

    // 2. Build sequential edges
    let byDocument = Dictionary(grouping: chunks) { $0.metadata.documentId }
    for (_, docChunks) in byDocument {
        let sorted = docChunks.sorted { $0.metadata.index < $1.metadata.index }
        for i in 0..<sorted.count - 1 {
            addEdge(from: sorted[i].id, to: sorted[i+1].id,
                    type: .sequential, weight: 1.0)
            addEdge(from: sorted[i+1].id, to: sorted[i].id,
                    type: .sequential, weight: 1.0)
        }
    }

    // 3. Build semantic edges (O(n²) - optimize for large graphs)
    for i in 0..<chunks.count {
        for j in (i+1)..<chunks.count {
            let similarity = cosineSimilarity(
                embeddings[i].vector,
                embeddings[j].vector
            )
            if similarity >= similarityThreshold {
                addEdge(from: chunks[i].id, to: chunks[j].id,
                        type: .semantic, weight: similarity)
                addEdge(from: chunks[j].id, to: chunks[i].id,
                        type: .semantic, weight: similarity)
            }
        }
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
```

**Optimization Note:** For large graphs (>10K nodes), consider:
- Approximate nearest neighbors (HNSW) for semantic edges
- Incremental graph construction
- Edge pruning (keep top-k per node)

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Retrieval/Graph/ChunkGraph.swift`

**Success Criteria:**
- [ ] All tests pass
- [ ] Performance acceptable for 1K nodes
- [ ] Memory efficient

---

### Task 4.2: GraphRetriever Implementation
**Priority:** P2
**Estimated Time:** 3 days
**Complexity:** High
**Dependencies:** ChunkGraph

#### Sub-task 4.2.1: Test Design (TDD Red Phase)
**Estimated Time:** 6 hours
**Owner:** `test-specialist` agent

**Test Cases:**
1. **Basic BFS Expansion** (`testBasicGraphRetrieval`)
   - Initial: 1 seed result
   - Hops: 2
   - Expected: Seed + 1-hop neighbors + 2-hop neighbors
   - Verify: Score decay applied

2. **Score Propagation** (`testScorePropagation`)
   - Seed score: 1.0
   - 1-hop edge weight: 0.8
   - Expected 1-hop score: 1.0 * 0.8 * 0.5 = 0.4 (with decay)

3. **Deduplication** (`testVisitedNodeTracking`)
   - Graph with cycles
   - Verify: Each node visited only once
   - Verify: Highest score kept

4. **Edge Threshold** (`testEdgeWeightThreshold`)
   - Threshold: 0.7
   - Verify: Edges < 0.7 not traversed
   - Verify: Low-quality paths pruned

5. **Limit Enforcement** (`testResultLimit`)
   - Limit: 10
   - Graph expansion: 50 nodes
   - Expected: Top 10 by final score

**ChromaDB Cross-Validation:**
```swift
// Store expected graph traversal paths
await chromaDB.addDocuments(
    collection: "graph_retrieval_expected",
    documents: expectedPath.map { $0.chunk.content },
    metadata: [
        "seed_id": seedChunk.id,
        "hops": hops,
        "expected_score": score,
        "traversal_order": order
    ]
)
```

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Retrieval/GraphRetrieverTests.swift`

**Success Criteria:**
- [ ] BFS algorithm testable
- [ ] Score propagation verified
- [ ] Tests fail (Red phase)

#### Sub-task 4.2.2: Implementation (TDD Green Phase)
**Estimated Time:** 10 hours
**Owner:** `implementer` agent

**BFS Algorithm:**
```swift
public func retrieve(
    query: String,
    limit: Int,
    filter: MetadataFilter?
) async throws -> [RetrievalResult] {
    // 1. Get seed results via vector search
    let queryEmbedding = try await embeddingProvider.embed(query)
    let seedLimit = max(3, limit / 2)
    let seedResults = try await vectorStore.search(
        query: queryEmbedding,
        limit: seedLimit,
        filter: filter
    )

    // 2. Initialize BFS
    var visited: Set<String> = []
    var scores: [String: Float] = [:]
    var frontier = seedResults.map { $0.chunk.id }

    for seed in seedResults {
        scores[seed.chunk.id] = seed.score
        visited.insert(seed.chunk.id)
    }

    // 3. BFS expansion
    for hop in 0..<hops {
        var nextFrontier: [String] = []
        let decayFactor = Float(1.0 / Double(hop + 2))

        for nodeId in frontier {
            let neighbors = await graph.neighbors(of: nodeId)

            for edge in neighbors {
                guard !visited.contains(edge.targetId) else { continue }
                guard edge.weight >= edgeWeightThreshold else { continue }

                visited.insert(edge.targetId)
                nextFrontier.append(edge.targetId)

                // Propagate score with decay
                let parentScore = scores[nodeId] ?? 0
                let propagatedScore = parentScore * edge.weight * decayFactor
                scores[edge.targetId] = max(
                    scores[edge.targetId] ?? 0,
                    propagatedScore
                )
            }
        }

        frontier = nextFrontier
    }

    // 4. Fetch and rank
    let topIds = scores
        .sorted { $0.value > $1.value }
        .prefix(limit)
        .map { $0.key }

    return topIds.compactMap { id in
        guard let chunk = await graph.chunk(forId: id),
              let score = scores[id] else { return nil }

        return RetrievalResult(chunk: chunk, score: score, metadata: [:])
    }
}
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Retrieval/Retrievers/GraphRetriever.swift`

**Success Criteria:**
- [ ] All tests pass
- [ ] BFS terminates correctly
- [ ] Performance acceptable

---

### Task 4.3: RAGEvaluator Framework
**Priority:** P2
**Estimated Time:** 4 days
**Complexity:** High
**Dependencies:** RAGPipeline, LLMProvider

#### Sub-task 4.3.1: Evaluation Metrics Design
**Estimated Time:** 4 hours
**Owner:** `protocol-architect` agent

**Metrics to Implement:**

**Retrieval Metrics:**
1. **Precision** = Relevant Retrieved / Total Retrieved
2. **Recall** = Relevant Retrieved / Total Relevant
3. **F1 Score** = 2 * (Precision * Recall) / (Precision + Recall)
4. **Mean Reciprocal Rank (MRR)** = Average of 1/rank of first relevant result
5. **NDCG** = Normalized Discounted Cumulative Gain (position-aware)

**Generation Metrics:**
1. **Faithfulness** = Is answer grounded in retrieved context?
2. **Relevance** = Does answer address the query?
3. **Coherence** = Is answer well-structured?

**ChromaDB for Evaluation Storage:**
```swift
// Store evaluation runs for analysis
await chromaDB.addDocuments(
    collection: "rag_evaluation_runs",
    documents: [evaluationSummary],
    metadata: [
        "dataset": datasetName,
        "precision": precision,
        "recall": recall,
        "f1": f1Score,
        "faithfulness": faithfulness,
        "timestamp": timestamp
    ]
)
```

**Data Structures:**
```swift
public struct EvaluationItem: Sendable {
    public let query: String
    public let expectedChunkIds: [String]?
    public let groundTruthAnswer: String?
    public let relevantDocumentIds: [String]?
}

public struct EvaluationDataset: Sendable {
    public let items: [EvaluationItem]
    public let name: String
}

public struct RetrievalMetrics: Sendable {
    public let precision: Float
    public let recall: Float
    public let f1Score: Float
    public let mrr: Float
    public let ndcg: Float
    public let averageLatencyMs: Double
}

public struct GenerationMetrics: Sendable {
    public let faithfulness: Float
    public let relevance: Float
    public let coherence: Float
    public let averageLatencyMs: Double
}

public struct EvaluationResults: Sendable {
    public let retrievalMetrics: RetrievalMetrics
    public let generationMetrics: GenerationMetrics
    public let itemResults: [ItemResult]
    public let timestamp: Date
}
```

**Success Criteria:**
- [ ] Metrics mathematically defined
- [ ] Data structures Sendable
- [ ] Design reviewed

#### Sub-task 4.3.2: Test Design (TDD Red Phase)
**Estimated Time:** 8 hours
**Owner:** `test-specialist` agent

**Test Cases:**
1. **Precision/Recall Calculation** (`testPrecisionRecall`)
   - Retrieved: [A, B, C, D]
   - Relevant: [B, C, E, F]
   - Expected: Precision = 2/4 = 0.5, Recall = 2/4 = 0.5

2. **F1 Score** (`testF1Score`)
   - Perfect: P=1, R=1 → F1=1
   - Balanced: P=0.5, R=0.5 → F1=0.5
   - Imbalanced: P=0.9, R=0.3 → F1=0.45

3. **MRR Calculation** (`testMRR`)
   - Query 1: First relevant at rank 1 → 1/1 = 1.0
   - Query 2: First relevant at rank 3 → 1/3 = 0.33
   - MRR = (1.0 + 0.33) / 2 = 0.665

4. **Faithfulness Evaluation** (`testFaithfulnessScoring`)
   - Mock LLM judge returns scores
   - Verify: Scores in range [0, 1]
   - Test: Answer with hallucination gets low score

5. **End-to-End Evaluation** (`testFullEvaluation`)
   - Mock pipeline with known results
   - Dataset: 5 queries
   - Verify: All metrics calculated
   - Verify: Latency tracked

**Mock Setup:**
```swift
class MockRAGPipeline: RAGPipeline {
    var mockRetrievals: [String: [RetrievalResult]] = [:]
    var mockResponses: [String: RAGResponse] = [:]

    override func retrieve(_ query: String, limit: Int) async throws -> [RetrievalResult] {
        return mockRetrievals[query] ?? []
    }

    override func query(_ query: String) async throws -> RAGResponse {
        return mockResponses[query] ?? RAGResponse(answer: "", sources: [])
    }
}
```

**Test File:** `/Users/chriskarani/CodingProjects/zoni/Tests/ZoniTests/Evaluation/RAGEvaluatorTests.swift`

**Success Criteria:**
- [ ] All metric calculations testable
- [ ] Mock pipeline working
- [ ] Tests fail (Red phase)

#### Sub-task 4.3.3: Implementation (TDD Green Phase)
**Estimated Time:** 12 hours
**Owner:** `implementer` agent

**Core Evaluation Logic:**
```swift
public actor RAGEvaluator {
    private let pipeline: RAGPipeline
    private let llmJudge: (any LLMProvider)?

    public func evaluate(_ dataset: EvaluationDataset) async throws -> EvaluationResults {
        var itemResults: [EvaluationResults.ItemResult] = []

        for item in dataset.items {
            let result = try await evaluateItem(item)
            itemResults.append(result)
        }

        return EvaluationResults(
            retrievalMetrics: aggregateRetrievalMetrics(itemResults),
            generationMetrics: aggregateGenerationMetrics(itemResults),
            itemResults: itemResults,
            timestamp: Date()
        )
    }

    private func evaluateItem(_ item: EvaluationItem) async throws -> ItemResult {
        // Retrieval phase
        let retrievalStart = ContinuousClock.now
        let retrievalResults = try await pipeline.retrieve(item.query, limit: 10)
        let retrievalLatency = (ContinuousClock.now - retrievalStart).milliseconds

        let retrievedIds = Set(retrievalResults.map { $0.chunk.id })
        let relevantIds = Set(item.expectedChunkIds ?? [])

        let (precision, recall) = calculatePrecisionRecall(
            retrieved: retrievedIds,
            relevant: relevantIds
        )

        // Generation phase
        let generationStart = ContinuousClock.now
        let response = try await pipeline.query(item.query)
        let generationLatency = (ContinuousClock.now - generationStart).milliseconds

        // Faithfulness (optional)
        var faithfulness: Float? = nil
        if let judge = llmJudge, let groundTruth = item.groundTruthAnswer {
            faithfulness = try await calculateFaithfulness(
                answer: response.answer,
                context: retrievalResults.map { $0.chunk.content }.joined(separator: "\n"),
                groundTruth: groundTruth,
                judge: judge
            )
        }

        return ItemResult(
            query: item.query,
            retrievedChunkIds: Array(retrievedIds),
            generatedAnswer: response.answer,
            precision: precision,
            recall: recall,
            faithfulness: faithfulness,
            retrievalLatencyMs: Double(retrievalLatency),
            generationLatencyMs: Double(generationLatency)
        )
    }

    private func calculateFaithfulness(
        answer: String,
        context: String,
        groundTruth: String,
        judge: any LLMProvider
    ) async throws -> Float {
        let prompt = """
        Evaluate the faithfulness of this answer on a scale of 0.0 to 1.0.

        Context: \(context.prefix(2000))
        Answer: \(answer)
        Ground Truth: \(groundTruth)

        Respond with only a number between 0.0 and 1.0.
        """

        let response = try await judge.generate(prompt: prompt)
        return Float(response.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.5
    }
}
```

**File:** `/Users/chriskarani/CodingProjects/zoni/Sources/Zoni/Evaluation/RAGEvaluator.swift`

**Success Criteria:**
- [ ] All tests pass
- [ ] Metrics accurate
- [ ] Async evaluation efficient

---

## Workflow Orchestration

### Recommended Agent Sequence

For each feature implementation, follow this TDD workflow:

```
1. context-builder (if unfamiliar with codebase patterns)
   ↓
2. test-specialist (write failing tests - RED)
   ↓
3. implementer (make tests pass - GREEN)
   ↓
4. code-reviewer (refactor and optimize - REFACTOR)
   ↓
5. context-manager (checkpoint progress)
```

### Parallel Execution Opportunities

Tasks that can run in parallel:

**Phase 2 (P0 Features):**
- Task 2.3 (HuggingFace) || Task 2.4 (Mistral)
- Task 2.1 (ParentChildChunker) can start immediately
- Task 2.2 (ParentChildRetriever) blocks on 2.1 completion

**Phase 3 (P1 Features):**
- Task 3.1 (OCR) || Task 3.2 (TableExtractor)
- Both are independent, can run fully parallel

**Phase 4 (P2 Features):**
- Task 4.1 (ChunkGraph) must complete before Task 4.2 (GraphRetriever)
- Task 4.3 (RAGEvaluator) can run independently

### Critical Path

```
Week 1-2:  Task 2.1 → Task 2.2 (ParentChild features)
Week 2-3:  Task 2.3, Task 2.4 (Embedding providers - parallel)
Week 3-4:  Task 3.1, Task 3.2 (Preprocessing - parallel)
Week 5-6:  Task 4.1 → Task 4.2 (Graph retrieval)
Week 7-8:  Task 4.3 (Evaluation framework)
```

---

## ChromaDB Development Workflow

### Setup ChromaDB for Development

```swift
// Developer setup script
import ChromaDB

let chromaDB = ChromaDBClient(host: "localhost", port: 8000)

// Create development collections
await chromaDB.createCollection("parent_child_test_vectors")
await chromaDB.createCollection("embedding_benchmarks")
await chromaDB.createCollection("graph_validation")
await chromaDB.createCollection("evaluation_runs")
```

### Usage Patterns

**1. Test Fixture Storage:**
```swift
// Store test embeddings for consistent testing
await chromaDB.addDocuments(
    collection: "parent_child_test_vectors",
    documents: testChunks.map { $0.content },
    embeddings: knownEmbeddings,
    ids: testChunks.map { $0.id },
    metadata: testChunks.map { ["type": "test_fixture"] }
)
```

**2. Cross-Validation:**
```swift
// Compare Zoni results with ChromaDB reference
let chromaResults = await chromaDB.query(
    collection: "test_vectors",
    query: testQuery,
    limit: 10
)

let zoniResults = try await retriever.retrieve(query: testQuery, limit: 10)

// Assert results are similar
for (chroma, zoni) in zip(chromaResults, zoniResults) {
    XCTAssertEqual(chroma.id, zoni.chunk.id, accuracy: 0.01)
}
```

**3. Benchmark Storage:**
```swift
// Store performance baselines
await chromaDB.addDocuments(
    collection: "embedding_benchmarks",
    documents: [benchmarkSummary],
    metadata: [
        "provider": "huggingface",
        "model": "MiniLM",
        "batch_size": 32,
        "latency_ms": latency,
        "throughput_docs_per_sec": throughput
    ]
)
```

**4. Evaluation Result Tracking:**
```swift
// Track evaluation runs over time
await chromaDB.addDocuments(
    collection: "evaluation_runs",
    documents: [evaluationReport],
    metadata: [
        "version": "1.1.0",
        "dataset": "test_suite_v1",
        "precision": metrics.precision,
        "recall": metrics.recall,
        "timestamp": Date().iso8601
    ]
)
```

---

## Key Decision Points

### Decision 1: ParentChildRetriever Score Aggregation Default
**When:** Task 2.2.2
**Options:**
- `.max` - Simpler, rewards best child match
- `.average` - Balanced, reduces noise
- `.sum` - Rewards multiple child matches, but unbounded

**Recommendation:** Default to `.max`, allow configuration
**Rationale:** Most intuitive, aligns with standard retrieval expectations

### Decision 2: ChunkGraph Semantic Edge Threshold
**When:** Task 4.1.1
**Options:**
- 0.7 (loose) - More connections, slower search
- 0.8 (balanced) - Recommended default
- 0.9 (strict) - Sparse graph, faster search

**Recommendation:** Default 0.8, make configurable
**Rationale:** Empirical sweet spot for most embeddings

### Decision 3: RAGEvaluator LLM Judge Requirement
**When:** Task 4.3.1
**Options:**
- Required - Blocks evaluation without LLM
- Optional - Degrades gracefully

**Recommendation:** Optional with fallback to rule-based metrics
**Rationale:** Not all use cases have LLM access for evaluation

---

## Testing Strategy

### Test Coverage Targets
- Unit tests: 85%+ coverage
- Integration tests: All public APIs
- Performance tests: Critical paths (chunking, retrieval)

### Test Data Requirements

**Fixtures to Create:**
```
Tests/ZoniTests/Fixtures/
├── documents/
│   ├── sample_doc_small.txt (500 chars)
│   ├── sample_doc_medium.txt (5000 chars)
│   ├── sample_doc_large.txt (50000 chars)
│   └── sample_pdf.pdf
├── embeddings/
│   ├── openai_embeddings_384d.json
│   ├── openai_embeddings_1536d.json
│   └── huggingface_miniLM_384d.json
└── expected_results/
    ├── parent_child_chunks.json
    └── graph_structures.json

Tests/ZoniAppleTests/Fixtures/
├── images/
│   ├── test_document_clear.png
│   ├── test_document_blurry.png
│   └── test_table_simple.png
└── pdfs/
    └── test_document_3pages.pdf
```

### Performance Benchmarks

**Targets:**
- ParentChildChunker: 10MB doc in <1s
- ParentChildRetriever: 1000 chunks in <100ms
- HuggingFaceEmbedding: 32 texts in <500ms (network-dependent)
- ChunkGraph: 10K nodes in <5s
- GraphRetriever: 2-hop BFS in <200ms

---

## Risk Mitigation

### Risk 1: HuggingFace API Rate Limits
**Impact:** High
**Likelihood:** Medium
**Mitigation:**
- Implement exponential backoff
- Add request queuing
- Support batch API endpoints
- Provide clear error messages

### Risk 2: ChunkGraph Memory Explosion
**Impact:** High
**Likelihood:** Medium
**Mitigation:**
- Document memory requirements (O(n²) for semantic edges)
- Implement edge pruning (top-k per node)
- Add memory usage warnings
- Provide streaming graph construction

### Risk 3: Vision Framework Availability
**Impact:** Medium
**Likelihood:** Low
**Mitigation:**
- Strict `@available` annotations
- Runtime feature detection
- Clear documentation of requirements
- Fallback suggestions (external OCR services)

### Risk 4: RAGEvaluator Performance
**Impact:** Medium
**Likelihood:** Medium
**Mitigation:**
- Parallel evaluation of items
- Batch LLM judge calls
- Cache faithfulness scores
- Provide streaming evaluation results

---

## Success Metrics

### Phase 2 (P0) Success Criteria
- [ ] All P0 tests pass (100%)
- [ ] Code review approved
- [ ] Performance benchmarks met
- [ ] Documentation complete with examples
- [ ] Integration tests with existing RAGPipeline

### Phase 3 (P1) Success Criteria
- [ ] All P1 tests pass
- [ ] Works on macOS 10.15+, iOS 13+ (OCR)
- [ ] Works on macOS 13+, iOS 16+ (Tables)
- [ ] Sample images processed correctly

### Phase 4 (P2) Success Criteria
- [ ] All P2 tests pass
- [ ] Graph retrieval outperforms baseline on test dataset
- [ ] Evaluation metrics align with external tools
- [ ] Complete evaluation report generated

### Overall Success Criteria
- [ ] Swift 6 strict concurrency compliance
- [ ] No force unwraps or unsafe patterns
- [ ] All public APIs documented with DocC
- [ ] README updated with new features
- [ ] Migration guide published

---

## Appendix: File Locations Reference

### Source Files to Create

```
Sources/Zoni/Chunking/Strategies/
└── ParentChildChunker.swift

Sources/Zoni/Retrieval/
├── ParentLookup.swift
├── VectorStoreParentLookup.swift
└── Retrievers/
    ├── ParentChildRetriever.swift
    └── GraphRetriever.swift

Sources/Zoni/Retrieval/Graph/
└── ChunkGraph.swift

Sources/Zoni/Embedding/Providers/
├── HuggingFaceEmbedding.swift
└── MistralEmbedding.swift

Sources/Zoni/Evaluation/
└── RAGEvaluator.swift

Sources/ZoniApple/Preprocessing/
├── OCRProcessor.swift
└── TableExtractor.swift
```

### Test Files to Create

```
Tests/ZoniTests/Chunking/
└── ParentChildChunkerTests.swift

Tests/ZoniTests/Retrieval/
├── ParentChildRetrieverTests.swift
├── GraphRetrieverTests.swift
└── ChunkGraphTests.swift

Tests/ZoniTests/Embedding/
├── HuggingFaceEmbeddingTests.swift
└── MistralEmbeddingTests.swift

Tests/ZoniTests/Evaluation/
└── RAGEvaluatorTests.swift

Tests/ZoniAppleTests/Preprocessing/
├── OCRProcessorTests.swift
└── TableExtractorTests.swift
```

---

## Conclusion

This implementation plan provides a comprehensive, execution-ready breakdown of all tasks required for Zoni v1.1 and v1.2. The plan:

1. **Prioritizes TDD** - All features start with failing tests
2. **Leverages ChromaDB** - For validation, benchmarking, and development
3. **Maintains Quality** - Strict Swift 6 concurrency, no unsafe patterns
4. **Enables Parallelism** - Clear task dependencies for efficient execution
5. **Mitigates Risks** - Identified and addressed potential blockers

Each task is sized for a specialist agent to complete within 1-3 days, with clear success criteria and test coverage targets. The workflow orchestration ensures smooth handoffs between `test-specialist`, `implementer`, and `code-reviewer` agents.

**Total Estimated Time:** 8-10 weeks
**Recommended Team Size:** 2-3 developers working in parallel
**Next Step:** Begin with Phase 1 (Foundation Setup) and Task 2.1 (ParentChildChunker)
