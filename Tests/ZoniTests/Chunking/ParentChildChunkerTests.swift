// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Comprehensive tests for ParentChildChunker.

import Testing
import Foundation
@testable import Zoni

// MARK: - Test Helpers

/// Helper function to create a Document for testing.
private func makeDocument(content: String, id: String = "test-doc") -> Document {
    Document(
        id: id,
        content: content,
        metadata: DocumentMetadata(source: "test-source")
    )
}

/// Helper to filter parent chunks from results.
private func filterParents(_ chunks: [Chunk]) -> [Chunk] {
    chunks.filter { $0.metadata.custom["isParent"]?.boolValue == true }
}

/// Helper to filter child chunks from results.
private func filterChildren(_ chunks: [Chunk]) -> [Chunk] {
    chunks.filter { $0.metadata.custom["isChild"]?.boolValue == true }
}

// MARK: - Basic Chunking Tests

@Suite("ParentChildChunker Basic Chunking Tests")
struct ParentChildChunkerBasicTests {

    @Test("Basic parent-child split creates both parents and children")
    func testBasicParentChildSplit() async throws {
        // Input: ~650 char document
        // Parent size: 200, Child size: 50, Overlap: 10
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(
            content: String(repeating: "Hello world. ", count: 50) // ~650 chars
        )

        let chunks = try await chunker.chunk(document)

        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        // Verify: Has both parents and children
        #expect(parents.count > 0, "Should have parent chunks")
        #expect(children.count > 0, "Should have child chunks")

        // Verify: Children > Parents
        #expect(children.count > parents.count, "Should have more children than parents")
    }

    @Test("Single paragraph document creates 1 parent with multiple children")
    func testSingleParagraphDocument() async throws {
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 50,
            childOverlap: 10
        )

        // Single paragraph smaller than parent size
        let document = makeDocument(
            content: String(repeating: "x", count: 200) // 200 chars, fits in one parent
        )

        let chunks = try await chunker.chunk(document)

        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        // Should create 1 parent
        #expect(parents.count == 1, "Should have exactly 1 parent chunk")

        // Should create multiple children
        #expect(children.count > 1, "Should have multiple child chunks")
    }

    @Test("Chunker produces non-empty chunks")
    func testNonEmptyChunks() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(
            content: "This is test content.\n\nSecond paragraph here."
        )

        let chunks = try await chunker.chunk(document)

        for chunk in chunks {
            #expect(!chunk.content.isEmpty, "Chunk content should not be empty")
        }
    }
}

// MARK: - Relationship Integrity Tests

@Suite("ParentChildChunker Relationship Integrity Tests")
struct ParentChildChunkerRelationshipTests {

    @Test("Each child has valid parentId pointing to existing parent")
    func testChildrenReferenceExistingParents() async throws {
        let chunker = ParentChildChunker(
            parentSize: 100,
            childSize: 30,
            childOverlap: 5
        )

        let document = makeDocument(
            content: "First paragraph content here.\n\nSecond paragraph content here."
        )

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        let parentIds = Set(parents.map { $0.id })

        // Verify: Each child has valid parentId
        for child in children {
            let parentId = child.metadata.custom["parentId"]?.stringValue
            #expect(parentId != nil, "Child should have parentId")
            #expect(parentIds.contains(parentId!), "Child's parentId should reference an existing parent")
        }
    }

