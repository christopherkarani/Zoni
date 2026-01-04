// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Code-aware chunking strategy for splitting source code at function boundaries.

import Foundation

// MARK: - CodeChunker

/// A chunking strategy that splits source code at function and method boundaries.
///
/// `CodeChunker` provides intelligent code-aware chunking that respects the structure
/// of source code files. It can detect the programming language and split code at
/// natural boundaries like function definitions, class declarations, and module imports.
///
/// The chunker supports multiple programming languages and can:
/// - Detect language from file extension or content analysis
/// - Split by function/method boundaries
/// - Include import statements at the start of each chunk for context
/// - Respect maximum chunk size constraints
///
/// ## Supported Languages
/// - Swift
/// - Python
/// - JavaScript/TypeScript
/// - Java
/// - Go
/// - Rust
///
/// ## Example Usage
/// ```swift
/// // Basic code chunking with auto-detection
/// let chunker = CodeChunker()
/// let chunks = try await chunker.chunk(document)
///
/// // Language-specific chunking
/// let swiftChunker = CodeChunker(
///     language: .swift,
///     maxChunkSize: 1500,
///     chunkByFunction: true,
///     includeImports: true
/// )
/// let swiftChunks = try await swiftChunker.chunk(document)
/// ```
///
/// ## Performance Considerations
/// - Language detection adds minimal overhead when the language is not specified
/// - Function boundary detection uses regex patterns optimized for each language
/// - Large files with many small functions may produce many chunks
public struct CodeChunker: ChunkingStrategy, Sendable {

    // MARK: - Language

    /// Supported programming languages for code chunking.
    ///
    /// Each language has specific patterns for detecting function boundaries,
    /// import statements, and code structure.
    public enum Language: String, Sendable, CaseIterable {
        /// Swift programming language
        case swift
        /// Python programming language
        case python
        /// JavaScript programming language
        case javascript
        /// TypeScript programming language
        case typescript
        /// Java programming language
        case java
        /// Go programming language
        case go
        /// Rust programming language
        case rust
        /// Unknown or unsupported language
        case unknown
    }

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"code"` for identification in configurations and logging.
    public let name = "code"

    /// The programming language to use for parsing.
    ///
    /// When set to `.unknown`, the chunker will attempt to detect the language
    /// from the file extension or content analysis.
    public var language: Language

    /// The maximum size for each chunk in characters.
    ///
    /// Functions that exceed this size will be split into smaller chunks.
    /// Defaults to 2000 characters.
    public var maxChunkSize: Int

    /// Whether to split code at function/method boundaries.
    ///
    /// When `true`, the chunker will identify function definitions and create
    /// separate chunks for each function. When `false`, the code will be split
    /// using a simpler character-based approach.
    public var chunkByFunction: Bool

    /// Whether to include import statements at the start of each chunk.
    ///
    /// When `true`, import/include statements from the beginning of the file
    /// are prepended to each chunk to provide context for the code.
    public var includeImports: Bool

    // MARK: - Initialization

    /// Creates a new code-aware chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - language: The programming language to use. Defaults to `.unknown` for auto-detection.
    ///   - maxChunkSize: The maximum chunk size in characters. Defaults to 2000.
    ///   - chunkByFunction: Whether to split at function boundaries. Defaults to `true`.
    ///   - includeImports: Whether to include imports in each chunk. Defaults to `true`.
    public init(
        language: Language = .unknown,
        maxChunkSize: Int = 2000,
        chunkByFunction: Bool = true,
        includeImports: Bool = true
    ) {
        self.language = language
        self.maxChunkSize = max(100, maxChunkSize)
        self.chunkByFunction = chunkByFunction
        self.includeImports = includeImports
    }

    // MARK: - Language Detection

    /// Detects the programming language from content and file extension.
    ///
    /// The detection uses a combination of file extension matching and content
    /// analysis to identify the language. File extension takes precedence when available.
    ///
    /// - Parameters:
    ///   - content: The source code content to analyze.
    ///   - fileExtension: The file extension (without the dot), if available.
    /// - Returns: The detected language, or `.unknown` if detection fails.
    ///
    /// ## Detection Rules
    /// - **Swift**: `.swift` extension or `import`, `func`, `struct`, `class`, `enum` keywords
    /// - **Python**: `.py` extension or `def`, `import`, `class` keywords with indentation
    /// - **JavaScript**: `.js` extension or `function`, `const`, `let`, `export`, `import` keywords
    /// - **TypeScript**: `.ts`, `.tsx` extension or TypeScript-specific syntax
    /// - **Java**: `.java` extension or `public class`, `import`, `void` keywords
    /// - **Go**: `.go` extension or `func`, `package`, `import` keywords
    /// - **Rust**: `.rs` extension or `fn`, `use`, `mod`, `pub` keywords
    public static func detectLanguage(_ content: String, fileExtension: String?) -> Language {
        // First, try to detect from file extension
        if let ext = fileExtension?.lowercased() {
            switch ext {
            case "swift":
                return .swift
            case "py":
                return .python
            case "js", "jsx", "mjs", "cjs":
                return .javascript
            case "ts", "tsx":
                return .typescript
            case "java":
                return .java
            case "go":
                return .go
            case "rs":
                return .rust
            default:
                break
            }
        }

        // Fall back to content analysis
        return detectLanguageFromContent(content)
    }

    // MARK: - Public Methods

    /// Chunks a document containing source code.
    ///
    /// Extracts the content from the document and creates chunks with metadata
    /// linking back to the source document. The document's ID and source are
    /// preserved in the chunk metadata.
    ///
    /// - Parameter document: The document to chunk.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/emptyDocument`` if the document content is empty.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = CodeChunker(language: .swift)
    /// let chunks = try await chunker.chunk(document)
    /// for chunk in chunks {
    ///     print("Chunk \(chunk.metadata.index): \(chunk.characterCount) chars")
    /// }
    /// ```
    public func chunk(_ document: Document) async throws -> [Chunk] {
        // Extract file extension from document source or URL
        let fileExtension = extractFileExtension(from: document)

        let baseMetadata = ChunkMetadata(
            documentId: document.id,
            index: 0,
            source: document.metadata.source
        )

        return try await chunkCode(
            document.content,
            metadata: baseMetadata,
            fileExtension: fileExtension
        )
    }

