// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Parent-child chunking strategy for hierarchical document segmentation.

import Foundation

// MARK: - ParentChildChunker

/// A chunking strategy that creates a hierarchical parent-child structure for retrieval.
///
/// `ParentChildChunker` implements a two-level chunking approach where larger "parent" chunks
/// provide broad context, and smaller "child" chunks enable precise retrieval. This strategy
/// is particularly effective for RAG systems because:
///
/// 1. **Child chunks** are used for similarity search (smaller = more precise matching)
/// 2. **Parent chunks** are returned as context (larger = more complete information)
///
/// The chunker first splits the document by paragraph boundaries (or a custom separator),
/// then greedily aggregates paragraphs into parent chunks up to `parentSize`. Each parent
/// is then subdivided into overlapping child chunks using a sliding window approach.
///
/// ## Parent Creation Algorithm
/// 1. Split the document by `parentSeparator` (default: `"\n\n"`)
/// 2. Greedily aggregate consecutive paragraphs until reaching `parentSize`
/// 3. Track `startOffset` and `endOffset` for each parent in the original document
///
/// ## Child Creation Algorithm
/// 1. For each parent, apply a sliding window with size `childSize` and overlap `childOverlap`
/// 2. Position advances by `childSize - childOverlap` on each iteration
/// 3. Each child stores a reference to its parent's ID for context retrieval
///
/// ## Example Usage
/// ```swift
/// // Default configuration
/// let chunker = ParentChildChunker()
/// let chunks = try await chunker.chunk(document)
///
/// // Custom configuration for dense technical documents
/// let technicalChunker = ParentChildChunker(
///     parentSize: 3000,
///     childSize: 500,
///     childOverlap: 100,
///     includeParentsInOutput: true
/// )
/// let technicalChunks = try await technicalChunker.chunk(document)
///
/// // Filter children for search, retrieve parents for context
/// let childChunks = chunks.filter { $0.metadata.custom["isChild"]?.boolValue == true }
/// let parentChunks = chunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
/// ```
///
/// ## Metadata Structure
/// **Child chunks** include:
/// - `isChild`: `.bool(true)` - Identifies this as a child chunk
/// - `parentId`: `.string(id)` - The ID of the parent chunk this child belongs to
/// - `parentIndex`: `.int(index)` - The zero-based index of the parent in the document
/// - `positionInParent`: `.int(position)` - The zero-based sequential position of this child within its parent
///
/// **Parent chunks** (when `includeParentsInOutput` is `true`) include:
/// - `isParent`: `.bool(true)` - Identifies this as a parent chunk
/// - `childIds`: `.array([.string(id1), ...])` - Array of child chunk IDs
/// - `childCount`: `.int(count)` - Number of child chunks created from this parent
///
/// ## Performance Considerations
/// - Smaller `childSize` increases retrieval precision but creates more chunks
/// - Larger `parentSize` provides more context but may include irrelevant information
/// - `childOverlap` prevents losing context at chunk boundaries
/// - Setting `includeParentsInOutput` to `false` reduces output size when parents are stored separately
public struct ParentChildChunker: ChunkingStrategy, Sendable {

    // MARK: - Properties

    /// The name of this chunking strategy.
    ///
    /// Returns `"parent_child"` for identification in configurations and logging.
    public let name = "parent_child"

    /// The target maximum size for parent chunks in characters.
    ///
    /// Parent chunks are created by aggregating paragraphs until reaching this size.
    /// Must be greater than `childSize`.
    public let parentSize: Int

    /// The target size for child chunks in characters.
    ///
    /// Child chunks are created using a sliding window over each parent chunk.
    /// Must be greater than `childOverlap` and less than `parentSize`.
    public let childSize: Int

    /// The number of characters to overlap between consecutive child chunks.
    ///
    /// Overlap helps maintain context across chunk boundaries. A value of 0 means
    /// no overlap. Must be less than `childSize`.
    public let childOverlap: Int

