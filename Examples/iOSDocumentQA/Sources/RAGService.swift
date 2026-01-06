// iOSDocumentQA - Example iOS app demonstrating Zoni RAG capabilities
//
// RAGService.swift - RAG pipeline service for document Q&A

import Foundation
import Zoni
import ZoniApple

// MARK: - RAGService

/// The main RAG service for the iOSDocumentQA app.
///
/// `RAGService` manages the RAG pipeline including:
/// - Document ingestion and chunking
/// - Embedding generation using Apple's NaturalLanguage framework
/// - Vector storage and retrieval
/// - Question answering with mock LLM responses
///
/// ## Architecture
/// The service uses @Observable for SwiftUI integration and @MainActor
/// for thread-safe UI updates. All heavy operations are performed
/// asynchronously to keep the UI responsive.
///
/// ## Example Usage
/// ```swift
/// @Environment(RAGService.self) var ragService
///
/// // Ingest a document
/// try await ragService.ingestDocument(content: "...", title: "My Doc")
///
/// // Query the knowledge base
/// let answer = try await ragService.query("What is this about?")
/// ```
@Observable
@MainActor
public final class RAGService {

    // MARK: - Published State

    /// The number of documents currently in the knowledge base.
    public private(set) var documentCount: Int = 0

    /// The number of chunks stored in the vector store.
    public private(set) var chunkCount: Int = 0

    /// Whether a document ingestion is in progress.
    public private(set) var isIngesting: Bool = false

    /// Whether a query is in progress.
    public private(set) var isQuerying: Bool = false

    /// The most recent error message, if any.
    public private(set) var errorMessage: String?

    /// Titles of ingested documents for display.
    public private(set) var documentTitles: [String] = []

    // MARK: - Private Properties

    /// The embedding provider using Apple's NaturalLanguage framework.
    private var embeddingProvider: NLEmbeddingProvider?

    /// The in-memory vector store for document chunks.
    private let vectorStore: InMemoryVectorStore

    /// The retriever for semantic search.
    private var retriever: VectorRetriever?

    /// The query engine for RAG operations.
    private var queryEngine: QueryEngine?

    /// The chunking strategy for splitting documents.
    private let chunker: ParagraphChunker

    /// Track ingested document IDs for counting.
    private var ingestedDocumentIds: Set<String> = []

    // MARK: - Initialization

    /// Creates a new RAG service with default configuration.
    ///
    /// The service initializes with:
    /// - Apple NaturalLanguage embeddings (English)
    /// - In-memory vector storage
    /// - Paragraph-based chunking
    /// - Mock LLM for demo responses
    public init() {
        self.vectorStore = InMemoryVectorStore()
        self.chunker = ParagraphChunker(
            maxParagraphsPerChunk: 3,
            maxChunkSize: 1500,
            overlapParagraphs: 1
        )

        // Initialize components asynchronously
        Task {
            await initializeComponents()
        }
    }

    // MARK: - Public Methods

    /// Ingests a document into the RAG knowledge base.
    ///
    /// The document is chunked, embedded, and stored in the vector store
    /// for later retrieval.
    ///
    /// - Parameters:
    ///   - content: The text content of the document.
    ///   - title: A title for the document (used for display).
    ///   - source: Optional source identifier (e.g., filename).
    /// - Throws: `RAGServiceError` if ingestion fails.
    public func ingestDocument(
        content: String,
        title: String,
        source: String? = nil
    ) async throws {
        guard let embeddingProvider = embeddingProvider else {
            throw RAGServiceError.notInitialized
        }

        isIngesting = true
        errorMessage = nil

        defer {
            isIngesting = false
        }

        do {
            // Create the document
            let document = Document(
                content: content,
                metadata: DocumentMetadata(
                    source: source,
                    title: title
                )
            )

            // Chunk the document
            let chunks = try await chunker.chunk(document)

            guard !chunks.isEmpty else {
                throw RAGServiceError.emptyDocument
            }

            // Generate embeddings for all chunks
            let texts = chunks.map { $0.content }
            let embeddings = try await embeddingProvider.embed(texts)

            // Store in vector store
            try await vectorStore.add(chunks, embeddings: embeddings)

            // Update state
            ingestedDocumentIds.insert(document.id)
            documentCount = ingestedDocumentIds.count
            chunkCount = try await vectorStore.count()
            documentTitles.append(title)

        } catch let error as ZoniError {
            errorMessage = "Ingestion failed: \(error.localizedDescription)"
            throw RAGServiceError.ingestionFailed(error.localizedDescription)
        } catch {
            errorMessage = "Ingestion failed: \(error.localizedDescription)"
            throw RAGServiceError.ingestionFailed(error.localizedDescription)
        }
    }

