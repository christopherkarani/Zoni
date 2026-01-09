#if VAPOR
// ZoniVapor - Vapor framework integration for Zoni RAG
//
// IndexController.swift - Controller for index management endpoints.
//
// This file provides HTTP endpoints for managing vector store indices,
// including creation, listing, and deletion.

import Vapor
import Zoni

// MARK: - IndexController

/// Controller for index management endpoints.
///
/// `IndexController` provides the HTTP API for managing vector store indices.
/// Indices are the underlying storage for document chunks and their embeddings.
///
/// ## Endpoints
///
/// - `GET /indices` - List all indices for the tenant
/// - `POST /indices` - Create a new index
/// - `GET /indices/:name` - Get information about a specific index
/// - `DELETE /indices/:name` - Delete an index
///
/// ## Authentication
///
/// All endpoints require tenant authentication via `TenantMiddleware`.
/// Indices are isolated per tenant using the tenant's index prefix.
///
/// ## Example Requests
///
/// ```http
/// POST /api/v1/indices
/// Authorization: Bearer <token>
/// Content-Type: application/json
///
/// {
///     "name": "knowledge-base",
///     "dimensions": 1536,
///     "indexType": "hnsw"
/// }
/// ```
struct IndexController: RouteCollection {

    // MARK: - RouteCollection Protocol

    /// Registers index management routes with the router.
    ///
    /// - Parameter routes: The routes builder to register routes with.
    func boot(routes: any RoutesBuilder) throws {
        let indices = routes.grouped("indices")
            .grouped(TenantMiddleware())

        indices.get(use: listIndices)
        indices.post(use: createIndex)
        indices.get(":name", use: getIndex)
        indices.delete(":name", use: deleteIndex)
    }

    // MARK: - Route Handlers

    /// Lists all indices for the authenticated tenant.
    ///
    /// Returns information about all indices owned by the tenant,
    /// including document counts and creation dates.
    ///
    /// ## Response
    ///
    /// ```json
    /// [
    ///     {
    ///         "name": "knowledge-base",
    ///         "documentCount": 150,
    ///         "chunkCount": 2340,
    ///         "dimensions": 1536,
    ///         "createdAt": "2024-01-15T10:30:00Z"
    ///     }
    /// ]
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: An array of index info objects.
    @Sendable
    func listIndices(req: Request) async throws -> [IndexInfo] {
        // In a full implementation, this would query the vector store
        // for all indices belonging to the tenant
        _ = try req.requireTenant()

        // Placeholder response
        return []
    }

    /// Creates a new vector store index.
    ///
    /// Creates a new index with the specified configuration. The index name
    /// is prefixed with the tenant's index prefix for isolation.
    ///
    /// ## Request Body
    ///
    /// ```json
    /// {
    ///     "name": "knowledge-base",
    ///     "dimensions": 1536,
    ///     "indexType": "hnsw"
    /// }
    /// ```
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "name": "knowledge-base",
    ///     "documentCount": 0,
    ///     "chunkCount": 0,
    ///     "dimensions": 1536,
    ///     "createdAt": "2024-01-15T10:30:00Z"
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: Information about the created index.
    /// - Throws: `Abort(.conflict)` if an index with the name already exists.
    @Sendable
    func createIndex(req: Request) async throws -> IndexInfo {
        let createRequest = try req.content.decode(CreateIndexRequest.self)
        let tenant = try req.requireTenant()

        // Apply tenant prefix to index name
        let prefixedName = tenant.config.indexPrefix + createRequest.name

        // In a full implementation, this would create the index in the vector store
        _ = prefixedName

        return IndexInfo(
            name: createRequest.name,
            documentCount: 0,
            chunkCount: 0,
            dimensions: createRequest.dimensions ?? 1536,
            createdAt: Date()
        )
    }

    /// Gets information about a specific index.
    ///
    /// Returns detailed information about an index, including current
    /// document and chunk counts.
    ///
    /// ## Path Parameters
    ///
    /// - `name`: The name of the index
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "name": "knowledge-base",
    ///     "documentCount": 150,
    ///     "chunkCount": 2340,
    ///     "dimensions": 1536,
    ///     "createdAt": "2024-01-15T10:30:00Z"
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: Information about the index.
    /// - Throws: `Abort(.notFound)` if the index does not exist.
    @Sendable
    func getIndex(req: Request) async throws -> IndexInfo {
        guard let name = req.parameters.get("name") else {
            throw Abort(.badRequest, reason: "Missing index name")
        }

        let tenant = try req.requireTenant()

        // Apply tenant prefix to index name
        let prefixedName = tenant.config.indexPrefix + name

        // In a full implementation, this would query the vector store
        _ = prefixedName

        // Placeholder - would throw .notFound if index doesn't exist
        return IndexInfo(
            name: name,
            documentCount: 0,
            chunkCount: 0,
            dimensions: 1536,
            createdAt: Date()
        )
    }

    /// Deletes an index and all its contents.
    ///
    /// Permanently removes an index and all documents/chunks it contains.
    /// This operation cannot be undone.
    ///
    /// ## Path Parameters
    ///
    /// - `name`: The name of the index to delete
    ///
    /// ## Response
    ///
    /// Returns 204 No Content on successful deletion.
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: An empty response with 204 status.
    /// - Throws: `Abort(.notFound)` if the index does not exist.
    @Sendable
    func deleteIndex(req: Request) async throws -> Response {
        guard let name = req.parameters.get("name") else {
            throw Abort(.badRequest, reason: "Missing index name")
        }

        let tenant = try req.requireTenant()

        // Apply tenant prefix to index name
        let prefixedName = tenant.config.indexPrefix + name

        // In a full implementation, this would delete the index from the vector store
        _ = prefixedName

        return Response(status: .noContent)
    }
}

// MARK: - Content Conformance

extension IndexInfo: Content {}
extension CreateIndexRequest: Content {}

#endif
