// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RefineSynthesizer.swift - Iterative refinement response synthesis.

// MARK: - RefineSynthesizer

/// A response synthesizer that iteratively refines answers with each context chunk.
///
/// `RefineSynthesizer` implements an iterative refinement strategy where the answer
/// is progressively improved as each context chunk is processed. This approach is
/// particularly effective when dealing with large context sets that might exceed
/// token limits in a single prompt, or when incremental refinement produces higher
/// quality answers than one-shot generation.
///
/// ## Synthesis Strategy
///
/// The refinement synthesis strategy:
/// 1. Generates an initial answer from the first context chunk using `initialPrompt`
/// 2. For each subsequent chunk, refines the existing answer using `refinePrompt`
/// 3. The LLM is instructed to incorporate new relevant information while preserving
///    useful content from the existing answer
/// 4. If new context is not relevant, the existing answer is returned unchanged
///
/// This iterative approach allows the synthesizer to handle arbitrarily large context
/// sets while maintaining coherent, well-integrated answers.
///
/// ## Thread Safety
///
/// `RefineSynthesizer` is implemented as an actor to ensure thread-safe access to
/// its mutable prompt configuration. The `streamSynthesize` method is marked
/// `nonisolated` since it returns immediately and spawns an internal task for
/// actor-isolated operations.
///
/// ## Example Usage
///
/// ```swift
/// let synthesizer = RefineSynthesizer(llmProvider: openAIProvider)
///
/// // Iterative refinement synthesis
/// let response = try await synthesizer.synthesize(
///     query: "What are the key features of Swift?",
///     context: formattedContext,
///     results: retrievalResults,  // Multiple chunks to refine through
///     options: .default
/// )
///
/// // Streaming synthesis (streams only final refinement)
/// for try await chunk in synthesizer.streamSynthesize(
///     query: "Explain Swift concurrency",
///     context: formattedContext,
///     results: retrievalResults,
///     options: .default
/// ) {
///     print(chunk, terminator: "")
/// }
/// ```
///
/// ## Customization
///
/// Both the initial and refinement prompt templates can be customized:
///
/// ```swift
/// let synthesizer = RefineSynthesizer(llmProvider: provider)
/// synthesizer.initialPrompt = """
///     Context: {context}
///     Question: {query}
///     Provide an initial answer:
///     """
/// synthesizer.refinePrompt = """
///     Existing answer: {existing_answer}
///     New context: {context}
///     Question: {query}
///     Refine the answer:
///     """
/// ```
///
/// ## Performance Considerations
///
/// The refinement strategy requires N LLM calls for N context chunks, making it
/// slower than compact synthesis but more capable of handling large context sets.
/// Consider using `CompactSynthesizer` when context fits within token limits and
/// speed is a priority.
public actor RefineSynthesizer: ResponseSynthesizer {

    // MARK: - Properties

    /// Message returned when no retrieval results are available.
    private static let noResultsMessage = "No relevant information found to answer the question."

    /// The LLM provider used for text generation.
    private let llmProvider: any LLMProvider

    /// The template used to generate the initial answer from the first chunk.
    ///
    /// The template must contain `{context}` and `{query}` placeholders that will
    /// be replaced with actual values during synthesis.
    /// Defaults to `RAGPrompts.refineInitialTemplate`.
    public var initialPrompt: String = RAGPrompts.refineInitialTemplate

    /// The template used to refine the answer with each subsequent chunk.
    ///
    /// The template must contain `{existing_answer}`, `{context}`, and `{query}`
    /// placeholders that will be replaced with actual values during refinement.
    /// Defaults to `RAGPrompts.refineIterativeTemplate`.
    public var refinePrompt: String = RAGPrompts.refineIterativeTemplate

    // MARK: - Initialization

    /// Creates a new refine synthesizer with the specified LLM provider.
    ///
    /// - Parameter llmProvider: The LLM provider to use for text generation.
    ///                          Must conform to `LLMProvider` protocol.
    ///
    /// Example:
    /// ```swift
    /// let provider = OpenAIProvider(apiKey: "sk-...", model: "gpt-4")
    /// let synthesizer = RefineSynthesizer(llmProvider: provider)
    /// ```
    public init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - ResponseSynthesizer Protocol

    /// Synthesizes a response by iteratively refining with each context chunk.
    ///
    /// This method processes retrieval results sequentially, generating an initial
    /// answer from the first chunk and then refining it with each subsequent chunk.
    /// The LLM is instructed to incorporate relevant new information while preserving
    /// useful content from the existing answer.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string (not used directly; chunks are
    ///              processed individually from results).
    ///   - results: The retrieval results containing chunks to process iteratively.
    ///              Each chunk's content is accessed via `results[i].chunk.content`.
    ///   - options: Query options controlling generation behavior, including
    ///              temperature and optional system prompt override.
    /// - Returns: The final refined answer after processing all chunks.
    /// - Throws: `ZoniError.generationFailed` if any LLM call fails,
    ///           `ZoniError.contextTooLong` if a prompt exceeds token limits.
    ///
    /// Example:
    /// ```swift
    /// let answer = try await synthesizer.synthesize(
    ///     query: "What are actors in Swift?",
    ///     context: formattedContext,
    ///     results: retrievedChunks,
    ///     options: QueryOptions(temperature: 0.7)
    /// )
    /// ```
    public func synthesize(
        query: String,
        context: String,
        results: [RetrievalResult],
        options: QueryOptions
    ) async throws -> String {
        // Handle empty results case
        guard !results.isEmpty else {
            return Self.noResultsMessage
        }

        let llmOptions = LLMOptions(temperature: options.temperature)
        let effectiveSystemPrompt = options.systemPrompt ?? RAGPrompts.defaultSystemPrompt

        // Generate initial answer from first chunk
        let firstChunkContent = results[0].chunk.content
        let initialPromptText = buildInitialPrompt(query: query, context: firstChunkContent)

        var currentAnswer = try await llmProvider.generate(
            prompt: initialPromptText,
            systemPrompt: effectiveSystemPrompt,
            options: llmOptions
        )

        // Refine with each subsequent chunk
        for i in 1..<results.count {
            try Task.checkCancellation()
            let chunkContent = results[i].chunk.content
            let refinePromptText = buildRefinePrompt(
                query: query,
                context: chunkContent,
                existingAnswer: currentAnswer
            )

            currentAnswer = try await llmProvider.generate(
                prompt: refinePromptText,
                systemPrompt: effectiveSystemPrompt,
                options: llmOptions
            )
        }

        return currentAnswer
    }

    /// Streams a synthesized response, streaming only the final refinement step.
    ///
    /// This method processes all chunks non-streaming except for the final refinement,
    /// which is streamed to provide real-time feedback. For single-chunk results,
    /// the initial generation is streamed.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string (not used directly; chunks are
    ///              processed individually from results).
    ///   - results: The retrieval results containing chunks to process iteratively.
    ///   - options: Query options controlling generation behavior, including
    ///              temperature and optional system prompt override.
    /// - Returns: An async throwing stream that yields response text chunks from
    ///            the final refinement step. The stream completes when synthesis
    ///            is finished, or throws on error.
    ///
    /// Example:
    /// ```swift
    /// var fullResponse = ""
    /// for try await chunk in synthesizer.streamSynthesize(
    ///     query: "Explain Swift actors",
    ///     context: formattedContext,
    ///     results: results,
    ///     options: .default
    /// ) {
    ///     print(chunk, terminator: "")
    ///     fullResponse += chunk
    /// }
    /// ```
    public nonisolated func streamSynthesize(
        query: String,
        context: String,
        results: [RetrievalResult],
        options: QueryOptions
    ) -> AsyncThrowingStream<String, Error> {
        // Capture the LLM provider to avoid actor isolation issues
        let llmProvider = self.llmProvider

        return AsyncThrowingStream { continuation in
            let task = Task {
                // Handle empty results case
                guard !results.isEmpty else {
                    continuation.yield(Self.noResultsMessage)
                    continuation.finish()
                    return
                }

                let llmOptions = LLMOptions(temperature: options.temperature)
                let effectiveSystemPrompt = options.systemPrompt ?? RAGPrompts.defaultSystemPrompt

                do {
                    // Access actor-isolated properties within the task
                    let initialPromptTemplate = await self.initialPrompt
                    let refinePromptTemplate = await self.refinePrompt

                    // Check for cancellation before starting
                    try Task.checkCancellation()

                    // If only one result, stream the initial generation
                    if results.count == 1 {
                        let firstChunkContent = results[0].chunk.content
                        let initialPromptText = initialPromptTemplate
                            .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: firstChunkContent)
                            .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)

                        let stream = llmProvider.stream(
                            prompt: initialPromptText,
                            systemPrompt: effectiveSystemPrompt,
                            options: llmOptions
                        )

                        for try await chunk in stream {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                        return
                    }

                    // Multiple results: process all but last non-streaming
                    let firstChunkContent = results[0].chunk.content
                    let initialPromptText = initialPromptTemplate
                        .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: firstChunkContent)
                        .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)

                    var currentAnswer = try await llmProvider.generate(
                        prompt: initialPromptText,
                        systemPrompt: effectiveSystemPrompt,
                        options: llmOptions
                    )

                    // Refine with all chunks except the last (non-streaming)
                    for i in 1..<(results.count - 1) {
                        try Task.checkCancellation()

                        let chunkContent = results[i].chunk.content
                        let refinePromptText = refinePromptTemplate
                            .replacingOccurrences(of: RAGPrompts.existingAnswerPlaceholder, with: currentAnswer)
                            .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: chunkContent)
                            .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)

                        currentAnswer = try await llmProvider.generate(
                            prompt: refinePromptText,
                            systemPrompt: effectiveSystemPrompt,
                            options: llmOptions
                        )
                    }

                    // Stream the final refinement
                    let lastChunkContent = results[results.count - 1].chunk.content
                    let finalRefinePromptText = refinePromptTemplate
                        .replacingOccurrences(of: RAGPrompts.existingAnswerPlaceholder, with: currentAnswer)
                        .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: lastChunkContent)
                        .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)

                    let stream = llmProvider.stream(
                        prompt: finalRefinePromptText,
                        systemPrompt: effectiveSystemPrompt,
                        options: llmOptions
                    )

                    for try await chunk in stream {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Methods

    /// Builds the initial prompt by replacing placeholders in the template.
    ///
    /// - Parameters:
    ///   - query: The user's query to insert into the template.
    ///   - context: The first chunk's content to insert into the template.
    /// - Returns: The complete initial prompt string ready for LLM generation.
    private func buildInitialPrompt(query: String, context: String) -> String {
        initialPrompt
            .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: context)
            .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)
    }

    /// Builds the refinement prompt by replacing placeholders in the template.
    ///
    /// - Parameters:
    ///   - query: The user's query to insert into the template.
    ///   - context: The current chunk's content to insert into the template.
    ///   - existingAnswer: The current answer to be refined.
    /// - Returns: The complete refinement prompt string ready for LLM generation.
    private func buildRefinePrompt(query: String, context: String, existingAnswer: String) -> String {
        refinePrompt
            .replacingOccurrences(of: RAGPrompts.existingAnswerPlaceholder, with: existingAnswer)
            .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: context)
            .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)
    }

    // MARK: - Configuration Methods

    /// Updates the initial prompt template used for the first chunk.
    ///
    /// The template must contain `{context}` and `{query}` placeholders.
    ///
    /// - Parameter newPrompt: The new initial prompt template to use.
    ///
    /// Example:
    /// ```swift
    /// await synthesizer.setInitialPrompt("""
    ///     Reference:
    ///     {context}
    ///
    ///     Question: {query}
    ///
    ///     Initial answer:
    ///     """)
    /// ```
    public func setInitialPrompt(_ newPrompt: String) {
        initialPrompt = newPrompt
    }

    /// Updates the refinement prompt template used for subsequent chunks.
    ///
    /// The template must contain `{existing_answer}`, `{context}`, and `{query}` placeholders.
    ///
    /// - Parameter newPrompt: The new refinement prompt template to use.
    ///
    /// Example:
    /// ```swift
    /// await synthesizer.setRefinePrompt("""
    ///     Current answer: {existing_answer}
    ///     Additional context: {context}
    ///     Original question: {query}
    ///
    ///     Improved answer:
    ///     """)
    /// ```
    public func setRefinePrompt(_ newPrompt: String) {
        refinePrompt = newPrompt
    }
}
