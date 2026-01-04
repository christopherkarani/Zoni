// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// LLMProvider.swift - Protocol for large language model integrations.

// MARK: - LLMProvider

/// A protocol for generating text with large language models.
///
/// Implement this protocol to integrate with LLM providers
/// like OpenAI, Anthropic, or local models.
///
/// `LLMProvider` defines the interface for text generation in the RAG pipeline,
/// supporting both single-response and streaming generation modes.
///
/// ## Conformance Requirements
///
/// Types conforming to `LLMProvider` must be `Sendable` to ensure thread-safe
/// usage in concurrent contexts. All generation methods are asynchronous.
///
/// ## Example Implementation
///
/// ```swift
/// struct OpenAIProvider: LLMProvider {
///     let name = "openai"
///     let model: String
///     let maxContextTokens: Int
///
///     init(model: String = "gpt-4", maxContextTokens: Int = 8192) {
///         self.model = model
///         self.maxContextTokens = maxContextTokens
///     }
///
///     func generate(
///         prompt: String,
///         systemPrompt: String?,
///         options: LLMOptions
///     ) async throws -> String {
///         // Implementation using OpenAI API
///     }
///
///     func stream(
///         prompt: String,
///         systemPrompt: String?,
///         options: LLMOptions
///     ) -> AsyncThrowingStream<String, Error> {
///         // Streaming implementation using OpenAI API
///     }
/// }
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let provider = OpenAIProvider(model: "gpt-4")
///
/// // Single response generation
/// let response = try await provider.generate(
///     prompt: "Explain Swift concurrency",
///     systemPrompt: "You are a helpful assistant."
/// )
///
/// // Streaming generation
/// for try await chunk in provider.stream(prompt: "Write a story") {
///     print(chunk, terminator: "")
/// }
/// ```
public protocol LLMProvider: Sendable {
    /// The provider name (e.g., "openai", "anthropic", "local").
    ///
    /// This identifier is used for logging, debugging, and provider selection.
    var name: String { get }

    /// The model identifier (e.g., "gpt-4", "claude-3-opus").
    ///
    /// This specifies which model within the provider should be used for generation.
    var model: String { get }

    /// The maximum number of context tokens the model supports.
    ///
    /// This value is used to ensure prompts do not exceed the model's capacity.
    /// It includes both input and output tokens for most providers.
    var maxContextTokens: Int { get }

    /// Generates a text response for the given prompt.
    ///
    /// This method performs a single, non-streaming generation request to the LLM.
    /// Use this when you need the complete response before proceeding.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt to generate a response for.
    ///   - systemPrompt: An optional system prompt to guide the model's behavior.
    ///   - options: Generation options controlling temperature, max tokens, etc.
    /// - Returns: The generated text response.
    /// - Throws: `ZoniError.generationFailed` if generation fails,
    ///           `ZoniError.contextTooLong` if the prompt exceeds token limits,
    ///           `ZoniError.rateLimited` if the API rate limit is exceeded.
    func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String

    /// Streams a text response for the given prompt.
    ///
    /// This method returns an async stream that yields text chunks as they are
    /// generated. Use this for real-time display of responses or when working
    /// with long-form content.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt to generate a response for.
    ///   - systemPrompt: An optional system prompt to guide the model's behavior.
    ///   - options: Generation options controlling temperature, max tokens, etc.
    /// - Returns: An async throwing stream that yields text chunks as they are generated.
    ///            The stream completes when generation is finished, or throws on error.
    func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - LLMProvider Default Implementations

extension LLMProvider {
    /// Generates a text response with default options.
    ///
    /// This convenience method calls `generate(prompt:systemPrompt:options:)` with
    /// `LLMOptions.default`, which uses the model's default generation parameters.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt to generate a response for.
    ///   - systemPrompt: An optional system prompt to guide the model's behavior.
    ///                   Defaults to `nil`.
    /// - Returns: The generated text response.
    /// - Throws: `ZoniError.generationFailed` if generation fails.
    public func generate(
        prompt: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        try await generate(prompt: prompt, systemPrompt: systemPrompt, options: .default)
    }

    /// Streams a text response with default options.
    ///
    /// This convenience method calls `stream(prompt:systemPrompt:options:)` with
    /// `LLMOptions.default`, which uses the model's default generation parameters.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt to generate a response for.
    ///   - systemPrompt: An optional system prompt to guide the model's behavior.
    ///                   Defaults to `nil`.
    /// - Returns: An async throwing stream that yields text chunks as they are generated.
    public func stream(
        prompt: String,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        stream(prompt: prompt, systemPrompt: systemPrompt, options: .default)
    }
}
