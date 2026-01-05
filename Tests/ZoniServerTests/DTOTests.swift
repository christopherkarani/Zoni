// ZoniServer - Server-side extensions for Zoni
//
// DTOTests.swift - Comprehensive tests for Server Data Transfer Objects
//
// This file tests encoding/decoding behavior for all server DTOs,
// ensuring proper JSON serialization for API communication.

import Testing
import Foundation
@testable import ZoniServer

// MARK: - Server DTO Tests

@Suite("Server DTO Tests")
struct DTOTests {

    // MARK: - MetadataValueDTO Tests

    @Suite("MetadataValueDTO Tests")
    struct MetadataValueDTOTests {

        @Test("MetadataValueDTO encodes null correctly")
        func testNullEncoding() throws {
            let value = MetadataValueDTO.null

            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(MetadataValueDTO.self, from: data)

            #expect(decoded == .null)
        }

        @Test("MetadataValueDTO encodes bool correctly")
        func testBoolEncoding() throws {
            let trueValue = MetadataValueDTO.bool(true)
            let falseValue = MetadataValueDTO.bool(false)

            let trueData = try JSONEncoder().encode(trueValue)
            let falseData = try JSONEncoder().encode(falseValue)

            let decodedTrue = try JSONDecoder().decode(MetadataValueDTO.self, from: trueData)
            let decodedFalse = try JSONDecoder().decode(MetadataValueDTO.self, from: falseData)

            #expect(decodedTrue == .bool(true))
            #expect(decodedFalse == .bool(false))
        }

        @Test("MetadataValueDTO encodes int correctly")
        func testIntEncoding() throws {
            let values: [Int] = [0, 1, -1, 42, Int.max, Int.min]

            for intValue in values {
                let value = MetadataValueDTO.int(intValue)
                let data = try JSONEncoder().encode(value)
                let decoded = try JSONDecoder().decode(MetadataValueDTO.self, from: data)

                #expect(decoded == .int(intValue))
            }
        }

        @Test("MetadataValueDTO encodes double correctly")
        func testDoubleEncoding() throws {
            let values: [Double] = [0.0, 3.14, -2.718, 1.0e10]

            for doubleValue in values {
                let value = MetadataValueDTO.double(doubleValue)
                let data = try JSONEncoder().encode(value)
                let decoded = try JSONDecoder().decode(MetadataValueDTO.self, from: data)

                #expect(decoded == .double(doubleValue))
            }
        }

        @Test("MetadataValueDTO encodes string correctly")
        func testStringEncoding() throws {
            let values = ["", "test", "Hello, World!", "Unicode: \u{1F600}"]

            for stringValue in values {
                let value = MetadataValueDTO.string(stringValue)
                let data = try JSONEncoder().encode(value)
                let decoded = try JSONDecoder().decode(MetadataValueDTO.self, from: data)

                #expect(decoded == .string(stringValue))
            }
        }

        @Test("MetadataValueDTO encodes array correctly")
        func testArrayEncoding() throws {
            let array: [MetadataValueDTO] = [
                .null,
                .bool(true),
                .int(42),
                .double(3.14),
                .string("test")
            ]
            let value = MetadataValueDTO.array(array)

            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(MetadataValueDTO.self, from: data)

            #expect(decoded == value)
        }

        @Test("MetadataValueDTO encodes dictionary correctly")
        func testDictionaryEncoding() throws {
            let dict: [String: MetadataValueDTO] = [
                "isNull": .null,
                "enabled": .bool(true),
                "count": .int(42),
                "rating": .double(4.5),
                "name": .string("test")
            ]
            let value = MetadataValueDTO.dictionary(dict)

            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(MetadataValueDTO.self, from: data)

            #expect(decoded == value)
        }