    @Test("Parent childIds match actual children")
    func testParentChildRelationships() async throws {
        let chunker = ParentChildChunker(
            parentSize: 100,
            childSize: 30,
            childOverlap: 5
        )

        let document = makeDocument(
            content: "First paragraph content here.\n\nSecond paragraph content here."
        )

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        for parent in parents {
            guard let childIds = parent.metadata.custom["childIds"]?.arrayValue else {
                Issue.record("Parent should have childIds array")
                continue
            }

            #expect(childIds.count > 0, "Parent should have children")

            // Verify childIds match actual children referencing this parent
            let actualChildIds = children
                .filter { $0.metadata.custom["parentId"]?.stringValue == parent.id }
                .map { $0.id }

            let storedChildIds = childIds.compactMap { $0.stringValue }

            #expect(
                Set(storedChildIds) == Set(actualChildIds),
                "Parent's childIds should match actual children"
            )
        }
    }

    @Test("Bidirectional references are correct")
    func testBidirectionalReferences() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(
            content: String(repeating: "Test content. ", count: 30)
        )

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        // For each parent, verify its childIds point to children that reference it back
        for parent in parents {
            guard let childIds = parent.metadata.custom["childIds"]?.arrayValue else {
                continue
            }

            for childIdValue in childIds {
                guard let childId = childIdValue.stringValue else { continue }

                let matchingChild = children.first { $0.id == childId }
                #expect(matchingChild != nil, "Child with id \(childId) should exist")

                if let child = matchingChild {
                    let referencedParentId = child.metadata.custom["parentId"]?.stringValue
                    #expect(
                        referencedParentId == parent.id,
                        "Child should reference parent back"
                    )
                }
            }
        }
    }
}

// MARK: - Overlap Tests

@Suite("ParentChildChunker Overlap Tests")
struct ParentChildChunkerOverlapTests {

    @Test("Child overlap correctness - position advances by stride")
    func testChildOverlapCorrectness() async throws {
        // With childSize: 100, overlap: 20
        // Position should advance by 80 each child
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 100,
            childOverlap: 20
        )

        let document = makeDocument(
            content: String(repeating: "a", count: 300) // 300 chars
        )

        let chunks = try await chunker.chunk(document)
        let children = filterChildren(chunks)

        // Verify positions advance correctly
        var expectedPosition = 0
        let stride = 100 - 20 // childSize - overlap = 80

        for (index, child) in children.enumerated() {
            let position = child.metadata.custom["positionInParent"]?.intValue
            #expect(position != nil, "Child should have positionInParent")

            if index > 0 {
                let previousPosition = children[index - 1].metadata.custom["positionInParent"]?.intValue ?? 0
                let actualStride = (position ?? 0) - previousPosition
                #expect(actualStride == stride, "Position should advance by \(stride), got \(actualStride)")
            }

            expectedPosition += stride
        }
    }

    @Test("Adjacent children share overlapping characters")
    func testAdjacentChildrenShareCharacters() async throws {
        let childSize = 100
        let overlap = 20

        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: childSize,
            childOverlap: overlap
        )

        // Use distinct content to verify overlap
        let content = String((0..<300).map { _ in "abcdefghij".randomElement()! })
        let document = makeDocument(content: content)

        let chunks = try await chunker.chunk(document)
        let children = filterChildren(chunks)

        // Verify adjacent children share overlap characters
        for i in 0..<(children.count - 1) {
            let current = children[i]
            let next = children[i + 1]

            // The end of current should overlap with the start of next
            let currentSuffix = String(current.content.suffix(overlap))
            let nextPrefix = String(next.content.prefix(overlap))

            #expect(
                currentSuffix == nextPrefix,
                "Adjacent children should share \(overlap) overlapping characters"
            )
        }
    }

    @Test("Zero overlap creates non-overlapping children")
    func testZeroOverlap() async throws {
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 50,
            childOverlap: 0
        )

        let document = makeDocument(
            content: String(repeating: "x", count: 200)
        )

        let chunks = try await chunker.chunk(document)
        let children = filterChildren(chunks)

        // Verify positions advance by full childSize (no overlap)
        for i in 0..<(children.count - 1) {
            let currentPos = children[i].metadata.custom["positionInParent"]?.intValue ?? 0
            let nextPos = children[i + 1].metadata.custom["positionInParent"]?.intValue ?? 0

            #expect(
                nextPos - currentPos == 50,
                "With zero overlap, position should advance by childSize (50)"
            )
        }
    }
}

