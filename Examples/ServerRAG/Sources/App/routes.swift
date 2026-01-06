// ServerRAG - Vapor-based RAG Server Example
//
// routes.swift - HTTP endpoint definitions.
//
// Provides endpoints for document ingestion, querying, and statistics.

import Vapor
import Zoni
import ZoniServer
import ZoniVapor

// MARK: - Routes Registration

/// Registers all routes for the ServerRAG application.
///
/// Endpoints:
/// - `POST /ingest` - Ingest documents into the RAG pipeline
/// - `POST /query` - Execute a RAG query
/// - `GET /stats` - Get pipeline statistics
///
/// - Parameter app: The Vapor application to register routes with.
func routes(_ app: Application) throws {
    // Health check endpoint (no auth required)
    app.get("health") { _ in
        ["status": "healthy", "service": "ServerRAG"]
    }

    // Main API routes
    app.post("ingest", use: ingestDocuments)
    app.post("query", use: executeQuery)
    app.get("stats", use: getStatistics)
}

// MARK: - Ingest Endpoint

/// Request body for document ingestion.
struct IngestRequestBody: Content {
    /// Array of documents to ingest.
    let documents: [DocumentInput]
}

/// A document to be ingested.
struct DocumentInput: Content {
    /// The text content of the document.
    let content: String

    /// Optional title for the document.
    let title: String?

    /// Optional source identifier (e.g., filename, URL).
    let source: String?

    /// Optional custom metadata.
    let metadata: [String: String]?
}

/// Response from document ingestion.
struct IngestResponseBody: Content {
    /// Whether the operation succeeded.
    let success: Bool

    /// Number of documents processed.
    let documentsProcessed: Int

    /// Total number of chunks created.
    let chunksCreated: Int

    /// Optional message with details.
    let message: String?
}

/// Ingests documents into the RAG pipeline.
///
/// ## Request Body
/// ```json
/// {
///     "documents": [
///         {
///             "content": "Document text content...",
///             "title": "Optional Title",
///             "source": "document.txt",
///             "metadata": {"category": "documentation"}
///         }
///     ]
/// }
/// ```
///
/// ## Response
/// ```json
/// {
///     "success": true,
///     "documentsProcessed": 1,
///     "chunksCreated": 5,
///     "message": "Successfully ingested 1 documents"
/// }
/// ```
@Sendable
func ingestDocuments(req: Request) async throws -> IngestResponseBody {
    let body = try req.content.decode(IngestRequestBody.self)

    guard !body.documents.isEmpty else {
        throw Abort(.badRequest, reason: "No documents provided")
    }

    let vectorStore = req.application.vectorStore
    let embeddingProvider = req.application.embeddingProvider
    let chunker = req.application.chunker

    var totalChunks = 0

    for docInput in body.documents {
        // Create document
        var metadata = DocumentMetadata(
            source: docInput.source,
            title: docInput.title
        )

        // Add custom metadata
        if let customMeta = docInput.metadata {
            for (key, value) in customMeta {
                metadata[key] = .string(value)
            }
        }

        let document = Document(
            content: docInput.content,
            metadata: metadata
        )

        // Chunk the document
        let chunks = try await chunker.chunk(document)

        // Generate embeddings for chunks
        let contents = chunks.map { $0.content }
        let embeddings = try await embeddingProvider.embed(contents)

        // Store in vector store
        try await vectorStore.add(chunks, embeddings: embeddings)
        totalChunks += chunks.count
    }

    req.logger.info("Ingested \(body.documents.count) documents, created \(totalChunks) chunks")

    return IngestResponseBody(
        success: true,
        documentsProcessed: body.documents.count,
        chunksCreated: totalChunks,
        message: "Successfully ingested \(body.documents.count) documents"
    )
}

// MARK: - Query Endpoint

/// Request body for RAG queries.
struct QueryRequestBody: Content {
    /// The question to answer.
    let query: String

    /// Maximum number of chunks to retrieve (default: 5).
    let retrievalLimit: Int?

    /// Whether to include source metadata in response (default: true).
    let includeMetadata: Bool?
}

