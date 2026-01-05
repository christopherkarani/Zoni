// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ToolTests.swift - Tests for Agent Tools

import Testing
import Foundation
@testable import Zoni

// MARK: - Mock Retriever

/// A mock retriever for testing tools.
actor ToolMockRetriever: Retriever {
    let name = "mock-retriever"

    private var mockResults: [RetrievalResult] = []
    private(set) var lastQuery: String?
    private(set) var lastLimit: Int?

    init(results: [RetrievalResult] = []) {
        self.mockResults = results
    }

    func setResults(_ results: [RetrievalResult]) {
        self.mockResults = results
    }

    func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        lastQuery = query
        lastLimit = limit
        return Array(mockResults.prefix(limit))
    }
}

// MARK: - Test Helpers

private func makeChunk(
    id: String = UUID().uuidString,
    content: String,
    documentId: String = "doc-1",
    source: String? = nil
) -> Chunk {
    Chunk(
        id: id,
        content: content,
        metadata: ChunkMetadata(
            documentId: documentId,
            index: 0,
            startOffset: 0,
            endOffset: content.count,
            source: source,
            custom: [:]
        )
    )
}

private func makeRetrievalResult(
    content: String,
    score: Float = 0.9,
    source: String? = nil
) -> RetrievalResult {
    RetrievalResult(
        chunk: makeChunk(content: content, source: source),
        score: score,
        metadata: [:]
    )
}

// MARK: - SendableValue Tests

@Suite("SendableValue Tests")
struct SendableValueTests {

    @Test("stringValue returns string from .string case")
    func testStringValue() {
        let value = SendableValue.string("hello")
        #expect(value.stringValue == "hello")
    }

    @Test("stringValue returns nil for non-string cases")
    func testStringValueReturnsNil() {
        #expect(SendableValue.int(42).stringValue == nil)
        #expect(SendableValue.bool(true).stringValue == nil)
        #expect(SendableValue.null.stringValue == nil)
    }

    @Test("intValue returns int from .int case")
    func testIntValue() {
        let value = SendableValue.int(42)
        #expect(value.intValue == 42)
    }

    @Test("doubleValue returns double from .double case")
    func testDoubleValue() {
        let value = SendableValue.double(3.14)
        #expect(value.doubleValue == 3.14)
    }

    @Test("doubleValue converts int to double")
    func testDoubleValueConvertsInt() {
        let value = SendableValue.int(42)
        #expect(value.doubleValue == 42.0)
    }

    @Test("boolValue returns bool from .bool case")
    func testBoolValue() {
        #expect(SendableValue.bool(true).boolValue == true)
        #expect(SendableValue.bool(false).boolValue == false)
    }

    @Test("arrayValue returns array from .array case")
    func testArrayValue() {
        let value = SendableValue.array([.int(1), .int(2)])
        #expect(value.arrayValue?.count == 2)
    }

    @Test("dictionaryValue returns dictionary from .dictionary case")
    func testDictionaryValue() {
        let value = SendableValue.dictionary(["key": .string("value")])
        #expect(value.dictionaryValue?["key"]?.stringValue == "value")
    }

    @Test("isNull returns true for .null case")
    func testIsNull() {
        #expect(SendableValue.null.isNull == true)
        #expect(SendableValue.string("test").isNull == false)
    }

    @Test("Codable roundtrip preserves values")
    func testCodableRoundtrip() throws {
        let original = SendableValue.dictionary([
            "name": .string("test"),
            "count": .int(42),
            "active": .bool(true),
            "scores": .array([.double(1.5), .double(2.5)])
        ])

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SendableValue.self, from: data)

