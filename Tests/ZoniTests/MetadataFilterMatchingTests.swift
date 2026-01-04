// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Tests for MetadataFilter matching functionality against Chunk metadata.

import Testing
@testable import Zoni

@Suite("MetadataFilter Matching Tests")
struct MetadataFilterMatchingTests {

    // MARK: - Test Helper

    private func makeChunk(
        id: String = "test-id",
        content: String = "test content",
        documentId: String = "doc-1",
        index: Int = 0,
        source: String? = "test-source",
        custom: [String: MetadataValue] = [:]
    ) -> Chunk {
        Chunk(
            id: id,
            content: content,
            metadata: ChunkMetadata(
                documentId: documentId,
                index: index,
                startOffset: 0,
                endOffset: content.count,
                source: source,
                custom: custom
            )
        )
    }

    // MARK: - Equality Tests

    @Test("equals filter matches correct documentId value")
    func testEqualsMatchesCorrectValue() {
        let filter = MetadataFilter.equals("documentId", "doc-1")
        let matchingChunk = makeChunk(documentId: "doc-1")

        #expect(filter.matches(matchingChunk))
    }

    @Test("equals filter rejects incorrect documentId value")
    func testEqualsRejectsIncorrectValue() {
        let filter = MetadataFilter.equals("documentId", "doc-1")
        let nonMatchingChunk = makeChunk(documentId: "doc-2")

        #expect(!filter.matches(nonMatchingChunk))
    }

    @Test("equals filter matches custom field")
    func testEqualsOnCustomField() {
        let filter = MetadataFilter.equals("category", "tech")
        let matchingChunk = makeChunk(custom: ["category": .string("tech")])

        #expect(filter.matches(matchingChunk))
    }

    // MARK: - Not Equals Tests

    @Test("notEquals filter works correctly")
    func testNotEqualsWorks() {
        let filter = MetadataFilter.notEquals("documentId", "doc-1")

        let rejectedChunk = makeChunk(documentId: "doc-1")
        let acceptedChunk = makeChunk(documentId: "doc-2")

        #expect(!filter.matches(rejectedChunk))
        #expect(filter.matches(acceptedChunk))
    }

    // MARK: - Numeric Comparison Tests

    @Test("greaterThan filter matches with int value")
    func testGreaterThanWithInt() {
        let filter = MetadataFilter.greaterThan("index", 5)

        let matchingChunk = makeChunk(index: 10)
        let nonMatchingChunk = makeChunk(index: 3)

        #expect(filter.matches(matchingChunk))
        #expect(!filter.matches(nonMatchingChunk))
    }

    @Test("lessThan filter matches with double value")
    func testLessThanWithDouble() {
        let filter = MetadataFilter.lessThan("score", 0.5)

        let matchingChunk = makeChunk(custom: ["score": .double(0.3)])
        let nonMatchingChunk = makeChunk(custom: ["score": .double(0.8)])

        #expect(filter.matches(matchingChunk))
        #expect(!filter.matches(nonMatchingChunk))
    }

    @Test("greaterThanOrEqual filter includes boundary value")
    func testGreaterThanOrEqualIncludesBoundary() {
        let filter = MetadataFilter.greaterThanOrEqual("index", 5)

        let boundaryChunk = makeChunk(index: 5)
        let aboveChunk = makeChunk(index: 6)
        let belowChunk = makeChunk(index: 4)

        #expect(filter.matches(boundaryChunk))
        #expect(filter.matches(aboveChunk))
        #expect(!filter.matches(belowChunk))
    }

    @Test("lessThanOrEqual filter includes boundary value")
    func testLessThanOrEqualIncludesBoundary() {
        let filter = MetadataFilter.lessThanOrEqual("index", 5)

        let boundaryChunk = makeChunk(index: 5)
        let belowChunk = makeChunk(index: 4)
        let aboveChunk = makeChunk(index: 6)

        #expect(filter.matches(boundaryChunk))
        #expect(filter.matches(belowChunk))
        #expect(!filter.matches(aboveChunk))
    }

    // MARK: - In/NotIn Tests

    @Test("in filter matches values in set")
    func testInMatchesValuesInSet() {
        let filter = MetadataFilter.in("documentId", ["doc-1", "doc-2"])

        let matchingChunk1 = makeChunk(documentId: "doc-1")
        let matchingChunk2 = makeChunk(documentId: "doc-2")
        let nonMatchingChunk = makeChunk(documentId: "doc-3")

        #expect(filter.matches(matchingChunk1))
        #expect(filter.matches(matchingChunk2))
        #expect(!filter.matches(nonMatchingChunk))
    }

    @Test("notIn filter excludes values in set")
    func testNotInExcludesValuesInSet() {
        let filter = MetadataFilter.notIn("documentId", ["doc-1"])

        let rejectedChunk = makeChunk(documentId: "doc-1")
        let acceptedChunk = makeChunk(documentId: "doc-3")

        #expect(!filter.matches(rejectedChunk))
        #expect(filter.matches(acceptedChunk))
    }

    // MARK: - String Operation Tests

    @Test("contains filter matches substring")
    func testContainsMatchesSubstring() {
        let filter = MetadataFilter.contains("source", "test")

        let matchingChunk = makeChunk(source: "test-source")
        let nonMatchingChunk = makeChunk(source: "other-source")

        #expect(filter.matches(matchingChunk))
        #expect(!filter.matches(nonMatchingChunk))
    }

