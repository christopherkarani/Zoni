// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Markdown-aware chunking strategy for splitting documents at section boundaries.

import Foundation

// MARK: - MarkdownChunker

/// A chunking strategy that splits markdown documents at section boundaries.
///
/// `MarkdownChunker` uses markdown header syntax to identify document sections
/// and creates semantically meaningful chunks that preserve the document structure.
/// This approach is particularly effective for technical documentation, README files,
/// and other structured markdown content.
///
/// The chunker respects markdown conventions:
/// - Headers are identified by leading `#` characters
/// - Code blocks (fenced with ```) are never split mid-block
/// - Section hierarchy is preserved through header inclusion
///
/// ## Header Levels
/// The `minHeaderLevel` parameter controls which headers trigger section splits:
/// - Level 1 (`#`): Only split on top-level headers
/// - Level 2 (`##`): Split on level 1 and 2 headers (default)
/// - Level 3 (`###`): Split on levels 1, 2, and 3
///
/// ## Size Constraints
/// The `maxChunkSize` parameter sets the maximum size for any chunk. Sections
/// exceeding this limit are further subdivided while respecting code block boundaries.
///
/// ## Example Usage
/// ```swift
/// // Basic markdown chunking
/// let chunker = MarkdownChunker()
/// let chunks = try await chunker.chunk(document)
///
/// // Custom configuration
/// let customChunker = MarkdownChunker(
///     maxChunkSize: 1500,
///     includeHeaders: true,
///     minHeaderLevel: 3,
///     chunkBySection: true
/// )
/// let chunks = try await customChunker.chunk(document)
/// ```
///
/// ## Performance Considerations
/// - Header detection uses regex matching for reliable parsing
/// - Code block detection prevents splitting inside fenced blocks
/// - Large documents with deep nesting may produce many chunks
public struct MarkdownChunker: ChunkingStrategy, Sendable {

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"markdown"` for identification in configurations and logging.
    public let name = "markdown"

    /// The maximum size for each chunk in characters.
    ///
    /// Sections exceeding this limit are further subdivided. Code blocks are
    /// kept intact when possible, but very large code blocks may be split.
    public var maxChunkSize: Int

    /// Whether to include the section header in each chunk.
    ///
    /// When `true`, each chunk starts with its section header(s), providing
    /// context for the chunk content. When `false`, headers are omitted
    /// and only the section content is included.
    public var includeHeaders: Bool

    /// The minimum header level to split on.
    ///
    /// Headers at or above this level (fewer `#` characters) trigger section splits:
    /// - `1`: Only `#` headers create splits
    /// - `2`: `#` and `##` headers create splits (default)
    /// - `3`: `#`, `##`, and `###` headers create splits
    /// - And so on...
    public var minHeaderLevel: Int

    /// Whether to split the document by sections.
    ///
    /// When `true`, the document is split at header boundaries according to
    /// `minHeaderLevel`. When `false`, the entire document is treated as a
    /// single section and only split if it exceeds `maxChunkSize`.
    public var chunkBySection: Bool

    // MARK: - Initialization

    /// Creates a new markdown-aware chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - maxChunkSize: The maximum chunk size in characters. Defaults to 2000.
    ///   - includeHeaders: Whether to include headers in chunks. Defaults to `true`.
    ///   - minHeaderLevel: The minimum header level to split on. Defaults to 2.
    ///   - chunkBySection: Whether to split by sections. Defaults to `true`.
    ///
    /// ## Validation
    /// - If `maxChunkSize` is less than 1, it is clamped to 1.
    /// - If `minHeaderLevel` is less than 1, it is clamped to 1.
    /// - If `minHeaderLevel` is greater than 6, it is clamped to 6.
    public init(
        maxChunkSize: Int = 2000,
        includeHeaders: Bool = true,
        minHeaderLevel: Int = 2,
        chunkBySection: Bool = true
    ) {
        self.maxChunkSize = max(1, maxChunkSize)
        self.includeHeaders = includeHeaders
        self.minHeaderLevel = max(1, min(6, minHeaderLevel))
        self.chunkBySection = chunkBySection
    }

    // MARK: - Public Methods

    /// Chunks a markdown document into section-based segments.
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
    /// let chunker = MarkdownChunker(maxChunkSize: 1000)
    /// let chunks = try await chunker.chunk(document)
    /// for chunk in chunks {
    ///     print("Chunk \(chunk.metadata.index): \(chunk.characterCount) chars")
    /// }
    /// ```
    public func chunk(_ document: Document) async throws -> [Chunk] {
        let baseMetadata = ChunkMetadata(
            documentId: document.id,
            index: 0,
            source: document.metadata.source
        )

        return try await chunk(document.content, metadata: baseMetadata)
    }

