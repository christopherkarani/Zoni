// ZoniServer - Server-side extensions for Zoni
//
// ServerErrors.swift - Comprehensive error types for server operations.
//
// This file defines all server-specific errors covering authentication,
// rate limiting, validation, job processing, resource management,
// WebSocket operations, and internal server errors.

import Foundation

// MARK: - ZoniServerError

/// Errors specific to server operations in Zoni.
///
/// `ZoniServerError` provides detailed, categorized errors for server-side operations:
/// - Authentication and authorization
/// - Rate limiting and quota management
/// - Request validation
/// - Job processing
/// - Resource management
/// - WebSocket connections
/// - Internal server errors
///
/// All cases include contextual information to aid debugging and provide
/// actionable recovery suggestions where possible.
///
/// ## Example
/// ```swift
/// do {
///     try await authenticate(apiKey: key)
/// } catch let error as ZoniServerError {
///     print(error.localizedDescription)
///     // Set appropriate HTTP status
///     response.status = HTTPStatus(statusCode: error.httpStatusCode)
/// }
/// ```
public enum ZoniServerError: Error, Sendable, LocalizedError, Equatable {

    // MARK: - Authentication Errors

    /// The request is unauthorized due to missing or invalid credentials.
    ///
    /// - Parameter reason: A description of why authorization failed.
    case unauthorized(reason: String)

    /// The provided API key is invalid or has been revoked.
    case invalidApiKey

    /// The provided JWT token is invalid.
    ///
    /// - Parameter reason: A description of the JWT validation failure.
    case invalidJWT(reason: String)

    /// The authentication token has expired.
    case tokenExpired

    /// The specified tenant was not found.
    ///
    /// - Parameter tenantId: The tenant identifier that was not found.
    case tenantNotFound(tenantId: String)

    // MARK: - Rate Limiting Errors

    /// The rate limit has been exceeded for the specified operation.
    ///
    /// - Parameters:
    ///   - operation: The operation that was rate limited.
    ///   - retryAfter: The suggested duration to wait before retrying, if available.
    case rateLimited(operation: RateLimitOperation, retryAfter: Duration?)

    /// The resource quota has been exceeded.
    ///
    /// - Parameters:
    ///   - resource: The name of the resource that exceeded quota.
    ///   - limit: The maximum allowed value.
    ///   - current: The current usage value.
    case quotaExceeded(resource: String, limit: Int, current: Int)

    // MARK: - Validation Errors

    /// The request is invalid.
    ///
    /// - Parameter reason: A description of why the request is invalid.
    case invalidRequest(reason: String)

    /// A required field is missing from the request.
    ///
    /// - Parameter field: The name of the missing required field.
    case missingRequiredField(field: String)

    /// The document exceeds the maximum allowed size.
    ///
    /// - Parameters:
    ///   - size: The actual document size in bytes.
    ///   - maxSize: The maximum allowed size in bytes.
    case documentTooLarge(size: Int, maxSize: Int)

    /// The query exceeds the maximum allowed length.
    ///
    /// - Parameters:
    ///   - length: The actual query length in characters.
    ///   - maxLength: The maximum allowed length in characters.
    case queryTooLong(length: Int, maxLength: Int)

    // MARK: - Job Errors

    /// The specified job was not found.
    ///
    /// - Parameter jobId: The job identifier that was not found.
    case jobNotFound(jobId: String)

    /// The job is already running and cannot be started again.
    ///
    /// - Parameter jobId: The job identifier that is already running.
    case jobAlreadyRunning(jobId: String)

    /// The job was cancelled before completion.
    ///
    /// - Parameter jobId: The job identifier that was cancelled.
    case jobCancelled(jobId: String)

    /// The job failed during execution.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier that failed.
    ///   - reason: A description of why the job failed.
    case jobFailed(jobId: String, reason: String)

    // MARK: - Resource Errors

    /// The specified index was not found.
    ///
    /// - Parameter name: The name of the index that was not found.
    case indexNotFound(name: String)

    /// An index with the specified name already exists.
    ///
    /// - Parameter name: The name of the existing index.
    case indexAlreadyExists(name: String)

    /// The specified document was not found.
    ///
    /// - Parameter documentId: The document identifier that was not found.
    case documentNotFound(documentId: String)

    // MARK: - WebSocket Errors

    /// Failed to establish a WebSocket connection.
    ///
    /// - Parameter reason: A description of the connection failure.
    case webSocketConnectionFailed(reason: String)

    /// WebSocket authentication is required before proceeding.
    case webSocketAuthenticationRequired

    /// The maximum number of concurrent WebSocket connections has been exceeded.
    ///
    /// - Parameter limit: The maximum allowed concurrent connections.
    case maxConnectionsExceeded(limit: Int)