    /// The separator used to split the document into paragraphs for parent creation.
    ///
    /// Common values include `"\n\n"` for paragraph breaks or `"\n---\n"` for
    /// markdown horizontal rules.
    public let parentSeparator: String

    /// Whether to include parent chunks in the output alongside child chunks.
    ///
    /// When `true`, both parent and child chunks are returned. When `false`,
    /// only child chunks are returned (parents can be reconstructed from child metadata).
    public let includeParentsInOutput: Bool

    // MARK: - Initialization

    /// Creates a new parent-child chunker with the specified configuration.
    ///
    /// - Parameters:
    ///   - parentSize: The target maximum size for parent chunks. Defaults to 2000.
    ///   - childSize: The target size for child chunks. Defaults to 400.
    ///   - childOverlap: The number of characters to overlap between children. Defaults to 50.
    ///   - parentSeparator: The separator for splitting into paragraphs. Defaults to `"\n\n"`.
    ///   - includeParentsInOutput: Whether to include parents in output. Defaults to `true`.
    ///
    /// - Precondition: `parentSize` must be greater than `childSize`.
    /// - Precondition: `childSize` must be greater than `childOverlap`.
    ///
    /// ## Example
    /// ```swift
    /// // Default configuration suitable for most documents
    /// let chunker = ParentChildChunker()
    ///
    /// // Custom configuration for code documentation
    /// let codeChunker = ParentChildChunker(
    ///     parentSize: 1500,
    ///     childSize: 300,
    ///     childOverlap: 30,
    ///     parentSeparator: "\n\n",
    ///     includeParentsInOutput: true
    /// )
    /// ```
    public init(
        parentSize: Int = 2000,
        childSize: Int = 400,
        childOverlap: Int = 50,
        parentSeparator: String = "\n\n",
        includeParentsInOutput: Bool = true
    ) {
        precondition(parentSize > childSize, "parentSize must be greater than childSize")
        precondition(childSize > childOverlap, "childSize must be greater than childOverlap")

        self.parentSize = parentSize
        self.childSize = childSize
        self.childOverlap = childOverlap
        self.parentSeparator = parentSeparator
        self.includeParentsInOutput = includeParentsInOutput
    }

    // MARK: - Public Methods

    /// Chunks a document into a hierarchical parent-child structure.
    ///
    /// Extracts the content from the document and creates both parent and child chunks
    /// with metadata linking them together. The document's ID and source are preserved
    /// in the chunk metadata.
    ///
    /// - Parameter document: The document to chunk.
    /// - Returns: An array of chunks containing both parents and children (if `includeParentsInOutput` is `true`).
    /// - Throws: ``ZoniError/emptyDocument`` if the document content is empty or whitespace-only.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = ParentChildChunker(parentSize: 1000, childSize: 200)
    /// let chunks = try await chunker.chunk(document)
    ///
    /// // Access child chunks for retrieval
    /// let children = chunks.filter { $0.metadata.custom["isChild"]?.boolValue == true }
    ///
    /// // Access parent chunks for context
    /// let parents = chunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
    /// ```
    public func chunk(_ document: Document) async throws -> [Chunk] {
        let trimmedContent = document.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw ZoniError.emptyDocument
        }

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
                var parentCustom = parent.metadata.custom
                parentCustom["childIds"] = .array(children.map { .string($0.id) })
                parentCustom["isParent"] = .bool(true)
                parentCustom["childCount"] = .int(children.count)

                let parentMetadata = ChunkMetadata(
                    documentId: parent.metadata.documentId,
                    index: parent.metadata.index,
                    startOffset: parent.metadata.startOffset,
                    endOffset: parent.metadata.endOffset,
                    source: parent.metadata.source,
                    custom: parentCustom
                )