        #expect(decoded == original)
    }

    @Test("Literal initialization works correctly")
    func testLiteralInitialization() {
        let nilValue: SendableValue = nil
        let boolValue: SendableValue = true
        let intValue: SendableValue = 42
        let doubleValue: SendableValue = 3.14
        let stringValue: SendableValue = "hello"
        let arrayValue: SendableValue = [1, 2, 3]
        let dictValue: SendableValue = ["key": "value"]

        #expect(nilValue.isNull)
        #expect(boolValue.boolValue == true)
        #expect(intValue.intValue == 42)
        #expect(doubleValue.doubleValue == 3.14)
        #expect(stringValue.stringValue == "hello")
        #expect(arrayValue.arrayValue?.count == 3)
        #expect(dictValue.dictionaryValue?["key"]?.stringValue == "value")
    }

    @Test("Hashable implementation works correctly")
    func testHashable() {
        let value1 = SendableValue.string("test")
        let value2 = SendableValue.string("test")
        let value3 = SendableValue.string("different")

        #expect(value1.hashValue == value2.hashValue)
        #expect(value1.hashValue != value3.hashValue)

        // Test in Set
        var set = Set<SendableValue>()
        set.insert(value1)
        set.insert(value2)
        #expect(set.count == 1)
    }

    @Test("CustomStringConvertible produces readable output")
    func testDescription() {
        #expect(SendableValue.null.description == "null")
        #expect(SendableValue.bool(true).description == "true")
        #expect(SendableValue.int(42).description == "42")
        #expect(SendableValue.string("hello").description == "\"hello\"")
    }
}

// MARK: - MetadataValue Bridging Tests

@Suite("MetadataValue Bridging Tests")
struct MetadataValueBridgingTests {

    @Test("SendableValue converts to MetadataValue")
    func testSendableToMetadata() {
        let sendable = SendableValue.dictionary([
            "name": .string("test"),
            "count": .int(42)
        ])

        let metadata = sendable.toMetadataValue()

        if case .dictionary(let dict) = metadata {
            #expect(dict["name"]?.stringValue == "test")
            #expect(dict["count"]?.intValue == 42)
        } else {
            Issue.record("Expected dictionary")
        }
    }

    @Test("MetadataValue converts to SendableValue")
    func testMetadataToSendable() {
        let metadata = MetadataValue.dictionary([
            "name": .string("test"),
            "count": .int(42)
        ])

        let sendable = metadata.toSendableValue()

        #expect(sendable.dictionaryValue?["name"]?.stringValue == "test")
        #expect(sendable.dictionaryValue?["count"]?.intValue == 42)
    }

    @Test("Bridging roundtrip preserves values")
    func testBridgingRoundtrip() {
        let original = SendableValue.array([
            .string("a"),
            .int(1),
            .double(2.5),
            .bool(true),
            .null
        ])

        let roundtripped = original.toMetadataValue().toSendableValue()

        #expect(roundtripped == original)
    }

    @Test("Nested structures convert correctly")
    func testNestedStructures() {
        let sendable = SendableValue.dictionary([
            "nested": .dictionary([
                "inner": .array([.int(1), .int(2)])
            ])
        ])

        let metadata = sendable.toMetadataValue()
        let back = metadata.toSendableValue()

        #expect(back == sendable)
    }
}

// MARK: - ChunkMetadata Conversion Tests

@Suite("ChunkMetadata Conversion Tests")
struct ChunkMetadataConversionTests {

    @Test("ChunkMetadata converts to SendableValue")
    func testChunkMetadataToSendable() {
        let metadata = ChunkMetadata(
            documentId: "doc-123",
            index: 5,
            startOffset: 100,
            endOffset: 200,
            source: "test.txt",
            custom: ["key": .string("value")]
        )

        let sendable = metadata.toSendableValue()
        let dict = sendable.dictionaryValue

        #expect(dict?["document_id"]?.stringValue == "doc-123")
        #expect(dict?["index"]?.intValue == 5)
        #expect(dict?["start_offset"]?.intValue == 100)
        #expect(dict?["end_offset"]?.intValue == 200)
        #expect(dict?["source"]?.stringValue == "test.txt")
    }

    @Test("ChunkMetadata without source omits source field")
    func testChunkMetadataWithoutSource() {
        let metadata = ChunkMetadata(
            documentId: "doc-123",
            index: 0
        )

        let sendable = metadata.toSendableValue()
        let dict = sendable.dictionaryValue

        #expect(dict?["source"] == nil)
    }
}

// MARK: - RetrievalResult Conversion Tests

@Suite("RetrievalResult Conversion Tests")
struct RetrievalResultConversionTests {

    @Test("RetrievalResult converts to SendableValue")
    func testRetrievalResultToSendable() {
        let result = makeRetrievalResult(content: "Test content", score: 0.85, source: "doc.txt")

        let sendable = result.toSendableValue()
        let dict = sendable.dictionaryValue

        #expect(dict?["content"]?.stringValue == "Test content")
        // Use approximate comparison for Float -> Double conversion
        if let score = dict?["score"]?.doubleValue {
            #expect(abs(score - 0.85) < 0.001)
        } else {
            Issue.record("Score not found in result")
        }
        #expect(dict?["source"]?.stringValue == "doc.txt")
    }

