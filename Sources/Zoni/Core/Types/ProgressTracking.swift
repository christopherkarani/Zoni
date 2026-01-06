// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ProgressTracking.swift - Progress tracking types for pipeline operations.

import Foundation

// MARK: - IngestionProgress

/// Progress information during document ingestion.
///
/// `IngestionProgress` provides real-time feedback during the document
/// ingestion process, tracking progress through chunking, embedding,
/// and storage phases.
///
/// Example usage:
/// ```swift
/// pipeline.onIngestionProgress = { progress in
///     switch progress.phase {
///     case .chunking:
///         print("Chunking document...")
///     case .embedding:
///         print("Generating embeddings...")
///     case .storing:
///         print("Storing in vector database...")
///     case .complete:
///         print("Ingestion complete!")
///     }
/// }
/// ```
public struct IngestionProgress: Sendable {
    /// The current phase of the ingestion process.
    public enum Phase: Sendable {
        /// Document content is being validated.
        case validating
        /// Document is being split into chunks.
        case chunking
        /// Embeddings are being generated for chunks.
        case embedding
        /// Chunks and embeddings are being stored in the vector store.
        case storing
        /// Ingestion has completed successfully.
        case complete
        /// Ingestion failed with an error.
        case failed
    }

    /// The current phase of ingestion.
    public let phase: Phase

    /// The current item being processed (1-based index).
    public let current: Int

    /// The total number of items to process.
    public let total: Int

    /// The identifier of the document being ingested, if available.
    public let documentId: String?

    /// Optional message providing additional context.
    ///
    /// This is particularly useful for the `.failed` phase to communicate
    /// error details to progress handlers.
    public let message: String?

    /// Creates new ingestion progress information.
    ///
    /// - Parameters:
    ///   - phase: The current phase of ingestion.
    ///   - current: The current item being processed.
    ///   - total: The total number of items to process.
    ///   - documentId: The identifier of the document being ingested.
    ///   - message: An optional message with additional details.
    public init(phase: Phase, current: Int, total: Int, documentId: String? = nil, message: String? = nil) {
        self.phase = phase
        self.current = current
        self.total = total
        self.documentId = documentId
        self.message = message
    }

    /// The progress as a fraction from 0.0 to 1.0.
    public var fraction: Double {
        guard total > 0 else { return 0.0 }
        return Double(current) / Double(total)
    }
}

// MARK: - QueryProgress

/// Progress information during query execution.
///
/// `QueryProgress` provides real-time feedback during query execution,
/// tracking progress through retrieval and generation phases.
///
/// Example usage:
/// ```swift
/// pipeline.onQueryProgress = { progress in
///     switch progress.phase {
///     case .retrieving:
///         print("Searching for relevant documents...")
///     case .generating:
///         print("Generating response...")
///     case .complete:
///         print("Query complete!")
///     }
/// }
/// ```
public struct QueryProgress: Sendable {
    /// The current phase of the query process.
    public enum Phase: Sendable {
        /// Retrieving relevant chunks from the vector store.
        case retrieving
        /// Generating response using the LLM.
        case generating
        /// Query has completed successfully.
        case complete
        /// Query failed with an error.
        case failed
    }

    /// The current phase of query execution.
    public let phase: Phase

    /// An optional message providing additional details about the current phase.
    public let message: String?

    /// Creates new query progress information.
    ///
    /// - Parameters:
    ///   - phase: The current phase of query execution.
    ///   - message: An optional message with additional details.
    public init(phase: Phase, message: String? = nil) {
        self.phase = phase
        self.message = message
    }
}

// MARK: - CustomStringConvertible

extension IngestionProgress: CustomStringConvertible {
    public var description: String {
        var result = "IngestionProgress(\(phaseString), \(current)/\(total)"
        if let docId = documentId {
            result += ", doc: \(docId)"
        }
        if let msg = message {
            result += ", message: \(msg)"
        }
        result += ")"
        return result
    }

    private var phaseString: String {
        switch phase {
        case .validating: return "validating"
        case .chunking: return "chunking"
        case .embedding: return "embedding"
        case .storing: return "storing"
        case .complete: return "complete"
        case .failed: return "failed"
        }
    }
}

extension QueryProgress: CustomStringConvertible {
    public var description: String {
        if let message = message {
            return "QueryProgress(\(phaseString): \(message))"
        }
        return "QueryProgress(\(phaseString))"
    }

    private var phaseString: String {
        switch phase {
        case .retrieving: return "retrieving"
        case .generating: return "generating"
        case .complete: return "complete"
        case .failed: return "failed"
        }
    }
}

// MARK: - Equatable

extension IngestionProgress: Equatable {}
extension IngestionProgress.Phase: Equatable {}
extension QueryProgress: Equatable {}
extension QueryProgress.Phase: Equatable {}
