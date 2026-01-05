// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ResponseSynthesizer.swift - Protocol for synthesizing responses from retrieval context.

// MARK: - ResponseSynthesizer

/// A protocol for synthesizing responses from query context and retrieval results.
///
/// Response synthesizers combine the user's query with retrieved context to generate
/// coherent, grounded responses. They serve as the final stage in the RAG pipeline,
/// transforming raw retrieval results into user-facing answers.
///
/// ## Conformance Requirements
///
/// Types conforming to `ResponseSynthesizer` must be `Sendable` to ensure thread-safe
/// usage in concurrent contexts. Both synchronous and streaming synthesis methods
/// are required.
///
/// ## Example Implementation
///
/// ```swift
/// struct SimpleSynthesizer: ResponseSynthesizer {
///     let llmProvider: LLMProvider
///
///     func synthesize(
///         query: String,
///         context: String,
///         results: [RetrievalResult],
///         options: QueryOptions
///     ) async throws -> String {
///         let prompt = """
///         Context:
///         \(context)
///
///         Question: \(query)
///
///         Answer based on the context provided:
///         """
///         return try await llmProvider.generate(
///             prompt: prompt,
///             systemPrompt: options.systemPrompt
///         )
///     }
///
///     func streamSynthesize(
///         query: String,
///         context: String,
///         results: [RetrievalResult],
///         options: QueryOptions
///     ) -> AsyncThrowingStream<String, Error> {
///         // Streaming implementation
///     }
/// }
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let synthesizer = SimpleSynthesizer(llmProvider: openAIProvider)
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
public protocol ResponseSynthesizer: Sendable {
    /// Synthesizes a complete response from query and retrieval context.
    ///
    /// This method generates a single, complete response by combining the user's
    /// query with the provided context from retrieval. The synthesizer should
    /// produce a coherent answer grounded in the retrieved information.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string constructed from retrieval results.
    ///   - results: The raw retrieval results, available for additional processing
    ///              such as citation generation or metadata extraction.
    ///   - options: Query options controlling generation behavior, including
    ///              temperature, system prompt, and other LLM parameters.
    /// - Returns: The synthesized response text.
    /// - Throws: `ZoniError.generationFailed` if synthesis fails,
    ///           `ZoniError.contextTooLong` if the context exceeds token limits.
    func synthesize(
        query: String,
        context: String,
        results: [RetrievalResult],
        options: QueryOptions
    ) async throws -> String

    /// Streams a synthesized response from query and retrieval context.
    ///
    /// This method returns an async stream that yields response chunks as they
    /// are generated. Use this for real-time display of responses or when working
    /// with long-form content where immediate feedback improves user experience.
    ///
    /// The stream yields text chunks in the order they are generated and completes
    /// when the full response has been synthesized.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string constructed from retrieval results.
    ///   - results: The raw retrieval results, available for additional processing
    ///              such as citation generation or metadata extraction.
    ///   - options: Query options controlling generation behavior, including
    ///              temperature, system prompt, and other LLM parameters.
    /// - Returns: An async throwing stream that yields response text chunks as
    ///            they are generated. The stream completes when synthesis is
    ///            finished, or throws on error.
    func streamSynthesize(
        query: String,
        context: String,
        results: [RetrievalResult],
        options: QueryOptions
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - ResponseSynthesizer Default Implementations

extension ResponseSynthesizer {
    /// Synthesizes a response with default query options.
    ///
    /// This convenience method calls `synthesize(query:context:results:options:)` with
    /// `QueryOptions.default`, which uses standard retrieval and generation parameters.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string constructed from retrieval results.
    ///   - results: The raw retrieval results.
    /// - Returns: The synthesized response text.
    /// - Throws: `ZoniError.generationFailed` if synthesis fails.
    public func synthesize(
        query: String,
        context: String,
        results: [RetrievalResult]
    ) async throws -> String {
        try await synthesize(
            query: query,
            context: context,
            results: results,
            options: .default
        )
    }

    /// Streams a synthesized response with default query options.
    ///
    /// This convenience method calls `streamSynthesize(query:context:results:options:)`
    /// with `QueryOptions.default`, which uses standard retrieval and generation parameters.
    ///
    /// - Parameters:
    ///   - query: The user's original query text.
    ///   - context: The formatted context string constructed from retrieval results.
    ///   - results: The raw retrieval results.
    /// - Returns: An async throwing stream that yields response text chunks.
    public func streamSynthesize(
        query: String,
        context: String,
        results: [RetrievalResult]
    ) -> AsyncThrowingStream<String, Error> {
        streamSynthesize(
            query: query,
            context: context,
            results: results,
            options: .default
        )
    }
}