    @Test("RetrievalResult includes full metadata when requested")
    func testRetrievalResultWithFullMetadata() {
        let result = makeRetrievalResult(content: "Test", score: 0.9)

        let sendable = result.toSendableValue(includeFullMetadata: true)
        let dict = sendable.dictionaryValue

        #expect(dict?["metadata"] != nil)
    }
}

// MARK: - RAGSearchTool Tests

@Suite("RAGSearchTool Tests")
struct RAGSearchToolTests {

    @Test("Tool has correct name")
    func testToolName() {
        let tool = RAGSearchTool(retriever: ToolMockRetriever())
        #expect(tool.name == "search_knowledge")
    }

    @Test("Tool has required query parameter")
    func testRequiredParameters() {
        let tool = RAGSearchTool(retriever: ToolMockRetriever())
        let queryParam = tool.parameters.first { $0.name == "query" }
        #expect(queryParam?.isRequired == true)
        #expect(queryParam?.type == .string)
    }

    @Test("Tool has optional limit parameter")
    func testLimitParameter() {
        let tool = RAGSearchTool(retriever: ToolMockRetriever())
        let limitParam = tool.parameters.first { $0.name == "limit" }
        #expect(limitParam?.isRequired == false)
        #expect(limitParam?.type == .int)
        #expect(limitParam?.defaultValue?.intValue == 5)
    }

    @Test("Tool has optional min_score parameter")
    func testMinScoreParameter() {
        let tool = RAGSearchTool(retriever: ToolMockRetriever())
        let minScoreParam = tool.parameters.first { $0.name == "min_score" }
        #expect(minScoreParam?.isRequired == false)
        #expect(minScoreParam?.type == .double)
        #expect(minScoreParam?.defaultValue?.doubleValue == 0.0)
    }

    @Test("Execute returns results for valid query")
    func testExecuteReturnsResults() async throws {
        let mockResults = [
            makeRetrievalResult(content: "Result 1", score: 0.9),
            makeRetrievalResult(content: "Result 2", score: 0.8)
        ]
        let retriever = ToolMockRetriever(results: mockResults)
        let tool = RAGSearchTool(retriever: retriever)

        let result = try await tool.execute(arguments: [
            "query": .string("test query")
        ])

        let results = result.dictionaryValue?["results"]?.arrayValue
        #expect(results?.count == 2)
        #expect(result.dictionaryValue?["total_found"]?.intValue == 2)
        #expect(result.dictionaryValue?["query"]?.stringValue == "test query")
    }

    @Test("Execute passes query to retriever")
    func testExecutePassesQuery() async throws {
        let retriever = ToolMockRetriever()
        let tool = RAGSearchTool(retriever: retriever)

        _ = try await tool.execute(arguments: [
            "query": .string("specific query")
        ])

        let lastQuery = await retriever.lastQuery
        #expect(lastQuery == "specific query")
    }

    @Test("Execute respects limit parameter")
    func testExecuteRespectsLimit() async throws {
        let mockResults = [
            makeRetrievalResult(content: "Result 1", score: 0.9),
            makeRetrievalResult(content: "Result 2", score: 0.8),
            makeRetrievalResult(content: "Result 3", score: 0.7)
        ]
        let retriever = ToolMockRetriever(results: mockResults)
        let tool = RAGSearchTool(retriever: retriever)

        _ = try await tool.execute(arguments: [
            "query": .string("test"),
            "limit": .int(2)
        ])

        let lastLimit = await retriever.lastLimit
        #expect(lastLimit == 2)
    }

    @Test("Execute filters by min_score")
    func testExecuteFiltersMinScore() async throws {
        let mockResults = [
            makeRetrievalResult(content: "High score", score: 0.9),
            makeRetrievalResult(content: "Low score", score: 0.3)
        ]
        let retriever = ToolMockRetriever(results: mockResults)
        let tool = RAGSearchTool(retriever: retriever)

        let result = try await tool.execute(arguments: [
            "query": .string("test"),
            "min_score": .double(0.5)
        ])

        let results = result.dictionaryValue?["results"]?.arrayValue
        #expect(results?.count == 1)
    }