        @Test("MetadataValueDTO encodes nested structures correctly")
        func testNestedStructureEncoding() throws {
            let nested = MetadataValueDTO.dictionary([
                "outer": .dictionary([
                    "inner": .array([
                        .string("deep"),
                        .int(123)
                    ])
                ])
            ])

            let data = try JSONEncoder().encode(nested)
            let decoded = try JSONDecoder().decode(MetadataValueDTO.self, from: data)

            #expect(decoded == nested)
        }

        @Test("MetadataValueDTO is Hashable")
        func testHashable() {
            let values: Set<MetadataValueDTO> = [
                .null,
                .bool(true),
                .int(42),
                .double(3.14),
                .string("test")
            ]

            #expect(values.count == 5)
            #expect(values.contains(.null))
            #expect(values.contains(.int(42)))
        }
    }

    // MARK: - QueryRequest Tests

    @Suite("QueryRequest Tests")
    struct QueryRequestTests {

        @Test("QueryRequest encodes and decodes correctly")
        func testQueryRequestCodable() throws {
            let request = QueryRequest(
                query: "What is Swift?",
                options: QueryRequestOptions(
                    retrievalLimit: 10,
                    temperature: 0.7
                )
            )

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(QueryRequest.self, from: data)

            #expect(decoded.query == "What is Swift?")
            #expect(decoded.options?.retrievalLimit == 10)
            #expect(decoded.options?.temperature == 0.7)
        }

        @Test("QueryRequest without options")
        func testQueryRequestWithoutOptions() throws {
            let request = QueryRequest(query: "Simple query")

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(QueryRequest.self, from: data)

            #expect(decoded.query == "Simple query")
            #expect(decoded.options == nil)
        }

        @Test("QueryRequest with all options")
        func testQueryRequestWithAllOptions() throws {
            let filter = MetadataFilterDTO(
                type: "equals",
                field: "category",
                value: .string("documentation")
            )

            let options = QueryRequestOptions(
                retrievalLimit: 5,
                systemPrompt: "You are a helpful assistant",
                temperature: 0.5,
                filter: filter,
                maxContextTokens: 4000,
                includeMetadata: true
            )

            let request = QueryRequest(query: "How do I use async/await?", options: options)

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(QueryRequest.self, from: data)

            #expect(decoded.query == "How do I use async/await?")
            #expect(decoded.options?.retrievalLimit == 5)
            #expect(decoded.options?.systemPrompt == "You are a helpful assistant")
            #expect(decoded.options?.temperature == 0.5)
            #expect(decoded.options?.maxContextTokens == 4000)
            #expect(decoded.options?.includeMetadata == true)
            #expect(decoded.options?.filter?.type == "equals")
        }

        @Test("QueryRequest from JSON string")
        func testQueryRequestFromJSON() throws {
            let json = """
            {
                "query": "What is Swift?",
                "options": {
                    "retrievalLimit": 10,
                    "temperature": 0.7
                }
            }
            """

            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(QueryRequest.self, from: data)

            #expect(decoded.query == "What is Swift?")
            #expect(decoded.options?.retrievalLimit == 10)
        }
    }

    // MARK: - IngestRequest Tests

    @Suite("IngestRequest Tests")
    struct IngestRequestTests {

        @Test("IngestRequest with content")
        func testIngestRequestWithContent() throws {
            let request = IngestRequest(
                content: "This is the document content.",
                url: nil,
                documents: nil,
                options: nil
            )

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(IngestRequest.self, from: data)

            #expect(decoded.content == "This is the document content.")
            #expect(decoded.url == nil)
            #expect(decoded.documents == nil)
        }

        @Test("IngestRequest with URL")
        func testIngestRequestWithURL() throws {
            let request = IngestRequest(
                content: nil,
                url: "https://example.com/document.md",
                documents: nil,
                options: nil
            )

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(IngestRequest.self, from: data)

            #expect(decoded.url == "https://example.com/document.md")
            #expect(decoded.content == nil)
        }

