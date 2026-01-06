// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGPipeline.swift - The main RAG pipeline orchestrator.

import Foundation

// MARK: - RAGPipeline

/// The main RAG pipeline orchestrator.
///
/// `RAGPipeline` coordinates document ingestion, embedding generation,
/// vector storage, retrieval, and response generation. It serves as the
/// central entry point for all RAG operations.
///
/// ## Overview
///
/// The pipeline handles the complete RAG workflow:
/// 1. **Ingestion**: Load and chunk documents, generate embeddings, store in vector store
/// 2. **Retrieval**: Find relevant chunks based on semantic similarity
/// 3. **Generation**: Use retrieved context to generate LLM responses
///
/// ## Example Usage
///
/// ```swift
/// // Create pipeline components
/// let embedding = OpenAIEmbeddingProvider(apiKey: "...")
/// let vectorStore = InMemoryVectorStore()
/// let llm = OpenAIProvider(model: "gpt-4")
/// let chunker = CharacterChunker(chunkSize: 512, overlap: 50)
///
/// // Initialize pipeline
/// let pipeline = RAGPipeline(
///     embedding: embedding,
///     vectorStore: vectorStore,
///     llm: llm,
///     chunker: chunker
/// )
///
/// // Ingest documents
/// try await pipeline.ingest(document)
///
/// // Query the knowledge base
/// let response = try await pipeline.query("What is Swift concurrency?")
/// print(response.answer)
/// ```
///
/// ## Thread Safety
///
/// `RAGPipeline` is implemented as an actor to ensure thread-safe access
/// to its internal state and components. All methods are safe to call
/// from any actor context.
public actor RAGPipeline {

    // MARK: - Properties

    /// Pipeline configuration controlling chunking, retrieval, and generation behavior.
    public let configuration: RAGConfiguration

    /// The embedding provider used to generate vector embeddings from text.
    private let embeddingProvider: any EmbeddingProvider

    /// The vector store for storing and searching chunk embeddings.
    private let vectorStore: any VectorStore

    /// The LLM provider for generating responses.
    private let llmProvider: any LLMProvider

    /// The chunking strategy for splitting documents into smaller pieces.
    private let chunker: any ChunkingStrategy

    /// Registry for document loaders handling various file formats.
    private let loaderRegistry: LoaderRegistry

    /// Tracks ingested document count for statistics.
    private var documentCount: Int = 0

    /// Callback invoked during document ingestion progress.
    ///
    /// Set this property to receive progress updates during ingestion operations.
    /// The callback is invoked at each phase: chunking, embedding, storing, and complete.
    ///
    /// Example:
    /// ```swift
    /// await pipeline.setIngestionProgressHandler { progress in
    ///     print("Phase: \(progress.phase), \(progress.current)/\(progress.total)")
    /// }
    /// ```
    private var _onIngestionProgress: (@Sendable (IngestionProgress) -> Void)?

    /// Callback invoked during query progress.
    ///
    /// Set this property to receive progress updates during query operations.
    /// The callback is invoked at each phase: retrieving, generating, and complete.
    ///
    /// Example:
    /// ```swift
    /// await pipeline.setQueryProgressHandler { progress in
    ///     print("Phase: \(progress.phase)")
    /// }
    /// ```
    private var _onQueryProgress: (@Sendable (QueryProgress) -> Void)?

    /// Sets the ingestion progress handler.
    ///
    /// - Parameter handler: The progress handler to invoke during ingestion operations.
    public func setIngestionProgressHandler(_ handler: (@Sendable (IngestionProgress) -> Void)?) {
        _onIngestionProgress = handler
    }

    /// Sets the query progress handler.
    ///
    /// - Parameter handler: The progress handler to invoke during query operations.
    public func setQueryProgressHandler(_ handler: (@Sendable (QueryProgress) -> Void)?) {
        _onQueryProgress = handler
    }

    // MARK: - Initialization

    /// Creates a new RAG pipeline with the specified components.
    ///
    /// - Parameters:
    ///   - embedding: The embedding provider for generating vector embeddings.
    ///   - vectorStore: The vector store for storing and searching embeddings.
    ///   - llm: The LLM provider for generating responses.
    ///   - chunker: The chunking strategy for splitting documents.
    ///   - loaderRegistry: Registry for document loaders. Defaults to an empty registry.
    ///   - configuration: Pipeline configuration. Defaults to `.default`.
    public init(
        embedding: any EmbeddingProvider,
        vectorStore: any VectorStore,
        llm: any LLMProvider,
        chunker: any ChunkingStrategy,
        loaderRegistry: LoaderRegistry = LoaderRegistry(),
        configuration: RAGConfiguration = .default
    ) {
        self.embeddingProvider = embedding
        self.vectorStore = vectorStore
        self.llmProvider = llm
        self.chunker = chunker
        self.loaderRegistry = loaderRegistry
        self.configuration = configuration
    }

    // MARK: - Ingestion

    /// Ingests a single document into the knowledge base.
    ///
    /// This method chunks the document, generates embeddings for each chunk,
    /// and stores them in the vector store.
    ///
    /// - Parameter document: The document to ingest.
    /// - Throws: `ZoniError` if chunking, embedding, or storage fails.
    public func ingest(_ document: Document) async throws {
        // Capture handler at start to prevent mid-operation changes
        let progressHandler = _onIngestionProgress

        do {
            // Report validation phase starting
            progressHandler?(IngestionProgress(
                phase: .validating,
                current: 0,
                total: 1,
                documentId: document.id
            ))

            // Validate document has content
            guard !document.content.isEmpty else {
                progressHandler?(IngestionProgress(
                    phase: .complete,
                    current: 0,
                    total: 0,
                    documentId: document.id
                ))
                return
            }

            // Report validation phase complete
            progressHandler?(IngestionProgress(
                phase: .validating,
                current: 1,
                total: 1,
                documentId: document.id
            ))

            // Report chunking phase starting
            progressHandler?(IngestionProgress(
                phase: .chunking,
                current: 0,
                total: 1,
                documentId: document.id
            ))

            // Chunk the document
            let chunks = try await chunker.chunk(document)
            guard !chunks.isEmpty else {
                progressHandler?(IngestionProgress(
                    phase: .complete,
                    current: 0,
                    total: 0,
                    documentId: document.id
                ))
                return
            }

            // Report chunking phase complete
            progressHandler?(IngestionProgress(
                phase: .chunking,
                current: 1,
                total: 1,
                documentId: document.id
            ))

            // Report embedding phase starting
            progressHandler?(IngestionProgress(
                phase: .embedding,
                current: 0,
                total: chunks.count,
                documentId: document.id
            ))

            // Generate embeddings for all chunks
            let texts = chunks.map(\.content)
            let embeddings = try await embeddingProvider.embed(texts)

            // Validate embedding count matches chunks
            guard embeddings.count == chunks.count else {
                throw ZoniError.embeddingFailed(
                    reason: "Embedding count mismatch: expected \(chunks.count), got \(embeddings.count)"
                )
            }

            // Report embedding phase complete
            progressHandler?(IngestionProgress(
                phase: .embedding,
                current: chunks.count,
                total: chunks.count,
                documentId: document.id
            ))

            // Report storing phase starting
            progressHandler?(IngestionProgress(
                phase: .storing,
                current: 0,
                total: chunks.count,
                documentId: document.id
            ))

            // Store chunks and embeddings in vector store
            try await vectorStore.add(chunks, embeddings: embeddings)

            // Track the document count
            documentCount += 1

            // Report storing phase complete
            progressHandler?(IngestionProgress(
                phase: .storing,
                current: chunks.count,
                total: chunks.count,
                documentId: document.id
            ))

            // Report completion
            progressHandler?(IngestionProgress(
                phase: .complete,
                current: chunks.count,
                total: chunks.count,
                documentId: document.id
            ))
        } catch {
            // Report failure with error details before re-throwing
            progressHandler?(IngestionProgress(
                phase: .failed,
                current: 0,
                total: 0,
                documentId: document.id,
                message: error.localizedDescription
            ))
            throw error
        }
    }

    /// Ingests multiple documents into the knowledge base.
    ///
    /// Documents are processed in batches for efficiency. Use this method
    /// when ingesting large collections of documents.
    ///
    /// - Parameter documents: The documents to ingest.
    /// - Throws: `ZoniError` if any document fails to process.
    public func ingest(_ documents: [Document]) async throws {
        for document in documents {
            try await ingest(document)
        }
    }

    /// Ingests a document from a URL using registered document loaders.
    ///
    /// The pipeline automatically selects an appropriate loader based on
    /// the URL's file extension.
    ///
    /// - Parameter url: The URL of the document to ingest.
    /// - Throws: `ZoniError.unsupportedFileType` if no loader handles the file type,
    ///           or other `ZoniError` if loading or ingestion fails.
    public func ingest(from url: URL) async throws {
        guard await loaderRegistry.canLoad(url) else {
            throw ZoniError.unsupportedFileType(url.pathExtension)
        }
        let document = try await loaderRegistry.load(from: url)
        try await ingest(document)
    }

    /// Ingests all documents from a directory.
    ///
    /// The pipeline recursively scans the directory and ingests all files
    /// that have registered loaders.
    ///
    /// - Parameters:
    ///   - directory: The directory URL to scan for documents.
    ///   - recursive: Whether to scan subdirectories. Defaults to `true`.
    /// - Throws: `ZoniError` if directory access or document ingestion fails.
    public func ingest(directory: URL, recursive: Bool = true) async throws {
        // Collect file URLs synchronously using nonisolated helper
        let fileURLs = try Self.enumerateDirectory(directory, recursive: recursive)

        // Process files asynchronously
        for fileURL in fileURLs {
            guard await loaderRegistry.canLoad(fileURL) else { continue }
            try await ingest(from: fileURL)
        }
    }

    /// Enumerates files in a directory synchronously.
    ///
    /// This nonisolated helper avoids async iterator issues with FileManager.
    private nonisolated static func enumerateDirectory(_ directory: URL, recursive: Bool) throws -> [URL] {
        let fileManager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? []
            : [.skipsSubdirectoryDescendants]

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else {
            throw ZoniError.loadingFailed(
                url: directory,
                reason: "Cannot enumerate directory: \(directory.path)"
            )
        }

        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            // Filter to only include regular files
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues?.isRegularFile == true {
                fileURLs.append(fileURL)
            }
        }
        return fileURLs
    }

    // MARK: - Query

    /// Queries the knowledge base and generates a response.
    ///
    /// This method retrieves relevant chunks from the vector store,
    /// constructs a prompt with the context, and generates a response
    /// using the LLM provider.
    ///
    /// - Parameters:
    ///   - question: The question to answer.
    ///   - options: Query options controlling retrieval and generation. Defaults to `.default`.
    /// - Returns: A `RAGResponse` containing the answer and source documents.
    /// - Throws: `ZoniError` if retrieval or generation fails.
    public func query(_ question: String, options: QueryOptions = .default) async throws -> RAGResponse {
        // Capture handler at start to prevent mid-operation changes
        let progressHandler = _onQueryProgress

        do {
            // Report retrieving phase
            progressHandler?(QueryProgress(phase: .retrieving, message: nil))

            let retriever = VectorRetriever(vectorStore: vectorStore, embeddingProvider: embeddingProvider)
            let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)

            // Report generating phase
            progressHandler?(QueryProgress(phase: .generating, message: nil))

            let response = try await engine.query(question, options: options)

            // Report completion
            progressHandler?(QueryProgress(phase: .complete, message: nil))

            return response
        } catch {
            // Report failure before re-throwing
            progressHandler?(QueryProgress(
                phase: .failed,
                message: error.localizedDescription
            ))
            throw error
        }
    }

    /// Streams a query response for real-time display.
    ///
    /// Use this method when you want to display the response as it is generated,
    /// providing a more interactive user experience.
    ///
    /// - Parameters:
    ///   - question: The question to answer.
    ///   - options: Query options controlling retrieval and generation. Defaults to `.default`.
    /// - Returns: An async stream of `RAGStreamEvent` objects representing
    ///            the progress of retrieval and generation.
    public func streamQuery(_ question: String, options: QueryOptions = .default) -> AsyncThrowingStream<RAGStreamEvent, Error> {
        let retriever = VectorRetriever(vectorStore: vectorStore, embeddingProvider: embeddingProvider)
        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)
        return engine.streamQuery(question, options: options)
    }

    // MARK: - Retrieval Only

    /// Retrieves relevant chunks without generating a response.
    ///
    /// Use this method when you only need to find relevant documents
    /// without LLM generation, such as for document search or debugging.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum number of results to return. Defaults to 5.
    ///   - filter: Optional metadata filter to narrow results.
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance.
    /// - Throws: `ZoniError` if embedding or search fails.
    public func retrieve(_ query: String, limit: Int = 5, filter: MetadataFilter? = nil) async throws -> [RetrievalResult] {
        let retriever = VectorRetriever(vectorStore: vectorStore, embeddingProvider: embeddingProvider)
        return try await retriever.retrieve(query: query, limit: limit, filter: filter)
    }

    // MARK: - Management

    /// Returns statistics about the pipeline's current state.
    ///
    /// Use this method to monitor the pipeline's data and configuration.
    ///
    /// - Returns: A `RAGStatistics` object containing counts and configuration info.
    /// - Throws: `ZoniError` if statistics cannot be retrieved.
    public func statistics() async throws -> RAGStatistics {
        let chunkCount = try await vectorStore.count()
        return RAGStatistics(
            documentCount: documentCount,
            chunkCount: chunkCount,
            embeddingDimensions: embeddingProvider.dimensions,
            vectorStoreName: vectorStore.name,
            embeddingProviderName: embeddingProvider.name
        )
    }

    /// Clears all documents from the vector store.
    ///
    /// This operation permanently removes all ingested content and cannot be undone.
    ///
    /// - Throws: `ZoniError` if the clear operation fails.
    public func clear() async throws {
        // Delete all chunks - use exists filter to match all records
        // All chunks have a documentId, so this matches everything
        try await vectorStore.delete(filter: .exists("documentId"))
        documentCount = 0
    }

    /// Registers a document loader with the pipeline's registry.
    ///
    /// Document loaders are used to load content from various file formats
    /// during ingestion. The loader is registered for all its supported extensions.
    ///
    /// - Parameter loader: The document loader to register.
    public func registerLoader(_ loader: any DocumentLoader) async {
        await loaderRegistry.register(loader)
    }
}