    @Test("Execute throws on missing query")
    func testExecuteThrowsOnMissingQuery() async {
        let tool = RAGSearchTool(retriever: ToolMockRetriever())

        await #expect(throws: ZoniError.self) {
            _ = try await tool.execute(arguments: [:])
        }
    }

    @Test("Execute returns empty results when no matches")
    func testExecuteReturnsEmptyResults() async throws {
        let retriever = ToolMockRetriever(results: [])
        let tool = RAGSearchTool(retriever: retriever)

        let result = try await tool.execute(arguments: [
            "query": .string("test")
        ])

        let results = result.dictionaryValue?["results"]?.arrayValue
        #expect(results?.isEmpty == true)
        #expect(result.dictionaryValue?["total_found"]?.intValue == 0)
    }

    @Test("Execute uses default limit when not specified")
    func testExecuteUsesDefaultLimit() async throws {
        let retriever = ToolMockRetriever()
        let tool = RAGSearchTool(retriever: retriever)

        _ = try await tool.execute(arguments: [
            "query": .string("test")
        ])

        let lastLimit = await retriever.lastLimit
        #expect(lastLimit == 5)
    }
}

// MARK: - MultiIndexTool Tests

@Suite("MultiIndexTool Tests")
struct MultiIndexToolTests {

    @Test("Tool has correct name")
    func testToolName() async {
        let tool = MultiIndexTool()
        #expect(tool.name == "multi_index_search")
    }

    @Test("Tool has required query parameter")
    func testQueryParameter() async {
        let tool = MultiIndexTool()
        let queryParam = tool.parameters.first { $0.name == "query" }
        #expect(queryParam?.isRequired == true)
        #expect(queryParam?.type == .string)
    }

    @Test("Tool has optional indexes parameter")
    func testIndexesParameter() async {
        let tool = MultiIndexTool()
        let indexesParam = tool.parameters.first { $0.name == "indexes" }
        #expect(indexesParam?.isRequired == false)
    }

    @Test("Tool has optional limit_per_index parameter")
    func testLimitPerIndexParameter() async {
        let tool = MultiIndexTool()
        let limitParam = tool.parameters.first { $0.name == "limit_per_index" }
        #expect(limitParam?.isRequired == false)
        #expect(limitParam?.type == .int)
        #expect(limitParam?.defaultValue?.intValue == 3)
    }

