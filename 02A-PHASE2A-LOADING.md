# Phase 2A: Document Loading — Plan & Prompt

## Plan Overview

**Duration:** 4-5 days
**Dependencies:** Phase 1 (Core Foundation)
**Parallelizable With:** Phase 2B, Phase 2C

### Objectives
1. Implement document loaders for common formats
2. Support both file and URL sources
3. Handle streaming/large files efficiently
4. Cross-platform compatibility (Linux + Apple)

### Directory Structure
```
Sources/Zoni/Loading/
├── Loaders/
│   ├── TextLoader.swift
│   ├── MarkdownLoader.swift
│   ├── JSONLoader.swift
│   ├── CSVLoader.swift
│   ├── HTMLLoader.swift
│   ├── WebLoader.swift
│   └── PDFLoader.swift
├── DirectoryLoader.swift
├── LoaderRegistry.swift
└── LoadingUtils.swift
```

---

# Phase 2A Prompt: Document Loading

You are continuing work on **Zoni**. Phase 1 (Core Foundation) is complete. You are implementing **Document Loading** — loaders for various file formats.

## Implementation Requirements

### 1. TextLoader.swift

Load plain text files.

```swift
public struct TextLoader: DocumentLoader {
    public static let supportedExtensions: Set<String> = ["txt", "text"]
    
    public init()
    
    public func load(from url: URL) async throws -> Document {
        let data = try Data(contentsOf: url)
        return try load(from: data, metadata: DocumentMetadata(source: url.path, url: url))
    }
    
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ZoniError.invalidData(reason: "Unable to decode text as UTF-8")
        }
        return Document(content: content, metadata: metadata ?? DocumentMetadata())
    }
}
```

### 2. MarkdownLoader.swift

Load markdown with frontmatter extraction.

```swift
public struct MarkdownLoader: DocumentLoader {
    public static let supportedExtensions: Set<String> = ["md", "markdown"]
    
    public var extractFrontmatter: Bool = true
    
    public init(extractFrontmatter: Bool = true)
    
    public func load(from url: URL) async throws -> Document
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document
    
    /// Parse YAML frontmatter from markdown
    private func parseFrontmatter(_ content: String) -> (frontmatter: [String: String], body: String)
}
```

Frontmatter format:
```markdown
---
title: My Document
author: John Doe
date: 2024-01-01
---

# Content here
```

### 3. JSONLoader.swift

Load JSON with JSONPath extraction.

```swift
public struct JSONLoader: DocumentLoader {
    public static let supportedExtensions: Set<String> = ["json"]
    
    /// JSONPath to content field (e.g., "$.content" or "$.data.text")
    public var contentPath: String?
    
    /// JSONPath to metadata fields
    public var metadataPaths: [String: String]?
    
    public init(contentPath: String? = nil, metadataPaths: [String: String]? = nil)
    
    public func load(from url: URL) async throws -> Document
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document
    
    /// Load JSON array as multiple documents
    public func loadMultiple(from url: URL, arrayPath: String?) async throws -> [Document]
}
```

### 4. CSVLoader.swift

Load CSV files as documents.

```swift
public struct CSVLoader: DocumentLoader {
    public static let supportedExtensions: Set<String> = ["csv", "tsv"]
    
    /// Column to use as content
    public var contentColumn: String?
    
    /// Columns to use as metadata
    public var metadataColumns: [String]?
    
    /// Whether first row is headers
    public var hasHeaders: Bool = true
    
    /// Delimiter (comma for CSV, tab for TSV)
    public var delimiter: Character = ","
    
    public init(contentColumn: String? = nil, metadataColumns: [String]? = nil)
    
    /// Load as single document (all rows combined)
    public func load(from url: URL) async throws -> Document
    
    /// Load each row as a separate document
    public func loadRows(from url: URL) async throws -> [Document]
}
```

### 5. HTMLLoader.swift

Load HTML with content extraction.

```swift
import SwiftSoup  // Add to Package.swift

public struct HTMLLoader: DocumentLoader {
    public static let supportedExtensions: Set<String> = ["html", "htm"]
    
    /// CSS selectors for content (e.g., "article", "main", ".content")
    public var contentSelectors: [String]?
    
    /// CSS selectors to exclude (e.g., "nav", "footer", ".ads")
    public var excludeSelectors: [String]?
    
    /// Extract metadata from meta tags
    public var extractMetaTags: Bool = true
    
    public init(
        contentSelectors: [String]? = nil,
        excludeSelectors: [String]? = ["nav", "footer", "header", "script", "style"]
    )
    
    public func load(from url: URL) async throws -> Document
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document
    
    /// Extract clean text from HTML
    private func extractText(from html: String) throws -> String
}
```

### 6. WebLoader.swift

Fetch and load web pages.

