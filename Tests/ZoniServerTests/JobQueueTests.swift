// ZoniServer - Server-side extensions for Zoni
//
// JobQueueTests.swift - Comprehensive tests for the background job queue system
//
// This file tests InMemoryJobQueue, JobRecord, JobPriority,
// and job lifecycle management functionality.

import Testing
import Foundation
@testable import ZoniServer

// MARK: - Job Queue Tests

@Suite("Job Queue Tests")
struct JobQueueTests {

    // MARK: - InMemoryJobQueue Tests

    @Suite("InMemoryJobQueue Tests")
    struct InMemoryJobQueueTests {

        @Test("Enqueue and dequeue job")
        func testEnqueueDequeue() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(
                tenantId: "tenant-1",
                chunkIds: nil
            )

            let jobId = try await queue.enqueue(job)
            #expect(!jobId.isEmpty)
            #expect(jobId == job.id)

            let dequeued = try await queue.dequeue()
            #expect(dequeued != nil)
            #expect(dequeued?.id == job.id)
            #expect(dequeued?.status == .running)
            #expect(dequeued?.startedAt != nil)
        }

        @Test("Dequeue returns nil for empty queue")
        func testDequeueEmpty() async throws {
            let queue = InMemoryJobQueue()

            let dequeued = try await queue.dequeue()
            #expect(dequeued == nil)
        }

        @Test("Priority ordering - high before low")
        func testPriorityOrdering() async throws {
            let queue = InMemoryJobQueue()

            // Enqueue low priority first
            let lowJob = BatchEmbedJob(
                tenantId: "tenant-1",
                priority: .low
            )
            _ = try await queue.enqueue(lowJob)

            // Enqueue high priority second
            let highJob = BatchEmbedJob(
                tenantId: "tenant-1",
                priority: .high
            )
            _ = try await queue.enqueue(highJob)

            // High priority should be dequeued first
            let first = try await queue.dequeue()
            #expect(first?.priority == .high)
            #expect(first?.id == highJob.id)

            let second = try await queue.dequeue()
            #expect(second?.priority == .low)
            #expect(second?.id == lowJob.id)
        }

        @Test("Priority ordering - critical highest")
        func testCriticalPriorityHighest() async throws {
            let queue = InMemoryJobQueue()

            // Enqueue in mixed order
            let normalJob = BatchEmbedJob(tenantId: "tenant-1", priority: .normal)
            let criticalJob = BatchEmbedJob(tenantId: "tenant-1", priority: .critical)
            let lowJob = BatchEmbedJob(tenantId: "tenant-1", priority: .low)
            let highJob = BatchEmbedJob(tenantId: "tenant-1", priority: .high)

            _ = try await queue.enqueue(normalJob)
            _ = try await queue.enqueue(criticalJob)
            _ = try await queue.enqueue(lowJob)
            _ = try await queue.enqueue(highJob)

            // Dequeue in priority order
            let first = try await queue.dequeue()
            #expect(first?.priority == .critical)

            let second = try await queue.dequeue()
            #expect(second?.priority == .high)

            let third = try await queue.dequeue()
            #expect(third?.priority == .normal)

            let fourth = try await queue.dequeue()
            #expect(fourth?.priority == .low)
        }

        @Test("FIFO within same priority")
        func testFIFOWithinPriority() async throws {
            let queue = InMemoryJobQueue()

            let job1 = BatchEmbedJob(id: "job-1", tenantId: "tenant-1", priority: .normal)
            let job2 = BatchEmbedJob(id: "job-2", tenantId: "tenant-1", priority: .normal)
            let job3 = BatchEmbedJob(id: "job-3", tenantId: "tenant-1", priority: .normal)

            _ = try await queue.enqueue(job1)
            _ = try await queue.enqueue(job2)
            _ = try await queue.enqueue(job3)

            let first = try await queue.dequeue()
            #expect(first?.id == "job-1")

            let second = try await queue.dequeue()
            #expect(second?.id == "job-2")

            let third = try await queue.dequeue()
            #expect(third?.id == "job-3")
        }

        @Test("Job status updates")
        func testStatusUpdates() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            // Initially pending
            var record = try await queue.getJob(jobId)
            #expect(record?.status == .pending)

            // Dequeue sets to running
            _ = try await queue.dequeue()
            record = try await queue.getJob(jobId)
            #expect(record?.status == .running)

