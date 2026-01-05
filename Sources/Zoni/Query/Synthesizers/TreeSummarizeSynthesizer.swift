// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// TreeSummarizeSynthesizer.swift - Hierarchical tree summarization synthesis.

// MARK: - TreeSummarizeSynthesizer

/// A response synthesizer that uses hierarchical tree summarization for large context sets.
///
/// `TreeSummarizeSynthesizer` implements a recursive summarization strategy that handles
/// very large context sets by progressively combining and summarizing groups of chunks
/// until a single coherent answer emerges. This approach is effective when the total
/// context exceeds the model's token limits.
///
/// ## Synthesis Strategy
///
/// The tree summarization strategy works as follows:
/// 1. Start with the content from all retrieved chunks
/// 2. Group chunks into sets of `groupSize` (default 4)
/// 3. Summarize each group using the LLM with the query context
/// 4. Collect the summaries and repeat steps 2-3 until only one summary remains
/// 5. Return the final summary as the answer
///
/// This hierarchical approach ensures that all retrieved information is considered,
/// even when the total context would exceed model limits in a single prompt.
///
/// ## Thread Safety
///
/// `TreeSummarizeSynthesizer` is implemented as an actor to ensure thread-safe access
/// to its mutable configuration properties. The `streamSynthesize` method is marked
/// `nonisolated` since it returns immediately with an `AsyncThrowingStream`.
///
/// ## Example Usage
///
/// ```swift
/// let synthesizer = TreeSummarizeSynthesizer(llmProvider: openAIProvider)
///
/// // Single response synthesis
/// let response = try await synthesizer.synthesize(
///     query: "Summarize the key findings from this research",
///     context: formattedContext,
///     results: retrievalResults,
///     options: .default
/// )
///
/// // Streaming synthesis (streams final level only)
/// for try await chunk in synthesizer.streamSynthesize(
///     query: "What are the main themes in these documents?",
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
/// The group size and summarization prompt can be customized:
///
/// ```swift
/// let synthesizer = TreeSummarizeSynthesizer(
///     llmProvider: provider,
///     groupSize: 6  // Larger groups for fewer summarization levels
/// )
/// await synthesizer.setSummarizePrompt("""
///     Multiple document excerpts:
///     {context}
///
///     Based on these excerpts, answer: {query}
///
///     Synthesized response:
///     """)
/// ```
///
/// ## Performance Considerations
///
/// - Smaller `groupSize` values create more summarization levels but handle larger contexts
/// - Larger `groupSize` values are faster but may hit token limits sooner
/// - Each summarization level requires LLM calls proportional to `ceil(chunks / groupSize)`
public actor TreeSummarizeSynthesizer: ResponseSynthesizer {

    // MARK: - Properties

    /// Message returned when no retrieval results are available.
    private static let noResultsMessage = "No relevant information found to answer the question."

    /// The LLM provider used for text generation.
    private let llmProvider: any LLMProvider

    /// The number of chunks to group together at each summarization level.
    ///
    /// Smaller values create more levels but handle larger contexts.
    /// Larger values are faster but may exceed token limits.
    /// Defaults to 4.
    public var groupSize: Int

    /// The prompt template used for summarization at each level.
    ///
    /// The template must contain `{context}` and `{query}` placeholders that will
    /// be replaced with the grouped content and query. Defaults to `RAGPrompts.treeSummarizeTemplate`.
    public var summarizePrompt: String = RAGPrompts.treeSummarizeTemplate

    /// The system prompt used to guide the LLM's behavior during summarization.
    ///
    /// Defaults to `RAGPrompts.defaultSystemPrompt`.
    public var systemPrompt: String = RAGPrompts.defaultSystemPrompt

    // MARK: - Initialization

    /// Creates a new tree summarization synthesizer with the specified LLM provider.
    ///
    /// - Parameters:
    ///   - llmProvider: The LLM provider to use for text generation.
    ///                  Must conform to `LLMProvider` protocol.
    ///   - groupSize: The number of chunks to group at each summarization level.
    ///                Must be at least 2. Defaults to 4.
    ///
    /// Example:
    /// ```swift
    /// let provider = OpenAIProvider(apiKey: "sk-...", model: "gpt-4")
    /// let synthesizer = TreeSummarizeSynthesizer(llmProvider: provider, groupSize: 4)
    /// ```
    public init(llmProvider: any LLMProvider, groupSize: Int = 4) {
        self.llmProvider = llmProvider
        self.groupSize = max(2, groupSize)  // Ensure at least 2 to make progress
    }

    // MARK: - ResponseSynthesizer Protocol

    /// Synthesizes a response using hierarchical tree summarization.
    ///
    /// This method recursively summarizes groups of chunks until a single
    /// coherent answer emerges. At each level, chunks are grouped and
    /// summarized with the query context.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string (not used directly; chunks are extracted from results).
    ///   - results: The retrieval results containing chunks to summarize.
    ///   - options: Query options controlling generation behavior.
    /// - Returns: The synthesized response text from hierarchical summarization.
    /// - Throws: `ZoniError.generationFailed` if any summarization step fails.
    ///
    /// Example:
    /// ```swift
    /// let answer = try await synthesizer.synthesize(
    ///     query: "What are the key findings?",
    ///     context: formattedContext,
    ///     results: retrievedChunks,
    ///     options: QueryOptions(temperature: 0.5)
    /// )
    /// ```
    public func synthesize(
        query: String,
        context: String,
        results: [RetrievalResult],
        options: QueryOptions
    ) async throws -> String {
        // Handle empty results
        guard !results.isEmpty else {
            return Self.noResultsMessage
        }

        // Start with chunk contents
        var currentLevel = results.map { $0.chunk.content }

        let effectiveSystemPrompt = options.systemPrompt ?? systemPrompt
        let llmOptions = LLMOptions(temperature: options.temperature)

        // Recursively summarize until we have a single summary
        while currentLevel.count > 1 {
            try Task.checkCancellation()
            let groups = currentLevel.chunked(into: groupSize)
            var nextLevel: [String] = []
            nextLevel.reserveCapacity(groups.count)

            for group in groups {
                try Task.checkCancellation()
                // Format group as [Source N]: content (sequential within each group)
                // Note: After first level, we're summarizing summaries, so numbering is relative
                let formattedContext = group.enumerated()
                    .map { "[Source \($0.offset + 1)]: \($0.element)" }
                    .joined(separator: "\n\n")

                let prompt = buildPrompt(query: query, context: formattedContext)

                let summary = try await llmProvider.generate(
                    prompt: prompt,
                    systemPrompt: effectiveSystemPrompt,
                    options: llmOptions
                )

                nextLevel.append(summary)
            }

            currentLevel = nextLevel
        }

        return currentLevel.first ?? "Unable to generate summary."
    }

    /// Streams a synthesized response using hierarchical tree summarization.
    ///
    /// Intermediate summarization levels are performed without streaming.
    /// Only the final summarization step (when `currentLevel.count <= groupSize`)
    /// is streamed to the caller.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string (not used directly).
    ///   - results: The retrieval results containing chunks to summarize.
    ///   - options: Query options controlling generation behavior.
    /// - Returns: An async throwing stream that yields response text chunks from
    ///            the final summarization level.
    ///
    /// Example:
    /// ```swift
    /// var fullResponse = ""
    /// for try await chunk in synthesizer.streamSynthesize(
    ///     query: "Summarize these findings",
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
                // Handle empty results
                guard !results.isEmpty else {
                    continuation.yield(Self.noResultsMessage)
                    continuation.finish()
                    return
                }

                do {
                    // Access actor-isolated properties within the task
                    let effectiveGroupSize = await self.groupSize
                    let effectiveSummarizePrompt = await self.summarizePrompt
                    let actorSystemPrompt = await self.systemPrompt
                    let effectiveSystemPrompt = options.systemPrompt ?? actorSystemPrompt
                    let llmOptions = LLMOptions(temperature: options.temperature)

                    // Start with chunk contents
                    var currentLevel = results.map { $0.chunk.content }

                    // Process intermediate levels without streaming
                    while currentLevel.count > effectiveGroupSize {
                        try Task.checkCancellation()

                        let groups = currentLevel.chunked(into: effectiveGroupSize)
                        var nextLevel: [String] = []
                        nextLevel.reserveCapacity(groups.count)

                        for group in groups {
                            try Task.checkCancellation()

                            // Format group as [Source N]: content (sequential within each group)
                            let formattedContext = group.enumerated()
                                .map { "[Source \($0.offset + 1)]: \($0.element)" }
                                .joined(separator: "\n\n")

                            let prompt = Self.buildPromptStatic(
                                query: query,
                                context: formattedContext,
                                template: effectiveSummarizePrompt
                            )

                            let summary = try await llmProvider.generate(
                                prompt: prompt,
                                systemPrompt: effectiveSystemPrompt,
                                options: llmOptions
                            )

                            nextLevel.append(summary)
                        }

                        currentLevel = nextLevel
                    }

                    // Stream the final summarization
                    if currentLevel.count == 1 {
                        // Only one item left, yield it directly
                        continuation.yield(currentLevel[0])
                        continuation.finish()
                    } else {
                        // Final level: stream the summarization
                        let formattedContext = currentLevel.enumerated()
                            .map { "[Source \($0.offset + 1)]: \($0.element)" }
                            .joined(separator: "\n\n")

                        let prompt = Self.buildPromptStatic(
                            query: query,
                            context: formattedContext,
                            template: effectiveSummarizePrompt
                        )

                        let stream = llmProvider.stream(
                            prompt: prompt,
                            systemPrompt: effectiveSystemPrompt,
                            options: llmOptions
                        )

                        for try await chunk in stream {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    }
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
    /// This is a pure function that substitutes the `{context}` and `{query}`
    /// placeholders in the summarize prompt template with the provided values.
    ///
    /// - Parameters:
    ///   - query: The user's query to insert into the template.
    ///   - context: The formatted context to insert into the template.
    /// - Returns: The complete prompt string ready for LLM generation.
    private func buildPrompt(query: String, context: String) -> String {
        summarizePrompt
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
    ///     You are an expert at synthesizing information from multiple sources.
    ///     Focus on identifying key themes and connections.
    ///     """)
    /// ```
    public func setSystemPrompt(_ newPrompt: String) {
        systemPrompt = newPrompt
    }

    /// Updates the summarization prompt template.
    ///
    /// The template must contain `{context}` and `{query}` placeholders.
    ///
    /// - Parameter newPrompt: The new prompt template to use.
    ///
    /// Example:
    /// ```swift
    /// await synthesizer.setSummarizePrompt("""
    ///     Document excerpts:
    ///     {context}
    ///
    ///     Question: {query}
    ///
    ///     Provide a comprehensive synthesis:
    ///     """)
    /// ```
    public func setSummarizePrompt(_ newPrompt: String) {
        summarizePrompt = newPrompt
    }

    /// Updates the group size for summarization levels.
    ///
    /// - Parameter newSize: The new group size. Must be at least 2.
    ///
    /// Example:
    /// ```swift
    /// await synthesizer.setGroupSize(6)  // Larger groups for fewer levels
    /// ```
    public func setGroupSize(_ newSize: Int) {
        groupSize = max(2, newSize)
    }
}
