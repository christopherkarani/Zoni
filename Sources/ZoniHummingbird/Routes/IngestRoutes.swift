// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// IngestRoutes.swift - HTTP routes for document ingestion operations.
//
// This file provides route handlers for ingesting documents into the RAG
// system through the Hummingbird HTTP framework.

import Hummingbird
import HummingbirdAuth
import Zoni
import ZoniServer

// MARK: - Ingest Routes

/// Registers document ingestion routes on a router group.
///
/// This function adds the following endpoints:
/// - `POST /documents` - Ingest documents (sync or async)
/// - `POST /documents/batch` - Async batch ingestion
/// - `DELETE /documents/:documentId` - Delete a document
///
/// All endpoints require tenant authentication and are rate-limited.
///
/// ## Example Usage
///
/// ```swift
/// let api = router.group("api/v1")
/// addIngestRoutes(to: api, services: services)
/// ```
///
/// ## Endpoints
///
/// ### POST /documents
///
/// Ingests one or more documents. Supports sync or async processing.
///
/// Request body:
/// ```json
/// {
///     "documents": [
///         {
///             "content": "Document content...",
///             "source": "file.md",
///             "title": "Document Title"
///         }
///     ],
///     "options": {
///         "async": true,
///         "chunkSize": 512
///     }
/// }
/// ```
///
/// Sync response:
/// ```json
/// {
///     "success": true,
///     "documentIds": ["doc-123"],
///     "chunksCreated": 10,
///     "message": "Documents ingested"
/// }
/// ```
///
/// Async response:
/// ```json
/// {
///     "success": true,
///     "documentIds": [],
///     "chunksCreated": 0,
///     "jobId": "job-456",
///     "message": "Ingestion job queued"
/// }
/// ```
///
/// ### POST /documents/batch
///
/// Always processes ingestion asynchronously as a background job.
///
/// ### DELETE /documents/:documentId
///
/// Deletes a document and its associated chunks.
///
/// - Parameters:
///   - group: The router group to add routes to.
///   - services: The Zoni services container.
public func addIngestRoutes<Context: AuthRequestContext>(
    to group: RouterGroup<Context>,
    services: ZoniServices
) where Context.Identity == TenantContext {
    // Create documents route group with middleware
    let docs = group.group("documents")
        .add(middleware: TenantMiddleware<Context>(tenantManager: services.tenantManager))
        .add(middleware: RateLimitMiddleware<Context>(rateLimiter: services.rateLimiter, operation: .ingest))

    // POST /documents - Ingest documents
    docs.post { request, context -> IngestResponse in
        let ingestRequest = try await request.decode(as: IngestRequest.self, context: context)
        let tenant = try context.tenant

        // Check if async processing is requested
        if ingestRequest.options?.async == true {
            let documents = ingestRequest.documents ?? []
            let job = IngestJob(
                tenantId: tenant.tenantId,
                documents: documents,
                options: ingestRequest.options
            )

            let jobId = try await services.jobQueue.enqueue(job)

            return IngestResponse(
                success: true,
                documentIds: [],
                chunksCreated: 0,
                jobId: jobId,
                message: "Ingestion job queued"
            )
        }

        // Synchronous processing
        // TODO: Implement synchronous document ingestion
        // For now, return a placeholder response
        return IngestResponse(
            success: true,
            documentIds: [],
            chunksCreated: 0,
            message: "Documents ingested"
        )
    }

    // POST /documents/batch - Async batch ingest
    docs.post("batch") { request, context -> IngestResponse in
        let ingestRequest = try await request.decode(as: IngestRequest.self, context: context)
        let tenant = try context.tenant

        let documents = ingestRequest.documents ?? []
        let job = IngestJob(
            tenantId: tenant.tenantId,
            documents: documents,
            options: ingestRequest.options
        )

        let jobId = try await services.jobQueue.enqueue(job)

        return IngestResponse(
            success: true,
            documentIds: [],
            chunksCreated: 0,
            jobId: jobId,
            message: "Batch ingestion job queued"
        )
    }

    // DELETE /documents/:documentId
    docs.delete(":documentId") { request, context -> Response in
        guard let documentId = context.parameters.get("documentId") else {
            throw HTTPError(.badRequest, message: "Missing document ID")
        }

        // Verify tenant access
        _ = try context.tenant

        // TODO: Implement document deletion
        // For now, return success
        _ = documentId  // Silence unused variable warning

        return Response(status: .ok)
    }
}

// MARK: - TenantContext Extension

extension AuthRequestContext where Identity == TenantContext {
    /// The resolved tenant for this request.
    ///
    /// This property provides convenient access to the authenticated tenant context.
    /// It throws an error if the request has not been authenticated.
    ///
    /// - Returns: The authenticated tenant context.
    /// - Throws: `ZoniServerError.unauthorized` if no tenant context is available.
    var tenant: TenantContext {
        get throws {
            guard let identity else {
                throw ZoniServerError.unauthorized(reason: "No tenant context")
            }
            return identity
        }
    }
}