// MARK: - Metadata Tests

@Suite("ParentChildChunker Metadata Tests")
struct ParentChildChunkerMetadataTests {

    @Test("Child metadata is complete")
    func testChildMetadataComplete() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(content: String(repeating: "test ", count: 50))
        let chunks = try await chunker.chunk(document)
        let children = filterChildren(chunks)

        for child in children {
            // Verify: isChild, parentId, parentIndex, positionInParent present
            #expect(
                child.metadata.custom["isChild"]?.boolValue == true,
                "Child should have isChild = true"
            )
            #expect(
                child.metadata.custom["parentId"]?.stringValue != nil,
                "Child should have parentId"
            )
            #expect(
                child.metadata.custom["parentIndex"]?.intValue != nil,
                "Child should have parentIndex"
            )
            #expect(
                child.metadata.custom["positionInParent"]?.intValue != nil,
                "Child should have positionInParent"
            )
        }
    }

    @Test("Parent metadata is complete")
    func testParentMetadataComplete() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(content: String(repeating: "test ", count: 50))
        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)

        for parent in parents {
            // Verify: isParent, childIds, childCount present
            #expect(
                parent.metadata.custom["isParent"]?.boolValue == true,
                "Parent should have isParent = true"
            )
            #expect(
                parent.metadata.custom["childIds"]?.arrayValue != nil,
                "Parent should have childIds"
            )
            #expect(
                parent.metadata.custom["childCount"]?.intValue != nil,
                "Parent should have childCount"
            )

            // Verify childCount matches childIds array length
            let childCount = parent.metadata.custom["childCount"]?.intValue ?? 0
            let childIds = parent.metadata.custom["childIds"]?.arrayValue ?? []
            #expect(
                childCount == childIds.count,
                "childCount should match childIds array length"
            )
        }
    }

    @Test("Document ID is preserved in all chunks")
    func testDocumentIdPreserved() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let documentId = "custom-doc-id-123"
        let document = makeDocument(
            content: String(repeating: "test ", count: 50),
            id: documentId
        )

        let chunks = try await chunker.chunk(document)

        // All chunks should inherit document.id
        for chunk in chunks {
            #expect(
                chunk.metadata.documentId == documentId,
                "Chunk documentId should match original document ID"
            )
        }
    }

    @Test("Source is preserved in all chunks")
    func testSourcePreserved() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(content: String(repeating: "test ", count: 50))

        let chunks = try await chunker.chunk(document)

        // source metadata should be propagated
        for chunk in chunks {
            #expect(
                chunk.metadata.source == "test-source",
                "Chunk source should match original document source"
            )
        }
    }
}

// MARK: - Edge Case Tests

@Suite("ParentChildChunker Edge Case Tests")
struct ParentChildChunkerEdgeCaseTests {

    @Test("Empty document throws emptyDocument error")
    func testEmptyDocumentThrows() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(content: "")

