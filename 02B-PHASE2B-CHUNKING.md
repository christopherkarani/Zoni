# Phase 2B: Chunking Strategies — Plan & Prompt

## Plan Overview

**Duration:** 3-4 days
**Dependencies:** Phase 1 (Core Foundation)
**Parallelizable With:** Phase 2A, Phase 2C

### Objectives
1. Implement multiple chunking strategies
2. Support overlap for context continuity
3. Preserve document structure where possible
4. Token-aware chunking

### Directory Structure
```
Sources/Zoni/Chunking/
├── Strategies/
│   ├── FixedSizeChunker.swift
│   ├── SentenceChunker.swift
│   ├── ParagraphChunker.swift
│   ├── RecursiveChunker.swift
│   ├── MarkdownChunker.swift
│   ├── CodeChunker.swift
│   └── SemanticChunker.swift
├── TokenCounter.swift
├── TextSplitter.swift
└── ChunkingUtils.swift
```

---

# Phase 2B Prompt: Chunking Strategies

You are implementing **Chunking Strategies** for Zoni — methods to split documents into optimal chunks for retrieval.

## Context

Chunking is critical for RAG quality. Chunks must be:
- Small enough to fit in context windows
- Large enough to contain meaningful information
- Overlapping to preserve context at boundaries
- Semantically coherent when possible

## Implementation Requirements

### 1. TokenCounter.swift

Estimate token counts for chunking decisions.

```swift
public struct TokenCounter: Sendable {
    public enum Model: Sendable {
        case cl100k   // GPT-4, text-embedding-3
        case p50k     // GPT-3
        case simple   // ~4 chars per token estimate
    }
    
    public let model: Model
    
    public init(model: Model = .simple)
    
    /// Estimate tokens in text
    public func count(_ text: String) -> Int
    
    /// Estimate tokens for array of texts
    public func count(_ texts: [String]) -> [Int]
    
    /// Split text to fit within token limit
    public func splitToFit(_ text: String, maxTokens: Int) -> [String]
}
```

For `.simple` model: `return max(1, text.count / 4)`

### 2. TextSplitter.swift

Core text splitting utilities.

```swift
public enum TextSplitter {
    /// Split on sentence boundaries
    public static func splitSentences(_ text: String) -> [String]
    
    /// Split on paragraph boundaries (double newline)
    public static func splitParagraphs(_ text: String) -> [String]
    
    /// Split on any separator
    public static func split(_ text: String, separators: [String]) -> [String]
    
    /// Split with regex pattern
    public static func split(_ text: String, pattern: String) -> [String]
    
    /// Merge small segments to meet minimum size
    public static func mergeSmall(_ segments: [String], minLength: Int, separator: String) -> [String]
}
```

### 3. FixedSizeChunker.swift

Simple fixed-size chunking with overlap.

```swift
public struct FixedSizeChunker: ChunkingStrategy {
    public let name = "fixed_size"
    
    public var chunkSize: Int          // Target characters per chunk
    public var chunkOverlap: Int       // Overlap between chunks
    public var useTokens: Bool         // If true, sizes are in tokens
    public var tokenCounter: TokenCounter?
    
    public init(
        chunkSize: Int = 1000,
        chunkOverlap: Int = 200,
        useTokens: Bool = false,
        tokenCounter: TokenCounter? = nil
    )
    
    public func chunk(_ document: Document) async throws -> [Chunk] {
        return try await chunk(document.content, metadata: ChunkMetadata(
            documentId: document.id,
            index: 0,
            source: document.metadata.source
        ))
    }
    
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
}
```

### 4. SentenceChunker.swift

Chunk on sentence boundaries.

```swift
public struct SentenceChunker: ChunkingStrategy {
    public let name = "sentence"
    
    public var targetSize: Int         // Target chunk size
    public var minSize: Int            // Minimum chunk size
    public var maxSize: Int            // Maximum chunk size
    public var overlapSentences: Int   // Number of sentences to overlap
    
    public init(
        targetSize: Int = 1000,
        minSize: Int = 100,
        maxSize: Int = 2000,
        overlapSentences: Int = 1
    )
    
    public func chunk(_ document: Document) async throws -> [Chunk]
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
}
```

### 5. ParagraphChunker.swift

Chunk on paragraph boundaries.

```swift
public struct ParagraphChunker: ChunkingStrategy {
    public let name = "paragraph"
    
    public var maxParagraphsPerChunk: Int
    public var maxChunkSize: Int
    public var overlapParagraphs: Int
    public var preserveShortParagraphs: Bool  // Keep short paragraphs together
    
    public init(
        maxParagraphsPerChunk: Int = 3,
        maxChunkSize: Int = 2000,
        overlapParagraphs: Int = 1
    )
    
    public func chunk(_ document: Document) async throws -> [Chunk]
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
}
```

### 6. RecursiveChunker.swift

LlamaIndex-style recursive splitting — tries larger separators first.

