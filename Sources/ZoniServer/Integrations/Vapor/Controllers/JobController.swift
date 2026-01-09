#if VAPOR
// ZoniVapor - Vapor framework integration for Zoni RAG
//
// JobController.swift - Controller for job management endpoints.
//
// This file provides HTTP endpoints for managing background jobs,
// including listing, status checks, and cancellation.

import Vapor

// MARK: - Response DTOs

/// Response for job cancellation.
struct CancelResponse: Content {
    let cancelled: Bool
}

// MARK: - JobController

/// Controller for job management endpoints.
///
/// `JobController` provides the HTTP API for managing background jobs
/// created during async operations like document ingestion. Tenants can
/// list their jobs, check status, and cancel pending jobs.
///
/// ## Endpoints
///
/// - `GET /jobs` - List jobs for the authenticated tenant
/// - `GET /jobs/:jobId` - Get status of a specific job
/// - `DELETE /jobs/:jobId` - Cancel a pending or running job
///
/// ## Authentication
///
/// All endpoints require tenant authentication via `TenantMiddleware`.
/// Tenants can only access jobs they own.
///
/// ## Example Requests
///
/// ```http
/// GET /api/v1/jobs?status=running&limit=10
/// Authorization: Bearer <token>
/// ```
///
/// ```http
/// GET /api/v1/jobs/job-123
/// Authorization: Bearer <token>
/// ```
struct JobController: RouteCollection {

    // MARK: - RouteCollection Protocol

    /// Registers job management routes with the router.
    ///
    /// - Parameter routes: The routes builder to register routes with.
    func boot(routes: any RoutesBuilder) throws {
        let jobs = routes.grouped("jobs")
            .grouped(TenantMiddleware())

        jobs.get(use: listJobs)
        jobs.get(":jobId", use: getJob)
        jobs.delete(":jobId", use: cancelJob)
    }

    // MARK: - Route Handlers

    /// Lists jobs for the authenticated tenant.
    ///
    /// Returns a paginated list of jobs owned by the tenant, with optional
    /// filtering by status. Results are sorted by creation time (newest first).
    ///
    /// ## Query Parameters
    ///
    /// - `status` (optional): Filter by job status (`pending`, `running`, `completed`, `failed`, `cancelled`)
    /// - `limit` (optional): Maximum results to return (default: 50, max: 100)
    ///
    /// ## Response
    ///
    /// ```json
    /// [
    ///     {
    ///         "jobId": "job-123",
    ///         "status": "running",
    ///         "progress": 0.45,
    ///         "createdAt": "2024-01-15T10:30:00Z"
    ///     }
    /// ]
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: An array of job status responses.
    @Sendable
    func listJobs(req: Request) async throws -> [JobStatusResponse] {
        let tenant = try req.requireTenant()
        let status = req.query[String.self, at: "status"].flatMap { JobStatus(rawValue: $0) }
        let limit = min(req.query[Int.self, at: "limit"] ?? 50, 100)

        let records = try await req.application.zoni.jobQueue.listJobs(
            tenantId: tenant.tenantId,
            status: status,
            limit: limit
        )

        return records.map { JobStatusResponse(from: $0) }
    }

    /// Gets the status of a specific job.
    ///
    /// Returns detailed status information for a job, including progress
    /// and result data for completed jobs.
    ///
    /// ## Path Parameters
    ///
    /// - `jobId`: The unique identifier of the job
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "jobId": "job-123",
    ///     "status": "completed",
    ///     "progress": 1.0,
    ///     "result": {
    ///         "documentIds": ["doc-1", "doc-2"],
    ///         "chunksCreated": 42
    ///     },
    ///     "createdAt": "2024-01-15T10:30:00Z",
    ///     "completedAt": "2024-01-15T10:31:30Z"
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: The job status response.
    /// - Throws: `Abort(.notFound)` if the job does not exist or belongs to another tenant.
    @Sendable
    func getJob(req: Request) async throws -> JobStatusResponse {
        guard let jobId = req.parameters.get("jobId") else {
            throw Abort(.badRequest, reason: "Missing job ID")
        }

        guard let record = try await req.application.zoni.jobQueue.getJob(jobId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        // Verify tenant owns this job
        let tenant = try req.requireTenant()
        if record.tenantId != tenant.tenantId {
            throw Abort(.notFound, reason: "Job not found")
        }

        return JobStatusResponse(from: record)
    }

    /// Cancels a pending or running job.
    ///
    /// Attempts to cancel a job that has not yet completed. Jobs that are
    /// already completed or failed cannot be cancelled.
    ///
    /// ## Path Parameters
    ///
    /// - `jobId`: The unique identifier of the job to cancel
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "cancelled": true
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: A response indicating whether cancellation was successful.
    /// - Throws: `Abort(.badRequest)` if job ID is missing.
    @Sendable
    func cancelJob(req: Request) async throws -> Response {
        guard let jobId = req.parameters.get("jobId") else {
            throw Abort(.badRequest, reason: "Missing job ID")
        }

        // Verify job exists and belongs to tenant
        let tenant = try req.requireTenant()
        if let record = try await req.application.zoni.jobQueue.getJob(jobId) {
            if record.tenantId != tenant.tenantId {
                throw Abort(.notFound, reason: "Job not found")
            }
        }

        let cancelled = try await req.application.zoni.jobQueue.cancel(jobId)

        let response = CancelResponse(cancelled: cancelled)
        return try await response.encodeResponse(status: cancelled ? .ok : .conflict, for: req)
    }
}

// MARK: - JobStatusResponse Extension

extension JobStatusResponse {

    /// Creates a job status response from a job record.
    ///
    /// - Parameter record: The job record to convert.
    init(from record: JobRecord) {
        // Decode result data if present
        var resultDTO: JobResultDTO?
        if let resultData = record.result {
            if let decoded = try? JSONDecoder().decode(JobResultData.self, from: resultData) {
                resultDTO = JobResultDTO(
                    documentIds: decoded.documentIds,
                    chunksCreated: decoded.chunksCreated,
                    message: decoded.message
                )
            }
        }

        self.init(
            jobId: record.id,
            status: record.status,
            progress: record.progress,
            result: resultDTO,
            error: record.error,
            createdAt: record.createdAt,
            completedAt: record.completedAt
        )
    }
}

// MARK: - Content Conformance

extension JobStatusResponse: Content {}

#endif