```swift
import AsyncHTTPClient  // Add to Package.swift

public actor WebLoader: DocumentLoader {
    public static let supportedExtensions: Set<String> = []  // Handles URLs
    
    private let httpClient: HTTPClient
    private let htmlLoader: HTMLLoader
    
    public var userAgent: String = "Zoni/1.0"
    public var timeout: Duration = .seconds(30)
    public var followRedirects: Bool = true
    
    public init(httpClient: HTTPClient? = nil)
    
    public func load(from url: URL) async throws -> Document {
        // Fetch URL content
        var request = HTTPClientRequest(url: url.absoluteString)
        request.headers.add(name: "User-Agent", value: userAgent)
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 10 * 1024 * 1024)
        
        // Parse HTML
        return try await htmlLoader.load(from: Data(buffer: body), metadata: DocumentMetadata(url: url))
    }
    
    /// Load multiple URLs concurrently
    public func loadMultiple(urls: [URL], maxConcurrency: Int = 5) async throws -> [Document]
    
    public func canLoad(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}
```

### 7. PDFLoader.swift

Cross-platform PDF loading.

```swift
public struct PDFLoader: DocumentLoader {
    public static let supportedExtensions: Set<String> = ["pdf"]
    
    /// Extract images as base64 (expensive)
    public var extractImages: Bool = false
    
    /// Page range to extract (nil = all pages)
    public var pageRange: ClosedRange<Int>?
    
    public init(extractImages: Bool = false, pageRange: ClosedRange<Int>? = nil)
    
    public func load(from url: URL) async throws -> Document
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document
    
    /// Load each page as a separate document
    public func loadPages(from url: URL) async throws -> [Document]
}

// Use conditional compilation for implementation:
// - Apple: PDFKit
// - Linux: External library or basic text extraction
```

### 8. DirectoryLoader.swift

Recursively load directories.

```swift
public actor DirectoryLoader {
    private let loaderRegistry: LoaderRegistry
    
    public var recursive: Bool = true
    public var includeHidden: Bool = false
    public var fileExtensions: Set<String>?  // nil = all supported
    public var excludePatterns: [String]?    // Glob patterns
    
    public init(registry: LoaderRegistry = .default)
    
    /// Load all documents from a directory
    public func load(from directory: URL) async throws -> [Document]
    
    /// Stream documents as they're loaded
    public func loadStream(from directory: URL) -> AsyncThrowingStream<Document, Error>
    
    /// Get list of files that would be loaded
    public func listFiles(in directory: URL) async throws -> [URL]
}
```

### 9. LoaderRegistry.swift

Registry for document loaders.

```swift
public actor LoaderRegistry {
    private var loaders: [String: any DocumentLoader] = [:]
    
    public static let `default`: LoaderRegistry = {
        let registry = LoaderRegistry()
        Task {
            await registry.register(TextLoader())
            await registry.register(MarkdownLoader())
            await registry.register(JSONLoader())
            await registry.register(CSVLoader())
            await registry.register(HTMLLoader())
            await registry.register(PDFLoader())
        }
        return registry
    }()
    
    /// Register a loader for its supported extensions
    public func register(_ loader: any DocumentLoader)
    
    /// Get loader for a file extension
    public func loader(for extension: String) -> (any DocumentLoader)?
    
    /// Get loader for a URL
    public func loader(for url: URL) -> (any DocumentLoader)?
    
    /// Load a document using appropriate loader
    public func load(from url: URL) async throws -> Document
}
```

### 10. LoadingUtils.swift

Utility functions.

```swift
public enum LoadingUtils {
    /// Detect file encoding
    public static func detectEncoding(_ data: Data) -> String.Encoding
    
    /// Extract text from various binary formats
    public static func extractText(from data: Data, mimeType: String?) -> String?
    
    /// Normalize whitespace in text
    public static func normalizeWhitespace(_ text: String) -> String
    
    /// Clean text for embedding (remove special chars, etc.)
    public static func cleanForEmbedding(_ text: String) -> String
}
```

## Package.swift Updates

```swift
dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
],
targets: [
    .target(
        name: "Zoni",
        dependencies: [
            .product(name: "SwiftSoup", package: "SwiftSoup"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
        ]
    ),
]
```

## Tests

### LoaderTests.swift
- Test TextLoader with various encodings
- Test MarkdownLoader frontmatter extraction
- Test JSONLoader with JSONPath
- Test CSVLoader row extraction
- Test HTMLLoader content extraction
- Test DirectoryLoader recursive loading
- Test LoaderRegistry automatic loader selection

## Code Standards

- All loaders must be `Sendable`
- Handle large files efficiently (streaming where possible)
- Proper error handling with descriptive messages
- Cross-platform compatibility (conditional compilation for PDF)

## Verification

```bash
swift build
swift test --filter Loading
```