    @Test("Register and list indexes")
    func testRegisterAndListIndexes() async {
        let tool = MultiIndexTool()
        let retriever = ToolMockRetriever()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "test-index",
            description: "A test index",
            retriever: retriever
        ))

        let indexes = await tool.availableIndexes()
        #expect(indexes["test-index"] == "A test index")
    }

    @Test("Register multiple indexes")
    func testRegisterMultipleIndexes() async {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-a",
            description: "Index A",
            retriever: ToolMockRetriever()
        ))

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-b",
            description: "Index B",
            retriever: ToolMockRetriever()
        ))

        let indexes = await tool.availableIndexes()
        #expect(indexes.count == 2)
        #expect(indexes["index-a"] == "Index A")
        #expect(indexes["index-b"] == "Index B")
    }

    @Test("Remove index")
    func testRemoveIndex() async {
        let tool = MultiIndexTool()
        let retriever = ToolMockRetriever()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "test-index",
            description: "A test index",
            retriever: retriever
        ))

        await tool.removeIndex(name: "test-index")

        let indexes = await tool.availableIndexes()
        #expect(indexes.isEmpty)
    }

    @Test("indexNames returns registered index names")
    func testIndexNames() async {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-a",
            description: "Index A",
            retriever: ToolMockRetriever()
        ))

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-b",
            description: "Index B",
            retriever: ToolMockRetriever()
        ))

        let names = await tool.indexNames()
        #expect(names.count == 2)
        #expect(names.contains("index-a"))
        #expect(names.contains("index-b"))
    }

    @Test("Search single index")
    func testSearchSingleIndex() async throws {
        let tool = MultiIndexTool()
        let mockResults = [makeRetrievalResult(content: "Result 1", score: 0.9)]
        let retriever = ToolMockRetriever(results: mockResults)

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "test-index",
            description: "A test index",
            retriever: retriever
        ))

        let result = try await tool.execute(arguments: [
            "query": .string("test query")
        ])

        let indexesSearched = result.dictionaryValue?["indexes_searched"]?.arrayValue
        #expect(indexesSearched?.count == 1)

        let resultsByIndex = result.dictionaryValue?["results_by_index"]?.arrayValue
        #expect(resultsByIndex?.count == 1)
    }

    @Test("Search all indexes when none specified")
    func testSearchAllIndexes() async throws {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-a",
            description: "Index A",
            retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "A", score: 0.9)])
        ))

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-b",
            description: "Index B",
            retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "B", score: 0.8)])
        ))

        let result = try await tool.execute(arguments: [
            "query": .string("test")
        ])

        let indexesSearched = result.dictionaryValue?["indexes_searched"]?.arrayValue
        #expect(indexesSearched?.count == 2)

        let totalIndexes = result.dictionaryValue?["total_indexes"]?.intValue
        #expect(totalIndexes == 2)
    }

    @Test("Search specific indexes only")
    func testSearchSpecificIndexes() async throws {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-a",
            description: "Index A",
            retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "A", score: 0.9)])
        ))

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "index-b",
            description: "Index B",
            retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "B", score: 0.8)])
        ))

        let result = try await tool.execute(arguments: [
            "query": .string("test"),
            "indexes": .array([.string("index-a")])
        ])

        let indexesSearched = result.dictionaryValue?["indexes_searched"]?.arrayValue
        #expect(indexesSearched?.count == 1)
        #expect(indexesSearched?.first?.stringValue == "index-a")
    }

    @Test("Search ignores non-existent indexes")
    func testSearchIgnoresNonExistentIndexes() async throws {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "existing",
            description: "Existing Index",
            retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "Result", score: 0.9)])
        ))

        let result = try await tool.execute(arguments: [
            "query": .string("test"),
            "indexes": .array([.string("existing"), .string("non-existent")])
        ])

        let indexesSearched = result.dictionaryValue?["indexes_searched"]?.arrayValue
        #expect(indexesSearched?.count == 1)
        #expect(indexesSearched?.first?.stringValue == "existing")
    }

    @Test("Returns empty when no indexes registered")
    func testReturnsEmptyWhenNoIndexes() async throws {
        let tool = MultiIndexTool()

        let result = try await tool.execute(arguments: [
            "query": .string("test")
        ])

        let indexesSearched = result.dictionaryValue?["indexes_searched"]?.arrayValue
        #expect(indexesSearched?.isEmpty == true)

        let message = result.dictionaryValue?["message"]?.stringValue
        #expect(message == "No indexes registered")
    }

    @Test("Returns message when no matching indexes found")
    func testReturnsMessageWhenNoMatchingIndexes() async throws {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "existing",
            description: "Existing Index",
            retriever: ToolMockRetriever()
        ))

        let result = try await tool.execute(arguments: [
            "query": .string("test"),
            "indexes": .array([.string("non-existent")])
        ])

        let message = result.dictionaryValue?["message"]?.stringValue
        #expect(message == "No matching indexes found")
    }

    @Test("Execute throws on missing query")
    func testExecuteThrowsOnMissingQuery() async {
        let tool = MultiIndexTool()

        await #expect(throws: ZoniError.self) {
            _ = try await tool.execute(arguments: [:])
        }
    }

    @Test("Results include index description")
    func testResultsIncludeIndexDescription() async throws {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "test-index",
            description: "Test Index Description",
            retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "Result", score: 0.9)])
        ))

        let result = try await tool.execute(arguments: [
            "query": .string("test")
        ])

        let resultsByIndex = result.dictionaryValue?["results_by_index"]?.arrayValue
        let firstIndexResult = resultsByIndex?.first?.dictionaryValue
        #expect(firstIndexResult?["index_description"]?.stringValue == "Test Index Description")
    }
}

// MARK: - Argument Extraction Tests

@Suite("Argument Extraction Tests")
struct ArgumentExtractionTests {

    @Test("requireString extracts string value")
    func testRequireString() throws {
        let args: [String: SendableValue] = ["name": .string("test")]
        let value = try args.requireString("name")
        #expect(value == "test")
    }