        @Test("IngestRequest with documents")
        func testIngestRequestWithDocuments() throws {
            let request = IngestRequest(
                content: nil,
                url: nil,
                documents: [
                    DocumentDTO(content: "Test content", source: "test.md", title: "Test")
                ],
                options: IngestOptions(chunkSize: 500, async: true)
            )

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(IngestRequest.self, from: data)

            #expect(decoded.documents?.count == 1)
            #expect(decoded.documents?.first?.content == "Test content")
            #expect(decoded.documents?.first?.source == "test.md")
            #expect(decoded.documents?.first?.title == "Test")
            #expect(decoded.options?.chunkSize == 500)
            #expect(decoded.options?.async == true)
        }

        @Test("IngestRequest with multiple documents")
        func testIngestRequestWithMultipleDocuments() throws {
            let docs = [
                DocumentDTO(content: "First document", source: "first.md", title: "First"),
                DocumentDTO(content: "Second document", source: "second.md", title: "Second"),
                DocumentDTO(content: "Third document", source: "third.md", title: "Third")
            ]

            let request = IngestRequest(
                content: nil,
                url: nil,
                documents: docs,
                options: IngestOptions(chunkSize: 1000, chunkOverlap: 100)
            )

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(IngestRequest.self, from: data)

            #expect(decoded.documents?.count == 3)
            #expect(decoded.options?.chunkSize == 1000)
            #expect(decoded.options?.chunkOverlap == 100)
        }

        @Test("DocumentDTO with metadata")
        func testDocumentDTOWithMetadata() throws {
            let metadata: [String: MetadataValueDTO] = [
                "author": .string("John Doe"),
                "version": .int(2),
                "published": .bool(true)
            ]

            let doc = DocumentDTO(
                content: "Document content",
                source: "doc.md",
                title: "My Document",
                metadata: metadata
            )

            let data = try JSONEncoder().encode(doc)
            let decoded = try JSONDecoder().decode(DocumentDTO.self, from: data)

            #expect(decoded.content == "Document content")
            #expect(decoded.metadata?["author"] == .string("John Doe"))
            #expect(decoded.metadata?["version"] == .int(2))
            #expect(decoded.metadata?["published"] == .bool(true))
        }
    }

    // MARK: - IngestResponse Tests

    @Suite("IngestResponse Tests")
    struct IngestResponseTests {

