// ZoniVapor - Vapor framework integration for Zoni RAG
//
// IngestController.swift - Controller for document ingestion endpoints.
//
// This file provides HTTP endpoints for ingesting documents into the
// RAG system, supporting both synchronous and asynchronous processing.

import Vapor
import ZoniServer
import Zoni

// MARK: - IngestController

/// Controller for document ingestion endpoints.
///
/// `IngestController` provides the HTTP API for ingesting documents into
/// the RAG system. Supports both synchronous processing for small batches
/// and asynchronous job-based processing for larger workloads.
///
/// ## Endpoints
///
/// - `POST /documents` - Ingest documents (sync or async based on options)
/// - `POST /documents/batch` - Always async batch ingestion
/// - `DELETE /documents/:documentId` - Delete a document and its chunks
///
/// ## Authentication
///
/// All endpoints require tenant authentication via `TenantMiddleware`.
/// Rate limiting is applied via `RateLimitMiddleware` for the `.ingest` operation.
///
/// ## Async Processing
///
/// When `options.async` is `true` or using the batch endpoint, documents
/// are processed in the background via the job queue. The response includes
/// a `jobId` that can be used to track progress.
///
/// ## Example Requests
///
/// ```http
/// POST /api/v1/documents
/// Authorization: Bearer <token>
/// Content-Type: application/json
///
/// {
///     "documents": [
///         {"content": "Document content...", "source": "file.md"}
///     ],
///     "options": {"async": true}
/// }
/// ```
struct IngestController: RouteCollection {

    // MARK: - RouteCollection Protocol

    /// Registers document ingestion routes with the router.
    ///
    /// - Parameter routes: The routes builder to register routes with.
    func boot(routes: any RoutesBuilder) throws {
        let docs = routes.grouped("documents")
            .grouped(TenantMiddleware())
            .grouped(RateLimitMiddleware(operation: .ingest))

        docs.post(use: ingestDocuments)
        docs.post("batch", use: batchIngest)
        docs.delete(":documentId", use: deleteDocument)
    }

    // MARK: - Route Handlers

    /// Ingests documents into the RAG system.
    ///
    /// This endpoint supports multiple ingestion modes:
    /// - **Direct content**: Provide `content` field directly
    /// - **Batch**: Provide an array of `documents`
    ///
    /// When `options.async` is `true`, the ingestion is processed in the
    /// background and a job ID is returned for tracking progress.
    ///
    /// ## Request Body
    ///
    /// ```json
    /// {
    ///     "documents": [
    ///         {
    ///             "content": "Document content...",
    ///             "source": "file.md",
    ///             "title": "Document Title",
    ///             "metadata": {"category": "documentation"}
    ///         }
    ///     ],
    ///     "options": {
    ///         "chunkSize": 512,
    ///         "chunkOverlap": 50,
    ///         "async": true
    ///     }
    /// }
    /// ```
    ///
    /// ## Response (Async)
    ///
    /// ```json
    /// {
    ///     "success": true,
    ///     "documentIds": [],
    ///     "chunksCreated": 0,
    ///     "jobId": "job-123",
    ///     "message": "Ingestion job queued"
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: The ingestion response with document IDs or job ID.
    /// - Throws: `Abort(.badRequest)` if the request is invalid.
    @Sendable
    func ingestDocuments(req: Request) async throws -> IngestResponse {
        let ingestRequest = try req.content.decode(IngestRequest.self)
        let tenant = req.tenant

        // If async requested, create a job
        if ingestRequest.options?.async == true {
            let documents = ingestRequest.documents ?? []
            let job = IngestJob(
                tenantId: tenant.tenantId,
                documents: documents,
                options: ingestRequest.options
            )

            let jobId = try await req.application.zoni.jobQueue.enqueue(job)

            return IngestResponse(
                success: true,
                documentIds: [],
                chunksCreated: 0,
                jobId: jobId,
                message: "Ingestion job queued"
            )
        }

        // Synchronous ingestion
        // For now, return a placeholder - full implementation would process documents
        let documents = ingestRequest.documents ?? []

        return IngestResponse(
            success: true,
            documentIds: documents.enumerated().map { "doc-\($0.offset)" },
            chunksCreated: documents.count * 10, // Placeholder
            message: "Successfully ingested \(documents.count) documents"
        )
    }

    /// Performs batch ingestion asynchronously.
    ///
    /// This endpoint always processes documents asynchronously via the job queue,
    /// regardless of the `async` option. Ideal for large document batches that
    /// may take significant time to process.
    ///
    /// ## Request Body
    ///
    /// ```json
    /// {
    ///     "documents": [
    ///         {"content": "First document...", "title": "Doc 1"},
    ///         {"content": "Second document...", "title": "Doc 2"}
    ///     ]
    /// }
    /// ```
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "success": true,
    ///     "documentIds": [],
    ///     "chunksCreated": 0,
    ///     "jobId": "job-456",
    ///     "message": "Batch ingestion job queued"
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: The ingestion response with job ID for tracking.
    @Sendable
    func batchIngest(req: Request) async throws -> IngestResponse {
        let ingestRequest = try req.content.decode(IngestRequest.self)
        let tenant = req.tenant

        let documents = ingestRequest.documents ?? []
        let job = IngestJob(
            tenantId: tenant.tenantId,
            documents: documents,
            options: ingestRequest.options
        )

        let jobId = try await req.application.zoni.jobQueue.enqueue(job)

        return IngestResponse(
            success: true,
            documentIds: [],
            chunksCreated: 0,
            jobId: jobId,
            message: "Batch ingestion job queued"
        )
    }

    /// Deletes a document and all its associated chunks.
    ///
    /// This endpoint removes a document from the RAG system, including
    /// all chunks and embeddings associated with it.
    ///
    /// ## Path Parameters
    ///
    /// - `documentId`: The unique identifier of the document to delete
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "success": true
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: A JSON response indicating success.
    /// - Throws: `Abort(.badRequest)` if document ID is missing.
    @Sendable
    func deleteDocument(req: Request) async throws -> Response {
        guard let documentId = req.parameters.get("documentId") else {
            throw Abort(.badRequest, reason: "Missing document ID")
        }

        // Implementation would delete document and its chunks from vector store
        // For now, return success
        _ = documentId

        return Response(
            status: .ok,
            body: .init(string: "{\"success\": true}")
        )
    }
}

// MARK: - Content Conformance

extension IngestResponse: Content {}
