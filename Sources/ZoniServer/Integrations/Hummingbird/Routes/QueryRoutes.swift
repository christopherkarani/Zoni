#if HUMMINGBIRD
// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// QueryRoutes.swift - HTTP routes for RAG query operations.
//
// This file provides route handlers for executing RAG queries and retrieval
// operations through the Hummingbird HTTP framework.

import Hummingbird
import HummingbirdAuth
import Zoni

// MARK: - Query Routes

/// Registers query routes on a router group.
///
/// This function adds the following endpoints:
/// - `POST /query` - Execute a RAG query with optional configuration
/// - `GET /query/retrieve` - Search for relevant documents without generation
///
/// Both endpoints require tenant authentication and are rate-limited.
///
/// ## Example Usage
///
/// ```swift
/// let api = router.group("api/v1")
/// addQueryRoutes(to: api, services: services)
/// ```
///
/// ## Endpoints
///
/// ### POST /query
///
/// Executes a RAG query and returns the generated answer with sources.
///
/// Request body:
/// ```json
/// {
///     "query": "What is Swift concurrency?",
///     "options": {
///         "retrievalLimit": 10,
///         "temperature": 0.7
///     }
/// }
/// ```
///
/// Response:
/// ```json
/// {
///     "answer": "Swift concurrency provides...",
///     "sources": [...],
///     "metadata": {...}
/// }
/// ```
///
/// ### GET /query/retrieve
///
/// Searches for relevant documents without generating a response.
///
/// Query parameters:
/// - `q` (required): The search query text
/// - `limit` (optional): Maximum results to return (default: 5)
///
/// Response: Array of source documents with scores.
///
/// - Parameters:
///   - group: The router group to add routes to.
///   - services: The Zoni services container.
public func addQueryRoutes<Context: AuthRequestContext>(
    to group: RouterGroup<Context>,
    services: ZoniServices
) where Context.Identity == TenantContext {
    // Create query route group with middleware
    let query = group.group("query")
        .add(middleware: TenantMiddleware<Context>(tenantManager: services.tenantManager))
        .add(middleware: RateLimitMiddleware<Context>(rateLimiter: services.rateLimiter, operation: .query))

    // POST /query - Execute RAG query
    query.post { request, context -> QueryResponse in
        let queryRequest = try await request.decode(as: QueryRequest.self, context: context)
        let options = queryRequest.toQueryOptions()

        let response = try await services.queryEngine.query(
            queryRequest.query,
            options: options
        )

        return QueryResponse(from: response)
    }

    // GET /query/retrieve - Search only (no generation)
    query.get("retrieve") { request, context -> [SourceDTO] in
        // Extract query parameter
        guard let queryText = request.uri.queryParameters.get("q") else {
            throw HTTPError(.badRequest, message: "Missing query parameter 'q'")
        }

        // Extract optional limit parameter
        let limit: Int
        if let limitString = request.uri.queryParameters.get("limit"),
           let parsedLimit = Int(limitString) {
            limit = parsedLimit
        } else {
            limit = 5
        }

        // Perform retrieval
        let results = try await services.queryEngine.retrieve(queryText, limit: limit)

        // Convert to DTOs
        return results.map { SourceDTO(from: $0) }
    }
}

#endif