/// Response from a RAG query.
struct QueryResponseBody: Content {
    /// The generated answer.
    let answer: String

    /// Source chunks used to generate the answer.
    let sources: [SourceInfo]

    /// Query metadata.
    let metadata: QueryMetadata
}

/// Information about a source chunk.
struct SourceInfo: Content {
    /// The chunk content.
    let content: String

    /// Relevance score (0.0 to 1.0).
    let score: Float

    /// Document ID this chunk belongs to.
    let documentId: String

    /// Original source identifier.
    let source: String?
}

/// Metadata about the query execution.
struct QueryMetadata: Content {
    /// Number of chunks retrieved.
    let chunksRetrieved: Int

    /// The model used for generation.
    let model: String?

    /// Total execution time in milliseconds.
    let totalTimeMs: Double?
}

/// Executes a RAG query and returns the answer with sources.
///
/// ## Request Body
/// ```json
/// {
///     "query": "What is Swift concurrency?",
///     "retrievalLimit": 5,
///     "includeMetadata": true
/// }
/// ```
///
/// ## Response
/// ```json
/// {
///     "answer": "Based on the provided context...",
///     "sources": [
///         {
///             "content": "Chunk content...",
///             "score": 0.85,
///             "documentId": "doc-123",
///             "source": "guide.md"
///         }
///     ],
///     "metadata": {
///         "chunksRetrieved": 3,
///         "model": "mock-llm-v1",
///         "totalTimeMs": 125.5
///     }
/// }
/// ```
@Sendable
func executeQuery(req: Request) async throws -> QueryResponseBody {
    let body = try req.content.decode(QueryRequestBody.self)

    guard !body.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "Query cannot be empty")
    }

    let queryEngine = req.application.zoni.queryEngine
    let retrievalLimit = body.retrievalLimit ?? 5

    // Clamp retrieval limit to reasonable bounds
    let limit = max(1, min(retrievalLimit, 20))

    let options = QueryOptions(
        retrievalLimit: limit,
        includeMetadata: body.includeMetadata ?? true
    )

    let startTime = ContinuousClock.now
    let response = try await queryEngine.query(body.query, options: options)
    let endTime = ContinuousClock.now

    let totalTime = endTime - startTime
    let totalMs = Double(totalTime.components.seconds) * 1000 +
                  Double(totalTime.components.attoseconds) / 1_000_000_000_000_000

    let sources = response.sources.map { result in
        SourceInfo(
            content: result.chunk.content,
            score: result.score,
            documentId: result.chunk.metadata.documentId,
            source: result.chunk.metadata.source
        )
    }

    return QueryResponseBody(
        answer: response.answer,
        sources: sources,
        metadata: QueryMetadata(
            chunksRetrieved: response.sources.count,
            model: response.metadata.model,
            totalTimeMs: totalMs
        )
    )
}

// MARK: - Statistics Endpoint

/// Response containing pipeline statistics.
struct StatsResponseBody: Content {
    /// Total number of chunks in the vector store.
    let totalChunks: Int

    /// Name of the vector store implementation.
    let vectorStore: String

    /// Name of the embedding provider.
    let embeddingProvider: String

    /// Embedding dimensions.
    let embeddingDimensions: Int

    /// Server status.
    let status: String
}

/// Returns statistics about the RAG pipeline.
///
/// ## Response
/// ```json
/// {
///     "totalChunks": 150,
///     "vectorStore": "in_memory",
///     "embeddingProvider": "mock",
///     "embeddingDimensions": 384,
///     "status": "ready"
/// }
/// ```
@Sendable
func getStatistics(req: Request) async throws -> StatsResponseBody {
    let vectorStore = req.application.vectorStore
    let embeddingProvider = req.application.embeddingProvider

    let chunkCount = try await vectorStore.count()

    return StatsResponseBody(
        totalChunks: chunkCount,
        vectorStore: vectorStore.name,
        embeddingProvider: embeddingProvider.name,
        embeddingDimensions: embeddingProvider.dimensions,
        status: "ready"
    )
}