        @Test("IngestResponse success encoding")
        func testSuccessResponse() throws {
            let response = IngestResponse(
                success: true,
                documentIds: ["doc-123", "doc-456"],
                chunksCreated: 42,
                jobId: nil,
                message: "Successfully ingested 2 documents"
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(IngestResponse.self, from: data)

            #expect(decoded.success == true)
            #expect(decoded.documentIds.count == 2)
            #expect(decoded.chunksCreated == 42)
            #expect(decoded.message == "Successfully ingested 2 documents")
        }

        @Test("IngestResponse async with jobId")
        func testAsyncResponse() throws {
            let response = IngestResponse(
                success: true,
                documentIds: [],
                chunksCreated: 0,
                jobId: "job-789",
                message: "Ingestion started. Track progress with job ID."
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(IngestResponse.self, from: data)

            #expect(decoded.success == true)
            #expect(decoded.jobId == "job-789")
        }
    }

    // MARK: - QueryResponse Tests

    @Suite("QueryResponse Tests")
    struct QueryResponseTests {

        @Test("QueryResponse encoding")
        func testQueryResponseEncoding() throws {
            let sources = [
                SourceDTO(
                    id: "chunk-1",
                    content: "Swift is a powerful programming language.",
                    score: 0.95,
                    documentId: "doc-1",
                    source: "swift-guide.md",
                    metadata: ["section": .string("Introduction")]
                )
            ]

            let metadata = QueryMetadataDTO(
                retrievalTimeMs: 45.2,
                generationTimeMs: 1250.5,
                totalTimeMs: 1295.7,
                model: "gpt-4",
                chunksRetrieved: 5
            )

            let response = QueryResponse(
                answer: "Swift is a modern programming language...",
                sources: sources,
                metadata: metadata
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)

            #expect(decoded.answer == "Swift is a modern programming language...")
            #expect(decoded.sources.count == 1)
            #expect(decoded.sources.first?.score == 0.95)
            #expect(decoded.metadata.retrievalTimeMs == 45.2)
            #expect(decoded.metadata.model == "gpt-4")
        }

        @Test("SourceDTO encoding")
        func testSourceDTOEncoding() throws {
            let source = SourceDTO(
                id: "chunk-123",
                content: "Test content",
                score: 0.85,
                documentId: "doc-456",
                source: "test.md",
                metadata: nil
            )

            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(SourceDTO.self, from: data)

            #expect(decoded.id == "chunk-123")
            #expect(decoded.content == "Test content")
            #expect(decoded.score == 0.85)
            #expect(decoded.documentId == "doc-456")
            #expect(decoded.source == "test.md")
        }
    }

    // MARK: - JobStatusResponse Tests

    @Suite("JobStatusResponse Tests")
    struct JobStatusResponseTests {

        @Test("JobStatusResponse pending")
        func testPendingJob() throws {
            let response = JobStatusResponse(
                jobId: "job-123",
                status: .pending,
                progress: 0.0,
                result: nil,
                error: nil,
                createdAt: Date(),
                completedAt: nil
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(JobStatusResponse.self, from: data)

            #expect(decoded.jobId == "job-123")
            #expect(decoded.status == .pending)
            #expect(decoded.progress == 0.0)
        }

        @Test("JobStatusResponse running with progress")
        func testRunningJob() throws {
            let response = JobStatusResponse(
                jobId: "job-456",
                status: .running,
                progress: 0.45,
                result: nil,
                error: nil,
                createdAt: Date(),
                completedAt: nil
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(JobStatusResponse.self, from: data)

            #expect(decoded.status == .running)
            #expect(decoded.progress == 0.45)
        }

        @Test("JobStatusResponse completed with result")
        func testCompletedJob() throws {
            let result = JobResultDTO(
                documentIds: ["doc-1", "doc-2"],
                chunksCreated: 42,
                message: "Successfully processed 2 documents"
            )

            let createdAt = Date()
            let completedAt = Date()

            let response = JobStatusResponse(
                jobId: "job-789",
                status: .completed,
                progress: 1.0,
                result: result,
                error: nil,
                createdAt: createdAt,
                completedAt: completedAt
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(JobStatusResponse.self, from: data)

            #expect(decoded.status == .completed)
            #expect(decoded.progress == 1.0)
            #expect(decoded.result?.documentIds?.count == 2)
            #expect(decoded.result?.chunksCreated == 42)
        }

        @Test("JobStatusResponse failed with error")
        func testFailedJob() throws {
            let response = JobStatusResponse(
                jobId: "job-error",
                status: .failed,
                progress: 0.3,
                result: nil,
                error: "Connection timeout during embedding generation",
                createdAt: Date(),
                completedAt: Date()
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(JobStatusResponse.self, from: data)

            #expect(decoded.status == .failed)
            #expect(decoded.error == "Connection timeout during embedding generation")
        }

        @Test("JobStatus enum values")
        func testJobStatusValues() throws {
            let statuses: [JobStatus] = [.pending, .running, .completed, .failed, .cancelled]

            for status in statuses {
                let data = try JSONEncoder().encode(status)
                let decoded = try JSONDecoder().decode(JobStatus.self, from: data)
                #expect(decoded == status)
            }
        }
    }

    // MARK: - MetadataFilterDTO Tests

    @Suite("MetadataFilterDTO Tests")
    struct MetadataFilterDTOTests {

        @Test("Equals filter")
        func testEqualsFilter() throws {
            let filter = MetadataFilterDTO(
                type: "equals",
                field: "category",
                value: .string("documentation")
            )

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "equals")
            #expect(decoded.field == "category")
            #expect(decoded.value == .string("documentation"))
        }

        @Test("GreaterThan filter")
        func testGreaterThanFilter() throws {
            let filter = MetadataFilterDTO(
                type: "greaterThan",
                field: "rating",
                value: .double(4.0)
            )

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "greaterThan")
            #expect(decoded.value == .double(4.0))
        }

        @Test("In filter with array values")
        func testInFilter() throws {
            let filter = MetadataFilterDTO(
                type: "in",
                field: "status",
                values: [.string("published"), .string("draft")]
            )

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "in")
            #expect(decoded.values?.count == 2)
        }

        @Test("And compound filter")
        func testAndFilter() throws {
            let filter = MetadataFilterDTO(
                type: "and",
                filters: [
                    MetadataFilterDTO(type: "equals", field: "status", value: .string("published")),
                    MetadataFilterDTO(type: "greaterThan", field: "rating", value: .double(4.0))
                ]
            )

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "and")
            #expect(decoded.filters?.count == 2)
        }

        @Test("Or compound filter")
        func testOrFilter() throws {
            let filter = MetadataFilterDTO(
                type: "or",
                filters: [
                    MetadataFilterDTO(type: "equals", field: "category", value: .string("guide")),
                    MetadataFilterDTO(type: "equals", field: "category", value: .string("tutorial"))
                ]
            )

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "or")
            #expect(decoded.filters?.count == 2)
        }

        @Test("Not filter")
        func testNotFilter() throws {
            let filter = MetadataFilterDTO(
                type: "not",
                filter: MetadataFilterDTO(type: "equals", field: "archived", value: .bool(true))
            )

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "not")
            #expect(decoded.filter?.value.type == "equals")
        }

