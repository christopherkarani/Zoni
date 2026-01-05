// ZoniVapor - Vapor framework integration for Zoni RAG
//
// QueryController.swift - Controller for RAG query endpoints.
//
// This file provides HTTP endpoints for executing RAG queries and
// retrieving relevant documents without generation.

import Vapor
import ZoniServer
import Zoni

// MARK: - QueryController

/// Controller for RAG query endpoints.
///
/// `QueryController` provides the HTTP API for executing retrieval-augmented
/// generation queries and performing search-only retrieval operations.
///
/// ## Endpoints
///
/// - `POST /query` - Execute a RAG query with LLM generation
/// - `GET /query/retrieve` - Search only, returns relevant chunks without generation
///
/// ## Authentication
///
/// All endpoints require tenant authentication via `TenantMiddleware`.
/// Rate limiting is applied via `RateLimitMiddleware` for the `.query` operation.
///
/// ## Example Requests
///
/// ```http
/// POST /api/v1/query
/// Authorization: Bearer <token>
/// Content-Type: application/json
///
/// {
///     "query": "What is Swift concurrency?",
///     "options": {
///         "retrievalLimit": 5,
///         "temperature": 0.7
///     }
/// }
/// ```
///
/// ```http
/// GET /api/v1/query/retrieve?q=swift+async&limit=10
/// Authorization: Bearer <token>
/// ```
struct QueryController: RouteCollection {

    // MARK: - RouteCollection Protocol

    /// Registers query routes with the router.
    ///
    /// - Parameter routes: The routes builder to register routes with.
    func boot(routes: any RoutesBuilder) throws {
        let query = routes.grouped("query")
            .grouped(TenantMiddleware())
            .grouped(RateLimitMiddleware(operation: .query))

        query.post(use: executeQuery)
        query.get("retrieve", use: retrieve)
    }

    // MARK: - Route Handlers

    /// Executes a RAG query and returns the generated response.
    ///
    /// This endpoint performs the full RAG pipeline:
    /// 1. Retrieves relevant chunks from the vector store
    /// 2. Builds context from the retrieved chunks
    /// 3. Generates a response using the configured LLM
    ///
    /// ## Request Body
    ///
    /// ```json
    /// {
    ///     "query": "What is Swift concurrency?",
    ///     "options": {
    ///         "retrievalLimit": 5,
    ///         "temperature": 0.7,
    ///         "filter": {
    ///             "type": "equals",
    ///             "field": "category",
    ///             "value": "documentation"
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "answer": "Swift concurrency provides...",
    ///     "sources": [...],
    ///     "metadata": {
    ///         "retrievalTimeMs": 45.2,
    ///         "generationTimeMs": 1250.5,
    ///         "totalTimeMs": 1295.7
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: The query response with answer, sources, and metadata.
    /// - Throws: `Abort(.badRequest)` if the request is invalid.
    @Sendable
    func executeQuery(req: Request) async throws -> QueryResponse {
        let queryRequest = try req.content.decode(QueryRequest.self)
        let options = queryRequest.toQueryOptions()

        let response = try await req.application.zoni.queryEngine.query(
            queryRequest.query,
            options: options
        )

        return QueryResponse(from: response)
    }

    /// Retrieves relevant chunks without LLM generation.
    ///
    /// This endpoint performs search-only retrieval, returning the most
    /// relevant document chunks for the given query. Useful for debugging
    /// retrieval quality or building custom RAG pipelines.
    ///
    /// ## Query Parameters
    ///
    /// - `q` (required): The search query text
    /// - `limit` (optional): Maximum results to return (default: 5, max: 100)
    ///
    /// ## Response
    ///
    /// ```json
    /// [
    ///     {
    ///         "id": "chunk-123",
    ///         "content": "Swift concurrency provides...",
    ///         "score": 0.92,
    ///         "documentId": "doc-456",
    ///         "source": "swift-guide.md"
    ///     }
    /// ]
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: An array of source DTOs representing relevant chunks.
    /// - Throws: `Abort(.badRequest)` if the query parameter is missing.
    @Sendable
    func retrieve(req: Request) async throws -> [SourceDTO] {
        guard let query = req.query[String.self, at: "q"] else {
            throw Abort(.badRequest, reason: "Missing query parameter 'q'")
        }

        // Validate limit parameter with sensible bounds
        let rawLimit = req.query[Int.self, at: "limit"] ?? 5
        let limit = max(1, min(rawLimit, 100))  // Clamp to [1, 100]

        // Log if limit was clamped (for debugging)
        if rawLimit != limit {
            req.logger.warning("Retrieval limit clamped from \(rawLimit) to \(limit)")
        }

        let results = try await req.application.zoni.queryEngine.retrieve(
            query,
            limit: limit
        )

        return results.map { SourceDTO(from: $0) }
    }
}

// MARK: - Query Parameter Constants

private enum QueryParameterLimits {
    /// Default retrieval limit when not specified.
    static let defaultLimit = 5

    /// Minimum allowed retrieval limit.
    static let minLimit = 1

    /// Maximum allowed retrieval limit to prevent abuse.
    static let maxLimit = 100
}

// MARK: - Content Conformance

extension QueryResponse: Content {}
extension SourceDTO: Content {}