    @Test("requireString throws on missing argument")
    func testRequireStringThrowsOnMissing() {
        let args: [String: SendableValue] = [:]
        #expect(throws: ZoniError.self) {
            _ = try args.requireString("name")
        }
    }

    @Test("requireString throws on wrong type")
    func testRequireStringThrowsOnWrongType() {
        let args: [String: SendableValue] = ["name": .int(42)]
        #expect(throws: ZoniError.self) {
            _ = try args.requireString("name")
        }
    }

    @Test("optionalString returns value when present")
    func testOptionalStringReturnsValue() {
        let args: [String: SendableValue] = ["name": .string("test")]
        let value = args.optionalString("name")
        #expect(value == "test")
    }

    @Test("optionalString returns nil when missing")
    func testOptionalStringReturnsNil() {
        let args: [String: SendableValue] = [:]
        let value = args.optionalString("name")
        #expect(value == nil)
    }

    @Test("optionalString returns default when missing")
    func testOptionalStringReturnsDefault() {
        let args: [String: SendableValue] = [:]
        let value = args.optionalString("name", default: "default")
        #expect(value == "default")
    }

    @Test("optionalInt returns value or default")
    func testOptionalInt() {
        let argsWithValue: [String: SendableValue] = ["count": .int(42)]
        let argsWithoutValue: [String: SendableValue] = [:]

        #expect(argsWithValue.optionalInt("count", default: 5) == 42)
        #expect(argsWithoutValue.optionalInt("count", default: 5) == 5)
    }

    @Test("optionalDouble returns value or default")
    func testOptionalDouble() {
        let argsWithValue: [String: SendableValue] = ["score": .double(0.95)]
        let argsWithoutValue: [String: SendableValue] = [:]

        #expect(argsWithValue.optionalDouble("score", default: 0.5) == 0.95)
        #expect(argsWithoutValue.optionalDouble("score", default: 0.5) == 0.5)
    }

    @Test("optionalDouble converts int to double")
    func testOptionalDoubleConvertsInt() {
        let args: [String: SendableValue] = ["score": .int(42)]
        #expect(args.optionalDouble("score", default: 0.0) == 42.0)
    }

    @Test("optionalBool returns value or default")
    func testOptionalBool() {
        let argsWithValue: [String: SendableValue] = ["enabled": .bool(false)]
        let argsWithoutValue: [String: SendableValue] = [:]

        #expect(argsWithValue.optionalBool("enabled", default: true) == false)
        #expect(argsWithoutValue.optionalBool("enabled", default: true) == true)
    }

    @Test("optionalStringArray extracts string array")
    func testOptionalStringArray() {
        let args: [String: SendableValue] = [
            "items": .array([.string("a"), .string("b")])
        ]

        let items = args.optionalStringArray("items")
        #expect(items == ["a", "b"])
    }

    @Test("optionalStringArray returns nil when missing")
    func testOptionalStringArrayReturnsNil() {
        let args: [String: SendableValue] = [:]
        let items = args.optionalStringArray("items")
        #expect(items == nil)
    }

    @Test("optionalStringArray filters non-string elements")
    func testOptionalStringArrayFiltersNonStrings() {
        let args: [String: SendableValue] = [
            "items": .array([.string("a"), .int(42), .string("b")])
        ]

        let items = args.optionalStringArray("items")
        #expect(items == ["a", "b"])
    }
}

// MARK: - ToolParameter Tests

@Suite("ToolParameter Tests")
struct ToolParameterTests {

    @Test("ToolParameter initializes correctly")
    func testToolParameterInit() {
        let param = ToolParameter(
            name: "query",
            description: "The search query",
            type: .string,
            isRequired: true,
            defaultValue: nil
        )

        #expect(param.name == "query")
        #expect(param.description == "The search query")
        #expect(param.type == .string)
        #expect(param.isRequired == true)
        #expect(param.defaultValue == nil)
    }

    @Test("ToolParameter with default value")
    func testToolParameterWithDefault() {
        let param = ToolParameter(
            name: "limit",
            description: "Maximum results",
            type: .int,
            isRequired: false,
            defaultValue: .int(10)
        )

        #expect(param.isRequired == false)
        #expect(param.defaultValue?.intValue == 10)
    }