        @Test("Exists filter")
        func testExistsFilter() throws {
            let filter = MetadataFilterDTO(type: "exists", field: "author")

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "exists")
            #expect(decoded.field == "author")
        }

        @Test("Contains string filter")
        func testContainsFilter() throws {
            let filter = MetadataFilterDTO(
                type: "contains",
                field: "title",
                value: .string("Swift")
            )

            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(MetadataFilterDTO.self, from: data)

            #expect(decoded.type == "contains")
            #expect(decoded.value == .string("Swift"))
        }
    }

    // MARK: - StreamEventDTO Tests

    @Suite("StreamEventDTO Tests")
    struct StreamEventDTOTests {

        @Test("RetrievalStarted event")
        func testRetrievalStarted() throws {
            let event = StreamEventDTO.retrievalStarted

            let data = try JSONEncoder().encode(event)
            let decoded = try JSONDecoder().decode(StreamEventDTO.self, from: data)

            #expect(decoded == .retrievalStarted)
        }

        @Test("GenerationChunk event")
        func testGenerationChunk() throws {
            let event = StreamEventDTO.generationChunk("Hello, ")

            let data = try JSONEncoder().encode(event)
            let decoded = try JSONDecoder().decode(StreamEventDTO.self, from: data)

            if case .generationChunk(let text) = decoded {
                #expect(text == "Hello, ")
            } else {
                Issue.record("Expected generationChunk event")
            }
        }

        @Test("Error event")
        func testErrorEvent() throws {
            let event = StreamEventDTO.error("Connection failed")

            let data = try JSONEncoder().encode(event)
            let decoded = try JSONDecoder().decode(StreamEventDTO.self, from: data)

            if case .error(let message) = decoded {
                #expect(message == "Connection failed")
            } else {
                Issue.record("Expected error event")
            }
        }
    }

    // MARK: - ErrorResponse Tests

    @Suite("ErrorResponse Tests")
    struct ErrorResponseTests {

        @Test("ErrorResponse encoding")
        func testErrorResponse() throws {
            let error = ErrorResponse(
                error: "ValidationError",
                message: "Query text cannot be empty",
                code: "VALIDATION_ERROR",
                details: ["field": .string("query")]
            )

            let data = try JSONEncoder().encode(error)
            let decoded = try JSONDecoder().decode(ErrorResponse.self, from: data)

            #expect(decoded.error == "ValidationError")
            #expect(decoded.message == "Query text cannot be empty")
            #expect(decoded.code == "VALIDATION_ERROR")
            #expect(decoded.details?["field"] == .string("query"))
        }

        @Test("ErrorResponse without details")
        func testErrorResponseWithoutDetails() throws {
            let error = ErrorResponse(
                error: "NotFound",
                message: "Document not found",
                code: nil,
                details: nil
            )

            let data = try JSONEncoder().encode(error)
            let decoded = try JSONDecoder().decode(ErrorResponse.self, from: data)

            #expect(decoded.error == "NotFound")
            #expect(decoded.code == nil)
            #expect(decoded.details == nil)
        }
    }

    // MARK: - HealthResponse Tests

    @Suite("HealthResponse Tests")
    struct HealthResponseTests {

        @Test("HealthResponse encoding")
        func testHealthResponse() throws {
            let response = HealthResponse(
                status: "healthy",
                version: "1.0.0",
                timestamp: Date()
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(response)
            let decoded = try decoder.decode(HealthResponse.self, from: data)

            #expect(decoded.status == "healthy")
            #expect(decoded.version == "1.0.0")
        }
    }

    // MARK: - ReadinessResponse Tests

    @Suite("ReadinessResponse Tests")
    struct ReadinessResponseTests {

        @Test("ReadinessResponse encoding")
        func testReadinessResponse() throws {
            let response = ReadinessResponse(
                ready: true,
                checks: [
                    "database": true,
                    "vectorStore": true,
                    "embeddingService": true
                ]
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(ReadinessResponse.self, from: data)

            #expect(decoded.ready == true)
            #expect(decoded.checks["database"] == true)
            #expect(decoded.checks.count == 3)
        }

        @Test("ReadinessResponse with failures")
        func testReadinessResponseWithFailures() throws {
            let response = ReadinessResponse(
                ready: false,
                checks: [
                    "database": true,
                    "vectorStore": false,
                    "embeddingService": true
                ]
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(ReadinessResponse.self, from: data)

            #expect(decoded.ready == false)
            #expect(decoded.checks["vectorStore"] == false)
        }
    }

    // MARK: - IndexInfo Tests

    @Suite("IndexInfo Tests")
    struct IndexInfoTests {

        @Test("IndexInfo encoding")
        func testIndexInfo() throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let info = IndexInfo(
                name: "my-knowledge-base",
                documentCount: 150,
                chunkCount: 2340,
                dimensions: 1536,
                createdAt: Date()
            )

            let data = try encoder.encode(info)
            let decoded = try decoder.decode(IndexInfo.self, from: data)

            #expect(decoded.name == "my-knowledge-base")
            #expect(decoded.documentCount == 150)
            #expect(decoded.chunkCount == 2340)
            #expect(decoded.dimensions == 1536)
        }
    }

    // MARK: - CreateIndexRequest Tests

    @Suite("CreateIndexRequest Tests")
    struct CreateIndexRequestTests {

        @Test("CreateIndexRequest encoding")
        func testCreateIndexRequest() throws {
            let request = CreateIndexRequest(
                name: "new-index",
                dimensions: 768,
                indexType: "hnsw"
            )

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(CreateIndexRequest.self, from: data)

            #expect(decoded.name == "new-index")
            #expect(decoded.dimensions == 768)
            #expect(decoded.indexType == "hnsw")
        }

        @Test("CreateIndexRequest with defaults")
        func testCreateIndexRequestDefaults() throws {
            let request = CreateIndexRequest(name: "simple-index")

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(CreateIndexRequest.self, from: data)

            #expect(decoded.name == "simple-index")
            #expect(decoded.dimensions == nil)
            #expect(decoded.indexType == nil)
        }
    }
}