    /// Queries the knowledge base and returns an answer.
    ///
    /// - Parameter question: The question to answer.
    /// - Returns: The generated answer based on retrieved context.
    /// - Throws: `RAGServiceError` if the query fails.
    public func query(_ question: String) async throws -> String {
        guard let queryEngine = queryEngine else {
            throw RAGServiceError.notInitialized
        }

        isQuerying = true
        errorMessage = nil

        defer {
            isQuerying = false
        }

        do {
            let response = try await queryEngine.query(
                question,
                options: QueryOptions(
                    retrievalLimit: 5,
                    includeMetadata: true
                )
            )
            return response.answer

        } catch let error as ZoniError {
            errorMessage = "Query failed: \(error.localizedDescription)"
            throw RAGServiceError.queryFailed(error.localizedDescription)
        } catch {
            errorMessage = "Query failed: \(error.localizedDescription)"
            throw RAGServiceError.queryFailed(error.localizedDescription)
        }
    }

    /// Searches the knowledge base and returns relevant chunks.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum number of results to return.
    /// - Returns: An array of retrieval results with scores.
    /// - Throws: `RAGServiceError` if search fails.
    public func search(_ query: String, limit: Int = 5) async throws -> [RetrievalResult] {
        guard let retriever = retriever else {
            throw RAGServiceError.notInitialized
        }

        do {
            return try await retriever.retrieve(
                query: query,
                limit: limit,
                filter: nil
            )
        } catch {
            throw RAGServiceError.searchFailed(error.localizedDescription)
        }
    }

    /// Clears all documents from the knowledge base.
    public func clearKnowledgeBase() async {
        await vectorStore.clear()
        ingestedDocumentIds.removeAll()
        documentTitles.removeAll()
        documentCount = 0
        chunkCount = 0
        errorMessage = nil
    }

    /// Checks if the service is ready for use.
    public var isReady: Bool {
        embeddingProvider != nil && queryEngine != nil
    }

    // MARK: - Private Methods

    /// Initializes the RAG pipeline components.
    private func initializeComponents() async {
        do {
            // Initialize embedding provider
            let provider = try NLEmbeddingProvider.english()
            self.embeddingProvider = provider

            // Initialize retriever
            let retriever = VectorRetriever(
                vectorStore: vectorStore,
                embeddingProvider: provider,
                similarityThreshold: 0.3
            )
            self.retriever = retriever

            // Initialize query engine with mock LLM
            let llmProvider = MockLLMProvider()
            let queryEngine = QueryEngine(
                retriever: retriever,
                llmProvider: llmProvider
            )
            self.queryEngine = queryEngine

        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }
}

// MARK: - RAGServiceError

/// Errors that can occur in the RAG service.
public enum RAGServiceError: LocalizedError {
    /// The service has not been initialized yet.
    case notInitialized

    /// The document content is empty.
    case emptyDocument

    /// Document ingestion failed.
    case ingestionFailed(String)

    /// Query execution failed.
    case queryFailed(String)

    /// Search operation failed.
    case searchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "RAG service is not initialized. Please wait for initialization to complete."
        case .emptyDocument:
            return "The document content is empty or contains only whitespace."
        case .ingestionFailed(let reason):
            return "Document ingestion failed: \(reason)"
        case .queryFailed(let reason):
            return "Query failed: \(reason)"
        case .searchFailed(let reason):
            return "Search failed: \(reason)"
        }
    }
}
