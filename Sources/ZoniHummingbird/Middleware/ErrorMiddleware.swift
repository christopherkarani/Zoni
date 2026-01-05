// ZoniHummingbird - Hummingbird framework integration for Zoni RAG
//
// ErrorMiddleware.swift - Error handling middleware for consistent error responses.
//
// This middleware catches errors from downstream handlers and converts them
// to consistent JSON error responses following the ErrorResponse DTO format.

import Foundation
import Hummingbird
import HummingbirdAuth
import NIOCore
import ZoniServer
import Zoni

// MARK: - ErrorMiddleware

/// Middleware that converts errors to consistent JSON error responses.
///
/// `ErrorMiddleware` intercepts errors thrown by downstream handlers and
/// converts them to structured `ErrorResponse` objects. This ensures clients
/// receive consistent error formats regardless of where the error originated.
///
/// ## Error Mapping
///
/// - `ZoniServerError`: Mapped to appropriate HTTP status codes
/// - `ZoniError`: Mapped based on error type (validation, not found, etc.)
/// - `HTTPError`: Passed through with original status
/// - Other errors: Returned as 500 Internal Server Error
///
/// ## Response Format
///
/// All errors are returned as JSON:
/// ```json
/// {
///     "error": "ValidationError",
///     "message": "Query text cannot be empty",
///     "code": "VALIDATION_ERROR"
/// }
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let router = Router()
/// router.middlewares.add(ErrorMiddleware())
/// // Add your routes...
/// ```
public struct ErrorMiddleware<Context: RequestContext>: RouterMiddleware {

    /// Creates a new error middleware instance.
    public init() {}

