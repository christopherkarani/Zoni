// ZoniServer - Server-side extensions for Zoni
//
// JobProtocols.swift - Core protocols and types for the background job system.
//
// This file defines the foundational abstractions for asynchronous job processing,
// including job priorities, records, execution context, and queue backend protocols.

import Foundation
import Zoni

// MARK: - Job Priority

/// Priority level for background jobs.
///
/// Higher priority jobs are dequeued before lower priority ones.
/// Jobs with the same priority are processed in FIFO order.
///
/// ## Usage
/// ```swift
/// let importantJob = MyJob(priority: .high)
/// let backgroundJob = MyJob(priority: .low)
/// ```
public enum JobPriority: Int, Sendable, Codable, Comparable, CaseIterable {
    /// Low priority for non-urgent background tasks.
    ///
    /// Use for maintenance tasks, analytics, or operations that can wait.
    case low = 0

    /// Normal priority for standard operations.
    ///
    /// This is the default priority for most jobs.
    case normal = 1

    /// High priority for time-sensitive operations.
    ///
    /// Use for user-initiated tasks that should complete quickly.
    case high = 2

    /// Critical priority for urgent operations.
    ///
    /// Use sparingly for operations that must complete as soon as possible.
    case critical = 3

    public static func < (lhs: JobPriority, rhs: JobPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Job Record

/// Persistent record of a job in the queue.
///
/// This struct represents the serializable state of a job,
/// suitable for storage in a database or cache. It contains all
/// information needed to track, execute, and report on a job.
///
/// ## Example
/// ```swift
/// let record = JobRecord(
///     jobType: "document-ingestion",
///     tenantId: "tenant_123",
///     priority: .high,
///     payload: try JSONEncoder().encode(myJob)
/// )
/// ```
public struct JobRecord: Sendable, Codable, Equatable, Identifiable {

    // MARK: - Properties

    /// The unique identifier for this job.
    public let id: String

    /// The type identifier of the job class.
    ///
    /// This must match the `jobType` of the `Job` implementation
    /// to enable proper deserialization.
    public let jobType: String

    /// The tenant that owns this job.
    public let tenantId: String

    /// The execution priority of this job.
    public let priority: JobPriority

    /// The current status of the job.
    public var status: JobStatus

    /// The progress percentage (0.0 to 1.0).
    public var progress: Double

    /// The serialized job payload.
    ///
    /// This contains the full job data encoded as JSON.
    public var payload: Data

    /// The serialized result data, if the job completed successfully.
    public var result: Data?

    /// The error message, if the job failed.
    public var error: String?

    /// The timestamp when the job was created.
    public let createdAt: Date

    /// The timestamp when the job started executing.
    public var startedAt: Date?

    /// The timestamp when the job completed (successfully or with failure).
    public var completedAt: Date?

    /// The number of retry attempts made for this job.
    public var retryCount: Int

    /// The maximum number of retry attempts allowed.
    public let maxRetries: Int

    // MARK: - Initialization

    /// Creates a new job record.
    ///
    /// - Parameters:
    ///   - id: The unique identifier. Defaults to a new UUID string.
    ///   - jobType: The type identifier of the job class.
    ///   - tenantId: The tenant that owns this job.
    ///   - priority: The execution priority. Defaults to `.normal`.
    ///   - payload: The serialized job data.
    ///   - maxRetries: Maximum retry attempts. Defaults to `3`.
    public init(
        id: String = UUID().uuidString,
        jobType: String,
        tenantId: String,
        priority: JobPriority = .normal,
        payload: Data,
        maxRetries: Int = 3
    ) {
        self.id = id
        self.jobType = jobType
        self.tenantId = tenantId
        self.priority = priority
        self.status = .pending
        self.progress = 0.0
        self.payload = payload
        self.result = nil
        self.error = nil
        self.createdAt = Date()
        self.startedAt = nil
        self.completedAt = nil
        self.retryCount = 0
        self.maxRetries = maxRetries
    }
}

// MARK: - Job Execution Context

/// Context provided to jobs during execution.
///
/// Contains services and utilities needed by jobs to perform their work,
/// including progress reporting and cancellation checking.
///
/// ## Example
/// ```swift
/// func execute(context: JobExecutionContext) async throws -> JobResultData {
///     for (index, item) in items.enumerated() {
///         // Check for cancellation
///         if await context.isCancelled() {
///             throw CancellationError()
///         }
///
///         // Process item
///         try await process(item)
///
///         // Report progress
///         let progress = Double(index + 1) / Double(items.count)
///         await context.reportProgress(progress)
///     }
///     return JobResultData(message: "Processed \(items.count) items")
/// }
/// ```
public struct JobExecutionContext: Sendable {

    /// The unique identifier of the job being executed.
    public let jobId: String

    /// The tenant that owns this job.
    public let tenantId: String

    /// Services available for job execution.
    public let services: JobServices

    /// Callback to report progress (0.0 to 1.0).
    ///
    /// Call this periodically to update the job's progress in the queue.
    /// Progress values are clamped to the range [0.0, 1.0].
    public let reportProgress: @Sendable (Double) async -> Void

    /// Check if the job has been cancelled.
    ///
    /// Jobs should check this periodically and stop execution gracefully
    /// if cancellation is requested.
    public let isCancelled: @Sendable () async -> Bool

    /// Creates a new job execution context.
    ///
    /// - Parameters:
    ///   - jobId: The unique identifier of the job.
    ///   - tenantId: The tenant that owns this job.
    ///   - services: Services available for job execution.
    ///   - reportProgress: Callback to report progress.
    ///   - isCancelled: Callback to check cancellation status.
    public init(
        jobId: String,
        tenantId: String,
        services: JobServices,
        reportProgress: @escaping @Sendable (Double) async -> Void,
        isCancelled: @escaping @Sendable () async -> Bool
    ) {
        self.jobId = jobId
        self.tenantId = tenantId
        self.services = services
        self.reportProgress = reportProgress
        self.isCancelled = isCancelled
    }
}

// MARK: - Job Services

/// Services available to jobs during execution.
///
/// Provides access to the core components needed for RAG operations,
/// including embedding generation, vector storage, chunking, and document loading.
public struct JobServices: Sendable {

    /// The embedding provider for generating vector embeddings.
    public let embeddingProvider: any EmbeddingProvider

    /// Factory for creating vector stores for a specific tenant.
    public let vectorStoreFactory: @Sendable (TenantContext) -> any VectorStore

    /// Factory for creating chunking strategies.
    public let chunkerFactory: @Sendable () -> any ChunkingStrategy

    /// Factory for creating document loaders based on file extension.
    ///
    /// - Parameter extension: The file extension (e.g., "pdf", "txt", "md").
    /// - Returns: A document loader for the extension, or `nil` if unsupported.
    public let documentLoaderFactory: @Sendable (String) -> (any DocumentLoader)?

    /// Creates a new job services container.
    ///
    /// - Parameters:
    ///   - embeddingProvider: The embedding provider.
    ///   - vectorStoreFactory: Factory for creating vector stores.
    ///   - chunkerFactory: Factory for creating chunking strategies.
    ///   - documentLoaderFactory: Factory for creating document loaders.
    public init(
        embeddingProvider: any EmbeddingProvider,
        vectorStoreFactory: @escaping @Sendable (TenantContext) -> any VectorStore,
        chunkerFactory: @escaping @Sendable () -> any ChunkingStrategy,
        documentLoaderFactory: @escaping @Sendable (String) -> (any DocumentLoader)?
    ) {
        self.embeddingProvider = embeddingProvider
        self.vectorStoreFactory = vectorStoreFactory
        self.chunkerFactory = chunkerFactory
        self.documentLoaderFactory = documentLoaderFactory
    }
}

// MARK: - Job Protocol

/// Protocol for background jobs that can be queued and executed.
///
/// Jobs must be codable for persistence and sendable for concurrent execution.
/// Implement this protocol to create custom job types for asynchronous processing.
///
/// ## Implementing a Job
///
/// ```swift
/// public struct DocumentIngestionJob: Job {
///     public static let jobType = "document-ingestion"
///
///     public let id: String
///     public let tenantId: String
///     public var priority: JobPriority = .normal
///     public var maxRetries: Int = 3
///
///     public let documentId: String
///     public let content: String
///
///     public func execute(context: JobExecutionContext) async throws -> JobResultData {
///         // Load and chunk document
///         await context.reportProgress(0.2)
///
///         // Generate embeddings
///         await context.reportProgress(0.5)
///
///         // Store in vector database
///         await context.reportProgress(0.9)
///
///         return JobResultData(
///             documentIds: [documentId],
///             chunksCreated: 10,
///             message: "Successfully ingested document"
///         )
///     }
/// }
/// ```
///
/// ## Thread Safety
/// All `Job` implementations must be `Sendable` to ensure safe concurrent access.
public protocol Job: Sendable, Codable {

    /// Unique type identifier for this job class.
    ///
    /// This identifier is used for serialization and deserialization of jobs.
    /// It must be unique across all registered job types.
    static var jobType: String { get }

    /// Unique identifier for this job instance.
    var id: String { get }

    /// Tenant that owns this job.
    var tenantId: String { get }

    /// Execution priority.
    var priority: JobPriority { get }

    /// Maximum retry attempts on failure.
    ///
    /// If a job fails, it will be retried up to this many times
    /// before being marked as permanently failed.
    var maxRetries: Int { get }

    /// Execute the job.
    ///
    /// Implement this method to perform the actual work of the job.
    /// Use the context to report progress and check for cancellation.
    ///
    /// - Parameter context: Execution context with services and progress reporting.
    /// - Returns: Result data upon successful completion.
    /// - Throws: Any error encountered during execution.
    func execute(context: JobExecutionContext) async throws -> JobResultData
}

// MARK: - Job Result

/// Data returned upon successful job completion.
///
/// This struct captures the outcome of a job execution, including
/// any created resources and informational messages.
public struct JobResultData: Sendable, Codable, Equatable {

    /// The IDs of documents created or processed by the job.
    public var documentIds: [String]?

    /// The number of chunks created by the job.
    public var chunksCreated: Int?

    /// The number of chunks deleted by the job.
    public var chunksDeleted: Int?

    /// An optional human-readable message describing the result.
    public var message: String?

    /// Additional metadata about the job result.
    public var metadata: [String: String]?

    /// Creates a new job result.
    ///
    /// - Parameters:
    ///   - documentIds: Document IDs created or processed.
    ///   - chunksCreated: Number of chunks created.
    ///   - chunksDeleted: Number of chunks deleted.
    ///   - message: Human-readable result message.
    ///   - metadata: Additional metadata.
    public init(
        documentIds: [String]? = nil,
        chunksCreated: Int? = nil,
        chunksDeleted: Int? = nil,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.documentIds = documentIds
        self.chunksCreated = chunksCreated
        self.chunksDeleted = chunksDeleted
        self.message = message
        self.metadata = metadata
    }
}

// MARK: - Job Queue Backend Protocol

/// Protocol for job queue storage backends.
///
/// Implementations persist and manage job records, supporting
/// operations like enqueue, dequeue, and status updates.
/// This abstraction allows different storage backends such as
/// in-memory, Redis, or PostgreSQL.
///
/// ## Thread Safety
/// All implementations must be `Sendable` and safe to use from any actor context.
/// Operations should be atomic where appropriate to prevent race conditions.
///
/// ## Example Implementation
/// ```swift
/// actor InMemoryJobQueue: JobQueueBackend {
///     private var jobs: [String: JobRecord] = [:]
///
///     func enqueue(_ job: any Job) async throws -> String {
///         let payload = try JSONEncoder().encode(job)
///         let record = JobRecord(
///             id: job.id,
///             jobType: type(of: job).jobType,
///             tenantId: job.tenantId,
///             priority: job.priority,
///             payload: payload,
///             maxRetries: job.maxRetries
///         )
///         jobs[record.id] = record
///         return record.id
///     }
///
///     func dequeue() async throws -> JobRecord? {
///         // Return highest priority pending job
///         let pending = jobs.values
///             .filter { $0.status == .pending }
///             .sorted { $0.priority > $1.priority }
///
///         guard var record = pending.first else { return nil }
///         record.status = .running
///         record.startedAt = Date()
///         jobs[record.id] = record
///         return record
///     }
///     // ... other methods
/// }
/// ```
public protocol JobQueueBackend: Sendable {

    /// Enqueue a new job.
    ///
    /// Serializes the job and stores it in the queue with pending status.
    ///
    /// - Parameter job: The job to enqueue.
    /// - Returns: The job ID.
    /// - Throws: An error if serialization or storage fails.
    func enqueue(_ job: any Job) async throws -> String

    /// Dequeue the next available job.
    ///
    /// Returns the highest priority pending job and marks it as running.
    /// This operation should be atomic to prevent the same job from
    /// being dequeued by multiple workers.
    ///
    /// - Returns: The next job record, or `nil` if the queue is empty.
    /// - Throws: An error if the operation fails.
    func dequeue() async throws -> JobRecord?

    /// Update job status.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - status: The new status.
    /// - Throws: `ZoniServerError.jobNotFound` if the job does not exist.
    func updateStatus(_ jobId: String, status: JobStatus) async throws

    /// Update job progress.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - progress: The progress value (0.0 to 1.0).
    /// - Throws: `ZoniServerError.jobNotFound` if the job does not exist.
    func updateProgress(_ jobId: String, progress: Double) async throws

    /// Update job retry count and status for retry attempts.
    ///
    /// This method increments the retry count and resets the job to pending status
    /// so it can be picked up again by the executor.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - retryCount: The new retry count value.
    /// - Throws: `ZoniServerError.jobNotFound` if the job does not exist.
    func updateRetryCount(_ jobId: String, retryCount: Int) async throws

    /// Store job result upon completion.
    ///
    /// This also updates the job status to `.completed` and sets `completedAt`.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - result: The result data.
    /// - Throws: `ZoniServerError.jobNotFound` if the job does not exist.
    func storeResult(_ jobId: String, result: JobResultData) async throws

    /// Store job error upon failure.
    ///
    /// This also updates the job status to `.failed` and sets `completedAt`.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - error: The error message.
    /// - Throws: `ZoniServerError.jobNotFound` if the job does not exist.
    func storeError(_ jobId: String, error: String) async throws

    /// Get a job by ID.
    ///
    /// - Parameter jobId: The job identifier.
    /// - Returns: The job record, or `nil` if not found.
    /// - Throws: An error if the operation fails.
    func getJob(_ jobId: String) async throws -> JobRecord?

    /// List jobs for a tenant.
    ///
    /// - Parameters:
    ///   - tenantId: The tenant identifier.
    ///   - status: Optional status filter. If `nil`, returns jobs of all statuses.
    ///   - limit: Maximum number of jobs to return.
    /// - Returns: An array of job records, sorted by creation time (newest first).
    /// - Throws: An error if the operation fails.
    func listJobs(
        tenantId: String,
        status: JobStatus?,
        limit: Int
    ) async throws -> [JobRecord]

    /// Cancel a pending or running job.
    ///
    /// Only jobs with status `.pending` or `.running` can be cancelled.
    /// Jobs that are already completed or failed cannot be cancelled.
    ///
    /// - Parameter jobId: The job identifier.
    /// - Returns: `true` if the job was cancelled, `false` if it could not be cancelled.
    /// - Throws: `ZoniServerError.jobNotFound` if the job does not exist.
    func cancel(_ jobId: String) async throws -> Bool

    /// Delete completed/failed jobs older than a date.
    ///
    /// Use this for periodic cleanup of old job records.
    ///
    /// - Parameter date: Jobs completed before this date will be deleted.
    /// - Returns: The number of jobs deleted.
    /// - Throws: An error if the operation fails.
    func pruneOldJobs(before date: Date) async throws -> Int
}

// MARK: - Job Registry

/// Registry for job type deserialization.
///
/// Allows the system to deserialize job payloads into the correct types
/// by maintaining a mapping of job type identifiers to factory functions.
///
/// ## Usage
///
/// Register job types at application startup:
/// ```swift
/// await JobRegistry.shared.register(DocumentIngestionJob.self)
/// await JobRegistry.shared.register(DocumentDeletionJob.self)
/// ```
///
/// Deserialize jobs from records:
/// ```swift
/// let job = try await JobRegistry.shared.deserialize(record)
/// ```
public actor JobRegistry {

    /// The shared job registry instance.
    public static let shared = JobRegistry()

    /// Factory functions keyed by job type.
    private var factories: [String: (Data) throws -> any Job] = [:]

    private init() {}

    /// Register a job type.
    ///
    /// Call this method for each job type at application startup.
    ///
    /// - Parameter type: The job type to register.
    public func register<T: Job>(_ type: T.Type) {
        factories[T.jobType] = { data in
            try JSONDecoder().decode(T.self, from: data)
        }
    }

    /// Deserialize a job from its record.
    ///
    /// - Parameter record: The job record to deserialize.
    /// - Returns: The deserialized job instance.
    /// - Throws: `ZoniServerError.jobFailed` if the job type is unknown
    ///   or deserialization fails.
    public func deserialize(_ record: JobRecord) throws -> any Job {
        guard let factory = factories[record.jobType] else {
            throw ZoniServerError.jobFailed(
                jobId: record.id,
                reason: "Unknown job type: \(record.jobType)"
            )
        }
        return try factory(record.payload)
    }

    /// Check if a job type is registered.
    ///
    /// - Parameter jobType: The job type identifier to check.
    /// - Returns: `true` if the job type is registered.
    public func isRegistered(_ jobType: String) -> Bool {
        factories[jobType] != nil
    }

    /// Get all registered job types.
    ///
    /// - Returns: An array of registered job type identifiers.
    public func registeredTypes() -> [String] {
        Array(factories.keys)
    }
}