                let parentWithRefs = Chunk(
                    id: parent.id,
                    content: parent.content,
                    metadata: parentMetadata
                )
                allChunks.append(parentWithRefs)
            }
        }

        return allChunks
    }

    /// Chunks raw text into a hierarchical parent-child structure with optional metadata.
    ///
    /// Use this method when working with text that is not wrapped in a `Document`,
    /// or when you need to provide custom base metadata for the resulting chunks.
    ///
    /// - Parameters:
    ///   - text: The text to chunk.
    ///   - metadata: Base metadata to include in each chunk. If `nil`, a new
    ///     document ID is generated and used for all chunks.
    /// - Returns: An array of chunks with parent-child relationships.
    /// - Throws: ``ZoniError/emptyDocument`` if the text is empty or whitespace-only.
    ///
    /// ## Example
    /// ```swift
    /// let chunker = ParentChildChunker()
    /// let chunks = try await chunker.chunk(longText, metadata: nil)
    /// ```
    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk] {
        let documentId = metadata?.documentId ?? UUID().uuidString
        let document = Document(
            id: documentId,
            content: text,
            metadata: DocumentMetadata(source: metadata?.source)
        )
        return try await chunk(document)
    }

    // MARK: - Private Methods

    /// Creates parent chunks by splitting on the paragraph separator and aggregating.
    ///
    /// - Parameter document: The document to create parent chunks from.
    /// - Returns: An array of parent chunks without child references yet.
    private func createParentChunks(from document: Document) -> [Chunk] {
        let text = document.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    chunks.append(createParentChunk(
                        content: currentContent,
                        documentId: document.id,
                        index: chunks.count,
                        startOffset: currentStart,
                        source: document.metadata.source
                    ))
                    // Use overflow-safe addition for very large documents
                    let increment = currentContent.count + parentSeparator.count
                    let (newOffset, overflow) = currentStart.addingReportingOverflow(increment)
                    currentStart = overflow ? Int.max : newOffset
                }
                currentContent = trimmed
            }
        }

        // Don't forget the last chunk
        if !currentContent.isEmpty {
            chunks.append(createParentChunk(
                content: currentContent,
                documentId: document.id,
                index: chunks.count,
                startOffset: currentStart,
                source: document.metadata.source
            ))
        }

        return chunks
    }

    /// Creates child chunks for a parent using a sliding window approach.
    ///
    /// - Parameters:
    ///   - parent: The parent chunk to create children from.
    ///   - parentIndex: The index of the parent in the document.
    ///   - document: The source document for metadata.
    /// - Returns: An array of child chunks with parent references.
    private func createChildChunks(
        from parent: Chunk,
        parentIndex: Int,
        document: Document
    ) -> [Chunk] {
        let text = parent.content
        var children: [Chunk] = []
        var position = 0
        var positionInParent = 0

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
                        "positionInParent": .int(positionInParent)
                    ]
                )
            )

            children.append(child)
            positionInParent += 1

            // Calculate next position with overlap
            let stride = childSize - childOverlap

            // Check if we've reached the end
            if endPosition >= text.count {
                break
            }

            // Prevent infinite loop - ensure we make progress
            let nextPosition = position + stride
            if nextPosition <= position {
                break
            }

            position = nextPosition
        }

        return children
    }

    /// Creates a parent chunk with initial metadata (without child references).
    ///
    /// - Parameters:
    ///   - content: The content of the parent chunk.
    ///   - documentId: The document ID for metadata.
    ///   - index: The index of this parent.
    ///   - startOffset: The start offset in the original document.
    ///   - source: The source for metadata.
    /// - Returns: A parent chunk.
    private func createParentChunk(
        content: String,
        documentId: String,
        index: Int,
        startOffset: Int,
        source: String?
    ) -> Chunk {
        Chunk(
            content: content,
            metadata: ChunkMetadata(
                documentId: documentId,
                index: index,
                startOffset: startOffset,
                endOffset: startOffset + content.count,
                source: source,
                custom: [:]
            )
        )
    }
}

// MARK: - CustomStringConvertible

extension ParentChildChunker: CustomStringConvertible {
    public var description: String {
        let includeParents = includeParentsInOutput ? "with parents" : "children only"
        return "ParentChildChunker(parent: \(parentSize), child: \(childSize), overlap: \(childOverlap), \(includeParents))"
    }
}
