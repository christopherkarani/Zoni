// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// JobRoutes.swift - HTTP routes for background job management.
//
// This file provides route handlers for managing asynchronous background
// jobs through the Hummingbird HTTP framework.

import Foundation
import Hummingbird
import HummingbirdAuth
import ZoniServer

// MARK: - Job Routes

/// Registers job management routes on a router group.
///
/// This function adds the following endpoints:
/// - `GET /jobs` - List jobs for the authenticated tenant
/// - `GET /jobs/:jobId` - Get status of a specific job
/// - `DELETE /jobs/:jobId` - Cancel a pending or running job
///
/// All endpoints require tenant authentication.
///
/// ## Example Usage
///
/// ```swift
/// let api = router.group("api/v1")
/// addJobRoutes(to: api, services: services)
/// ```
///
/// ## Endpoints
///
/// ### GET /jobs
///
/// Lists jobs for the authenticated tenant with optional filtering.
///
/// Query parameters:
/// - `status` (optional): Filter by job status (pending, running, completed, failed, cancelled)
/// - `limit` (optional): Maximum number of jobs to return (default: 50)
///
/// Response:
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
/// ### GET /jobs/:jobId
///
/// Gets the status of a specific job.
///
/// Response:
/// ```json
/// {
///     "jobId": "job-123",
///     "status": "completed",
///     "progress": 1.0,
///     "result": {
///         "documentIds": ["doc-456"],
///         "chunksCreated": 42
///     },
///     "createdAt": "2024-01-15T10:30:00Z",
///     "completedAt": "2024-01-15T10:31:30Z"
/// }
/// ```
///
/// ### DELETE /jobs/:jobId
///
/// Cancels a pending or running job.
///
/// - Returns 200 if cancelled successfully
/// - Returns 409 if the job cannot be cancelled (already completed/failed)
///
/// - Parameters:
///   - group: The router group to add routes to.
///   - services: The Zoni services container.
public func addJobRoutes<Context: AuthRequestContext>(
    to group: RouterGroup<Context>,
    services: ZoniServices
) where Context.Identity == TenantContext {
    // Create jobs route group with tenant authentication
    let jobs = group.group("jobs")
        .add(middleware: TenantMiddleware<Context>(tenantManager: services.tenantManager))

    // GET /jobs - List jobs
    jobs.get { request, context -> [JobStatusResponse] in
        let tenant = try context.tenant

        // Parse optional status filter
        let status: JobStatus?
        if let statusString = request.uri.queryParameters.get("status") {
            status = JobStatus(rawValue: statusString)
        } else {
            status = nil
        }

        // Parse limit parameter
        let limit: Int
        if let limitString = request.uri.queryParameters.get("limit"),
           let parsedLimit = Int(limitString) {
            limit = parsedLimit
        } else {
            limit = 50
        }

        // Fetch jobs from queue
        let records = try await services.jobQueue.listJobs(
            tenantId: tenant.tenantId,
            status: status,
            limit: limit
        )

        // Convert to response DTOs
        return records.map { record in
            JobStatusResponse(from: record)
        }
    }

    // GET /jobs/:jobId - Get job status
    jobs.get(":jobId") { request, context -> JobStatusResponse in
        guard let jobId = context.parameters.get("jobId") else {
            throw HTTPError(.badRequest, message: "Missing job ID")
        }

        let tenant = try context.tenant

        // Fetch job from queue
        guard let record = try await services.jobQueue.getJob(jobId) else {
            throw HTTPError(.notFound, message: "Job not found")
        }

        // Verify tenant owns this job
        if record.tenantId != tenant.tenantId {
            throw HTTPError(.notFound, message: "Job not found")
        }

        return JobStatusResponse(from: record)
    }

    // DELETE /jobs/:jobId - Cancel job
    jobs.delete(":jobId") { request, context -> Response in
        guard let jobId = context.parameters.get("jobId") else {
            throw HTTPError(.badRequest, message: "Missing job ID")
        }

        _ = try context.tenant

        // Attempt to cancel the job
        let cancelled = try await services.jobQueue.cancel(jobId)

        if cancelled {
            return Response(status: .ok)
        } else {
            return Response(status: .conflict)
        }
    }
}

// MARK: - JobStatusResponse Extension

extension JobStatusResponse {
    /// Creates a job status response from a job record.
    ///
    /// - Parameter record: The job record to convert.
    init(from record: JobRecord) {
        // Decode result if available
        let result: JobResultDTO?
        if let resultData = record.result {
            result = try? JSONDecoder().decode(JobResultData.self, from: resultData)
                .toDTO()
        } else {
            result = nil
        }

        self.init(
            jobId: record.id,
            status: record.status,
            progress: record.progress,
            result: result,
            error: record.error,
            createdAt: record.createdAt,
            completedAt: record.completedAt
        )
    }
}

// MARK: - JobResultData Extension

extension JobResultData {
    /// Converts job result data to a DTO.
    func toDTO() -> JobResultDTO {
        JobResultDTO(
            documentIds: documentIds,
            chunksCreated: chunksCreated,
            message: message
        )
    }
}
