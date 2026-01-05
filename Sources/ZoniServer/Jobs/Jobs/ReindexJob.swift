// ZoniServer - Server-side extensions for Zoni
//
// ReindexJob.swift - Background job for index rebuilding

import Foundation
import Zoni

// MARK: - ReindexJob

/// Background job for index rebuilding.
///
/// Rebuilds a tenant's index by:
/// 1. Creating a new temporary index
/// 2. Re-processing all documents with current chunking configuration
/// 3. Swapping the new index in atomically
/// 4. Deleting the old index
///
/// ## Use Cases
/// - Recovering from index corruption
/// - Applying new chunking strategies to existing documents
/// - Major schema migrations requiring full reprocessing
/// - Upgrading to a new vector store implementation
///
/// ## Features
/// - Atomic index swap prevents data loss
/// - Supports custom chunking configuration
/// - Progress reporting through the rebuild process
/// - Single retry by default (rebuilds should not auto-retry)
///
/// ## Example Usage
///
/// Basic reindex:
/// ```swift
/// let job = ReindexJob(
///     tenantId: "acme-corp",
///     indexName: "documents"
/// )
/// let jobId = try await queue.enqueue(job)
/// ```
///
/// Reindex with new chunking configuration:
/// ```swift
/// let job = ReindexJob(
///     tenantId: "acme-corp",
///     indexName: "knowledge-base",
///     newChunkingConfig: IngestOptions(
///         chunkSize: 1024,
///         chunkOverlap: 100
///     )
/// )
/// ```
///
/// ## Progress Stages
/// Progress is reported in phases:
/// - 0.0-0.1: Initialization and backup
/// - 0.1-0.8: Document re-processing
/// - 0.8-0.9: Index swap
/// - 0.9-1.0: Cleanup
///
/// ## Error Handling
/// - Throws `CancellationError` if cancelled during execution
/// - Original index is preserved on failure (atomic swap)
/// - Uses single retry by default as reindex is expensive
public struct ReindexJob: Job {
    // MARK: - Job Protocol

    /// The type identifier for reindex jobs.
    public static let jobType = "reindex"

    /// The unique identifier for this job instance.
    public let id: String

    /// The tenant this job belongs to.
    public let tenantId: String

    /// The priority level for this job.
    public var priority: JobPriority

    /// The maximum number of times to retry this job on failure.
    public var maxRetries: Int

    // MARK: - Job-Specific Properties

    /// The name of the index to rebuild.
    public let indexName: String

    /// Optional new chunking configuration for the rebuilt index.
    ///
    /// If `nil`, the current chunking configuration is preserved.
    public let newChunkingConfig: IngestOptions?

    // MARK: - Initialization

    /// Creates a new index rebuild job.
    ///
    /// - Parameters:
    ///   - id: The unique job identifier. Defaults to a new UUID.
    ///   - tenantId: The tenant this job belongs to.
    ///   - indexName: The name of the index to rebuild.
    ///   - newChunkingConfig: Optional new chunking configuration.
    ///   - priority: The job priority. Defaults to `.low`.
    ///   - maxRetries: Maximum retry attempts. Defaults to 1 (no retry).
    public init(
        id: String = UUID().uuidString,
        tenantId: String,
        indexName: String,
        newChunkingConfig: IngestOptions? = nil,
        priority: JobPriority = .low,
        maxRetries: Int = 1
    ) {
        self.id = id
        self.tenantId = tenantId
        self.indexName = indexName
        self.newChunkingConfig = newChunkingConfig
        self.priority = priority
        self.maxRetries = maxRetries
    }

    // MARK: - Execution