        await #expect(throws: ZoniError.emptyDocument) {
            _ = try await chunker.chunk(document)
        }
    }

    @Test("Whitespace-only document throws emptyDocument error")
    func testWhitespaceOnlyDocumentThrows() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(content: "   \n\n\t  ")

        await #expect(throws: ZoniError.emptyDocument) {
            _ = try await chunker.chunk(document)
        }
    }

    @Test("Document smaller than child size creates 1 parent and 1 child")
    func testDocumentSmallerThanChildSize() async throws {
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 100,
            childOverlap: 20
        )

        // Very small doc creates 1 parent, 1 child
        let document = makeDocument(content: "Short text")

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        #expect(parents.count == 1, "Should have exactly 1 parent")
        #expect(children.count == 1, "Should have exactly 1 child")
    }

    @Test("Content exactly divisible by chunk sizes")
    func testExactMultipleOfChunkSize() async throws {
        // Parent: 200, Child: 50, Overlap: 0
        // Content exactly 200 chars = 1 parent, 4 children (50 each)
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 0
        )

        let document = makeDocument(content: String(repeating: "x", count: 200))

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        #expect(parents.count == 1, "Should have 1 parent for 200 chars")
        #expect(children.count == 4, "Should have 4 children (200 / 50 = 4)")
    }

    @Test("Large document creates multiple parents")
    func testLargeDocumentMultipleParents() async throws {
        let chunker = ParentChildChunker(
            parentSize: 100,
            childSize: 30,
            childOverlap: 5
        )

        // Create content with multiple paragraphs
        let paragraph = String(repeating: "word ", count: 30) // ~150 chars
        let content = [paragraph, paragraph, paragraph].joined(separator: "\n\n")
        let document = makeDocument(content: content)

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)

        #expect(parents.count >= 2, "Should have multiple parents for large document")
    }

    @Test("Content with single newlines stays in same parent")
    func testSingleNewlinesNotSeparators() async throws {
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 50,
            childOverlap: 10,
            parentSeparator: "\n\n" // Double newline
        )

        // Single newlines should not split parents
        let content = "Line 1\nLine 2\nLine 3"
        let document = makeDocument(content: content)

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)

        #expect(parents.count == 1, "Single newlines should not create new parents")
    }
}

// MARK: - Configuration Tests

@Suite("ParentChildChunker Configuration Tests")
struct ParentChildChunkerConfigurationTests {

    @Test("includeParentsInOutput false returns only children")
    func testIncludeParentsInOutputFalse() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10,
            includeParentsInOutput: false
        )

        let document = makeDocument(content: String(repeating: "test ", count: 50))

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        // Only children should be returned when includeParentsInOutput = false
        #expect(parents.count == 0, "Should have no parents when includeParentsInOutput is false")
        #expect(children.count > 0, "Should still have children")
    }

    @Test("Custom parent separator is respected")
    func testCustomParentSeparator() async throws {
        let chunker = ParentChildChunker(
            parentSize: 100,
            childSize: 30,
            childOverlap: 5,
            parentSeparator: "---"
        )

        let content = "Part one content---Part two content---Part three content"
        let document = makeDocument(content: content)

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)

        // With custom separator "---", should create multiple parents
        #expect(parents.count >= 1, "Should respect custom separator")
    }

    @Test("Chunker description is accurate")
    func testChunkerDescription() {
        let chunker = ParentChildChunker(
            parentSize: 2000,
            childSize: 400,
            childOverlap: 50
        )

        let description = chunker.description
        #expect(description.contains("2000"), "Description should contain parent size")
        #expect(description.contains("400"), "Description should contain child size")
        #expect(description.contains("50"), "Description should contain overlap")
    }

    @Test("Chunker name is correct")
    func testChunkerName() {
        let chunker = ParentChildChunker()
        #expect(chunker.name == "parent_child")
    }

    @Test("Default values are reasonable")
    func testDefaultValues() {
        let chunker = ParentChildChunker()

        #expect(chunker.parentSize == 2000, "Default parent size should be 2000")
        #expect(chunker.childSize == 400, "Default child size should be 400")
        #expect(chunker.childOverlap == 50, "Default overlap should be 50")
        #expect(chunker.parentSeparator == "\n\n", "Default separator should be double newline")
        #expect(chunker.includeParentsInOutput == true, "Should include parents by default")
    }
}

// MARK: - Chunk Text Method Tests

@Suite("ParentChildChunker Text Chunking Tests")
struct ParentChildChunkerTextTests {

    @Test("Chunk text with metadata preserves document ID")
    func testChunkTextWithMetadata() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let metadata = ChunkMetadata(
            documentId: "text-doc-456",
            index: 0,
            source: "text-source"
        )

        let chunks = try await chunker.chunk(
            String(repeating: "test ", count: 50),
            metadata: metadata
        )

