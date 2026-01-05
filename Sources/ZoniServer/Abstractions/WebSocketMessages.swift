// ZoniServer - Server-side extensions for Zoni
//
// WebSocketMessages.swift - WebSocket message types for streaming RAG protocol.
//
// This file defines the message types exchanged over WebSocket connections
// for real-time streaming RAG queries, including client requests, server
// responses, and error handling.

import Foundation
import Zoni

// MARK: - Client Messages

/// Messages sent from client to server over WebSocket.
///
/// `WebSocketClientMessage` represents all message types that clients can send
/// to the server. Messages use a discriminated union pattern with a "type"
/// field for routing.
///
/// ## Example JSON
/// ```json
/// {"type": "authenticate", "token": "your-api-key"}
/// {"type": "query", "requestId": "uuid", "query": "What is Swift?"}
/// {"type": "cancel", "requestId": "uuid"}
/// {"type": "ping"}
/// ```
public enum WebSocketClientMessage: Codable, Sendable {
    /// Authenticate the WebSocket connection.
    ///
    /// This must be the first message sent after establishing a connection.
    /// - Parameter token: The API key or JWT token for authentication.
    case authenticate(token: String)

    /// Submit a RAG query for processing.
    ///
    /// - Parameter request: The query request with options.
    case query(QueryWebSocketRequest)

    /// Cancel an in-progress query.
    ///
    /// - Parameter requestId: The ID of the request to cancel.
    case cancel(requestId: String)

    /// Ping to keep the connection alive.
    ///
    /// The server responds with a `pong` message.
    case ping

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case type
        case token
        case requestId
        case query
        case options
    }

    private enum MessageType: String, Codable {
        case authenticate
        case query
        case cancel
        case ping
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .authenticate:
            let token = try container.decode(String.self, forKey: .token)
            self = .authenticate(token: token)

        case .query:
            let requestId = try container.decode(String.self, forKey: .requestId)
            let query = try container.decode(String.self, forKey: .query)
            let options = try container.decodeIfPresent(QueryRequestOptions.self, forKey: .options)
            self = .query(QueryWebSocketRequest(requestId: requestId, query: query, options: options))

        case .cancel:
            let requestId = try container.decode(String.self, forKey: .requestId)
            self = .cancel(requestId: requestId)

        case .ping:
            self = .ping
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .authenticate(let token):
            try container.encode(MessageType.authenticate, forKey: .type)
            try container.encode(token, forKey: .token)

        case .query(let request):
            try container.encode(MessageType.query, forKey: .type)
            try container.encode(request.requestId, forKey: .requestId)
            try container.encode(request.query, forKey: .query)
            try container.encodeIfPresent(request.options, forKey: .options)

        case .cancel(let requestId):
            try container.encode(MessageType.cancel, forKey: .type)
            try container.encode(requestId, forKey: .requestId)

        case .ping:
            try container.encode(MessageType.ping, forKey: .type)
        }
    }
}

// MARK: - QueryWebSocketRequest

/// A query request sent over WebSocket.
///
/// Contains the query text, a unique request ID for tracking, and optional
/// configuration settings.
///
/// ## Example JSON
/// ```json
/// {
///     "requestId": "550e8400-e29b-41d4-a716-446655440000",
///     "query": "How do I use async/await in Swift?",
///     "options": {
///         "retrievalLimit": 5,
///         "temperature": 0.7
///     }
/// }
/// ```
public struct QueryWebSocketRequest: Codable, Sendable {
    /// A unique identifier for this request.
    ///
    /// Used to correlate server responses with the original request,
    /// especially when multiple queries are in flight.
    public let requestId: String

    /// The query text to process.
    public let query: String

    /// Optional configuration for the query.
    public let options: QueryRequestOptions?