    // MARK: - Server Errors

    /// An internal server error occurred.
    ///
    /// - Parameter reason: A description of the internal error.
    case internalError(reason: String)

    /// A required service is unavailable.
    ///
    /// - Parameter service: The name of the unavailable service.
    case serviceUnavailable(service: String)

    // MARK: - LocalizedError Implementation

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        // Authentication errors
        case .unauthorized(let reason):
            return "Unauthorized: \(reason)"

        case .invalidApiKey:
            return "The provided API key is invalid or has been revoked"

        case .invalidJWT(let reason):
            return "Invalid JWT token: \(reason)"

        case .tokenExpired:
            return "The authentication token has expired"

        case .tenantNotFound(let tenantId):
            return "Tenant '\(tenantId)' not found"

        // Rate limiting errors
        case .rateLimited(let operation, let retryAfter):
            if let duration = retryAfter {
                return "Rate limit exceeded for \(operation.rawValue). Retry after \(formatDuration(duration))"
            }
            return "Rate limit exceeded for \(operation.rawValue)"

        case .quotaExceeded(let resource, let limit, let current):
            return "Quota exceeded for \(resource): \(current) exceeds limit of \(limit)"

        // Validation errors
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"

        case .missingRequiredField(let field):
            return "Missing required field: '\(field)'"

        case .documentTooLarge(let size, let maxSize):
            return "Document size \(formatBytes(size)) exceeds maximum of \(formatBytes(maxSize))"

        case .queryTooLong(let length, let maxLength):
            return "Query length \(length) exceeds maximum of \(maxLength) characters"

        // Job errors
        case .jobNotFound(let jobId):
            return "Job '\(jobId)' not found"

        case .jobAlreadyRunning(let jobId):
            return "Job '\(jobId)' is already running"

        case .jobCancelled(let jobId):
            return "Job '\(jobId)' was cancelled"

        case .jobFailed(let jobId, let reason):
            return "Job '\(jobId)' failed: \(reason)"

        // Resource errors
        case .indexNotFound(let name):
            return "Index '\(name)' not found"

        case .indexAlreadyExists(let name):
            return "Index '\(name)' already exists"

        case .documentNotFound(let documentId):
            return "Document '\(documentId)' not found"

        // WebSocket errors
        case .webSocketConnectionFailed(let reason):
            return "WebSocket connection failed: \(reason)"

        case .webSocketAuthenticationRequired:
            return "WebSocket authentication required"

        case .maxConnectionsExceeded(let limit):
            return "Maximum WebSocket connections (\(limit)) exceeded"

        // Server errors
        case .internalError(let reason):
            return "Internal server error: \(reason)"