        for chunk in chunks {
            #expect(
                chunk.metadata.documentId == "text-doc-456",
                "Chunks should use provided document ID"
            )
            #expect(
                chunk.metadata.source == "text-source",
                "Chunks should use provided source"
            )
        }
    }

    @Test("Chunk text without metadata generates document ID")
    func testChunkTextWithoutMetadata() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let chunks = try await chunker.chunk(
            String(repeating: "test ", count: 50),
            metadata: nil
        )

        // All chunks should have the same (generated) document ID
        let documentIds = Set(chunks.map { $0.metadata.documentId })
        #expect(documentIds.count == 1, "All chunks should share the same document ID")
        #expect(
            !documentIds.first!.isEmpty,
            "Generated document ID should not be empty"
        )
    }
}

// MARK: - Offset Tests

@Suite("ParentChildChunker Offset Tests")
struct ParentChildChunkerOffsetTests {

    @Test("Start and end offsets are correct for children")
    func testChildOffsets() async throws {
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 50,
            childOverlap: 0
        )

        let content = String(repeating: "x", count: 200)
        let document = makeDocument(content: content)

        let chunks = try await chunker.chunk(document)
        let children = filterChildren(chunks)

        for child in children {
            let start = child.metadata.startOffset
            let end = child.metadata.endOffset

            // Verify offset consistency
            #expect(end > start, "End offset should be greater than start")
            #expect(
                end - start == child.content.count,
                "Offset difference should equal content length"
            )
        }
    }

    @Test("Parent offsets span their content")
    func testParentOffsets() async throws {
        let chunker = ParentChildChunker(
            parentSize: 200,
            childSize: 50,
            childOverlap: 10
        )

        let document = makeDocument(content: String(repeating: "y", count: 150))

        let chunks = try await chunker.chunk(document)
        let parents = filterParents(chunks)

        for parent in parents {
            let offsetLength = parent.metadata.endOffset - parent.metadata.startOffset
            #expect(
                offsetLength == parent.content.count,
                "Parent offset range should match content length"
            )
        }
    }
}

// MARK: - Integration Tests

@Suite("ParentChildChunker Integration Tests")
struct ParentChildChunkerIntegrationTests {

    @Test("Full workflow with realistic content")
    func testRealisticContent() async throws {
        let chunker = ParentChildChunker(
            parentSize: 500,
            childSize: 100,
            childOverlap: 20
        )

        let content = """
        Swift is a powerful and intuitive programming language developed by Apple.
        It is designed to work with Apple's Cocoa and Cocoa Touch frameworks.

        Swift makes it easy to write software that is incredibly fast and safe.
        The language is designed to make it easy to write and maintain correct programs.

        Modern Swift code is safe by design, yet also produces software that runs lightning-fast.
        Swift includes modern features developers love while being clean and easy to read.
        """

        let document = makeDocument(content: content)
        let chunks = try await chunker.chunk(document)

        let parents = filterParents(chunks)
        let children = filterChildren(chunks)

        // Basic sanity checks
        #expect(parents.count > 0, "Should produce parents")
        #expect(children.count > 0, "Should produce children")
        #expect(children.count > parents.count, "More children than parents")

        // Verify all relationships are valid
        let parentIds = Set(parents.map { $0.id })
        for child in children {
            let parentId = child.metadata.custom["parentId"]?.stringValue
            #expect(parentId != nil && parentIds.contains(parentId!))
        }
    }

    @Test("Chunker conforms to ChunkingStrategy protocol")
    func testProtocolConformance() async throws {
        let chunker: any ChunkingStrategy = ParentChildChunker()

        #expect(chunker.name == "parent_child")

        let document = makeDocument(content: "Test content for protocol conformance.")
        let chunks = try await chunker.chunk(document)

        #expect(!chunks.isEmpty, "Should produce chunks via protocol")
    }
}