    /// Creates a new query WebSocket request.
    ///
    /// - Parameters:
    ///   - requestId: A unique identifier for tracking. Defaults to a new UUID.
    ///   - query: The query text to process.
    ///   - options: Optional query configuration.
    public init(
        requestId: String = UUID().uuidString,
        query: String,
        options: QueryRequestOptions? = nil
    ) {
        self.requestId = requestId
        self.query = query
        self.options = options
    }
}

// MARK: - Server Messages

/// Messages sent from server to client over WebSocket.
///
/// `WebSocketServerMessage` represents all message types that the server sends
/// to clients, including authentication responses, streaming events, and errors.
///
/// ## Example JSON
/// ```json
/// {"type": "authenticated", "tenantId": "tenant_123"}
/// {"type": "generationChunk", "requestId": "uuid", "text": "Hello"}
/// {"type": "error", "requestId": "uuid", "error": {...}}
/// {"type": "pong"}
/// ```
public enum WebSocketServerMessage: Codable, Sendable, Equatable {
    /// Sent after successful authentication.
    ///
    /// - Parameter tenantId: The authenticated tenant's identifier.
    case authenticated(tenantId: String)

    /// Sent when authentication fails.
    ///
    /// - Parameter reason: A description of why authentication failed.
    case authError(reason: String)

    /// Sent when retrieval begins for a query.
    ///
    /// - Parameter requestId: The ID of the request being processed.
    case retrievalStarted(requestId: String)

    /// Sent when retrieval completes with the sources found.
    ///
    /// - Parameters:
    ///   - requestId: The ID of the request.
    ///   - sources: The retrieved source documents.
    case retrievalComplete(requestId: String, sources: [SourceDTO])

    /// Sent when LLM generation begins.
    ///
    /// - Parameter requestId: The ID of the request.
    case generationStarted(requestId: String)

    /// Sent for each chunk of generated text during streaming.
    ///
    /// - Parameters:
    ///   - requestId: The ID of the request.
    ///   - text: The text chunk generated.
    case generationChunk(requestId: String, text: String)

    /// Sent when generation completes with the full answer.
    ///
    /// - Parameters:
    ///   - requestId: The ID of the request.
    ///   - answer: The complete generated answer.
    case generationComplete(requestId: String, answer: String)

    /// Sent when the entire RAG operation completes.
    ///
    /// - Parameters:
    ///   - requestId: The ID of the request.
    ///   - response: The complete query response.
    case complete(requestId: String, response: QueryResponse)

    /// Sent when an error occurs.
    ///
    /// - Parameters:
    ///   - requestId: The ID of the request, if applicable.
    ///   - error: The error details.
    case error(requestId: String?, error: WebSocketErrorDTO)

    /// Sent when a request is successfully cancelled.
    ///
    /// - Parameter requestId: The ID of the cancelled request.
    case cancelled(requestId: String)