    /// Chunks raw markdown text into section-based segments with optional metadata.
    ///
    /// Use this method when working with text that is not wrapped in a `Document`,
    /// or when you need to provide custom base metadata for the resulting chunks.
    ///
    /// - Parameters:
    ///   - text: The markdown text to chunk.
    ///   - metadata: Base metadata to include in each chunk. If `nil`, a new
    ///     document ID is generated and used for all chunks.
    /// - Returns: An array of chunks with position metadata.
    /// - Throws: ``ZoniError/emptyDocument`` if the text is empty or whitespace-only.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = MarkdownChunker(maxChunkSize: 500)
    /// let chunks = try await chunker.chunk(markdownText, metadata: nil)
    /// ```
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk] {
        // Validate input
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ZoniError.emptyDocument
        }

        // Prepare base metadata
        let baseDocumentId = metadata?.documentId ?? UUID().uuidString
        let baseSource = metadata?.source
        let baseCustom = metadata?.custom ?? [:]

        // Split into sections if enabled
        if chunkBySection {
            return createSectionChunks(
                from: trimmedText,
                documentId: baseDocumentId,
                source: baseSource,
                custom: baseCustom
            )
        } else {
            // Treat as single section
            return createChunksFromText(
                trimmedText,
                header: nil,
                startOffset: 0,
                documentId: baseDocumentId,
                source: baseSource,
                custom: baseCustom,
                startingIndex: 0
            )
        }
    }

    // MARK: - Private Methods

    /// Parses the markdown text into sections based on headers.
    private func createSectionChunks(
        from text: String,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue]
    ) -> [Chunk] {
        let sections = parseMarkdownSections(text)

        var chunks: [Chunk] = []
        var chunkIndex = 0

        for section in sections {
            let sectionChunks = createChunksFromText(
                section.content,
                header: includeHeaders ? section.header : nil,
                startOffset: section.startOffset,
                documentId: documentId,
                source: source,
                custom: custom,
                startingIndex: chunkIndex
            )

            chunks.append(contentsOf: sectionChunks)
            chunkIndex += sectionChunks.count
        }

        return chunks
    }

    /// Represents a parsed markdown section.
    private struct MarkdownSection {
        let header: String?
        let content: String
        let startOffset: Int
        let endOffset: Int
    }

    /// Parses markdown text into sections based on header boundaries.
    private func parseMarkdownSections(_ text: String) -> [MarkdownSection] {
        // Build regex pattern for headers at or above minHeaderLevel
        // Headers are lines starting with 1 to minHeaderLevel # characters followed by space
        let headerPattern = "^(#{1,\(minHeaderLevel)})\\s+(.+)$"

        guard let headerRegex = try? Regex(headerPattern).anchorsMatchLineEndings() else {
            // Fallback: treat entire text as one section
            return [MarkdownSection(
                header: nil,
                content: text,
                startOffset: 0,
                endOffset: text.count
            )]
        }

        var sections: [MarkdownSection] = []
        var currentHeader: String?
        var currentContentStart = text.startIndex
        var sectionStartOffset = 0

        // Find all header matches
        let matches = text.matches(of: headerRegex)

        if matches.isEmpty {
            // No headers found, treat entire text as one section
            return [MarkdownSection(
                header: nil,
                content: text,
                startOffset: 0,
                endOffset: text.count
            )]
        }

        for match in matches {
            let matchRange = match.range

            // Check if this header is inside a code block
            if isInsideCodeBlock(text: text, position: matchRange.lowerBound) {
                continue
            }

            // Extract content before this header (if any)
            if currentContentStart < matchRange.lowerBound {
                let contentBeforeHeader = String(text[currentContentStart..<matchRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !contentBeforeHeader.isEmpty || currentHeader != nil {
                    let endOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
                    sections.append(MarkdownSection(
                        header: currentHeader,
                        content: contentBeforeHeader,
                        startOffset: sectionStartOffset,
                        endOffset: endOffset
                    ))
                }
            }

            // Update current header and start position
            currentHeader = String(text[matchRange])
            sectionStartOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            currentContentStart = matchRange.upperBound
        }

        // Handle remaining content after last header
        if currentContentStart < text.endIndex {
            let remainingContent = String(text[currentContentStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !remainingContent.isEmpty || currentHeader != nil {
                sections.append(MarkdownSection(
                    header: currentHeader,
                    content: remainingContent,
                    startOffset: sectionStartOffset,
                    endOffset: text.count
                ))
            }
        } else if currentHeader != nil {
            // Header at end with no content
            sections.append(MarkdownSection(
                header: currentHeader,
                content: "",
                startOffset: sectionStartOffset,
                endOffset: text.count
            ))
        }

        // Handle case where no sections were created but we have content
        if sections.isEmpty && !text.isEmpty {
            return [MarkdownSection(
                header: nil,
                content: text,
                startOffset: 0,
                endOffset: text.count
            )]
        }

        return sections
    }

    /// Checks if a position in the text is inside a fenced code block.
    private func isInsideCodeBlock(text: String, position: String.Index) -> Bool {
        let textBeforePosition = text[text.startIndex..<position]

        // Count opening and closing code fences before this position
        let fencePattern = "^```"
        guard let fenceRegex = try? Regex(fencePattern).anchorsMatchLineEndings() else {
            return false
        }

        let fenceMatches = textBeforePosition.matches(of: fenceRegex)

        // If odd number of fences, we're inside a code block
        return fenceMatches.count % 2 == 1
    }

    /// Creates chunks from a section of text, splitting if necessary.
    private func createChunksFromText(
        _ content: String,
        header: String?,
        startOffset: Int,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue],
        startingIndex: Int
    ) -> [Chunk] {
        // Build the full chunk content with header if needed
        let fullContent: String
        if let header = header {
            if content.isEmpty {
                fullContent = header
            } else {
                fullContent = header + "\n\n" + content
            }
        } else {
            fullContent = content
        }

        // If content fits within maxChunkSize, create single chunk
        if fullContent.count <= maxChunkSize {
            let trimmedContent = fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContent.isEmpty else {
                return []
            }

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: startingIndex,
                startOffset: startOffset,
                endOffset: startOffset + trimmedContent.count,
                source: source,
                custom: custom
            )

            return [Chunk(content: trimmedContent, metadata: chunkMetadata)]
        }

        // Content exceeds maxChunkSize, need to split
        return splitLargeSection(
            content: content,
            header: header,
            startOffset: startOffset,
            documentId: documentId,
            source: source,
            custom: custom,
            startingIndex: startingIndex
        )
    }

    /// Splits a large section into smaller chunks while respecting code blocks.
    private func splitLargeSection(
        content: String,
        header: String?,
        startOffset: Int,
        documentId: String,
        source: String?,
        custom: [String: MetadataValue],
        startingIndex: Int
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var chunkIndex = startingIndex

        // Calculate space available for content after header
        let headerSize = header.map { $0.count + 2 } ?? 0 // +2 for "\n\n"
        let contentBudget = maxChunkSize - headerSize

        guard contentBudget > 0 else {
            // Header alone exceeds maxChunkSize, just include header
            if let header = header {
                let chunkMetadata = ChunkMetadata(
                    documentId: documentId,
                    index: chunkIndex,
                    startOffset: startOffset,
                    endOffset: startOffset + header.count,
                    source: source,
                    custom: custom
                )
                return [Chunk(content: header, metadata: chunkMetadata)]
            }
            return []
        }

        // Split content into segments respecting code blocks
        let segments = splitContentRespectingCodeBlocks(content, maxSegmentSize: contentBudget)

        var localOffset = 0
        let headerOffset = header.map { $0.count + 2 } ?? 0

        for (index, segment) in segments.enumerated() {
            let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSegment.isEmpty else {
                localOffset += segment.count
                continue
            }

            // Include header only in first chunk if includeHeaders is true
            let chunkContent: String
            if index == 0, let header = header {
                chunkContent = header + "\n\n" + trimmedSegment
            } else {
                chunkContent = trimmedSegment
            }

            let segmentStartOffset = startOffset + (index == 0 ? 0 : headerOffset) + localOffset
            let segmentEndOffset = segmentStartOffset + trimmedSegment.count

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: chunkIndex,
                startOffset: segmentStartOffset,
                endOffset: segmentEndOffset,
                source: source,
                custom: custom
            )

            chunks.append(Chunk(content: chunkContent, metadata: chunkMetadata))
            chunkIndex += 1
            localOffset += segment.count
        }

        return chunks
    }

    /// Splits content into segments while keeping code blocks intact when possible.
    private func splitContentRespectingCodeBlocks(_ content: String, maxSegmentSize: Int) -> [String] {
        // Find all code block boundaries
        let codeBlockRanges = findCodeBlockRanges(in: content)

        var segments: [String] = []
        var currentSegment = ""
        var index = content.startIndex

        while index < content.endIndex {
            // Check if we're at the start of a code block
            let currentOffset = content.distance(from: content.startIndex, to: index)
            let codeBlock = codeBlockRanges.first { $0.start == currentOffset }

            if let codeBlock = codeBlock {
                // Extract the code block
                let blockStart = content.index(content.startIndex, offsetBy: codeBlock.start)
                let blockEnd = content.index(content.startIndex, offsetBy: min(codeBlock.end, content.count))
                let blockContent = String(content[blockStart..<blockEnd])

                // Check if adding this code block would exceed limit
                if currentSegment.count + blockContent.count > maxSegmentSize {
                    // Flush current segment if not empty
                    if !currentSegment.isEmpty {
                        segments.append(currentSegment)
                        currentSegment = ""
                    }

                    // If code block itself exceeds limit, split it
                    if blockContent.count > maxSegmentSize {
                        let splitBlocks = splitLargeCodeBlock(blockContent, maxSize: maxSegmentSize)
                        segments.append(contentsOf: splitBlocks)
                    } else {
                        segments.append(blockContent)
                    }
                } else {
                    currentSegment += blockContent
                }

                index = blockEnd
            } else {
                // Regular content - accumulate until we hit limit or code block
                let nextCodeBlockStart = codeBlockRanges
                    .filter { $0.start > currentOffset }
                    .min(by: { $0.start < $1.start })?.start

                let endOffset: Int
                if let nextStart = nextCodeBlockStart {
                    endOffset = nextStart
                } else {
                    endOffset = content.count
                }

                let endIndex = content.index(content.startIndex, offsetBy: endOffset)
                let remainingContent = String(content[index..<endIndex])

                // Split remaining content by paragraphs or at maxSegmentSize
                let contentSegments = splitByParagraphs(remainingContent)

                for (segIndex, seg) in contentSegments.enumerated() {
                    if currentSegment.count + seg.count > maxSegmentSize {
                        if !currentSegment.isEmpty {
                            segments.append(currentSegment)
                            currentSegment = ""
                        }

                        if seg.count > maxSegmentSize {
                            // Split at character boundary
                            let splitSegs = splitAtCharacterBoundary(seg, maxSize: maxSegmentSize)
                            if let last = splitSegs.last {
                                segments.append(contentsOf: splitSegs.dropLast())
                                currentSegment = last
                            }
                        } else {
                            currentSegment = seg
                        }
                    } else {
                        if segIndex > 0 && !currentSegment.isEmpty {
                            currentSegment += "\n\n"
                        }
                        currentSegment += seg
                    }
                }

                index = endIndex
            }
        }

        // Flush remaining content
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        return segments
    }

    /// Represents a code block range in the content.
    private struct CodeBlockRange {
        let start: Int
        let end: Int
    }

    /// Finds all fenced code block ranges in the content.
    private func findCodeBlockRanges(in content: String) -> [CodeBlockRange] {
        var ranges: [CodeBlockRange] = []
        let fencePattern = "^```.*$"

        guard let fenceRegex = try? Regex(fencePattern).anchorsMatchLineEndings() else {
            return ranges
        }

        let matches = Array(content.matches(of: fenceRegex))
        var index = 0

        while index < matches.count - 1 {
            let openMatch = matches[index]
            let closeMatch = matches[index + 1]

            let startOffset = content.distance(from: content.startIndex, to: openMatch.range.lowerBound)
            let endOffset = content.distance(from: content.startIndex, to: closeMatch.range.upperBound)

            ranges.append(CodeBlockRange(start: startOffset, end: endOffset))
            index += 2
        }

        return ranges
    }

    /// Splits a large code block at line boundaries.
    private func splitLargeCodeBlock(_ block: String, maxSize: Int) -> [String] {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var segments: [String] = []
        var currentSegment = ""

        for line in lines {
            let lineWithNewline = line + "\n"
            if currentSegment.count + lineWithNewline.count > maxSize && !currentSegment.isEmpty {
                segments.append(currentSegment)
                currentSegment = lineWithNewline
            } else {
                currentSegment += lineWithNewline
            }
        }

        if !currentSegment.isEmpty {
            segments.append(currentSegment.trimmingCharacters(in: .newlines))
        }

        return segments
    }

    /// Splits content by paragraph boundaries.
    private func splitByParagraphs(_ content: String) -> [String] {
        let paragraphs = content.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs
    }

    /// Splits text at character boundaries when other methods fail.
    private func splitAtCharacterBoundary(_ text: String, maxSize: Int) -> [String] {
        var segments: [String] = []
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            let remainingDistance = text.distance(from: startIndex, to: text.endIndex)
            let segmentLength = min(maxSize, remainingDistance)
            let endIndex = text.index(startIndex, offsetBy: segmentLength)

            let segment = String(text[startIndex..<endIndex])
            segments.append(segment)

            startIndex = endIndex
        }

        return segments
    }
}

// MARK: - CustomStringConvertible

extension MarkdownChunker: CustomStringConvertible {
    public var description: String {
        "MarkdownChunker(maxSize: \(maxChunkSize), includeHeaders: \(includeHeaders), minHeaderLevel: \(minHeaderLevel), chunkBySection: \(chunkBySection))"
    }
}