        case .serviceUnavailable(let service):
            return "Service '\(service)' is unavailable"
        }
    }

    /// A localized suggestion for recovering from the error.
    public var recoverySuggestion: String? {
        switch self {
        // Authentication errors
        case .unauthorized:
            return "Provide valid authentication credentials"

        case .invalidApiKey:
            return "Check that your API key is correct and has not been revoked"

        case .invalidJWT:
            return "Ensure the JWT token is properly formatted and signed"

        case .tokenExpired:
            return "Obtain a new authentication token"

        case .tenantNotFound:
            return "Verify the tenant ID is correct"

        // Rate limiting errors
        case .rateLimited(_, let retryAfter):
            if retryAfter != nil {
                return "Wait for the specified duration before retrying"
            }
            return "Wait before retrying or reduce request frequency"

        case .quotaExceeded:
            return "Upgrade your plan for higher limits or wait for quota reset"

        // Validation errors
        case .invalidRequest:
            return "Review the request format and parameters"

        case .missingRequiredField:
            return "Include all required fields in the request"

        case .documentTooLarge:
            return "Reduce the document size or split into smaller documents"

        case .queryTooLong:
            return "Shorten the query text"

        // Job errors
        case .jobNotFound:
            return "Verify the job ID is correct"

        case .jobAlreadyRunning:
            return "Wait for the current job to complete"

        case .jobCancelled:
            return "Submit a new job if needed"

        case .jobFailed:
            return "Review the failure reason and retry if appropriate"

        // Resource errors
        case .indexNotFound:
            return "Create the index before performing operations on it"

        case .indexAlreadyExists:
            return "Use a different name or delete the existing index first"

        case .documentNotFound:
            return "Verify the document ID is correct"

        // WebSocket errors
        case .webSocketConnectionFailed:
            return "Check network connectivity and try reconnecting"

        case .webSocketAuthenticationRequired:
            return "Send an authenticate message before other operations"

        case .maxConnectionsExceeded:
            return "Close unused connections or upgrade your plan"

        // Server errors
        case .internalError:
            return "Try again later or contact support if the issue persists"

        case .serviceUnavailable:
            return "Try again later when the service is available"
        }
    }

    // MARK: - HTTP Status Code Mapping

    /// The HTTP status code corresponding to this error.
    ///
    /// Maps server errors to appropriate HTTP response status codes
    /// for REST API responses.
    public var httpStatusCode: Int {
        switch self {
        // Authentication errors - 401 Unauthorized or 403 Forbidden
        case .unauthorized, .invalidApiKey, .invalidJWT, .tokenExpired:
            return 401

        case .tenantNotFound:
            return 403

        // Rate limiting errors - 429 Too Many Requests
        case .rateLimited, .quotaExceeded:
            return 429

        // Validation errors - 400 Bad Request
        case .invalidRequest, .missingRequiredField, .documentTooLarge, .queryTooLong:
            return 400

        // Job errors - 404 Not Found or 409 Conflict
        case .jobNotFound:
            return 404

        case .jobAlreadyRunning:
            return 409

        case .jobCancelled:
            return 410  // Gone

        case .jobFailed:
            return 500

        // Resource errors - 404 Not Found or 409 Conflict
        case .indexNotFound, .documentNotFound:
            return 404

        case .indexAlreadyExists:
            return 409

        // WebSocket errors - 400 Bad Request or 401 Unauthorized
        case .webSocketConnectionFailed:
            return 400

        case .webSocketAuthenticationRequired:
            return 401

        case .maxConnectionsExceeded:
            return 429

        // Server errors - 500 Internal Server Error or 503 Service Unavailable
        case .internalError:
            return 500

        case .serviceUnavailable:
            return 503
        }
    }

    // MARK: - Error Code

    /// A machine-readable error code string.
    ///
    /// These codes are stable identifiers that clients can use for
    /// programmatic error handling.
    public var errorCode: String {
        switch self {
        case .unauthorized:
            return "UNAUTHORIZED"
        case .invalidApiKey:
            return "INVALID_API_KEY"
        case .invalidJWT:
            return "INVALID_JWT"
        case .tokenExpired:
            return "TOKEN_EXPIRED"
        case .tenantNotFound:
            return "TENANT_NOT_FOUND"
        case .rateLimited:
            return "RATE_LIMITED"
        case .quotaExceeded:
            return "QUOTA_EXCEEDED"
        case .invalidRequest:
            return "INVALID_REQUEST"
        case .missingRequiredField:
            return "MISSING_REQUIRED_FIELD"
        case .documentTooLarge:
            return "DOCUMENT_TOO_LARGE"
        case .queryTooLong:
            return "QUERY_TOO_LONG"
        case .jobNotFound:
            return "JOB_NOT_FOUND"
        case .jobAlreadyRunning:
            return "JOB_ALREADY_RUNNING"
        case .jobCancelled:
            return "JOB_CANCELLED"
        case .jobFailed:
            return "JOB_FAILED"
        case .indexNotFound:
            return "INDEX_NOT_FOUND"
        case .indexAlreadyExists:
            return "INDEX_ALREADY_EXISTS"
        case .documentNotFound:
            return "DOCUMENT_NOT_FOUND"
        case .webSocketConnectionFailed:
            return "WEBSOCKET_CONNECTION_FAILED"
        case .webSocketAuthenticationRequired:
            return "WEBSOCKET_AUTH_REQUIRED"
        case .maxConnectionsExceeded:
            return "MAX_CONNECTIONS_EXCEEDED"
        case .internalError:
            return "INTERNAL_ERROR"
        case .serviceUnavailable:
            return "SERVICE_UNAVAILABLE"
        }
    }

    /// Whether this error is potentially recoverable by retrying.
    ///
    /// Use this property to determine if automatic retries make sense.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .serviceUnavailable, .webSocketConnectionFailed:
            return true
        case .internalError:
            // Some internal errors may be transient
            return true
        default:
            return false
        }
    }

    // MARK: - Private Helpers

    /// Formats a Duration into a human-readable string.
    private func formatDuration(_ duration: Duration) -> String {
        let seconds = duration.components.seconds
        let attoseconds = duration.components.attoseconds

        if seconds >= 60 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds > 0 {
                return "\(minutes) minute\(minutes == 1 ? "" : "s") and \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")"
            }
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if seconds > 0 {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        } else {
            let milliseconds = attoseconds / 1_000_000_000_000_000
            return "\(milliseconds) millisecond\(milliseconds == 1 ? "" : "s")"
        }
    }

    /// Formats a byte count into a human-readable string.
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