```swift
public struct RecursiveChunker: ChunkingStrategy {
    public let name = "recursive"
    
    /// Separators to try, in order (larger to smaller)
    public var separators: [String]
    public var chunkSize: Int
    public var chunkOverlap: Int
    public var useTokens: Bool
    
    public static let defaultSeparators = [
        "\n\n",     // Paragraphs
        "\n",       // Lines
        ". ",       // Sentences
        ", ",       // Clauses
        " ",        // Words
        ""          // Characters
    ]
    
    public init(
        separators: [String]? = nil,
        chunkSize: Int = 1000,
        chunkOverlap: Int = 200,
        useTokens: Bool = false
    )
    
    public func chunk(_ document: Document) async throws -> [Chunk]
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
    
    /// Recursively split text
    private func splitRecursively(_ text: String, separators: [String]) -> [String]
}
```

### 7. MarkdownChunker.swift

Structure-aware markdown chunking.

```swift
public struct MarkdownChunker: ChunkingStrategy {
    public let name = "markdown"
    
    public var maxChunkSize: Int
    public var includeHeaders: Bool      // Include parent headers in each chunk
    public var minHeaderLevel: Int       // Only split on headers >= this level
    public var chunkBySection: Bool      // Each section becomes a chunk
    
    public init(
        maxChunkSize: Int = 2000,
        includeHeaders: Bool = true,
        minHeaderLevel: Int = 2,
        chunkBySection: Bool = true
    )
    
    public func chunk(_ document: Document) async throws -> [Chunk]
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
    
    /// Parse markdown structure
    private func parseStructure(_ markdown: String) -> [MarkdownSection]
}

struct MarkdownSection {
    let headerLevel: Int
    let title: String
    let content: String
    let children: [MarkdownSection]
}
```

### 8. CodeChunker.swift

Language-aware code chunking.

```swift
public struct CodeChunker: ChunkingStrategy {
    public let name = "code"
    
    public enum Language: String, Sendable {
        case swift, python, javascript, typescript, java, go, rust
        case unknown
    }
    
    public var language: Language
    public var maxChunkSize: Int
    public var chunkByFunction: Bool     // Each function/method as chunk
    public var chunkByClass: Bool        // Each class as chunk
    public var includeImports: Bool      // Include imports in each chunk
    
    public init(
        language: Language = .unknown,
        maxChunkSize: Int = 2000,
        chunkByFunction: Bool = true
    )
    
    /// Auto-detect language from content or file extension
    public static func detectLanguage(_ content: String, extension: String?) -> Language
    
    public func chunk(_ document: Document) async throws -> [Chunk]
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
}
```

Use regex-based splitting for functions/classes (no full AST parsing):
```swift
// Swift function pattern
let swiftFunctionPattern = #"(?:public|private|internal|fileprivate|open)?\s*(?:static)?\s*func\s+\w+.*?\{[\s\S]*?\n\}"#
```

### 9. SemanticChunker.swift

Embedding-based semantic chunking — splits where meaning changes.

```swift
public actor SemanticChunker: ChunkingStrategy {
    public let name = "semantic"
    
    private let embeddingProvider: any EmbeddingProvider
    
    public var targetChunkSize: Int
    public var similarityThreshold: Float   // Split when similarity drops below
    public var windowSize: Int              // Sentences to compare
    
    public init(
        embeddingProvider: any EmbeddingProvider,
        targetChunkSize: Int = 1000,
        similarityThreshold: Float = 0.5,
        windowSize: Int = 3
    )
    
    public func chunk(_ document: Document) async throws -> [Chunk]
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk]
    
    /// Find semantic breakpoints
    private func findBreakpoints(_ sentences: [String]) async throws -> [Int]
}
```

### 10. ChunkingUtils.swift

Utility functions.

```swift
public enum ChunkingUtils {
    /// Add overlap between chunks
    public static func addOverlap(
        to chunks: [Chunk],
        overlapSize: Int,
        originalText: String
    ) -> [Chunk]
    
    /// Remove overlap for content deduplication
    public static func removeOverlap(_ chunks: [Chunk]) -> [Chunk]
    
    /// Validate chunks don't exceed size
    public static func validate(_ chunks: [Chunk], maxSize: Int) -> [ChunkValidationError]
    
    /// Compute chunk statistics
    public static func statistics(_ chunks: [Chunk]) -> ChunkStatistics
}

public struct ChunkStatistics: Sendable {
    public let count: Int
    public let totalCharacters: Int
    public let averageSize: Int
    public let minSize: Int
    public let maxSize: Int
    public let overlapPercentage: Double
}
```

## Tests

### ChunkingTests.swift
- Test FixedSizeChunker produces correct sizes
- Test overlap is applied correctly
- Test RecursiveChunker respects boundaries
- Test MarkdownChunker preserves structure
- Test CodeChunker detects language
- Test no content loss: `chunks.joined() ≈ original`

## Key Behaviors

1. **No Content Loss:** Chunks must reassemble to original (minus overlap duplication)
2. **Respect Boundaries:** Prefer splitting at natural boundaries
3. **Overlap Consistency:** Overlap should be at chunk boundaries, not arbitrary
4. **Metadata Preservation:** Each chunk has proper `documentId`, `index`, offsets

## Code Standards

- All chunkers `Sendable`
- Document all public APIs
- Handle edge cases (empty text, single sentence, etc.)
- Efficient for large documents

## Verification

```bash
swift build
swift test --filter Chunking
```
