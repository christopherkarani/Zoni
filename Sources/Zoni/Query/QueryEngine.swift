// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// QueryEngine.swift - Main orchestrator for RAG query operations.

// MARK: - QueryEngine

/// The main orchestrator for Retrieval-Augmented Generation (RAG) queries.
///
/// `QueryEngine` coordinates the full RAG pipeline: transforming queries,
/// retrieving relevant documents, building context, and synthesizing responses.
/// It serves as the primary interface for executing RAG queries in Zoni.
///
/// ## Thread Safety
///
/// `QueryEngine` is implemented as an actor to ensure thread-safe access to
/// its mutable state, including the optional query transformer. The `streamQuery`
/// method is marked `nonisolated` to allow immediate stream creation without
/// actor isolation.
///
/// ## Pipeline Stages
///
/// A typical query flows through these stages:
/// 1. **Query Transformation** (optional): Expand, rephrase, or decompose the query
/// 2. **Retrieval**: Find relevant chunks from the vector store
/// 3. **Context Building**: Format retrieved chunks into LLM-ready context
/// 4. **Response Synthesis**: Generate the final answer using the LLM
///
/// ## Example Usage
///
/// ```swift
/// // Create the query engine
/// let engine = QueryEngine(
///     retriever: vectorRetriever,
///     llmProvider: openAIProvider
/// )
///
/// // Simple query
/// let response = try await engine.query("What is Swift concurrency?")
/// print(response.answer)
///
/// // Query with options
/// let options = QueryOptions(
///     retrievalLimit: 10,
///     filter: .equals("category", "documentation")
/// )
/// let response = try await engine.query("Explain async/await", options: options)
///
/// // Streaming query for real-time display
/// for try await event in engine.streamQuery("What are actors?") {
///     switch event {
///     case .generationChunk(let text):
///         print(text, terminator: "")
///     case .complete(let response):
///         print("\nSources: \(response.sources.count)")
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Query Transformation
///
/// Optionally set a query transformer to improve retrieval quality:
///
/// ```swift
/// let engine = QueryEngine(retriever: retriever, llmProvider: provider)
/// await engine.setQueryTransformer(QueryExpander(llmProvider: provider))
///
/// // Queries will now be expanded before retrieval
/// let response = try await engine.query("swift async")
/// ```
public actor QueryEngine {

    // MARK: - Constants

    /// Message returned when no relevant information is found for a query.
    private static let noResultsMessage = """
        I could not find any relevant information to answer your question. \
        Please try rephrasing your query or ensure the knowledge base contains relevant documents.
        """

    /// Maximum allowed retrieval limit to prevent excessive resource usage.
    private static let maxRetrievalLimit = 1000

    // MARK: - Properties

    /// The retriever used to find relevant documents for queries.
    private let retriever: any Retriever

    /// The LLM provider used for response synthesis.
    private let llmProvider: any LLMProvider

    /// The context builder used to format retrieval results for the LLM.
    private let contextBuilder: ContextBuilder

    /// The synthesizer used to generate responses from context.
    private let synthesizer: any ResponseSynthesizer

    /// An optional query transformer applied before retrieval.
    ///
    /// When set, the transformer modifies the user's query before it is used
    /// for retrieval. This can improve retrieval quality through techniques
    /// like query expansion, rephrasing, or HyDE.
    ///
    /// Use `setQueryTransformer(_:)` to modify this property.
    public private(set) var queryTransformer: (any QueryTransformer)?

    // MARK: - Initialization

    /// Creates a new query engine with the specified components.
    ///
    /// - Parameters:
    ///   - retriever: The retriever for finding relevant documents.
    ///   - llmProvider: The LLM provider for response generation.
    ///   - contextBuilder: The context builder for formatting results.
    ///                     Defaults to a new `ContextBuilder()` with standard settings.
    ///   - synthesizer: The response synthesizer. If `nil`, creates a
    ///                  `CompactSynthesizer` using the provided `llmProvider`.
    ///
    /// Example:
    /// ```swift
    /// // Minimal initialization
    /// let engine = QueryEngine(
    ///     retriever: vectorRetriever,
    ///     llmProvider: openAIProvider
    /// )
    ///
    /// // Full customization
    /// let engine = QueryEngine(
    ///     retriever: hybridRetriever,
    ///     llmProvider: claudeProvider,
    ///     contextBuilder: ContextBuilder(includeScores: true),
    ///     synthesizer: CustomSynthesizer()
    /// )
    /// ```
    public init(
        retriever: any Retriever,
        llmProvider: any LLMProvider,
        contextBuilder: ContextBuilder = ContextBuilder(),
        synthesizer: (any ResponseSynthesizer)? = nil
    ) {
        self.retriever = retriever
        self.llmProvider = llmProvider
        self.contextBuilder = contextBuilder
        self.synthesizer = synthesizer ?? CompactSynthesizer(llmProvider: llmProvider)
    }

    // MARK: - Public Methods

    /// Executes a RAG query and returns the complete response.
    ///
    /// This method performs the full RAG pipeline synchronously, returning
    /// the final response once generation is complete. Use this for cases
    /// where you need the full response before proceeding.
    ///
    /// The pipeline stages are:
    /// 1. Transform the query (if a transformer is configured)
    /// 2. Retrieve relevant chunks from the vector store
    /// 3. Build context from the retrieved chunks
    /// 4. Synthesize the response using the LLM
    ///
    /// - Parameters:
    ///   - question: The user's question or query text.
    ///   - options: Configuration options for retrieval and generation.
    ///              Defaults to `QueryOptions.default`.
    /// - Returns: A `RAGResponse` containing the answer, sources, and metadata.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails,
    ///           `ZoniError.generationFailed` if synthesis fails.
    ///
    /// Example:
    /// ```swift
    /// let response = try await engine.query(
    ///     "What are the benefits of Swift concurrency?",
    ///     options: QueryOptions(retrievalLimit: 10)
    /// )
    /// print("Answer: \(response.answer)")
    /// print("Based on \(response.sources.count) sources")
    /// if let totalTime = response.metadata.totalTime {
    ///     print("Completed in \(totalTime)")
    /// }
    /// ```
    public func query(
        _ question: String,
        options: QueryOptions = .default
    ) async throws -> RAGResponse {
        // Validate input
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw ZoniError.invalidConfiguration(reason: "Query cannot be empty")
        }

        // Validate options
        guard options.retrievalLimit > 0 else {
            throw ZoniError.invalidConfiguration(
                reason: "Retrieval limit must be greater than zero, got \(options.retrievalLimit)"
            )
        }
        guard options.retrievalLimit <= Self.maxRetrievalLimit else {
            throw ZoniError.invalidConfiguration(
                reason: "Retrieval limit of \(options.retrievalLimit) exceeds maximum of \(Self.maxRetrievalLimit)"
            )
        }
        guard options.maxContextTokens > 0 else {
            throw ZoniError.invalidConfiguration(
                reason: "maxContextTokens must be greater than zero, got \(options.maxContextTokens)"
            )
        }

        let startTime = ContinuousClock.now

        // Transform query if transformer is configured
        let effectiveQuery: String
        if let transformer = queryTransformer {
            effectiveQuery = try await transformer.transform(question)
        } else {
            effectiveQuery = question
        }

        // Retrieve relevant chunks
        let retrievalStartTime = ContinuousClock.now
        let results = try await retriever.retrieve(
            query: effectiveQuery,
            limit: options.retrievalLimit,
            filter: options.filter
        )
        let retrievalTime = ContinuousClock.now - retrievalStartTime

        // Handle no results case gracefully
        if results.isEmpty {
            let totalTime = ContinuousClock.now - startTime
            return RAGResponse(
                answer: Self.noResultsMessage,
                sources: [],
                metadata: RAGResponseMetadata(
                    retrievalTime: retrievalTime,
                    totalTime: totalTime,
                    model: llmProvider.model,
                    chunksRetrieved: 0
                )
            )
        }

        // Build context from retrieval results
        let context = contextBuilder.build(
            query: question,
            results: results,
            maxTokens: options.maxContextTokens,
            includeMetadata: options.includeMetadata
        )

        // Synthesize response
        let generationStartTime = ContinuousClock.now
        let answer = try await synthesizer.synthesize(
            query: question,
            context: context,
            results: results,
            options: options
        )
        let generationTime = ContinuousClock.now - generationStartTime

        let totalTime = ContinuousClock.now - startTime

        return RAGResponse(
            answer: answer,
            sources: results,
            metadata: RAGResponseMetadata(
                retrievalTime: retrievalTime,
                generationTime: generationTime,
                totalTime: totalTime,
                model: llmProvider.model,
                chunksRetrieved: results.count
            )
        )
    }

    /// Executes a RAG query with streaming response generation.
    ///
    /// This method returns an async stream that yields events as the RAG pipeline
    /// progresses through retrieval and generation. Use this for real-time display
    /// of responses or progress feedback to users.
    ///
    /// ## UI Updates
    ///
    /// When using streaming for UI updates, ensure you dispatch to MainActor:
    ///
    /// ```swift
    /// for try await event in engine.streamQuery("question") {
    ///     switch event {
    ///     case .generationChunk(let text):
    ///         await MainActor.run {
    ///             self.displayText.append(text)  // UI update
    ///         }
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    ///
    /// ## Cancellation
    ///
    /// The stream supports cooperative cancellation. Cancelling the consuming task
    /// will terminate the stream and clean up resources.
    ///
    /// The stream yields events in this order:
    /// 1. `.retrievalStarted` - When retrieval begins
    /// 2. `.retrievalComplete([RetrievalResult])` - When retrieval finishes
    /// 3. `.generationStarted` - When LLM generation begins
    /// 4. `.generationChunk(String)` - For each generated text chunk
    /// 5. `.generationComplete(String)` - When generation finishes with full text
    /// 6. `.complete(RAGResponse)` - When the entire operation completes
    ///
    /// If an error occurs, `.error(ZoniError)` is yielded and the stream terminates.
    ///
    /// - Parameters:
    ///   - question: The user's question or query text.
    ///   - options: Configuration options for retrieval and generation.
    ///              Defaults to `QueryOptions.default`.
    /// - Returns: An async throwing stream of `RAGStreamEvent` values.
    ///
    /// Example:
    /// ```swift
    /// var fullResponse = ""
    /// for try await event in engine.streamQuery("Explain async/await") {
    ///     switch event {
    ///     case .retrievalStarted:
    ///         print("Searching knowledge base...")
    ///     case .retrievalComplete(let sources):
    ///         print("Found \(sources.count) relevant sources")
    ///     case .generationStarted:
    ///         print("Generating response...")
    ///     case .generationChunk(let chunk):
    ///         print(chunk, terminator: "")
    ///         fullResponse += chunk
    ///     case .generationComplete(let answer):
    ///         print("\n--- Generation complete ---")
    ///     case .complete(let response):
    ///         print("Total time: \(response.metadata.totalTime ?? .zero)")
    ///     case .error(let error):
    ///         print("Error: \(error.localizedDescription)")
    ///     }
    /// }
    /// ```
    public nonisolated func streamQuery(
        _ question: String,
        options: QueryOptions = .default
    ) -> AsyncThrowingStream<RAGStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Validate input
                    let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedQuestion.isEmpty else {
                        throw ZoniError.invalidConfiguration(reason: "Query cannot be empty")
                    }

                    // Validate options
                    guard options.retrievalLimit > 0 else {
                        throw ZoniError.invalidConfiguration(
                            reason: "Retrieval limit must be greater than zero, got \(options.retrievalLimit)"
                        )
                    }
                    guard options.retrievalLimit <= QueryEngine.maxRetrievalLimit else {
                        throw ZoniError.invalidConfiguration(
                            reason: "Retrieval limit of \(options.retrievalLimit) exceeds maximum of \(QueryEngine.maxRetrievalLimit)"
                        )
                    }
                    guard options.maxContextTokens > 0 else {
                        throw ZoniError.invalidConfiguration(
                            reason: "maxContextTokens must be greater than zero, got \(options.maxContextTokens)"
                        )
                    }

                    let startTime = ContinuousClock.now

                    // Check for cancellation before starting
                    try Task.checkCancellation()

                    // Yield retrieval started
                    continuation.yield(.retrievalStarted)

                    // Capture transformer once to avoid race conditions
                    let capturedTransformer = await self.queryTransformer

                    // Transform query if transformer is configured
                    let effectiveQuery: String
                    if let transformer = capturedTransformer {
                        effectiveQuery = try await transformer.transform(question)
                    } else {
                        effectiveQuery = question
                    }

                    // Check for cancellation after transformation
                    try Task.checkCancellation()

                    // Retrieve relevant chunks
                    let retrievalStartTime = ContinuousClock.now
                    let retriever = await self.retriever
                    let results = try await retriever.retrieve(
                        query: effectiveQuery,
                        limit: options.retrievalLimit,
                        filter: options.filter
                    )
                    let retrievalTime = ContinuousClock.now - retrievalStartTime

                    // Yield retrieval complete
                    continuation.yield(.retrievalComplete(results))

                    // Check for cancellation after retrieval
                    try Task.checkCancellation()

                    // Handle no results case
                    if results.isEmpty {
                        continuation.yield(.generationComplete(QueryEngine.noResultsMessage))

                        let totalTime = ContinuousClock.now - startTime
                        let llmProvider = await self.llmProvider
                        let response = RAGResponse(
                            answer: QueryEngine.noResultsMessage,
                            sources: [],
                            metadata: RAGResponseMetadata(
                                retrievalTime: retrievalTime,
                                totalTime: totalTime,
                                model: llmProvider.model,
                                chunksRetrieved: 0
                            )
                        )
                        continuation.yield(.complete(response))
                        continuation.finish()
                        return
                    }

                    // Build context
                    let contextBuilder = await self.contextBuilder
                    let context = contextBuilder.build(
                        query: question,
                        results: results,
                        maxTokens: options.maxContextTokens,
                        includeMetadata: options.includeMetadata
                    )

                    // Check for cancellation after context building
                    try Task.checkCancellation()

                    // Yield generation started
                    continuation.yield(.generationStarted)

                    // Stream synthesis
                    let generationStartTime = ContinuousClock.now
                    let synthesizer = await self.synthesizer
                    let stream = synthesizer.streamSynthesize(
                        query: question,
                        context: context,
                        results: results,
                        options: options
                    )

                    var responseChunks: [String] = []
                    for try await chunk in stream {
                        try Task.checkCancellation()
                        responseChunks.append(chunk)
                        continuation.yield(.generationChunk(chunk))
                    }
                    let generationTime = ContinuousClock.now - generationStartTime
                    let fullResponse = responseChunks.joined()

                    // Yield generation complete
                    continuation.yield(.generationComplete(fullResponse))

                    // Build and yield complete response
                    let totalTime = ContinuousClock.now - startTime
                    let llmProvider = await self.llmProvider
                    let response = RAGResponse(
                        answer: fullResponse,
                        sources: results,
                        metadata: RAGResponseMetadata(
                            retrievalTime: retrievalTime,
                            generationTime: generationTime,
                            totalTime: totalTime,
                            model: llmProvider.model,
                            chunksRetrieved: results.count
                        )
                    )
                    continuation.yield(.complete(response))
                    continuation.finish()

                } catch is CancellationError {
                    // Handle task cancellation gracefully
                    continuation.finish(throwing: CancellationError())
                } catch {
                    // Convert to ZoniError and throw (consumers catch in for-await-in loop)
                    let zoniError: ZoniError
                    if let ze = error as? ZoniError {
                        zoniError = ze
                    } else {
                        zoniError = .generationFailed(reason: error.localizedDescription)
                    }
                    continuation.finish(throwing: zoniError)
                }
            }

            // Ensure task is cancelled when stream consumer cancels
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Retrieves relevant chunks for a query without generating a response.
    ///
    /// This method provides direct access to the retrieval stage of the RAG pipeline,
    /// useful for debugging, testing retrieval quality, or building custom pipelines.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return. Defaults to 5.
    ///   - filter: Optional metadata filter to apply to results. Defaults to `nil`.
    /// - Returns: An array of retrieval results, ranked by relevance score.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    ///
    /// Example:
    /// ```swift
    /// // Simple retrieval
    /// let results = try await engine.retrieve("Swift concurrency")
    /// for result in results {
    ///     print("Score: \(result.score)")
    ///     print("Content: \(result.chunk.content.prefix(100))...")
    /// }
    ///
    /// // Filtered retrieval
    /// let docResults = try await engine.retrieve(
    ///     "async await",
    ///     limit: 10,
    ///     filter: .equals("source", "documentation")
    /// )
    /// ```
    public func retrieve(
        _ query: String,
        limit: Int = 5,
        filter: MetadataFilter? = nil
    ) async throws -> [RetrievalResult] {
        // Validate input
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw ZoniError.invalidConfiguration(reason: "Query cannot be empty")
        }

        // Validate limit
        guard limit > 0 else {
            throw ZoniError.invalidConfiguration(
                reason: "Retrieval limit must be greater than zero, got \(limit)"
            )
        }
        guard limit <= Self.maxRetrievalLimit else {
            throw ZoniError.invalidConfiguration(
                reason: "Retrieval limit of \(limit) exceeds maximum of \(Self.maxRetrievalLimit)"
            )
        }

        return try await retriever.retrieve(
            query: trimmedQuery,
            limit: limit,
            filter: filter
        )
    }

    // MARK: - Configuration Methods

    /// Sets the query transformer used to modify queries before retrieval.
    ///
    /// - Parameter transformer: The transformer to use, or `nil` to disable transformation.
    ///
    /// Example:
    /// ```swift
    /// // Enable query expansion
    /// await engine.setQueryTransformer(QueryExpander(llmProvider: provider))
    ///
    /// // Disable transformation
    /// await engine.setQueryTransformer(nil)
    /// ```
    public func setQueryTransformer(_ transformer: (any QueryTransformer)?) {
        self.queryTransformer = transformer
    }
}

// MARK: - CustomStringConvertible

extension QueryEngine: CustomStringConvertible {
    public nonisolated var description: String {
        "QueryEngine()"
    }
}
