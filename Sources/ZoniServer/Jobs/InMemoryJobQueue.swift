// ZoniServer - Server-side extensions for Zoni
//
// InMemoryJobQueue.swift - In-memory implementation of JobQueueBackend.
//
// This file provides an in-memory job queue suitable for development,
// testing, and single-instance deployments. Jobs are lost on process restart.

import Foundation

// MARK: - InMemoryJobQueue

/// In-memory implementation of JobQueueBackend.
///
/// Suitable for development, testing, and single-instance deployments.
/// Jobs are lost on process restart.
///
/// ## Thread Safety
///
/// Implemented as an actor for thread-safe access to the job store.
///
/// ## Priority Ordering
///
/// Jobs are processed in priority order, with higher priority jobs
/// (`.critical`, `.high`) processed before lower priority jobs.
/// Within the same priority level, jobs are processed in FIFO order.
///
/// ## Example Usage
///
/// ```swift
/// let queue = InMemoryJobQueue()
/// let jobId = try await queue.enqueue(IngestJob(tenantId: "t1", documents: docs))
/// let status = try await queue.getJob(jobId)
/// ```
public actor InMemoryJobQueue: JobQueueBackend {

    // MARK: - Properties

    /// Storage for all job records, keyed by job ID.
    private var jobs: [String: JobRecord] = [:]

    /// Queue of pending job IDs in priority order.
    private var pendingQueue: [String] = []

    // MARK: - Initialization

    /// Creates a new in-memory job queue.
    public init() {}

    // MARK: - JobQueueBackend Protocol

    /// Enqueues a job for processing.
    ///
    /// The job is serialized and stored in memory, then added to the
    /// pending queue in priority order.
    ///
    /// - Parameter job: The job to enqueue.
    /// - Returns: The unique identifier of the enqueued job.
    /// - Throws: An encoding error if the job cannot be serialized.
    public func enqueue(_ job: any Job) async throws -> String {
        let payload = try JSONEncoder().encode(job)
        let record = JobRecord(
            id: job.id,
            jobType: type(of: job).jobType,
            tenantId: job.tenantId,
            priority: job.priority,
            payload: payload,
            maxRetries: job.maxRetries
        )

        jobs[record.id] = record
        insertInPriorityOrder(record.id, priority: record.priority)

        return record.id
    }

    /// Dequeues the next pending job for processing.
    ///
    /// The highest priority pending job is removed from the queue and
    /// its status is updated to `.running`.
    ///
    /// - Returns: The next job record to process, or `nil` if the queue is empty.
    public func dequeue() async throws -> JobRecord? {
        guard let jobId = pendingQueue.first else { return nil }
        pendingQueue.removeFirst()

        guard var record = jobs[jobId] else { return nil }
        record.status = .running
        record.startedAt = Date()
        jobs[jobId] = record

        return record
    }

    /// Updates the status of a job.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - status: The new status.
    /// - Throws: `ZoniServerError.jobNotFound` if the job does not exist.
    public func updateStatus(_ jobId: String, status: JobStatus) async throws {
        guard var record = jobs[jobId] else {
            throw ZoniServerError.jobNotFound(jobId: jobId)
        }
        record.status = status
        if status == .completed || status == .failed || status == .cancelled {
            record.completedAt = Date()
        }

        // If status is being reset to pending (for retry), add back to queue
        if status == .pending && !pendingQueue.contains(jobId) {
            insertInPriorityOrder(jobId, priority: record.priority)
        }

        jobs[jobId] = record
    }

    /// Updates the progress of a job.
    ///
    /// Progress is clamped to the range [0.0, 1.0].
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - progress: The progress value (0.0 to 1.0).
    public func updateProgress(_ jobId: String, progress: Double) async throws {
        guard var record = jobs[jobId] else { return }
        record.progress = min(1.0, max(0.0, progress))
        jobs[jobId] = record
    }

    /// Stores the result of a completed job.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - result: The result data.
    public func storeResult(_ jobId: String, result: JobResultData) async throws {
        guard var record = jobs[jobId] else { return }
        record.result = try JSONEncoder().encode(result)
        jobs[jobId] = record
    }

    /// Stores an error message for a failed job.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - error: The error message.
    public func storeError(_ jobId: String, error: String) async throws {
        guard var record = jobs[jobId] else { return }
        record.error = error
        jobs[jobId] = record
    }

    /// Retrieves a job by its identifier.
    ///
    /// - Parameter jobId: The job identifier.
    /// - Returns: The job record if found, or `nil`.
    public func getJob(_ jobId: String) async throws -> JobRecord? {
        jobs[jobId]
    }

    /// Lists jobs for a tenant with optional filtering.
    ///
    /// Jobs are sorted by creation date in descending order (newest first).
    ///
    /// - Parameters:
    ///   - tenantId: The tenant identifier.
    ///   - status: Optional status filter.
    ///   - limit: Maximum number of jobs to return.
    /// - Returns: An array of matching job records.
    public func listJobs(
        tenantId: String,
        status: JobStatus?,
        limit: Int
    ) async throws -> [JobRecord] {
        jobs.values
            .filter { $0.tenantId == tenantId }
            .filter { status == nil || $0.status == status }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Cancels a pending or running job.
    ///
    /// - If the job is pending, it is removed from the queue and marked as cancelled.
    /// - If the job is running, this returns `true` to indicate the executor
    ///   should cancel it (the actual cancellation happens in the executor).
    ///
    /// - Parameter jobId: The job identifier.
    /// - Returns: `true` if the job was or will be cancelled, `false` otherwise.
    public func cancel(_ jobId: String) async throws -> Bool {
        guard var record = jobs[jobId] else { return false }

        if record.status == .pending {
            record.status = .cancelled
            record.completedAt = Date()
            jobs[jobId] = record
            pendingQueue.removeAll { $0 == jobId }
            return true
        } else if record.status == .running {
            // Mark for cancellation (executor checks this)
            return true
        }
        return false
    }

    /// Removes old completed or failed jobs from storage.
    ///
    /// - Parameter before: Remove jobs completed before this date.
    /// - Returns: The number of jobs pruned.
    public func pruneOldJobs(before: Date) async throws -> Int {
        let toRemove = jobs.values.filter {
            ($0.status == .completed || $0.status == .failed || $0.status == .cancelled) &&
            ($0.completedAt ?? Date()) < before
        }.map { $0.id }

        for id in toRemove {
            jobs.removeValue(forKey: id)
        }
        return toRemove.count
    }

    // MARK: - Helpers

    /// Inserts a job ID into the pending queue in priority order.
    ///
    /// Higher priority jobs are placed earlier in the queue.
    ///
    /// - Parameters:
    ///   - jobId: The job ID to insert.
    ///   - priority: The priority of the job.
    private func insertInPriorityOrder(_ jobId: String, priority: JobPriority) {
        // Insert maintaining priority order (highest first)
        let insertIndex = pendingQueue.firstIndex { id in
            guard let existing = jobs[id] else { return true }
            return existing.priority < priority
        } ?? pendingQueue.endIndex

        pendingQueue.insert(jobId, at: insertIndex)
    }

    // MARK: - Testing Helpers

    /// The total number of jobs in storage (all statuses).
    public var totalJobCount: Int { jobs.count }

    /// The number of pending jobs in the queue.
    public var pendingCount: Int { pendingQueue.count }

    /// Clears all jobs from the queue.
    ///
    /// Useful for testing to reset state between tests.
    public func clear() {
        jobs.removeAll()
        pendingQueue.removeAll()
    }
}
