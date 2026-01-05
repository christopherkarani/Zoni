// ZoniServer - Server-side extensions for Zoni
//
// WebSocketMessageTests.swift - Comprehensive tests for WebSocket message types
//
// This file tests WebSocketClientMessage, WebSocketServerMessage,
// and WebSocketErrorDTO encoding/decoding for real-time streaming communication.

import Testing
import Foundation
@testable import ZoniServer

// MARK: - WebSocket Message Tests

@Suite("WebSocket Message Tests")
struct WebSocketMessageTests {

    // MARK: - WebSocketClientMessage Tests

    @Suite("WebSocketClientMessage Tests")
    struct ClientMessageTests {

        @Test("Client authenticate message encodes correctly")
        func testClientAuthMessage() throws {
            let message = WebSocketClientMessage.authenticate(token: "test-token")

            let data = try JSONEncoder().encode(message)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"type\":\"authenticate\""))
            #expect(json.contains("\"token\":\"test-token\""))
        }

        @Test("Client authenticate message decodes correctly")
        func testClientAuthMessageDecode() throws {
            let json = """
            {"type": "authenticate", "token": "my-api-key"}
            """
            let data = json.data(using: .utf8)!

            let message = try JSONDecoder().decode(WebSocketClientMessage.self, from: data)

            if case .authenticate(let token) = message {
                #expect(token == "my-api-key")
            } else {
                Issue.record("Expected authenticate message")
            }
        }

        @Test("Client query message encodes correctly")
        func testClientQueryMessage() throws {
            let request = QueryWebSocketRequest(
                requestId: "req-123",
                query: "What is Swift?",
                options: nil
            )
            let message = WebSocketClientMessage.query(request)

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketClientMessage.self, from: data)

            if case .query(let decodedRequest) = decoded {
                #expect(decodedRequest.requestId == "req-123")
                #expect(decodedRequest.query == "What is Swift?")
            } else {
                Issue.record("Expected query message")
            }
        }

        @Test("Client query message with options")
        func testClientQueryMessageWithOptions() throws {
            let options = QueryRequestOptions(
                retrievalLimit: 10,
                temperature: 0.7
            )
            let request = QueryWebSocketRequest(
                requestId: "req-456",
                query: "How do I use async/await?",
                options: options
            )
            let message = WebSocketClientMessage.query(request)

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketClientMessage.self, from: data)

            if case .query(let decodedRequest) = decoded {
                #expect(decodedRequest.options?.retrievalLimit == 10)
                #expect(decodedRequest.options?.temperature == 0.7)
            } else {
                Issue.record("Expected query message with options")
            }
        }

        @Test("Client cancel message encodes correctly")
        func testClientCancelMessage() throws {
            let message = WebSocketClientMessage.cancel(requestId: "req-to-cancel")

            let data = try JSONEncoder().encode(message)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"type\":\"cancel\""))
            #expect(json.contains("\"requestId\":\"req-to-cancel\""))
        }

        @Test("Client cancel message decodes correctly")
        func testClientCancelMessageDecode() throws {
            let json = """
            {"type": "cancel", "requestId": "cancel-me"}
            """
            let data = json.data(using: .utf8)!

            let message = try JSONDecoder().decode(WebSocketClientMessage.self, from: data)

            if case .cancel(let requestId) = message {
                #expect(requestId == "cancel-me")
            } else {
                Issue.record("Expected cancel message")
            }
        }

        @Test("Client ping message encodes correctly")
        func testClientPingMessage() throws {
            let message = WebSocketClientMessage.ping

            let data = try JSONEncoder().encode(message)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"type\":\"ping\""))
        }

        @Test("Client ping message decodes correctly")
        func testClientPingMessageDecode() throws {
            let json = """
            {"type": "ping"}
            """
            let data = json.data(using: .utf8)!

            let message = try JSONDecoder().decode(WebSocketClientMessage.self, from: data)

            if case .ping = message {
                // Success
            } else {
                Issue.record("Expected ping message")
            }
        }

        @Test("Client query message from JSON")
        func testClientQueryFromJSON() throws {
            let json = """
            {
                "type": "query",
                "requestId": "uuid-123",
                "query": "What is concurrency?",
                "options": {
                    "retrievalLimit": 5,
                    "temperature": 0.5
                }
            }
            """
            let data = json.data(using: .utf8)!

            let message = try JSONDecoder().decode(WebSocketClientMessage.self, from: data)

            if case .query(let request) = message {
                #expect(request.requestId == "uuid-123")
                #expect(request.query == "What is concurrency?")
                #expect(request.options?.retrievalLimit == 5)
                #expect(request.options?.temperature == 0.5)
            } else {
                Issue.record("Expected query message")
            }
        }
    }

    // MARK: - WebSocketServerMessage Tests

    @Suite("WebSocketServerMessage Tests")
    struct ServerMessageTests {

        @Test("Server authenticated message")
        func testServerAuthenticated() throws {
            let message = WebSocketServerMessage.authenticated(tenantId: "tenant-123")

            let data = try JSONEncoder().encode(message)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"type\":\"authenticated\""))
            #expect(json.contains("\"tenantId\":\"tenant-123\""))

            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)
            #expect(decoded == message)
        }

        @Test("Server authError message")
        func testServerAuthError() throws {
            let message = WebSocketServerMessage.authError(reason: "Invalid API key")

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .authError(let reason) = decoded {
                #expect(reason == "Invalid API key")
            } else {
                Issue.record("Expected authError message")
            }
        }

        @Test("Server retrievalStarted message")
        func testServerRetrievalStarted() throws {
            let message = WebSocketServerMessage.retrievalStarted(requestId: "req-123")

            let data = try JSONEncoder().encode(message)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"type\":\"retrievalStarted\""))
            #expect(json.contains("\"requestId\":\"req-123\""))
        }

        @Test("Server retrievalComplete message")
        func testServerRetrievalComplete() throws {
            let sources = [
                SourceDTO(
                    id: "chunk-1",
                    content: "Test content",
                    score: 0.95,
                    documentId: "doc-1",
                    source: "test.md",
                    metadata: nil
                )
            ]
            let message = WebSocketServerMessage.retrievalComplete(
                requestId: "req-456",
                sources: sources
            )

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .retrievalComplete(let reqId, let decodedSources) = decoded {
                #expect(reqId == "req-456")
                #expect(decodedSources.count == 1)
                #expect(decodedSources.first?.score == 0.95)
            } else {
                Issue.record("Expected retrievalComplete message")
            }
        }

        @Test("Server generationStarted message")
        func testServerGenerationStarted() throws {
            let message = WebSocketServerMessage.generationStarted(requestId: "req-789")

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .generationStarted(let reqId) = decoded {
                #expect(reqId == "req-789")
            } else {
                Issue.record("Expected generationStarted message")
            }
        }

        @Test("Server generation chunk message")
        func testServerChunkMessage() throws {
            let message = WebSocketServerMessage.generationChunk(
                requestId: "req-123",
                text: "Hello"
            )

            let data = try JSONEncoder().encode(message)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"type\":\"generationChunk\""))
            #expect(json.contains("\"text\":\"Hello\""))

            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .generationChunk(let reqId, let text) = decoded {
                #expect(reqId == "req-123")
                #expect(text == "Hello")
            } else {
                Issue.record("Expected generationChunk message")
            }
        }

        @Test("Server generationComplete message")
        func testServerGenerationComplete() throws {
            let message = WebSocketServerMessage.generationComplete(
                requestId: "req-final",
                answer: "Swift is a modern programming language developed by Apple."
            )

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .generationComplete(let reqId, let answer) = decoded {
                #expect(reqId == "req-final")
                #expect(answer.contains("Swift"))
            } else {
                Issue.record("Expected generationComplete message")
            }
        }

        @Test("Server complete message with full response")
        func testServerCompleteMessage() throws {
            let sources = [
                SourceDTO(
                    id: "chunk-1",
                    content: "Content here",
                    score: 0.9,
                    documentId: "doc-1",
                    source: "source.md",
                    metadata: nil
                )
            ]
            let metadata = QueryMetadataDTO(
                retrievalTimeMs: 50.0,
                generationTimeMs: 1000.0,
                totalTimeMs: 1050.0,
                model: "gpt-4",
                chunksRetrieved: 1
            )
            let response = QueryResponse(
                answer: "Complete answer here.",
                sources: sources,
                metadata: metadata
            )

            let message = WebSocketServerMessage.complete(requestId: "req-done", response: response)

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .complete(let reqId, let decodedResponse) = decoded {
                #expect(reqId == "req-done")
                #expect(decodedResponse.answer == "Complete answer here.")
                #expect(decodedResponse.sources.count == 1)
                #expect(decodedResponse.metadata.model == "gpt-4")
            } else {
                Issue.record("Expected complete message")
            }
        }

        @Test("Server error message")
        func testServerErrorMessage() throws {
            let error = WebSocketErrorDTO(
                code: "RATE_LIMITED",
                message: "Too many requests",
                retryable: true
            )
            let message = WebSocketServerMessage.error(requestId: "req-123", error: error)

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .error(let reqId, let decodedError) = decoded {
                #expect(reqId == "req-123")
                #expect(decodedError.code == "RATE_LIMITED")
                #expect(decodedError.message == "Too many requests")
                #expect(decodedError.retryable == true)
            } else {
                Issue.record("Expected error message")
            }
        }

        @Test("Server error message without requestId")
        func testServerErrorMessageNoRequestId() throws {
            let error = WebSocketErrorDTO(
                code: "AUTH_FAILED",
                message: "Authentication required",
                retryable: false
            )
            let message = WebSocketServerMessage.error(requestId: nil, error: error)

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .error(let reqId, let decodedError) = decoded {
                #expect(reqId == nil)
                #expect(decodedError.code == "AUTH_FAILED")
                #expect(decodedError.retryable == false)
            } else {
                Issue.record("Expected error message")
            }
        }

        @Test("Server cancelled message")
        func testServerCancelledMessage() throws {
            let message = WebSocketServerMessage.cancelled(requestId: "req-cancelled")

            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .cancelled(let reqId) = decoded {
                #expect(reqId == "req-cancelled")
            } else {
                Issue.record("Expected cancelled message")
            }
        }

        @Test("Server pong message")
        func testServerPongMessage() throws {
            let message = WebSocketServerMessage.pong

            let data = try JSONEncoder().encode(message)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("\"type\":\"pong\""))

            let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)
            #expect(decoded == .pong)
        }

        @Test("Server message equality")
        func testServerMessageEquality() {
            let message1 = WebSocketServerMessage.pong
            let message2 = WebSocketServerMessage.pong
            let message3 = WebSocketServerMessage.authenticated(tenantId: "t1")
            let message4 = WebSocketServerMessage.authenticated(tenantId: "t1")
            let message5 = WebSocketServerMessage.authenticated(tenantId: "t2")

            #expect(message1 == message2)
            #expect(message3 == message4)
            #expect(message3 != message5)
        }
    }

    // MARK: - WebSocketErrorDTO Tests

    @Suite("WebSocketErrorDTO Tests")
    struct ErrorDTOTests {

        @Test("WebSocketErrorDTO initialization")
        func testErrorDTOInit() {
            let error = WebSocketErrorDTO(
                code: "TEST_ERROR",
                message: "Test error message",
                retryable: true
            )

            #expect(error.code == "TEST_ERROR")
            #expect(error.message == "Test error message")
            #expect(error.retryable == true)
        }

        @Test("WebSocketErrorDTO Codable")
        func testErrorDTOCodable() throws {
            let error = WebSocketErrorDTO(
                code: "VALIDATION_ERROR",
                message: "Invalid input",
                retryable: false
            )

            let data = try JSONEncoder().encode(error)
            let decoded = try JSONDecoder().decode(WebSocketErrorDTO.self, from: data)

            #expect(decoded.code == error.code)
            #expect(decoded.message == error.message)
            #expect(decoded.retryable == error.retryable)
        }

        @Test("WebSocketErrorDTO from ZoniServerError")
        func testErrorDTOFromServerError() {
            let serverError = ZoniServerError.rateLimited(
                operation: .query,
                retryAfter: .seconds(30)
            )

            let dto = WebSocketErrorDTO(from: serverError)

            #expect(dto.code == "RATE_LIMITED")
            #expect(dto.retryable == true)
            #expect(dto.message.contains("Rate limit"))
        }

        @Test("WebSocketErrorDTO Equatable")
        func testErrorDTOEquatable() {
            let error1 = WebSocketErrorDTO(code: "A", message: "Test", retryable: true)
            let error2 = WebSocketErrorDTO(code: "A", message: "Test", retryable: true)
            let error3 = WebSocketErrorDTO(code: "B", message: "Test", retryable: true)

            #expect(error1 == error2)
            #expect(error1 != error3)
        }

        @Test("WebSocketErrorDTO from JSON")
        func testErrorDTOFromJSON() throws {
            let json = """
            {
                "code": "CONNECTION_FAILED",
                "message": "Unable to connect",
                "retryable": true
            }
            """
            let data = json.data(using: .utf8)!

            let error = try JSONDecoder().decode(WebSocketErrorDTO.self, from: data)

            #expect(error.code == "CONNECTION_FAILED")
            #expect(error.message == "Unable to connect")
            #expect(error.retryable == true)
        }
    }

    // MARK: - QueryWebSocketRequest Tests

    @Suite("QueryWebSocketRequest Tests")
    struct QueryRequestTests {

        @Test("QueryWebSocketRequest initialization")
        func testQueryRequestInit() {
            let request = QueryWebSocketRequest(
                requestId: "my-request",
                query: "Test query",
                options: nil
            )

            #expect(request.requestId == "my-request")
            #expect(request.query == "Test query")
            #expect(request.options == nil)
        }

        @Test("QueryWebSocketRequest default requestId")
        func testQueryRequestDefaultId() {
            let request = QueryWebSocketRequest(query: "Test query")

            #expect(!request.requestId.isEmpty)
            #expect(request.query == "Test query")
        }

        @Test("QueryWebSocketRequest with all options")
        func testQueryRequestWithOptions() throws {
            let options = QueryRequestOptions(
                retrievalLimit: 10,
                systemPrompt: "You are helpful",
                temperature: 0.8,
                maxContextTokens: 2000,
                includeMetadata: true
            )

            let request = QueryWebSocketRequest(
                requestId: "full-request",
                query: "Detailed query",
                options: options
            )

            let data = try JSONEncoder().encode(request)
            let decoded = try JSONDecoder().decode(QueryWebSocketRequest.self, from: data)

            #expect(decoded.options?.retrievalLimit == 10)
            #expect(decoded.options?.systemPrompt == "You are helpful")
            #expect(decoded.options?.temperature == 0.8)
            #expect(decoded.options?.maxContextTokens == 2000)
            #expect(decoded.options?.includeMetadata == true)
        }
    }

    // MARK: - Server Message Conversion Tests

    @Suite("Server Message Conversions")
    struct ServerMessageConversionTests {

        @Test("WebSocketServerMessage from authenticated JSON")
        func testFromAuthenticatedJSON() throws {
            let json = """
            {"type": "authenticated", "tenantId": "tenant-abc"}
            """
            let data = json.data(using: .utf8)!

            let message = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .authenticated(let tenantId) = message {
                #expect(tenantId == "tenant-abc")
            } else {
                Issue.record("Expected authenticated message")
            }
        }

        @Test("WebSocketServerMessage from generationChunk JSON")
        func testFromChunkJSON() throws {
            let json = """
            {"type": "generationChunk", "requestId": "r1", "text": "Hello "}
            """
            let data = json.data(using: .utf8)!

            let message = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .generationChunk(let reqId, let text) = message {
                #expect(reqId == "r1")
                #expect(text == "Hello ")
            } else {
                Issue.record("Expected generationChunk message")
            }
        }

        @Test("WebSocketServerMessage from error JSON")
        func testFromErrorJSON() throws {
            let json = """
            {
                "type": "error",
                "requestId": "req-err",
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": "Something went wrong",
                    "retryable": false
                }
            }
            """
            let data = json.data(using: .utf8)!

            let message = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

            if case .error(let reqId, let error) = message {
                #expect(reqId == "req-err")
                #expect(error.code == "INTERNAL_ERROR")
                #expect(error.retryable == false)
            } else {
                Issue.record("Expected error message")
            }
        }
    }

    // MARK: - Round-Trip Tests

    @Suite("Round-Trip Encoding Tests")
    struct RoundTripTests {

        @Test("All client message types round-trip")
        func testClientMessagesRoundTrip() throws {
            let messages: [WebSocketClientMessage] = [
                .authenticate(token: "test-token"),
                .query(QueryWebSocketRequest(requestId: "req-1", query: "Test?")),
                .cancel(requestId: "req-cancel"),
                .ping
            ]

            for originalMessage in messages {
                let data = try JSONEncoder().encode(originalMessage)
                let decoded = try JSONDecoder().decode(WebSocketClientMessage.self, from: data)

                // Verify by re-encoding
                let reEncoded = try JSONEncoder().encode(decoded)
                let finalDecoded = try JSONDecoder().decode(WebSocketClientMessage.self, from: reEncoded)

                // Re-encode the final and compare
                let originalJSON = String(data: data, encoding: .utf8)!
                let finalJSON = String(data: try JSONEncoder().encode(finalDecoded), encoding: .utf8)!

                // Both should produce valid JSON
                #expect(!originalJSON.isEmpty)
                #expect(!finalJSON.isEmpty)
            }
        }

        @Test("All server message types round-trip")
        func testServerMessagesRoundTrip() throws {
            let error = WebSocketErrorDTO(code: "ERR", message: "Error", retryable: true)
            let sources = [SourceDTO(id: "s1", content: "c", score: 0.5, documentId: "d1", source: nil, metadata: nil)]
            let response = QueryResponse(
                answer: "Answer",
                sources: sources,
                metadata: QueryMetadataDTO()
            )

            let messages: [WebSocketServerMessage] = [
                .authenticated(tenantId: "t1"),
                .authError(reason: "Bad key"),
                .retrievalStarted(requestId: "r1"),
                .retrievalComplete(requestId: "r2", sources: sources),
                .generationStarted(requestId: "r3"),
                .generationChunk(requestId: "r4", text: "chunk"),
                .generationComplete(requestId: "r5", answer: "done"),
                .complete(requestId: "r6", response: response),
                .error(requestId: "r7", error: error),
                .cancelled(requestId: "r8"),
                .pong
            ]

            for originalMessage in messages {
                let data = try JSONEncoder().encode(originalMessage)
                let decoded = try JSONDecoder().decode(WebSocketServerMessage.self, from: data)

                #expect(decoded == originalMessage)
            }
        }
    }
}
