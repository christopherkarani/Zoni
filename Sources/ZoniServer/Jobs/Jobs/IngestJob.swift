// ZoniServer - Server-side extensions for Zoni
//
// IngestJob.swift - Background job for document ingestion

import Foundation
import Zoni

// MARK: - IngestJob

/// Background job for document ingestion.
///
/// Handles loading, chunking, embedding, and storing documents
/// asynchronously, reporting progress throughout. This job is designed
/// for bulk document processing that may take significant time.
///
/// ## Features
/// - Processes documents in batch with progress reporting
/// - Supports cancellation at document boundaries
/// - Embeds chunks in batches for efficiency
/// - Properly isolates data by tenant
///
/// ## Example Usage
///
/// ```swift
/// let job = IngestJob(
///     tenantId: "acme-corp",
///     documents: [
///         DocumentDTO(content: "...", source: "file.md"),
///         DocumentDTO(content: "...", source: "guide.txt")
///     ],
///     options: IngestOptions(chunkSize: 500)
/// )
///
/// let jobId = try await queue.enqueue(job)
/// ```
///
/// ## Progress Reporting
/// Progress is reported as the ratio of processed documents to total documents.
/// For example, after processing 3 of 10 documents, progress will be 0.3.
///
/// ## Error Handling
/// - Throws `CancellationError` if cancelled during execution
/// - Throws embedding or storage errors from underlying services
/// - Retries are handled by the job queue based on `maxRetries`
public struct IngestJob: Job {
    // MARK: - Job Protocol

    /// The type identifier for ingestion jobs.
    public static let jobType = "ingest"

    /// The unique identifier for this job instance.
    public let id: String

    /// The tenant this job belongs to.
    public let tenantId: String

    /// The priority level for this job.
    public var priority: JobPriority

    /// The maximum number of times to retry this job on failure.
    public var maxRetries: Int

    // MARK: - Job-Specific Properties

    /// The documents to ingest.
    public let documents: [DocumentDTO]

    /// Optional ingestion configuration.
    public let options: IngestOptions?

    // MARK: - Initialization

    /// Creates a new document ingestion job.
    ///
    /// - Parameters:
    ///   - id: The unique job identifier. Defaults to a new UUID.
    ///   - tenantId: The tenant this job belongs to.
    ///   - documents: The documents to ingest.
    ///   - options: Optional ingestion configuration.
    ///   - priority: The job priority. Defaults to `.normal`.
    ///   - maxRetries: Maximum retry attempts. Defaults to 3.
    public init(
        id: String = UUID().uuidString,
        tenantId: String,
        documents: [DocumentDTO],
        options: IngestOptions? = nil,
        priority: JobPriority = .normal,
        maxRetries: Int = 3
    ) {
        self.id = id
        self.tenantId = tenantId
        self.documents = documents
        self.options = options
        self.priority = priority
        self.maxRetries = maxRetries
    }

    // MARK: - Execution

    /// Executes the document ingestion job.
    ///
    /// This method:
    /// 1. Iterates through each document
    /// 2. Converts DTOs to Document instances
    /// 3. Chunks each document using the configured chunker
    /// 4. Generates embeddings in batches
    /// 5. Stores chunks with embeddings in the vector store
    ///
    /// - Parameter context: The job execution context.
    /// - Returns: Result data containing document IDs and chunk counts.
    /// - Throws: `CancellationError` if cancelled, or service errors.
    public func execute(context: JobExecutionContext) async throws -> JobResultData {
        let tenant = TenantContext(tenantId: tenantId, tier: .standard)
        let vectorStore = context.services.vectorStoreFactory(tenant)
        let chunker = context.services.chunkerFactory()
        let embedder = context.services.embeddingProvider

        var allDocumentIds: [String] = []
        var totalChunks = 0

        for (index, docDTO) in documents.enumerated() {
            // Check cancellation before processing each document
            if await context.isCancelled() {
                throw CancellationError()
            }

            // Report progress based on document count
            let progress = Double(index) / Double(documents.count)
            await context.reportProgress(progress)

            // Convert DTO to Document with a new ID
            let documentId = UUID().uuidString
            let document = docDTO.toDocument(id: documentId)
            allDocumentIds.append(documentId)

            // Chunk the document
            let chunks = try await chunker.chunk(document)

            // Embed chunks in batches for efficiency
            let batchSize = min(embedder.optimalBatchSize, 50)
            for batch in chunks.chunked(into: batchSize) {
                // Check cancellation between batches
                if await context.isCancelled() {
                    throw CancellationError()
                }

                let texts = batch.map(\.content)
                let embeddings = try await embedder.embed(texts)
                try await vectorStore.add(batch, embeddings: embeddings)
            }

            totalChunks += chunks.count
        }

        // Report completion
        await context.reportProgress(1.0)

        return JobResultData(
            documentIds: allDocumentIds,
            chunksCreated: totalChunks,
            message: "Successfully ingested \(documents.count) documents"
        )
    }
}

// MARK: - IngestJob Equatable

extension IngestJob: Equatable {
    public static func == (lhs: IngestJob, rhs: IngestJob) -> Bool {
        lhs.id == rhs.id &&
        lhs.tenantId == rhs.tenantId &&
        lhs.priority == rhs.priority &&
        lhs.maxRetries == rhs.maxRetries &&
        lhs.documents == rhs.documents &&
        lhs.options == rhs.options
    }
}

// MARK: - IngestJob Hashable

extension IngestJob: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - IngestJob CustomStringConvertible

extension IngestJob: CustomStringConvertible {
    public var description: String {
        "IngestJob(id: \(id), tenant: \(tenantId), documents: \(documents.count))"
    }
}