    /// Sent in response to a ping message.
    case pong

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case type
        case tenantId
        case reason
        case requestId
        case sources
        case text
        case answer
        case response
        case error
    }

    private enum MessageType: String, Codable {
        case authenticated
        case authError
        case retrievalStarted
        case retrievalComplete
        case generationStarted
        case generationChunk
        case generationComplete
        case complete
        case error
        case cancelled
        case pong
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .authenticated:
            let tenantId = try container.decode(String.self, forKey: .tenantId)
            self = .authenticated(tenantId: tenantId)

        case .authError:
            let reason = try container.decode(String.self, forKey: .reason)
            self = .authError(reason: reason)

        case .retrievalStarted:
            let requestId = try container.decode(String.self, forKey: .requestId)
            self = .retrievalStarted(requestId: requestId)

        case .retrievalComplete:
            let requestId = try container.decode(String.self, forKey: .requestId)
            let sources = try container.decode([SourceDTO].self, forKey: .sources)
            self = .retrievalComplete(requestId: requestId, sources: sources)

        case .generationStarted:
            let requestId = try container.decode(String.self, forKey: .requestId)
            self = .generationStarted(requestId: requestId)

        case .generationChunk:
            let requestId = try container.decode(String.self, forKey: .requestId)
            let text = try container.decode(String.self, forKey: .text)
            self = .generationChunk(requestId: requestId, text: text)

        case .generationComplete:
            let requestId = try container.decode(String.self, forKey: .requestId)
            let answer = try container.decode(String.self, forKey: .answer)
            self = .generationComplete(requestId: requestId, answer: answer)

        case .complete:
            let requestId = try container.decode(String.self, forKey: .requestId)
            let response = try container.decode(QueryResponse.self, forKey: .response)
            self = .complete(requestId: requestId, response: response)

        case .error:
            let requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
            let error = try container.decode(WebSocketErrorDTO.self, forKey: .error)
            self = .error(requestId: requestId, error: error)

        case .cancelled:
            let requestId = try container.decode(String.self, forKey: .requestId)
            self = .cancelled(requestId: requestId)

        case .pong:
            self = .pong
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .authenticated(let tenantId):
            try container.encode(MessageType.authenticated, forKey: .type)
            try container.encode(tenantId, forKey: .tenantId)

        case .authError(let reason):
            try container.encode(MessageType.authError, forKey: .type)
            try container.encode(reason, forKey: .reason)

        case .retrievalStarted(let requestId):
            try container.encode(MessageType.retrievalStarted, forKey: .type)
            try container.encode(requestId, forKey: .requestId)

        case .retrievalComplete(let requestId, let sources):
            try container.encode(MessageType.retrievalComplete, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(sources, forKey: .sources)

        case .generationStarted(let requestId):
            try container.encode(MessageType.generationStarted, forKey: .type)
            try container.encode(requestId, forKey: .requestId)

        case .generationChunk(let requestId, let text):
            try container.encode(MessageType.generationChunk, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(text, forKey: .text)

        case .generationComplete(let requestId, let answer):
            try container.encode(MessageType.generationComplete, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(answer, forKey: .answer)

        case .complete(let requestId, let response):
            try container.encode(MessageType.complete, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(response, forKey: .response)

        case .error(let requestId, let error):
            try container.encode(MessageType.error, forKey: .type)
            try container.encodeIfPresent(requestId, forKey: .requestId)
            try container.encode(error, forKey: .error)

        case .cancelled(let requestId):
            try container.encode(MessageType.cancelled, forKey: .type)
            try container.encode(requestId, forKey: .requestId)

        case .pong:
            try container.encode(MessageType.pong, forKey: .type)
        }
    }
}

// MARK: - WebSocketErrorDTO

/// Error information sent over WebSocket.
///
/// Provides a standardized error format for WebSocket communication,
/// including a machine-readable code, human-readable message, and
/// retry information.
///
/// ## Example JSON
/// ```json
/// {
///     "code": "RATE_LIMITED",
///     "message": "Rate limit exceeded for query",
///     "retryable": true
/// }
/// ```
public struct WebSocketErrorDTO: Codable, Sendable, Equatable {
    /// A machine-readable error code.
    ///
    /// Clients can use this code for programmatic error handling.
    public let code: String

    /// A human-readable error message.
    public let message: String

    /// Whether this error is potentially recoverable by retrying.
    public let retryable: Bool

    /// Creates a new WebSocket error DTO.
    ///
    /// - Parameters:
    ///   - code: The machine-readable error code.
    ///   - message: The human-readable error message.
    ///   - retryable: Whether the operation can be retried.
    public init(code: String, message: String, retryable: Bool) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }

    /// Creates a WebSocket error DTO from a `ZoniServerError`.
    ///
    /// - Parameter error: The server error to convert.
    public init(from error: ZoniServerError) {
        self.code = error.errorCode
        self.message = error.errorDescription ?? "An error occurred"
        self.retryable = error.isRetryable
    }

    /// Creates a WebSocket error DTO from a `ZoniError`.
    ///
    /// - Parameter error: The Zoni error to convert.
    public init(from error: ZoniError) {
        self.code = mapZoniErrorToCode(error)
        self.message = error.errorDescription ?? "An error occurred"
        self.retryable = isZoniErrorRetryable(error)
    }
}

// MARK: - WebSocketServerMessage Conversions

extension WebSocketServerMessage {
    /// Creates a server message from a `RAGStreamEvent`.
    ///
    /// Maps RAG pipeline streaming events to WebSocket message format,
    /// adding request tracking via the request ID.
    ///
    /// - Parameters:
    ///   - event: The RAG stream event to convert.
    ///   - requestId: The request ID to associate with the message.
    ///   - includeMetadata: Whether to include metadata in sources.
    /// - Returns: The corresponding WebSocket server message.
    public static func from(
        _ event: RAGStreamEvent,
        requestId: String,
        includeMetadata: Bool = true
    ) -> WebSocketServerMessage {
        switch event {
        case .retrievalStarted:
            return .retrievalStarted(requestId: requestId)

        case .retrievalComplete(let results):
            let sources = results.map { SourceDTO(from: $0, includeMetadata: includeMetadata) }
            return .retrievalComplete(requestId: requestId, sources: sources)

        case .generationStarted:
            return .generationStarted(requestId: requestId)

        case .generationChunk(let text):
            return .generationChunk(requestId: requestId, text: text)

        case .generationComplete(let answer):
            return .generationComplete(requestId: requestId, answer: answer)

        case .complete(let response):
            return .complete(
                requestId: requestId,
                response: QueryResponse(from: response, includeMetadata: includeMetadata)
            )

        case .error(let error):
            let errorDTO = WebSocketErrorDTO(from: error)
            return .error(requestId: requestId, error: errorDTO)
        }
    }
}

// MARK: - Helper Functions

/// Maps a `ZoniError` to a machine-readable error code.
private func mapZoniErrorToCode(_ error: ZoniError) -> String {
    switch error {
    case .unsupportedFileType:
        return "UNSUPPORTED_FILE_TYPE"
    case .loadingFailed:
        return "LOADING_FAILED"
    case .invalidData:
        return "INVALID_DATA"
    case .chunkingFailed:
        return "CHUNKING_FAILED"
    case .emptyDocument:
        return "EMPTY_DOCUMENT"
    case .embeddingFailed:
        return "EMBEDDING_FAILED"
    case .embeddingDimensionMismatch:
        return "EMBEDDING_DIMENSION_MISMATCH"
    case .embeddingProviderUnavailable:
        return "EMBEDDING_PROVIDER_UNAVAILABLE"
    case .rateLimited:
        return "RATE_LIMITED"
    case .vectorStoreUnavailable:
        return "VECTOR_STORE_UNAVAILABLE"
    case .vectorStoreConnectionFailed:
        return "VECTOR_STORE_CONNECTION_FAILED"
    case .indexNotFound:
        return "INDEX_NOT_FOUND"
    case .insertionFailed:
        return "INSERTION_FAILED"
    case .searchFailed:
        return "SEARCH_FAILED"
    case .retrievalFailed:
        return "RETRIEVAL_FAILED"
    case .noResultsFound:
        return "NO_RESULTS_FOUND"
    case .generationFailed:
        return "GENERATION_FAILED"
    case .llmProviderUnavailable:
        return "LLM_PROVIDER_UNAVAILABLE"
    case .contextTooLong:
        return "CONTEXT_TOO_LONG"
    case .invalidConfiguration:
        return "INVALID_CONFIGURATION"
    case .missingRequiredComponent:
        return "MISSING_REQUIRED_COMPONENT"
    }
}

/// Determines if a `ZoniError` is potentially recoverable by retrying.
private func isZoniErrorRetryable(_ error: ZoniError) -> Bool {
    switch error {
    case .rateLimited, .vectorStoreConnectionFailed, .embeddingProviderUnavailable,
         .llmProviderUnavailable, .vectorStoreUnavailable:
        return true
    default:
        return false
    }
}