    @Test("ParameterType equality")
    func testParameterTypeEquality() {
        #expect(ParameterType.string == ParameterType.string)
        #expect(ParameterType.int == ParameterType.int)
        #expect(ParameterType.string != ParameterType.int)
        #expect(ParameterType.array(elementType: .string) == ParameterType.array(elementType: .string))
        #expect(ParameterType.array(elementType: .string) != ParameterType.array(elementType: .int))
    }
}

// MARK: - Tool Protocol Conformance Tests

@Suite("Tool Protocol Conformance Tests")
struct ToolProtocolConformanceTests {

    @Test("RAGSearchTool conforms to Tool protocol")
    func testRAGSearchToolConformance() {
        let tool: any Tool = RAGSearchTool(retriever: ToolMockRetriever())

        #expect(tool.name == "search_knowledge")
        #expect(!tool.description.isEmpty)
        #expect(!tool.parameters.isEmpty)
    }

    @Test("MultiIndexTool conforms to Tool protocol")
    func testMultiIndexToolConformance() async {
        let tool: any Tool = MultiIndexTool()

        #expect(tool.name == "multi_index_search")
        #expect(!tool.description.isEmpty)
        #expect(!tool.parameters.isEmpty)
    }

    @Test("Tools are Sendable")
    func testToolsSendable() async {
        let searchTool = RAGSearchTool(retriever: ToolMockRetriever())
        let multiIndexTool = MultiIndexTool()

        // These should compile without issues due to Sendable conformance
        await Task.detached {
            _ = searchTool.name
        }.value

        await Task.detached {
            _ = multiIndexTool.name
        }.value
    }
}

// MARK: - Validation Error Tests

@Suite("Validation Error Tests")
struct ValidationErrorTests {

    @Test("RAGSearchTool throws on zero limit")
    func testSearchToolZeroLimit() async {
        let tool = RAGSearchTool(retriever: ToolMockRetriever())

        await #expect(throws: ZoniError.self) {
            _ = try await tool.execute(arguments: [
                "query": .string("test"),
                "limit": .int(0)
            ])
        }
    }

    @Test("RAGSearchTool throws on negative limit")
    func testSearchToolNegativeLimit() async {
        let tool = RAGSearchTool(retriever: ToolMockRetriever())

        await #expect(throws: ZoniError.self) {
            _ = try await tool.execute(arguments: [
                "query": .string("test"),
                "limit": .int(-5)
            ])
        }
    }

    @Test("RAGSearchTool clamps min_score above 1.0")
    func testSearchToolClampsHighScore() async throws {
        let mockResults = [makeRetrievalResult(content: "Result", score: 0.9)]
        let retriever = ToolMockRetriever(results: mockResults)
        let tool = RAGSearchTool(retriever: retriever)

        // min_score of 2.0 should be clamped to 1.0, filtering out 0.9 score
        let result = try await tool.execute(arguments: [
            "query": .string("test"),
            "min_score": .double(2.0)
        ])

        let results = result.dictionaryValue?["results"]?.arrayValue
        #expect(results?.count == 0)
    }

    @Test("RAGSearchTool clamps min_score below 0.0")
    func testSearchToolClampsLowScore() async throws {
        let mockResults = [makeRetrievalResult(content: "Result", score: 0.1)]
        let retriever = ToolMockRetriever(results: mockResults)
        let tool = RAGSearchTool(retriever: retriever)

        // min_score of -1.0 should be clamped to 0.0, including 0.1 score
        let result = try await tool.execute(arguments: [
            "query": .string("test"),
            "min_score": .double(-1.0)
        ])

        let results = result.dictionaryValue?["results"]?.arrayValue
        #expect(results?.count == 1)
    }

    @Test("MultiIndexTool throws on zero limit_per_index")
    func testMultiIndexToolZeroLimit() async {
        let tool = MultiIndexTool()
        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "test",
            description: "Test index",
            retriever: ToolMockRetriever()
        ))

        await #expect(throws: ZoniError.self) {
            _ = try await tool.execute(arguments: [
                "query": .string("test"),
                "limit_per_index": .int(0)
            ])
        }
    }

    @Test("MultiIndexTool throws on negative limit_per_index")
    func testMultiIndexToolNegativeLimit() async {
        let tool = MultiIndexTool()
        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "test",
            description: "Test index",
            retriever: ToolMockRetriever()
        ))

        await #expect(throws: ZoniError.self) {
            _ = try await tool.execute(arguments: [
                "query": .string("test"),
                "limit_per_index": .int(-3)
            ])
        }
    }
}