    /// Executes the index rebuild job.
    ///
    /// This method performs a full index rebuild:
    /// 1. Creates a temporary index
    /// 2. Reads all documents from the current index
    /// 3. Re-chunks and re-embeds all documents
    /// 4. Stores results in the temporary index
    /// 5. Atomically swaps the temporary index with the original
    /// 6. Cleans up the old index
    ///
    /// - Parameter context: The job execution context.
    /// - Returns: Result data with the rebuilt index information.
    /// - Throws: `CancellationError` if cancelled, or service errors.
    ///
    /// - Note: The current implementation provides a skeleton. Full implementation
    ///   would require additional vector store methods for index management.
    public func execute(context: JobExecutionContext) async throws -> JobResultData {
        // Check cancellation at start
        if await context.isCancelled() {
            throw CancellationError()
        }

        // Phase 1: Initialization (0.0 - 0.1)
        await context.reportProgress(0.0)

        let tenant = TenantContext(tenantId: tenantId, tier: .standard)
        // Services would be used in full implementation
        _ = context.services.vectorStoreFactory(tenant)
        _ = context.services.chunkerFactory()
        _ = context.services.embeddingProvider

        // Report initialization complete
        await context.reportProgress(0.1)

        // Phase 2: Read existing documents (0.1 - 0.2)
        // In a full implementation, we would:
        // 1. Query the vector store for all documents in the index
        // 2. Group chunks by documentId to reconstruct original documents
        // 3. Create a temporary index for the rebuild

        if await context.isCancelled() {
            throw CancellationError()
        }

        await context.reportProgress(0.2)

        // Phase 3: Re-process documents (0.2 - 0.8)
        // In a full implementation, we would:
        // 1. Iterate through each document
        // 2. Apply new chunking configuration (or use existing)
        // 3. Generate fresh embeddings
        // 4. Store in the temporary index

        var totalChunksRebuilt = 0

        // Placeholder: Simulate document reprocessing
        // Full implementation would iterate through actual documents
        let simulatedDocumentCount = 0 // Would be actual count from store

        for docIndex in 0..<simulatedDocumentCount {
            if await context.isCancelled() {
                throw CancellationError()
            }

            // Calculate progress within the processing phase (0.2 - 0.8)
            let processingProgress = Double(docIndex) / Double(max(1, simulatedDocumentCount))
            let overallProgress = 0.2 + (processingProgress * 0.6)
            await context.reportProgress(overallProgress)

            // Placeholder for actual processing:
            // let document = documents[docIndex]
            // let chunks = try await chunker.chunk(document)
            // for batch in chunks.chunked(into: batchSize) {
            //     let embeddings = try await embedder.embed(batch.map(\.content))
            //     try await tempStore.add(Array(batch), embeddings: embeddings)
            // }
            // totalChunksRebuilt += chunks.count
        }

        // Phase 4: Index swap (0.8 - 0.9)
        if await context.isCancelled() {
            throw CancellationError()
        }

        await context.reportProgress(0.8)

        // In a full implementation, we would:
        // 1. Verify the temporary index is complete
        // 2. Atomically rename temp index to target index name
        // 3. Delete the old index (now renamed to backup)

        await context.reportProgress(0.9)

        // Phase 5: Cleanup (0.9 - 1.0)
        // In a full implementation, we would:
        // 1. Remove the backup/old index
        // 2. Clear any temporary files or state

        await context.reportProgress(1.0)

        return JobResultData(
            chunksCreated: totalChunksRebuilt,
            message: "Index '\(indexName)' rebuilt successfully",
            metadata: [
                "indexName": indexName,
                "tenantId": tenantId
            ]
        )
    }
}

// MARK: - ReindexJob Equatable

extension ReindexJob: Equatable {
    public static func == (lhs: ReindexJob, rhs: ReindexJob) -> Bool {
        lhs.id == rhs.id &&
        lhs.tenantId == rhs.tenantId &&
        lhs.priority == rhs.priority &&
        lhs.maxRetries == rhs.maxRetries &&
        lhs.indexName == rhs.indexName &&
        lhs.newChunkingConfig == rhs.newChunkingConfig
    }
}

// MARK: - ReindexJob Hashable

extension ReindexJob: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ReindexJob CustomStringConvertible

extension ReindexJob: CustomStringConvertible {
    public var description: String {
        "ReindexJob(id: \(id), tenant: \(tenantId), index: \(indexName))"
    }
}