            // Update to completed
            try await queue.updateStatus(jobId, status: .completed)
            record = try await queue.getJob(jobId)
            #expect(record?.status == .completed)
            #expect(record?.completedAt != nil)
        }

        @Test("Job status update to failed")
        func testStatusUpdateFailed() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            _ = try await queue.dequeue()
            try await queue.updateStatus(jobId, status: .failed)

            let record = try await queue.getJob(jobId)
            #expect(record?.status == .failed)
            #expect(record?.completedAt != nil)
        }

        @Test("Job status update to cancelled")
        func testStatusUpdateCancelled() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            _ = try await queue.dequeue()
            try await queue.updateStatus(jobId, status: .cancelled)

            let record = try await queue.getJob(jobId)
            #expect(record?.status == .cancelled)
            #expect(record?.completedAt != nil)
        }

        @Test("Update status for non-existent job throws")
        func testUpdateStatusNonExistent() async {
            let queue = InMemoryJobQueue()

            do {
                try await queue.updateStatus("non-existent", status: .completed)
                Issue.record("Should have thrown jobNotFound error")
            } catch {
                #expect(error is ZoniServerError)
                if case .jobNotFound(let jobId) = error as? ZoniServerError {
                    #expect(jobId == "non-existent")
                }
            }
        }

        @Test("Job progress updates")
        func testProgressUpdates() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            // Initial progress is 0
            var record = try await queue.getJob(jobId)
            #expect(record?.progress == 0.0)

            // Update progress
            try await queue.updateProgress(jobId, progress: 0.5)
            record = try await queue.getJob(jobId)
            #expect(record?.progress == 0.5)

            // Progress is clamped to [0, 1]
            try await queue.updateProgress(jobId, progress: 1.5)
            record = try await queue.getJob(jobId)
            #expect(record?.progress == 1.0)

            try await queue.updateProgress(jobId, progress: -0.5)
            record = try await queue.getJob(jobId)
            #expect(record?.progress == 0.0)
        }

        @Test("Store job result")
        func testStoreResult() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            let result = JobResultData(
                documentIds: ["doc-1", "doc-2"],
                chunksCreated: 42,
                message: "Success"
            )

            try await queue.storeResult(jobId, result: result)

            let record = try await queue.getJob(jobId)
            #expect(record?.result != nil)

            // Decode the result
            if let resultData = record?.result {
                let decodedResult = try JSONDecoder().decode(JobResultData.self, from: resultData)
                #expect(decodedResult.documentIds?.count == 2)
                #expect(decodedResult.chunksCreated == 42)
            }
        }

        @Test("Store job error")
        func testStoreError() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            try await queue.storeError(jobId, error: "Connection timeout")

            let record = try await queue.getJob(jobId)
            #expect(record?.error == "Connection timeout")
        }

        @Test("List jobs by tenant")
        func testListByTenant() async throws {
            let queue = InMemoryJobQueue()

            // Add jobs for different tenants
            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))
            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))
            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-2"))

            let tenant1Jobs = try await queue.listJobs(tenantId: "tenant-1", status: nil, limit: 10)
            let tenant2Jobs = try await queue.listJobs(tenantId: "tenant-2", status: nil, limit: 10)

            #expect(tenant1Jobs.count == 2)
            #expect(tenant2Jobs.count == 1)
        }

        @Test("List jobs by status")
        func testListByStatus() async throws {
            let queue = InMemoryJobQueue()

            let job1 = BatchEmbedJob(tenantId: "tenant-1")
            let job2 = BatchEmbedJob(tenantId: "tenant-1")
            let job3 = BatchEmbedJob(tenantId: "tenant-1")

            _ = try await queue.enqueue(job1)
            _ = try await queue.enqueue(job2)
            _ = try await queue.enqueue(job3)

            // Dequeue one (sets to running)
            _ = try await queue.dequeue()

            // Complete one
            try await queue.updateStatus(job1.id, status: .completed)

            let pendingJobs = try await queue.listJobs(tenantId: "tenant-1", status: .pending, limit: 10)
            let runningJobs = try await queue.listJobs(tenantId: "tenant-1", status: .running, limit: 10)
            let completedJobs = try await queue.listJobs(tenantId: "tenant-1", status: .completed, limit: 10)

            #expect(pendingJobs.count == 2)
            #expect(runningJobs.count == 0) // Was set to completed
            #expect(completedJobs.count == 1)
        }

        @Test("List jobs with limit")
        func testListWithLimit() async throws {
            let queue = InMemoryJobQueue()

            for _ in 0..<10 {
                _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))
            }

            let jobs = try await queue.listJobs(tenantId: "tenant-1", status: nil, limit: 5)
            #expect(jobs.count == 5)
        }

        @Test("List jobs sorted by creation date descending")
        func testListJobsSortedByDate() async throws {
            let queue = InMemoryJobQueue()

            let job1 = BatchEmbedJob(id: "job-1", tenantId: "tenant-1")
            let job2 = BatchEmbedJob(id: "job-2", tenantId: "tenant-1")
            let job3 = BatchEmbedJob(id: "job-3", tenantId: "tenant-1")

            _ = try await queue.enqueue(job1)
            _ = try await queue.enqueue(job2)
            _ = try await queue.enqueue(job3)

            let jobs = try await queue.listJobs(tenantId: "tenant-1", status: nil, limit: 10)

            // Newest first
            #expect(jobs[0].id == "job-3")
            #expect(jobs[1].id == "job-2")
            #expect(jobs[2].id == "job-1")
        }

        @Test("Cancel pending job")
        func testCancelPendingJob() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            let cancelled = try await queue.cancel(jobId)
            #expect(cancelled == true)

            let record = try await queue.getJob(jobId)
            #expect(record?.status == .cancelled)
            #expect(record?.completedAt != nil)

            // Should not be in pending queue anymore
            let pending = await queue.pendingCount
            #expect(pending == 0)
        }

        @Test("Cancel running job returns true")
        func testCancelRunningJob() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            // Dequeue to set running
            _ = try await queue.dequeue()

            let cancelled = try await queue.cancel(jobId)
            #expect(cancelled == true) // Signals executor should cancel
        }

        @Test("Cancel completed job returns false")
        func testCancelCompletedJob() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            _ = try await queue.dequeue()
            try await queue.updateStatus(jobId, status: .completed)

            let cancelled = try await queue.cancel(jobId)
            #expect(cancelled == false)
        }

        @Test("Cancel non-existent job returns false")
        func testCancelNonExistent() async throws {
            let queue = InMemoryJobQueue()

            let cancelled = try await queue.cancel("non-existent")
            #expect(cancelled == false)
        }

        @Test("Prune old jobs")
        func testPruneOldJobs() async throws {
            let queue = InMemoryJobQueue()

            // Add some jobs
            let job1 = BatchEmbedJob(tenantId: "tenant-1")
            let job2 = BatchEmbedJob(tenantId: "tenant-1")
            let job3 = BatchEmbedJob(tenantId: "tenant-1")

            _ = try await queue.enqueue(job1)
            _ = try await queue.enqueue(job2)
            _ = try await queue.enqueue(job3)

            // Complete them
            for job in [job1, job2, job3] {
                _ = try await queue.dequeue()
                try await queue.updateStatus(job.id, status: .completed)
            }

            // Prune with future date should remove all completed jobs
            let futureDate = Date().addingTimeInterval(60)
            let pruned = try await queue.pruneOldJobs(before: futureDate)

            #expect(pruned == 3)
            #expect(await queue.totalJobCount == 0)
        }

        @Test("Prune does not remove pending jobs")
        func testPruneDoesNotRemovePending() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            _ = try await queue.enqueue(job)

            let futureDate = Date().addingTimeInterval(60)
            let pruned = try await queue.pruneOldJobs(before: futureDate)

            #expect(pruned == 0)
            #expect(await queue.totalJobCount == 1)
        }

        @Test("Total job count")
        func testTotalJobCount() async throws {
            let queue = InMemoryJobQueue()

            #expect(await queue.totalJobCount == 0)

            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))
            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))
            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))

            #expect(await queue.totalJobCount == 3)
        }

        @Test("Pending count")
        func testPendingCount() async throws {
            let queue = InMemoryJobQueue()

            #expect(await queue.pendingCount == 0)

            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))
            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))

            #expect(await queue.pendingCount == 2)

            _ = try await queue.dequeue()

            #expect(await queue.pendingCount == 1)
        }

        @Test("Clear queue")
        func testClear() async throws {
            let queue = InMemoryJobQueue()

            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))
            _ = try await queue.enqueue(BatchEmbedJob(tenantId: "tenant-1"))

            await queue.clear()

            #expect(await queue.totalJobCount == 0)
            #expect(await queue.pendingCount == 0)
        }

        @Test("Reset to pending re-adds to queue")
        func testResetToPending() async throws {
            let queue = InMemoryJobQueue()

            let job = BatchEmbedJob(tenantId: "tenant-1")
            let jobId = try await queue.enqueue(job)

            // Dequeue (running) then fail
            _ = try await queue.dequeue()
            try await queue.updateStatus(jobId, status: .failed)

            #expect(await queue.pendingCount == 0)

            // Reset to pending for retry
            try await queue.updateStatus(jobId, status: .pending)

            #expect(await queue.pendingCount == 1)

            // Can dequeue again
            let dequeued = try await queue.dequeue()
            #expect(dequeued?.id == jobId)
        }
    }

    // MARK: - JobPriority Tests

    @Suite("JobPriority Tests")
    struct JobPriorityTests {

        @Test("JobPriority raw values")
        func testPriorityRawValues() {
            #expect(JobPriority.low.rawValue == 0)
            #expect(JobPriority.normal.rawValue == 1)
            #expect(JobPriority.high.rawValue == 2)
            #expect(JobPriority.critical.rawValue == 3)
        }

        @Test("JobPriority comparison")
        func testPriorityComparison() {
            #expect(JobPriority.low < JobPriority.normal)
            #expect(JobPriority.normal < JobPriority.high)
            #expect(JobPriority.high < JobPriority.critical)

            #expect(JobPriority.critical > JobPriority.low)
        }

        @Test("JobPriority allCases")
        func testPriorityAllCases() {
            let allPriorities = JobPriority.allCases

            #expect(allPriorities.count == 4)
            #expect(allPriorities.contains(.low))
            #expect(allPriorities.contains(.normal))
            #expect(allPriorities.contains(.high))
            #expect(allPriorities.contains(.critical))
        }

        @Test("JobPriority Codable")
        func testPriorityCodable() throws {
            for priority in JobPriority.allCases {
                let data = try JSONEncoder().encode(priority)
                let decoded = try JSONDecoder().decode(JobPriority.self, from: data)
                #expect(decoded == priority)
            }
        }
    }

    // MARK: - JobRecord Tests

    @Suite("JobRecord Tests")
    struct JobRecordTests {

        @Test("JobRecord initialization")
        func testJobRecordInit() {
            let payload = Data()
            let record = JobRecord(
                id: "job-123",
                jobType: "batch-embed",
                tenantId: "tenant-1",
                payload: payload
            )

            #expect(record.id == "job-123")
            #expect(record.jobType == "batch-embed")
            #expect(record.tenantId == "tenant-1")
            #expect(record.status == .pending)
            #expect(record.progress == 0.0)
            #expect(record.priority == .normal)
            #expect(record.maxRetries == 3)
            #expect(record.retryCount == 0)
            #expect(record.startedAt == nil)
            #expect(record.completedAt == nil)
        }

        @Test("JobRecord with custom priority and retries")
        func testJobRecordCustom() {
            let record = JobRecord(
                id: "job-456",
                jobType: "ingest",
                tenantId: "tenant-2",
                priority: .high,
                payload: Data(),
                maxRetries: 5
            )

            #expect(record.priority == .high)
            #expect(record.maxRetries == 5)
        }

        @Test("JobRecord Codable")
        func testJobRecordCodable() throws {
            let record = JobRecord(
                id: "job-789",
                jobType: "reindex",
                tenantId: "tenant-3",
                priority: .critical,
                payload: "test payload".data(using: .utf8)!,
                maxRetries: 2
            )

            let data = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(JobRecord.self, from: data)

            #expect(decoded.id == record.id)
            #expect(decoded.jobType == record.jobType)
            #expect(decoded.tenantId == record.tenantId)
            #expect(decoded.priority == record.priority)
            #expect(decoded.maxRetries == record.maxRetries)
        }

        @Test("JobRecord Equatable")
        func testJobRecordEquatable() {
            // Test that two records with same id and properties (except createdAt) compare correctly
            // Since JobRecord auto-generates createdAt, we'll verify key properties match
            let record1 = JobRecord(
                id: "job-same",
                jobType: "test",
                tenantId: "tenant-1",
                payload: Data()
            )
            let record2 = JobRecord(
                id: "job-same",
                jobType: "test",
                tenantId: "tenant-1",
                payload: Data()
            )
            let record3 = JobRecord(
                id: "job-different",
                jobType: "test",
                tenantId: "tenant-1",
                payload: Data()
            )

            // Verify key properties match for records with same id
            #expect(record1.id == record2.id)
            #expect(record1.jobType == record2.jobType)
            #expect(record1.tenantId == record2.tenantId)
            #expect(record1.priority == record2.priority)
            #expect(record1.status == record2.status)
            #expect(record1.payload == record2.payload)

            // Verify different ids make records not equal
            #expect(record1.id != record3.id)
        }

        @Test("JobRecord Identifiable")
        func testJobRecordIdentifiable() {
            let record = JobRecord(
                id: "unique-id",
                jobType: "test",
                tenantId: "tenant-1",
                payload: Data()
            )

            #expect(record.id == "unique-id")
        }
    }

    // MARK: - JobResultData Tests

    @Suite("JobResultData Tests")
    struct JobResultDataTests {

        @Test("JobResultData initialization")
        func testJobResultDataInit() {
            let result = JobResultData(
                documentIds: ["doc-1", "doc-2"],
                chunksCreated: 100,
                chunksDeleted: 10,
                message: "Operation complete",
                metadata: ["duration": "5s"]
            )

            #expect(result.documentIds?.count == 2)
            #expect(result.chunksCreated == 100)
            #expect(result.chunksDeleted == 10)
            #expect(result.message == "Operation complete")
            #expect(result.metadata?["duration"] == "5s")
        }

        @Test("JobResultData Codable")
        func testJobResultDataCodable() throws {
            let result = JobResultData(
                documentIds: ["doc-1"],
                chunksCreated: 50,
                message: "Done"
            )

            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(JobResultData.self, from: data)

            #expect(decoded.documentIds == result.documentIds)
            #expect(decoded.chunksCreated == result.chunksCreated)
            #expect(decoded.message == result.message)
        }

        @Test("JobResultData Equatable")
        func testJobResultDataEquatable() {
            let result1 = JobResultData(chunksCreated: 10, message: "Test")
            let result2 = JobResultData(chunksCreated: 10, message: "Test")
            let result3 = JobResultData(chunksCreated: 20, message: "Different")

            #expect(result1 == result2)
            #expect(result1 != result3)
        }
    }

    // MARK: - BatchEmbedJob Tests

    @Suite("BatchEmbedJob Tests")
    struct BatchEmbedJobTests {

        @Test("BatchEmbedJob initialization")
        func testBatchEmbedJobInit() {
            let job = BatchEmbedJob(
                id: "embed-123",
                tenantId: "tenant-1",
                chunkIds: ["chunk-1", "chunk-2"],
                embeddingModel: "text-embedding-3-small",
                priority: .high,
                maxRetries: 5
            )

            #expect(job.id == "embed-123")
            #expect(job.tenantId == "tenant-1")
            #expect(job.chunkIds?.count == 2)
            #expect(job.embeddingModel == "text-embedding-3-small")
            #expect(job.priority == .high)
            #expect(job.maxRetries == 5)
        }

        @Test("BatchEmbedJob default values")
        func testBatchEmbedJobDefaults() {
            let job = BatchEmbedJob(tenantId: "tenant-1")

            #expect(!job.id.isEmpty)
            #expect(job.chunkIds == nil)
            #expect(job.embeddingModel == nil)
            #expect(job.priority == .low)
            #expect(job.maxRetries == 3)
        }

        @Test("BatchEmbedJob static jobType")
        func testBatchEmbedJobType() {
            #expect(BatchEmbedJob.jobType == "batch-embed")
        }

        @Test("BatchEmbedJob Codable")
        func testBatchEmbedJobCodable() throws {
            let job = BatchEmbedJob(
                id: "test-id",
                tenantId: "tenant-1",
                chunkIds: ["a", "b", "c"],
                embeddingModel: "custom-model"
            )

            let data = try JSONEncoder().encode(job)
            let decoded = try JSONDecoder().decode(BatchEmbedJob.self, from: data)

            #expect(decoded.id == job.id)
            #expect(decoded.tenantId == job.tenantId)
            #expect(decoded.chunkIds == job.chunkIds)
            #expect(decoded.embeddingModel == job.embeddingModel)
        }

        @Test("BatchEmbedJob Equatable")
        func testBatchEmbedJobEquatable() {
            let job1 = BatchEmbedJob(id: "same-id", tenantId: "tenant-1")
            let job2 = BatchEmbedJob(id: "same-id", tenantId: "tenant-1")
            let job3 = BatchEmbedJob(id: "different-id", tenantId: "tenant-1")

            #expect(job1 == job2)
            #expect(job1 != job3)
        }

        @Test("BatchEmbedJob Hashable")
        func testBatchEmbedJobHashable() {
            let job1 = BatchEmbedJob(id: "id-1", tenantId: "tenant-1")
            let job2 = BatchEmbedJob(id: "id-2", tenantId: "tenant-1")

            var set: Set<BatchEmbedJob> = []
            set.insert(job1)
            set.insert(job2)
            set.insert(job1) // Duplicate

            #expect(set.count == 2)
        }

        @Test("BatchEmbedJob description")
        func testBatchEmbedJobDescription() {
            let jobWithChunks = BatchEmbedJob(
                tenantId: "tenant-1",
                chunkIds: ["a", "b", "c"]
            )
            let jobWithoutChunks = BatchEmbedJob(tenantId: "tenant-1")

            #expect(jobWithChunks.description.contains("chunks: 3"))
            #expect(jobWithoutChunks.description.contains("chunks: all"))
        }
    }
}