// MARK: - MultiIndexTool Concurrency Tests

@Suite("MultiIndexTool Concurrency Tests")
struct MultiIndexToolConcurrencyTests {

    @Test("Concurrent registrations are safe")
    func testConcurrentRegistrations() async {
        let tool = MultiIndexTool()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await tool.registerIndex(MultiIndexTool.IndexConfig(
                        name: "index-\(i)",
                        description: "Index \(i)",
                        retriever: ToolMockRetriever()
                    ))
                }
            }
        }

        let names = await tool.indexNames()
        #expect(names.count == 50)
    }

    @Test("Concurrent search and registration are safe")
    func testConcurrentSearchAndRegistration() async throws {
        let tool = MultiIndexTool()

        // Pre-register some indexes
        for i in 0..<5 {
            await tool.registerIndex(MultiIndexTool.IndexConfig(
                name: "initial-\(i)",
                description: "Initial Index \(i)",
                retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "Result \(i)", score: 0.9)])
            ))
        }

        // Run searches and registrations concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Add search tasks
            for _ in 0..<10 {
                group.addTask {
                    _ = try await tool.execute(arguments: [
                        "query": .string("test query")
                    ])
                }
            }

            // Add registration tasks concurrently
            for i in 0..<10 {
                group.addTask {
                    await tool.registerIndex(MultiIndexTool.IndexConfig(
                        name: "concurrent-\(i)",
                        description: "Concurrent Index \(i)",
                        retriever: ToolMockRetriever()
                    ))
                }
            }

            try await group.waitForAll()
        }

        // Verify all indexes are registered
        let names = await tool.indexNames()
        #expect(names.count == 15) // 5 initial + 10 concurrent
    }

    @Test("Search snapshot prevents race condition")
    func testSearchSnapshotPreventsRaceCondition() async throws {
        let tool = MultiIndexTool()

        // Register initial indexes
        for i in 0..<3 {
            await tool.registerIndex(MultiIndexTool.IndexConfig(
                name: "index-\(i)",
                description: "Index \(i)",
                retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "Result \(i)", score: 0.9)])
            ))
        }

        // Start a search (which should snapshot the configs)
        let searchTask = Task {
            try await tool.execute(arguments: [
                "query": .string("test")
            ])
        }

        // Remove an index while search is in progress
        await tool.removeIndex(name: "index-1")

        // Get the search result
        let result = try await searchTask.value

        // The search should have been consistent with the initial snapshot
        // (it may or may not include index-1 depending on timing, but should not crash)
        let totalIndexes = result.dictionaryValue?["total_indexes"]?.intValue ?? 0
        #expect(totalIndexes >= 0 && totalIndexes <= 3)
    }

    @Test("Concurrent removals are safe")
    func testConcurrentRemovals() async {
        let tool = MultiIndexTool()

        // Register many indexes
        for i in 0..<20 {
            await tool.registerIndex(MultiIndexTool.IndexConfig(
                name: "index-\(i)",
                description: "Index \(i)",
                retriever: ToolMockRetriever()
            ))
        }

        // Remove half of them concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in stride(from: 0, to: 20, by: 2) {
                group.addTask {
                    await tool.removeIndex(name: "index-\(i)")
                }
            }
        }

        let names = await tool.indexNames()
        #expect(names.count == 10)
    }

    @Test("Parallel searches on same tool are safe")
    func testParallelSearches() async throws {
        let tool = MultiIndexTool()

        await tool.registerIndex(MultiIndexTool.IndexConfig(
            name: "shared-index",
            description: "Shared Index",
            retriever: ToolMockRetriever(results: [makeRetrievalResult(content: "Shared result", score: 0.9)])
        ))

        // Run many parallel searches
        try await withThrowingTaskGroup(of: SendableValue.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await tool.execute(arguments: [
                        "query": .string("query \(i)")
                    ])
                }
            }

            var successCount = 0
            for try await result in group {
                let totalIndexes = result.dictionaryValue?["total_indexes"]?.intValue
                #expect(totalIndexes == 1)
                successCount += 1
            }

            #expect(successCount == 20)
        }
    }
}
