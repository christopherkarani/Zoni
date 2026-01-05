// ZoniServer - Server-side extensions for Zoni
//
// JobExecutor.swift - Background job execution engine.
//
// This file defines the JobExecutor actor that processes jobs from a queue,
// handling concurrent execution, retries, progress updates, and graceful shutdown.

import Foundation
import Logging

// MARK: - JobExecutor

/// Actor that executes background jobs from a queue.
///
/// The executor polls the queue for jobs and executes them concurrently
/// up to a configurable limit. It handles retries, progress updates,
/// and graceful shutdown.
///
/// ## Example Usage
///
/// ```swift
/// let queue = InMemoryJobQueue()
/// let executor = JobExecutor(
///     queue: queue,
///     services: services,
///     maxConcurrentJobs: 4
/// )
///
/// // Start processing in the background
/// Task { await executor.start() }
///
/// // Later, shut down gracefully
/// await executor.stop()
/// ```
///
/// ## Concurrency
///
/// The executor runs as an actor, ensuring thread-safe access to its state.
/// Jobs are executed in separate tasks, allowing concurrent processing
/// up to the `maxConcurrentJobs` limit.
///
/// ## Retry Behavior
///
/// Failed jobs are automatically retried up to their `maxRetries` limit.
/// Each retry is enqueued as a new attempt with an incremented retry count.
///
/// ## Cancellation
///
/// Jobs can be cancelled via `cancelJob(_:)`. Cancelled jobs receive a
/// `CancellationError` and are marked with `.cancelled` status.
public actor JobExecutor {

    // MARK: - Properties

    /// The queue backend to pull jobs from.
    private let queue: any JobQueueBackend

    /// Services available to jobs during execution.
    private let services: JobServices

    /// Maximum number of jobs to execute concurrently.
    private let maxConcurrentJobs: Int

    /// How often to poll the queue for new jobs.
    private let pollInterval: Duration

    /// IDs of jobs currently being executed.
    private var runningJobs: Set<String> = []

    /// IDs of jobs that have been marked for cancellation.
    private var cancelledJobs: Set<String> = []

    /// Whether the executor is currently running.
    private var isRunning = false

    /// The background task running the processing loop.
    private var processingTask: Task<Void, Never>?

    /// Logger for structured logging of job execution events.
    private let logger = Logger(label: "com.zoni.jobexecutor")

    // MARK: - Initialization

    /// Creates a new job executor.
    ///
    /// - Parameters:
    ///   - queue: The queue backend to pull jobs from.
    ///   - services: Services available to jobs during execution.
    ///   - maxConcurrentJobs: Maximum concurrent jobs. Defaults to 4.
    ///   - pollInterval: How often to poll for jobs. Defaults to 1 second.
    public init(
        queue: any JobQueueBackend,
        services: JobServices,
        maxConcurrentJobs: Int = 4,
        pollInterval: Duration = .seconds(1)
    ) {
        self.queue = queue
        self.services = services
        self.maxConcurrentJobs = maxConcurrentJobs
        self.pollInterval = pollInterval
    }

    // MARK: - Lifecycle

    /// Starts processing jobs from the queue.
    ///
    /// This method returns immediately after starting the background
    /// processing loop. Call `stop()` to shut down gracefully.
    ///
    /// If the executor is already running, this method does nothing.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true

        processingTask = Task {
            await processLoop()
        }
    }

    /// Stops processing and waits for running jobs to complete.
    ///
    /// This method blocks until all currently running jobs finish
    /// or a 30-second timeout is reached.
    ///
    /// After calling `stop()`, the executor can be restarted with `start()`.
    public func stop() async {
        isRunning = false
        processingTask?.cancel()

        // Wait for running jobs to finish (with timeout)
        let deadline = ContinuousClock.now + .seconds(30)
        while !runningJobs.isEmpty && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Cancels a specific job.
    ///
    /// If the job is pending, it is removed from the queue.
    /// If the job is running, it is marked for cancellation and will
    /// receive a `CancellationError` at the next cancellation check point.
    ///
    /// - Parameter jobId: The ID of the job to cancel.
    public func cancelJob(_ jobId: String) async {
        cancelledJobs.insert(jobId)
        _ = try? await queue.cancel(jobId)
    }

    // MARK: - Processing Loop

    /// The main processing loop that polls for and executes jobs.
    private func processLoop() async {
        while isRunning {
            // Check if we can take more jobs
            if runningJobs.count < maxConcurrentJobs {
                do {
                    if let record = try await queue.dequeue() {
                        runningJobs.insert(record.id)

                        Task {
                            await executeJob(record)
                            await removeFromRunning(record.id)
                        }
                    }
                } catch {
                    // Log error, continue processing
                    // In production, consider logging to a proper logging service
                }
            }

            try? await Task.sleep(for: pollInterval)
        }
    }

    /// Removes a job ID from the running set.
    ///
    /// This is a separate method to allow calling from a detached task.
    private func removeFromRunning(_ jobId: String) {
        runningJobs.remove(jobId)
    }

    // MARK: - Job Execution

    /// Executes a single job.
    ///
    /// - Parameter record: The job record to execute.
    private func executeJob(_ record: JobRecord) async {
        do {
            // Deserialize job
            let job = try await JobRegistry.shared.deserialize(record)

            // Capture cancellation state synchronously to avoid actor re-entrancy
            let isCancelledClosure: @Sendable () -> Bool = { [cancelledJobs] in
                // Capture the current cancelled state synchronously
                cancelledJobs.contains(record.id)
            }

            // Create execution context
            let context = JobExecutionContext(
                jobId: record.id,
                tenantId: record.tenantId,
                services: services,
                reportProgress: { [queue, logger] progress in
                    // Progress updates are best-effort - log failures but don't fail the job
                    do {
                        try await queue.updateProgress(record.id, progress: progress)
                    } catch {
                        logger.warning(
                            "Failed to update progress for job",
                            metadata: [
                                "jobId": .string(record.id),
                                "progress": .stringConvertible(progress),
                                "error": .string(error.localizedDescription)
                            ]
                        )
                    }
                },
                isCancelled: isCancelledClosure
            )

            // Execute
            let result = try await job.execute(context: context)

            // Store result
            try await queue.storeResult(record.id, result: result)
            try await queue.updateStatus(record.id, status: .completed)

        } catch is CancellationError {
            try? await queue.updateStatus(record.id, status: .cancelled)
        } catch {
            await handleJobError(record: record, error: error)
        }

        // Clean up cancellation tracking
        await removeCancelledJob(record.id)
    }

    /// Checks if a job has been cancelled.
    ///
    /// - Parameter jobId: The job ID to check.
    /// - Returns: `true` if the job has been cancelled.
    private func isJobCancelled(_ jobId: String) -> Bool {
        cancelledJobs.contains(jobId)
    }

    /// Removes a job from the cancelled set.
    ///
    /// - Parameter jobId: The job ID to remove.
    private func removeCancelledJob(_ jobId: String) {
        cancelledJobs.remove(jobId)
    }

    /// Handles a job execution error.
    ///
    /// If retries are available, the job is re-enqueued with an incremented
    /// retry count. Otherwise, the error is stored and the job is marked as failed.
    ///
    /// - Parameters:
    ///   - record: The job record that failed.
    ///   - error: The error that occurred.
    private func handleJobError(record: JobRecord, error: Error) async {
        // Check retry count
        if record.retryCount < record.maxRetries {
            // Increment retry count and re-enqueue the job
            let newRetryCount = record.retryCount + 1
            try? await queue.updateRetryCount(record.id, retryCount: newRetryCount)
        } else {
            // Max retries exceeded - mark as permanently failed
            try? await queue.storeError(record.id, error: error.localizedDescription)
            try? await queue.updateStatus(record.id, status: .failed)
        }
    }

    // MARK: - Status

    /// The number of jobs currently being executed.
    public var runningJobCount: Int {
        runningJobs.count
    }

    /// Whether the executor is currently processing jobs.
    public var isProcessing: Bool {
        isRunning
    }
}