    /// Handles the request, catching and converting errors to JSON responses.
    ///
    /// - Parameters:
    ///   - input: The incoming request.
    ///   - context: The request context.
    ///   - next: The next handler in the chain.
    /// - Returns: The response from the next handler, or an error response.
    public func handle(
        _ input: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(input, context)
        } catch let error as ZoniServerError {
            return errorResponse(from: error)
        } catch let error as ZoniError {
            return errorResponse(from: error)
        } catch let error as HTTPError {
            return errorResponse(
                status: error.status,
                error: "HTTPError",
                message: error.body ?? "An HTTP error occurred",
                code: "HTTP_\(error.status.code)"
            )
        } catch {
            // Unknown error - return generic 500
            return errorResponse(
                status: .internalServerError,
                error: "InternalError",
                message: "An unexpected error occurred",
                code: "INTERNAL_ERROR"
            )
        }
    }

    // MARK: - Private Helpers

    /// Creates an error response from a ZoniServerError.
    private func errorResponse(from error: ZoniServerError) -> Response {
        let status = HTTPResponse.Status(code: error.httpStatusCode)
        let errorType = String(describing: type(of: error))
        return errorResponse(
            status: status,
            error: errorType,
            message: error.errorDescription ?? "An error occurred",
            code: error.errorCode
        )
    }

    /// Creates an error response from a ZoniError.
    private func errorResponse(from error: ZoniError) -> Response {
        let (status, errorType, message, code) = mapZoniError(error)
        return errorResponse(status: status, error: errorType, message: message, code: code)
    }

    /// Creates a JSON error response.
    private func errorResponse(
        status: HTTPResponse.Status,
        error: String,
        message: String,
        code: String
    ) -> Response {
        let errorResponse = ErrorResponse(
            error: error,
            message: message,
            code: code,
            details: nil
        )

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(errorResponse)
            var buffer = ByteBuffer()
            buffer.writeBytes(data)
            return Response(
                status: status,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: buffer)
            )
        } catch {
            // Fallback if encoding fails
            var buffer = ByteBuffer()
            buffer.writeString("{\"error\":\"EncodingError\",\"message\":\"Failed to encode error response\"}")
            return Response(
                status: .internalServerError,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: buffer)
            )
        }
    }

    /// Maps a ZoniError to HTTP status and error details.
    private func mapZoniError(_ error: ZoniError) -> (HTTPResponse.Status, String, String, String) {
        switch error {
        // Loading errors
        case .unsupportedFileType(let ext):
            return (.badRequest, "UnsupportedFileType", "Unsupported file type: '\(ext)'", "UNSUPPORTED_FILE_TYPE")

        case .loadingFailed(let url, let reason):
            return (.internalServerError, "LoadingFailed", "Failed to load '\(url.lastPathComponent)': \(reason)", "LOADING_FAILED")

        case .invalidData(let reason):
            return (.badRequest, "InvalidData", reason, "INVALID_DATA")

        // Chunking errors
        case .chunkingFailed(let reason):
            return (.internalServerError, "ChunkingFailed", reason, "CHUNKING_FAILED")

        case .emptyDocument:
            return (.badRequest, "EmptyDocument", "Cannot process an empty document", "EMPTY_DOCUMENT")

        // Embedding errors
        case .embeddingFailed(let reason):
            return (.internalServerError, "EmbeddingFailed", reason, "EMBEDDING_FAILED")

        case .embeddingDimensionMismatch(let expected, let got):
            return (.internalServerError, "EmbeddingDimensionMismatch", "Expected \(expected), got \(got)", "EMBEDDING_DIMENSION_MISMATCH")

        case .embeddingProviderUnavailable(let name):
            return (.serviceUnavailable, "EmbeddingProviderUnavailable", "Provider '\(name)' unavailable", "EMBEDDING_PROVIDER_UNAVAILABLE")

        case .rateLimited(let retryAfter):
            let message = retryAfter.map { "Retry after \($0.components.seconds) seconds" } ?? "Rate limited"
            return (.tooManyRequests, "RateLimited", message, "RATE_LIMITED")

        // Vector store errors
        case .vectorStoreUnavailable(let name):
            return (.serviceUnavailable, "VectorStoreUnavailable", "Vector store '\(name)' unavailable", "VECTOR_STORE_UNAVAILABLE")

        case .vectorStoreConnectionFailed(let reason):
            return (.serviceUnavailable, "VectorStoreConnectionFailed", reason, "VECTOR_STORE_CONNECTION_FAILED")

        case .indexNotFound(let name):
            return (.notFound, "IndexNotFound", "Index '\(name)' not found", "INDEX_NOT_FOUND")

        case .insertionFailed(let reason):
            return (.internalServerError, "InsertionFailed", reason, "INSERTION_FAILED")

        case .searchFailed(let reason):
            return (.internalServerError, "SearchFailed", reason, "SEARCH_FAILED")

        // Retrieval errors
        case .retrievalFailed(let reason):
            return (.internalServerError, "RetrievalFailed", reason, "RETRIEVAL_FAILED")

        case .noResultsFound:
            return (.notFound, "NoResultsFound", "No results found for the query", "NO_RESULTS_FOUND")

        // Generation errors
        case .generationFailed(let reason):
            return (.internalServerError, "GenerationFailed", reason, "GENERATION_FAILED")

        case .llmProviderUnavailable(let name):
            return (.serviceUnavailable, "LLMProviderUnavailable", "LLM provider '\(name)' unavailable", "LLM_PROVIDER_UNAVAILABLE")

        case .contextTooLong(let tokens, let limit):
            return (.badRequest, "ContextTooLong", "Context (\(tokens) tokens) exceeds limit of \(limit)", "CONTEXT_TOO_LONG")

        // Configuration errors
        case .invalidConfiguration(let reason):
            return (.internalServerError, "InvalidConfiguration", reason, "INVALID_CONFIGURATION")

        case .missingRequiredComponent(let component):
            return (.internalServerError, "MissingRequiredComponent", "Missing: \(component)", "MISSING_REQUIRED_COMPONENT")
        }
    }
}