    /// Chunks raw source code text with optional metadata.
    ///
    /// Use this method when working with source code that is not wrapped in a `Document`,
    /// or when you need to provide custom base metadata for the resulting chunks.
    ///
    /// - Parameters:
    ///   - text: The source code to chunk.
    ///   - metadata: Base metadata to include in each chunk. If `nil`, a new
    ///     document ID is generated and used for all chunks.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/emptyDocument`` if the text is empty or whitespace-only.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = CodeChunker(language: .python)
    /// let chunks = try await chunker.chunk(pythonCode, metadata: nil)
    /// ```
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk] {
        return try await chunkCode(text, metadata: metadata, fileExtension: nil)
    }

    // MARK: - Private Methods

    /// Core chunking implementation with file extension support.
    private func chunkCode(
        _ text: String,
        metadata: ChunkMetadata?,
        fileExtension: String?
    ) async throws -> [Chunk] {
        // Validate input
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ZoniError.emptyDocument
        }

        // Prepare base metadata
        let baseDocumentId = metadata?.documentId ?? UUID().uuidString
        let baseSource = metadata?.source
        let baseCustom = metadata?.custom ?? [:]

        // Determine the language
        let detectedLanguage: Language
        if language == .unknown {
            detectedLanguage = Self.detectLanguage(trimmedText, fileExtension: fileExtension)
        } else {
            detectedLanguage = language
        }

        // Extract imports if needed
        let imports = includeImports ? extractImports(from: trimmedText, language: detectedLanguage) : ""

        // Chunk based on configuration
        if chunkByFunction {
            return chunkByFunctions(
                text: trimmedText,
                imports: imports,
                language: detectedLanguage,
                documentId: baseDocumentId,
                source: baseSource,
                custom: baseCustom
            )
        } else {
            return chunkBySize(
                text: trimmedText,
                imports: imports,
                documentId: baseDocumentId,
                source: baseSource,
                custom: baseCustom
            )
        }
    }

    /// Detects language from content analysis.
    private static func detectLanguageFromContent(_ content: String) -> Language {
        let sample = String(content.prefix(2000))

        // Swift detection
        let swiftPatterns = [
            #"^\s*import\s+\w+"#,
            #"\bfunc\s+\w+\s*\("#,
            #"\bstruct\s+\w+"#,
            #"\bclass\s+\w+\s*[:{]"#,
            #"\benum\s+\w+"#,
            #"\bvar\s+\w+\s*:"#,
            #"\blet\s+\w+\s*[:=]"#,
            #"@\w+\s+(struct|class|func|var)"#
        ]

        // Python detection
        let pythonPatterns = [
            #"^\s*def\s+\w+\s*\("#,
            #"^\s*class\s+\w+\s*[:\(]"#,
            #"^\s*import\s+\w+"#,
            #"^\s*from\s+\w+\s+import"#,
            #":\s*$"#,
            #"^\s{4,}"#
        ]

        // JavaScript/TypeScript detection
        let jsPatterns = [
            #"\bfunction\s+\w+\s*\("#,
            #"\bconst\s+\w+\s*="#,
            #"\blet\s+\w+\s*="#,
            #"\bexport\s+(default\s+)?(function|class|const)"#,
            #"^\s*import\s+.*\s+from\s+['\"]"#,
            #"=>\s*\{"#
        ]

        // TypeScript-specific patterns
        let tsPatterns = [
            #":\s*(string|number|boolean|void|any)\b"#,
            #"interface\s+\w+"#,
            #"type\s+\w+\s*="#,
            #"<\w+>"#
        ]

        // Java detection
        let javaPatterns = [
            #"public\s+class\s+\w+"#,
            #"public\s+static\s+void\s+main"#,
            #"^\s*import\s+[\w.]+;"#,
            #"(public|private|protected)\s+(static\s+)?\w+\s+\w+\s*\("#
        ]

        // Go detection
        let goPatterns = [
            #"^\s*package\s+\w+"#,
            #"^\s*func\s+(\(\w+\s+\*?\w+\)\s+)?\w+\s*\("#,
            #"^\s*import\s+\("#,
            #":=\s*"#,
            #"\btype\s+\w+\s+struct\b"#
        ]

        // Rust detection
        let rustPatterns = [
            #"^\s*fn\s+\w+\s*[<\(]"#,
            #"^\s*use\s+[\w:]+;"#,
            #"^\s*mod\s+\w+"#,
            #"^\s*pub\s+(fn|struct|enum|mod)"#,
            #"let\s+mut\s+\w+"#,
            #"->\s*\w+"#
        ]

        // Score each language
        var scores: [Language: Int] = [:]

        scores[.swift] = countMatches(in: sample, patterns: swiftPatterns)
        scores[.python] = countMatches(in: sample, patterns: pythonPatterns)
        scores[.javascript] = countMatches(in: sample, patterns: jsPatterns)
        scores[.typescript] = countMatches(in: sample, patterns: jsPatterns) + countMatches(in: sample, patterns: tsPatterns)
        scores[.java] = countMatches(in: sample, patterns: javaPatterns)
        scores[.go] = countMatches(in: sample, patterns: goPatterns)
        scores[.rust] = countMatches(in: sample, patterns: rustPatterns)

        // Return the language with the highest score
        let sortedScores = scores.sorted { $0.value > $1.value }
        if let best = sortedScores.first, best.value > 0 {
            return best.key
        }

        return .unknown
    }

    /// Counts regex pattern matches in text.
    private static func countMatches(in text: String, patterns: [String]) -> Int {
        var count = 0
        for pattern in patterns {
            if let regex = try? Regex(pattern) {
                let matches = text.matches(of: regex)
                count += matches.count
            }
        }
        return count
    }

    /// Extracts import statements from source code.
    private func extractImports(from text: String, language: Language) -> String {
        let lines = text.components(separatedBy: .newlines)
        var imports: [String] = []

        let importPatterns: [String]
        switch language {
        case .swift:
            importPatterns = [#"^\s*import\s+"#, #"^\s*@_exported\s+import"#]
        case .python:
            importPatterns = [#"^\s*import\s+"#, #"^\s*from\s+\w+\s+import"#]
        case .javascript, .typescript:
            importPatterns = [#"^\s*import\s+"#, #"^\s*require\s*\("#]
        case .java:
            importPatterns = [#"^\s*import\s+[\w.*]+;"#, #"^\s*package\s+"#]
        case .go:
            importPatterns = [#"^\s*import\s+"#, #"^\s*package\s+"#]
        case .rust:
            importPatterns = [#"^\s*use\s+"#, #"^\s*mod\s+"#, #"^\s*extern\s+crate"#]
        case .unknown:
            importPatterns = [#"^\s*import\s+"#, #"^\s*use\s+"#, #"^\s*from\s+.*\s+import"#]
        }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                continue
            }

            // Check if line matches any import pattern
            var isImport = false
            for pattern in importPatterns {
                if let regex = try? Regex(pattern), trimmedLine.firstMatch(of: regex) != nil {
                    isImport = true
                    break
                }
            }

            if isImport {
                imports.append(line)
            } else if !imports.isEmpty {
                // Stop at first non-import, non-empty line (after we have found some imports)
                // But continue if we see comments or empty lines
                if !trimmedLine.hasPrefix("//") && !trimmedLine.hasPrefix("#") &&
                   !trimmedLine.hasPrefix("/*") && !trimmedLine.hasPrefix("*") {
                    break
                }
            }
        }

        return imports.isEmpty ? "" : imports.joined(separator: "\n") + "\n\n"
    }

    /// Gets the function boundary regex pattern for a language.
    private func getFunctionPattern(for language: Language) -> String {
        switch language {
        case .swift:
            // Match func, init, deinit, subscript, and computed properties
            return #"(?m)^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|private|internal|fileprivate|open|static|class|override|final|mutating|nonmutating)*\s*(?:func|init|deinit|subscript)\s+[^\{]*\{"#
        case .python:
            // Match def and class definitions (including async)
            return #"(?m)^(?:async\s+)?def\s+\w+\s*\([^)]*\)\s*(?:->[^:]+)?:"#
        case .javascript, .typescript:
            // Match function declarations, arrow functions, and methods
            return #"(?m)^[ \t]*(?:export\s+)?(?:async\s+)?(?:function\s+\w+|(?:const|let|var)\s+\w+\s*=\s*(?:async\s+)?(?:function|\([^)]*\)\s*=>|\w+\s*=>))"#
        case .java:
            // Match method definitions
            return #"(?m)^[ \t]*(?:public|private|protected)?\s*(?:static\s+)?(?:final\s+)?(?:synchronized\s+)?(?:\w+(?:<[^>]+>)?\s+)+\w+\s*\([^)]*\)\s*(?:throws\s+[\w,\s]+)?\s*\{"#
        case .go:
            // Match func definitions including methods
            return #"(?m)^func\s+(?:\([^)]+\)\s*)?\w+\s*\([^)]*\)\s*(?:\([^)]+\)|\w+)?\s*\{"#
        case .rust:
            // Match fn definitions including pub and async
            return #"(?m)^[ \t]*(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?(?:unsafe\s+)?(?:extern\s+"[^"]+"\s+)?fn\s+\w+(?:<[^>]+>)?\s*\([^)]*\)"#
        case .unknown:
            // Generic pattern that might catch function-like structures
            return #"(?m)^[ \t]*(?:func|function|def|fn)\s+\w+\s*\("#
        }
    }

    /// Chunks code by function boundaries.
    private func chunkByFunctions(
        text: String,
        imports: String,
        language: Language,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        let pattern = getFunctionPattern(for: language)

        guard let regex = try? Regex(pattern) else {
            // Fallback to size-based chunking if pattern compilation fails
            return chunkBySize(
                text: text,
                imports: imports,
                documentId: documentId,
                source: source,
                custom: custom
            )
        }

        // Find all function boundaries
        let matches = text.matches(of: regex)

        if matches.isEmpty {
            // No functions found, fallback to size-based chunking
            return chunkBySize(
                text: text,
                imports: imports,
                documentId: documentId,
                source: source,
                custom: custom
            )
        }

        var chunks: [Chunk] = []
        var chunkIndex = 0
        var previousEnd = text.startIndex

        // Process text between and including function definitions
        for (index, match) in matches.enumerated() {
            let matchStart = match.range.lowerBound

            // Handle code before the first function (or between functions)
            if matchStart > previousEnd {
                let prefixText = String(text[previousEnd..<matchStart])
                let trimmedPrefix = prefixText.trimmingCharacters(in: .whitespacesAndNewlines)

                // If there is significant code before this function, create a chunk
                if !trimmedPrefix.isEmpty && trimmedPrefix.count > 20 {
                    let startOffset = text.distance(from: text.startIndex, to: previousEnd)
                    let endOffset = text.distance(from: text.startIndex, to: matchStart)

                    let newChunks = createChunksFromBlock(
                        content: trimmedPrefix,
                        imports: chunkIndex == 0 ? "" : imports,
                        startOffset: startOffset,
                        endOffset: endOffset,
                        startingIndex: chunkIndex,
                        documentId: documentId,
                        source: source,
                        custom: custom
                    )
                    chunks.append(contentsOf: newChunks)
                    chunkIndex += newChunks.count
                }
            }

            // Find the end of this function
            let functionEnd: String.Index
            if index + 1 < matches.count {
                functionEnd = matches[index + 1].range.lowerBound
            } else {
                functionEnd = text.endIndex
            }

            // Extract function body
            let functionText = String(text[matchStart..<functionEnd])
            let trimmedFunction = functionText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedFunction.isEmpty {
                let startOffset = text.distance(from: text.startIndex, to: matchStart)
                let endOffset = text.distance(from: text.startIndex, to: functionEnd)

                let newChunks = createChunksFromBlock(
                    content: trimmedFunction,
                    imports: imports,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    startingIndex: chunkIndex,
                    documentId: documentId,
                    source: source,
                    custom: custom
                )
                chunks.append(contentsOf: newChunks)
                chunkIndex += newChunks.count
            }

            previousEnd = functionEnd
        }

        // Handle any remaining code after the last function
        if previousEnd < text.endIndex {
            let remainingText = String(text[previousEnd..<text.endIndex])
            let trimmedRemaining = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedRemaining.isEmpty && trimmedRemaining.count > 20 {
                let startOffset = text.distance(from: text.startIndex, to: previousEnd)
                let endOffset = text.count

                let newChunks = createChunksFromBlock(
                    content: trimmedRemaining,
                    imports: imports,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    startingIndex: chunkIndex,
                    documentId: documentId,
                    source: source,
                    custom: custom
                )
                chunks.append(contentsOf: newChunks)
            }
        }

        // If no chunks were created, create at least one
        if chunks.isEmpty {
            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: 0,
                startOffset: 0,
                endOffset: text.count,
                source: source,
                custom: custom
            )
            chunks.append(Chunk(content: text, metadata: chunkMetadata))
        }

        return chunks
    }

    /// Creates chunks from a block of code, splitting if necessary.
    private func createChunksFromBlock(
        content: String,
        imports: String,
        startOffset: Int,
        endOffset: Int,
        startingIndex: Int,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        let fullContent = imports + content
        let effectiveMaxSize = maxChunkSize

        // If content fits in one chunk, return it
        if fullContent.count <= effectiveMaxSize {
            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: startingIndex,
                startOffset: startOffset,
                endOffset: endOffset,
                source: source,
                custom: custom
            )
            return [Chunk(content: fullContent, metadata: chunkMetadata)]
        }

        // Split large blocks
        var chunks: [Chunk] = []
        var chunkIndex = startingIndex
        var currentPosition = content.startIndex
        let importsLength = imports.count
        let contentMaxSize = effectiveMaxSize - importsLength

        while currentPosition < content.endIndex {
            let remainingDistance = content.distance(from: currentPosition, to: content.endIndex)
            let chunkLength = min(max(100, contentMaxSize), remainingDistance)

            var endPosition = content.index(currentPosition, offsetBy: chunkLength)

            // Try to find a good break point (newline, semicolon, brace)
            if endPosition < content.endIndex {
                let searchStart = content.index(currentPosition, offsetBy: max(0, chunkLength - 100), limitedBy: content.endIndex) ?? currentPosition
                let searchRange = searchStart..<endPosition

                // Look for line breaks first
                if let lastNewline = content[searchRange].lastIndex(of: "\n") {
                    endPosition = content.index(after: lastNewline)
                } else if let lastBrace = content[searchRange].lastIndex(of: "}") {
                    endPosition = content.index(after: lastBrace)
                } else if let lastSemi = content[searchRange].lastIndex(of: ";") {
                    endPosition = content.index(after: lastSemi)
                }
            }

            let chunkContent = imports + String(content[currentPosition..<endPosition])

            let localStartOffset = content.distance(from: content.startIndex, to: currentPosition)
            let localEndOffset = content.distance(from: content.startIndex, to: endPosition)

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: chunkIndex,
                startOffset: startOffset + localStartOffset,
                endOffset: startOffset + localEndOffset,
                source: source,
                custom: custom
            )

            chunks.append(Chunk(content: chunkContent, metadata: chunkMetadata))

            currentPosition = endPosition
            chunkIndex += 1
        }

        return chunks
    }

    /// Chunks code by size without function awareness.
    private func chunkBySize(
        text: String,
        imports: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        let importsLength = imports.count
        let contentMaxSize = maxChunkSize - importsLength

        var chunks: [Chunk] = []
        var currentPosition = text.startIndex
        var chunkIndex = 0

        while currentPosition < text.endIndex {
            let remainingDistance = text.distance(from: currentPosition, to: text.endIndex)
            let chunkLength = min(max(100, contentMaxSize), remainingDistance)

            var endPosition = text.index(currentPosition, offsetBy: chunkLength)

            // Try to break at a natural boundary
            if endPosition < text.endIndex {
                let searchStart = text.index(
                    currentPosition,
                    offsetBy: max(0, chunkLength - 200),
                    limitedBy: text.endIndex
                ) ?? currentPosition
                let searchRange = searchStart..<endPosition

                // Prefer breaking at blank lines, then single newlines
                let searchText = String(text[searchRange])
                if let blankLineRange = searchText.range(of: "\n\n", options: .backwards) {
                    let offset = searchText.distance(from: searchText.startIndex, to: blankLineRange.upperBound)
                    endPosition = text.index(searchStart, offsetBy: offset)
                } else if let newlineIndex = text[searchRange].lastIndex(of: "\n") {
                    endPosition = text.index(after: newlineIndex)
                }
            }

            let chunkContent: String
            if chunkIndex == 0 {
                // First chunk may already have imports at the start
                chunkContent = imports.isEmpty ? String(text[currentPosition..<endPosition]) :
                    imports + String(text[currentPosition..<endPosition])
            } else {
                chunkContent = imports + String(text[currentPosition..<endPosition])
            }

            let startOffset = text.distance(from: text.startIndex, to: currentPosition)
            let endOffset = text.distance(from: text.startIndex, to: endPosition)

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: chunkIndex,
                startOffset: startOffset,
                endOffset: endOffset,
                source: source,
                custom: custom
            )

            chunks.append(Chunk(content: chunkContent, metadata: chunkMetadata))

            currentPosition = endPosition
            chunkIndex += 1
        }

        return chunks
    }

    /// Extracts file extension from a document.
    private func extractFileExtension(from document: Document) -> String? {
        // Try to get from URL first
        if let url = document.metadata.url {
            let ext = url.pathExtension
            if !ext.isEmpty {
                return ext
            }
        }

        // Try to get from source
        if let source = document.metadata.source {
            let url = URL(fileURLWithPath: source)
            let ext = url.pathExtension
            if !ext.isEmpty {
                return ext
            }
        }

        return nil
    }
}

// MARK: - CustomStringConvertible

extension CodeChunker: CustomStringConvertible {
    public var description: String {
        "CodeChunker(language: \(language.rawValue), maxSize: \(maxChunkSize), byFunction: \(chunkByFunction), includeImports: \(includeImports))"
    }
}