    @Test("startsWith filter matches prefix")
    func testStartsWithMatchesPrefix() {
        let filter = MetadataFilter.startsWith("source", "test")

        let matchingChunk = makeChunk(source: "test-source")
        let nonMatchingChunk = makeChunk(source: "my-test-source")

        #expect(filter.matches(matchingChunk))
        #expect(!filter.matches(nonMatchingChunk))
    }

    @Test("endsWith filter matches suffix")
    func testEndsWithMatchesSuffix() {
        let filter = MetadataFilter.endsWith("source", "source")

        let matchingChunk = makeChunk(source: "test-source")
        let nonMatchingChunk = makeChunk(source: "source-test")

        #expect(filter.matches(matchingChunk))
        #expect(!filter.matches(nonMatchingChunk))
    }

    // MARK: - Existence Tests

    @Test("exists filter returns true for present field")
    func testExistsReturnsTrueForPresentField() {
        let filter = MetadataFilter.exists("source")

        let chunkWithSource = makeChunk(source: "test-source")

        #expect(filter.matches(chunkWithSource))
    }

    @Test("exists filter returns false for null value")
    func testExistsReturnsFalseForNull() {
        let filter = MetadataFilter.exists("missing")

        let chunkWithNull = makeChunk(custom: ["missing": .null])

        #expect(!filter.matches(chunkWithNull))
    }

    @Test("notExists filter returns true for missing field")
    func testNotExistsReturnsTrueForMissingField() {
        let filter = MetadataFilter.notExists("nonexistent")

        let chunk = makeChunk()

        #expect(filter.matches(chunk))
    }

    @Test("notExists filter returns true for null value")
    func testNotExistsReturnsTrueForNull() {
        let filter = MetadataFilter.notExists("nullField")

        let chunkWithNull = makeChunk(custom: ["nullField": .null])

        #expect(filter.matches(chunkWithNull))
    }

    // MARK: - Logical Operator Tests

    @Test("and filter requires all conditions to pass")
    func testAndRequiresAllConditions() {
        let filter1 = MetadataFilter.equals("documentId", "doc-1")
        let filter2 = MetadataFilter.greaterThan("index", 5.0)
        let andFilter = MetadataFilter.and([filter1, filter2])

        let matchingChunk = makeChunk(documentId: "doc-1", index: 10)
        let failsFirst = makeChunk(documentId: "doc-2", index: 10)
        let failsSecond = makeChunk(documentId: "doc-1", index: 3)
        let failsBoth = makeChunk(documentId: "doc-2", index: 3)

        #expect(andFilter.matches(matchingChunk))
        #expect(!andFilter.matches(failsFirst))
        #expect(!andFilter.matches(failsSecond))
        #expect(!andFilter.matches(failsBoth))
    }

    @Test("or filter requires any condition to pass")
    func testOrRequiresAnyCondition() {
        let filter1 = MetadataFilter.equals("documentId", "doc-1")
        let filter2 = MetadataFilter.equals("documentId", "doc-2")
        let orFilter = MetadataFilter.or([filter1, filter2])

        let matchesFirst = makeChunk(documentId: "doc-1")
        let matchesSecond = makeChunk(documentId: "doc-2")
        let matchesNeither = makeChunk(documentId: "doc-3")

        #expect(orFilter.matches(matchesFirst))
        #expect(orFilter.matches(matchesSecond))
        #expect(!orFilter.matches(matchesNeither))
    }

    @Test("not filter inverts condition")
    func testNotInvertsCondition() {
        let innerFilter = MetadataFilter.equals("documentId", "doc-1")
        let notFilter = MetadataFilter.not(innerFilter)

        let shouldNotMatch = makeChunk(documentId: "doc-1")
        let shouldMatch = makeChunk(documentId: "doc-2")

        #expect(!notFilter.matches(shouldNotMatch))
        #expect(notFilter.matches(shouldMatch))
    }

    // MARK: - Complex Nested Filter Test

    @Test("complex nested filter works correctly")
    func testComplexNestedFilter() {
        // Build: AND of (equals OR greaterThan) with NOT
        // Matches if: (documentId == "doc-1" OR index > 5) AND NOT (source == "excluded")

        let equalsFilter = MetadataFilter.equals("documentId", "doc-1")
        let greaterThanFilter = MetadataFilter.greaterThan("index", 5.0)
        let orFilter = MetadataFilter.or([equalsFilter, greaterThanFilter])

        let excludedSourceFilter = MetadataFilter.equals("source", "excluded")
        let notExcludedFilter = MetadataFilter.not(excludedSourceFilter)

        let complexFilter = MetadataFilter.and([orFilter, notExcludedFilter])

        // Should match: documentId is "doc-1" and source is not "excluded"
        let matches1 = makeChunk(documentId: "doc-1", index: 0, source: "allowed")
        #expect(complexFilter.matches(matches1))

        // Should match: index > 5 and source is not "excluded"
        let matches2 = makeChunk(documentId: "doc-99", index: 10, source: "allowed")
        #expect(complexFilter.matches(matches2))

        // Should NOT match: documentId is "doc-1" but source is "excluded"
        let noMatch1 = makeChunk(documentId: "doc-1", index: 0, source: "excluded")
        #expect(!complexFilter.matches(noMatch1))

        // Should NOT match: neither documentId == "doc-1" nor index > 5
        let noMatch2 = makeChunk(documentId: "doc-99", index: 3, source: "allowed")
        #expect(!complexFilter.matches(noMatch2))

        // Should NOT match: index > 5 but source is "excluded"
        let noMatch3 = makeChunk(documentId: "doc-99", index: 10, source: "excluded")
        #expect(!complexFilter.matches(noMatch3))
    }
}
