// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// CompactSynthesizer.swift - Simple single-prompt response synthesis.

// MARK: - CompactSynthesizer

/// A response synthesizer that uses a single compact prompt for generation.
///
/// `CompactSynthesizer` implements the simplest and most efficient synthesis strategy,
/// combining all retrieved context into a single prompt for one-shot answer generation.
/// This approach works well for most RAG use cases where the context fits within the
/// model's token limits.
///
/// ## Synthesis Strategy
///
/// The compact synthesis strategy:
/// 1. Formats all retrieved chunks into a single context string
/// 2. Builds a prompt using the configurable template with placeholders replaced
/// 3. Sends the complete prompt to the LLM in a single request
/// 4. Returns the generated response
///
/// This is the fastest synthesis method but may not handle very large context sets
/// as effectively as iterative refinement or tree summarization approaches.
///
/// ## Thread Safety
///
/// `CompactSynthesizer` is implemented as an actor to ensure thread-safe access to
/// its mutable prompt configuration. The `streamSynthesize` and `buildPrompt` methods
/// are marked `nonisolated` since they either return immediately or are pure functions.
///
/// ## Example Usage
///
/// ```swift
/// let synthesizer = CompactSynthesizer(llmProvider: openAIProvider)
///
/// // Single response synthesis
/// let response = try await synthesizer.synthesize(
///     query: "What is Swift concurrency?",
///     context: formattedContext,
///     results: retrievalResults,
///     options: .default
/// )
///
/// // Streaming synthesis
/// for try await chunk in synthesizer.streamSynthesize(
///     query: "Explain async/await",
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
/// Both the system prompt and user prompt template can be customized:
///
/// ```swift
/// let synthesizer = CompactSynthesizer(llmProvider: provider)
/// await synthesizer.setSystemPrompt("You are a coding expert.")
/// await synthesizer.setPromptTemplate("""
///     Code Context:
///     {context}
///
///     Developer Question: {query}
///
///     Provide a detailed answer with code examples:
///     """)
/// ```
public actor CompactSynthesizer: ResponseSynthesizer {

    // MARK: - Properties

    /// The LLM provider used for text generation.
    private let llmProvider: any LLMProvider

    /// The system prompt used to guide the LLM's behavior.
    ///
    /// This prompt establishes the model's role and guidelines for answering
    /// questions based on provided context. Defaults to `RAGPrompts.defaultSystemPrompt`.
    public var systemPrompt: String = RAGPrompts.defaultSystemPrompt

    /// The template used to construct the user prompt.
    ///
    /// The template must contain `{context}` and `{query}` placeholders that will
    /// be replaced with actual values during synthesis. Defaults to `RAGPrompts.compactTemplate`.
    public var promptTemplate: String = RAGPrompts.compactTemplate

    // MARK: - Initialization

    /// Creates a new compact synthesizer with the specified LLM provider.
    ///
    /// - Parameter llmProvider: The LLM provider to use for text generation.
    ///                          Must conform to `LLMProvider` protocol.
    ///
    /// Example:
    /// ```swift
    /// let provider = OpenAIProvider(apiKey: "sk-...", model: "gpt-4")
    /// let synthesizer = CompactSynthesizer(llmProvider: provider)
    /// ```
    public init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - ResponseSynthesizer Protocol

    /// Synthesizes a complete response from query and retrieval context.
    ///
    /// This method builds a prompt by replacing placeholders in the template with
    /// the provided context and query, then calls the LLM to generate a response.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string constructed from retrieval results.
    ///   - results: The raw retrieval results (available for future enhancements
    ///              such as citation generation).
    ///   - options: Query options controlling generation behavior, including
    ///              temperature and optional system prompt override.
    /// - Returns: The synthesized response text from the LLM.
    /// - Throws: `ZoniError.generationFailed` if the LLM call fails,
    ///           `ZoniError.contextTooLong` if the prompt exceeds token limits.
    ///
    /// Example:
    /// ```swift
    /// let answer = try await synthesizer.synthesize(
    ///     query: "What are the benefits of Swift concurrency?",
    ///     context: "Swift concurrency provides structured concurrency...",
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
        let prompt = buildPrompt(query: query, context: context)
        let effectiveSystemPrompt = options.systemPrompt ?? systemPrompt
        let llmOptions = LLMOptions(temperature: options.temperature)

        return try await llmProvider.generate(
            prompt: prompt,
            systemPrompt: effectiveSystemPrompt,
            options: llmOptions
        )
    }

    /// Streams a synthesized response from query and retrieval context.
    ///
    /// This method returns an async stream that yields response chunks as they are
    /// generated by the LLM. The stream is created immediately (non-blocking) and
    /// generation begins when the stream is consumed.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string constructed from retrieval results.
    ///   - results: The raw retrieval results (available for future enhancements
    ///              such as citation generation).
    ///   - options: Query options controlling generation behavior, including
    ///              temperature and optional system prompt override.
    /// - Returns: An async throwing stream that yields response text chunks as
    ///            they are generated. The stream completes when synthesis is
    ///            finished, or throws on error.
    ///
    /// Example:
    /// ```swift
    /// var fullResponse = ""
    /// for try await chunk in synthesizer.streamSynthesize(
    ///     query: "Explain actors in Swift",
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
        // Capture values needed inside the stream to avoid actor isolation issues
        let llmProvider = self.llmProvider

        return AsyncThrowingStream { continuation in
            let task = Task {
                // Access actor-isolated properties within the task
                let promptTemplate = await self.promptTemplate
                let prompt = Self.buildPromptStatic(query: query, context: context, template: promptTemplate)
                let actorSystemPrompt = await self.systemPrompt
                let effectiveSystemPrompt = options.systemPrompt ?? actorSystemPrompt
                let llmOptions = LLMOptions(temperature: options.temperature)

                let stream = llmProvider.stream(
                    prompt: prompt,
                    systemPrompt: effectiveSystemPrompt,
                    options: llmOptions
                )

                do {
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

    /// Builds the complete prompt by replacing placeholders in the template.
    ///
    /// This method substitutes the `{context}` and `{query}` placeholders in the
    /// prompt template with the provided values.
    ///
    /// - Parameters:
    ///   - query: The user's query to insert into the template.
    ///   - context: The formatted context to insert into the template.
    /// - Returns: The complete prompt string ready for LLM generation.
    private func buildPrompt(query: String, context: String) -> String {
        promptTemplate
            .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: context)
            .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)
    }

    /// Static version of buildPrompt for use in nonisolated contexts.
    ///
    /// - Parameters:
    ///   - query: The user's query to insert into the template.
    ///   - context: The formatted context to insert into the template.
    ///   - template: The prompt template to use.
    /// - Returns: The complete prompt string ready for LLM generation.
    private static func buildPromptStatic(query: String, context: String, template: String) -> String {
        template
            .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: context)
            .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)
    }

    // MARK: - Configuration Methods

    /// Updates the system prompt used for generation.
    ///
    /// - Parameter newPrompt: The new system prompt to use.
    ///
    /// Example:
    /// ```swift
    /// await synthesizer.setSystemPrompt("""
    ///     You are a technical documentation expert.
    ///     Always provide code examples when relevant.
    ///     """)
    /// ```
    public func setSystemPrompt(_ newPrompt: String) {
        systemPrompt = newPrompt
    }

    /// Updates the prompt template used for generation.
    ///
    /// The template must contain `{context}` and `{query}` placeholders.
    ///
    /// - Parameter newTemplate: The new prompt template to use.
    ///
    /// Example:
    /// ```swift
    /// await synthesizer.setPromptTemplate("""
    ///     Reference Material:
    ///     {context}
    ///
    ///     User Question: {query}
    ///
    ///     Please provide a comprehensive answer:
    ///     """)
    /// ```
    public func setPromptTemplate(_ newTemplate: String) {
        promptTemplate = newTemplate
    }
}
