// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGResponse.swift - Response types for RAG pipeline operations.

import Foundation

// MARK: - LLMOptions

/// Configuration options for LLM generation requests.
///
/// `LLMOptions` provides fine-grained control over the language model's
/// generation behavior, including temperature, output length, and stop sequences.
///
/// Example usage:
/// ```swift
/// let options = LLMOptions(
///     temperature: 0.7,
///     maxTokens: 1024,
///     stopSequences: ["###", "END"]
/// )
/// ```
public struct LLMOptions: Sendable, Equatable {
    /// The sampling temperature for generation.
    ///
    /// Lower values (e.g., 0.2) produce more focused, deterministic output.
    /// Higher values (e.g., 0.8) produce more creative, varied output.
    /// Typical range is 0.0 to 2.0. Defaults to nil (use model default).
    public var temperature: Double?

    /// The maximum number of tokens to generate.
    ///
    /// This limits the length of the generated response. Defaults to nil
    /// (use model default or no limit).
    public var maxTokens: Int?

    /// Sequences that signal the model to stop generating.
    ///
    /// When the model generates one of these sequences, it stops immediately.
    /// Useful for structured output formats.
    public var stopSequences: [String]?

    /// Creates new LLM generation options.
    ///
    /// - Parameters:
    ///   - temperature: Sampling temperature. Defaults to nil.
    ///   - maxTokens: Maximum tokens to generate. Defaults to nil.
    ///   - stopSequences: Stop sequences. Defaults to nil.
    public init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stopSequences: [String]? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
    }

    /// Default LLM options with all values set to nil (use model defaults).
    public static let `default` = LLMOptions()
}

// MARK: - QueryOptions

/// Configuration options for RAG query operations.
///
/// `QueryOptions` controls the retrieval and generation phases of a RAG query,
/// including how many documents to retrieve and optional filtering.
///
/// Example usage:
/// ```swift
/// let options = QueryOptions(
///     retrievalLimit: 10,
///     systemPrompt: "You are a helpful coding assistant.",
///     filter: .equals("category", "documentation")
/// )
/// let response = try await pipeline.query("How do I use async/await?", options: options)
/// ```
public struct QueryOptions: Sendable, Equatable {
    /// The maximum number of chunks to retrieve for context.
    ///
    /// More chunks provide more context but may exceed model token limits.
    /// Defaults to 5.
    public var retrievalLimit: Int

    /// Whether to include metadata in the response sources.
    ///
    /// When true, source chunks include their full metadata. Defaults to true.
    public var includeMetadata: Bool

    /// An optional system prompt to use for generation.
    ///
    /// Overrides the default system prompt from configuration.
    public var systemPrompt: String?

    /// The sampling temperature for generation.
    ///
    /// Overrides the default temperature setting.
    public var temperature: Double?

    /// An optional metadata filter to apply during retrieval.
    ///
    /// Only chunks matching the filter will be considered.
    public var filter: MetadataFilter?

    /// The maximum number of tokens to include in the context.
    ///
    /// This limits the combined size of retrieved chunks passed to the LLM.
    /// Defaults to 4096 tokens.
    public var maxContextTokens: Int

    /// Creates new query options.
    ///
    /// - Parameters:
    ///   - retrievalLimit: Maximum chunks to retrieve. Defaults to 5.
    ///   - includeMetadata: Include metadata in sources. Defaults to true.
    ///   - systemPrompt: Optional system prompt override.
    ///   - temperature: Optional temperature override.
    ///   - filter: Optional metadata filter.
    public init(
        retrievalLimit: Int = 5,
        includeMetadata: Bool = true,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        filter: MetadataFilter? = nil,
        maxContextTokens: Int = 4096
    ) {
        self.retrievalLimit = retrievalLimit
        self.includeMetadata = includeMetadata
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.filter = filter
        self.maxContextTokens = maxContextTokens
    }

    /// Default query options with standard settings.
    public static let `default` = QueryOptions()
}

// MARK: - RAGResponseMetadata

/// Metadata about a RAG response including timing and token information.
///
/// `RAGResponseMetadata` provides observability into the RAG pipeline's
/// performance, tracking time spent in each phase and resource usage.
///
/// Example usage:
/// ```swift
/// let response = try await pipeline.query("What is Swift?")
/// if let totalTime = response.metadata.totalTime {
///     print("Query completed in \(totalTime)")
/// }
/// ```
public struct RAGResponseMetadata: Sendable, Equatable {
    /// Time spent parsing and processing the query.
    public var queryTime: Duration?

    /// Time spent retrieving relevant chunks from the vector store.
    public var retrievalTime: Duration?

    /// Time spent generating the response from the LLM.
    public var generationTime: Duration?

    /// Total time from query start to response completion.
    public var totalTime: Duration?

    /// Number of tokens used in the generation (input + output).
    public var tokensUsed: Int?

    /// The model identifier used for generation.
    public var model: String?

    /// The number of chunks retrieved from the vector store.
    public var chunksRetrieved: Int?

    /// Creates new response metadata.
    ///
    /// - Parameters:
    ///   - queryTime: Time spent on query processing.
    ///   - retrievalTime: Time spent on retrieval.
    ///   - generationTime: Time spent on generation.
    ///   - totalTime: Total elapsed time.
    ///   - tokensUsed: Total tokens used.
    ///   - model: The model identifier.
    public init(
        queryTime: Duration? = nil,
        retrievalTime: Duration? = nil,
        generationTime: Duration? = nil,
        totalTime: Duration? = nil,
        tokensUsed: Int? = nil,
        model: String? = nil,
        chunksRetrieved: Int? = nil
    ) {
        self.queryTime = queryTime
        self.retrievalTime = retrievalTime
        self.generationTime = generationTime
        self.totalTime = totalTime
        self.tokensUsed = tokensUsed
        self.model = model
        self.chunksRetrieved = chunksRetrieved
    }
}

// MARK: - RAGResponse

/// The complete response from a RAG query, including answer and sources.
///
/// `RAGResponse` contains the generated answer along with the source chunks
/// used to generate it, enabling attribution and verification.
///
/// Example usage:
/// ```swift
/// let response = try await pipeline.query("Explain async/await in Swift")
///
/// print("Answer: \(response.answer)")
/// print("Based on \(response.sources.count) sources:")
/// for source in response.sources {
///     print("  - \(source.chunk.metadata.source ?? "Unknown")")
/// }
/// ```
public struct RAGResponse: Sendable, Equatable {
    /// The generated answer text.
    public let answer: String

    /// The source chunks used to generate the answer.
    ///
    /// Sources are typically ordered by relevance (highest first).
    public let sources: [RetrievalResult]

    /// Metadata about the response generation process.
    public let metadata: RAGResponseMetadata

    /// Creates a new RAG response.
    ///
    /// - Parameters:
    ///   - answer: The generated answer text.
    ///   - sources: The source chunks used for generation.
    ///   - metadata: Response metadata. Defaults to empty metadata.
    public init(
        answer: String,
        sources: [RetrievalResult],
        metadata: RAGResponseMetadata = RAGResponseMetadata()
    ) {
        self.answer = answer
        self.sources = sources
        self.metadata = metadata
    }
}

// MARK: - RAGStreamEvent

/// Events emitted during a streaming RAG query.
///
/// `RAGStreamEvent` enables real-time feedback during long-running RAG operations,
/// notifying clients of progress through retrieval and generation phases.
///
/// Example usage:
/// ```swift
/// for try await event in pipeline.streamQuery("What is Swift?") {
///     switch event {
///     case .retrievalStarted:
///         print("Searching knowledge base...")
///     case .retrievalComplete(let sources):
///         print("Found \(sources.count) relevant sources")
///     case .generationChunk(let text):
///         print(text, terminator: "")
///     case .complete(let response):
///         print("\nDone!")
///     case .error(let error):
///         print("Error: \(error)")
///     }
/// }
/// ```
public enum RAGStreamEvent: Sendable {
    /// Emitted when retrieval begins.
    case retrievalStarted

    /// Emitted when retrieval completes with the retrieved sources.
    case retrievalComplete([RetrievalResult])

    /// Emitted when LLM generation begins.
    case generationStarted

    /// Emitted for each chunk of generated text.
    case generationChunk(String)

    /// Emitted when generation completes with the full answer.
    case generationComplete(String)

    /// Emitted when the entire RAG operation completes.
    case complete(RAGResponse)

    /// Emitted when an error occurs during the operation.
    case error(ZoniError)
}

// MARK: - RAGStatistics

/// Statistics about the RAG pipeline's current state.
///
/// `RAGStatistics` provides insight into the data stored in the pipeline,
/// useful for monitoring and debugging.
///
/// Example usage:
/// ```swift
/// let stats = try await pipeline.statistics()
/// print("Documents: \(stats.documentCount)")
/// print("Chunks: \(stats.chunkCount)")
/// print("Embedding dimensions: \(stats.embeddingDimensions)")
/// ```
public struct RAGStatistics: Sendable, Equatable {
    /// The total number of documents ingested.
    public let documentCount: Int

    /// The total number of chunks stored in the vector store.
    public let chunkCount: Int

    /// The dimensionality of the embeddings.
    public let embeddingDimensions: Int

    /// The name of the vector store being used.
    public let vectorStoreName: String

    /// The name of the embedding provider being used.
    public let embeddingProviderName: String

    /// Creates new RAG statistics.
    ///
    /// - Parameters:
    ///   - documentCount: Number of ingested documents.
    ///   - chunkCount: Number of stored chunks.
    ///   - embeddingDimensions: Embedding vector dimensionality.
    ///   - vectorStoreName: Name of the vector store.
    ///   - embeddingProviderName: Name of the embedding provider.
    public init(
        documentCount: Int,
        chunkCount: Int,
        embeddingDimensions: Int,
        vectorStoreName: String,
        embeddingProviderName: String
    ) {
        self.documentCount = documentCount
        self.chunkCount = chunkCount
        self.embeddingDimensions = embeddingDimensions
        self.vectorStoreName = vectorStoreName
        self.embeddingProviderName = embeddingProviderName
    }
}

// MARK: - CustomStringConvertible

extension RAGResponse: CustomStringConvertible {
    public var description: String {
        let answerPreview = answer.prefix(100)
        let truncated = answer.count > 100 ? "..." : ""
        return "RAGResponse(answer: \"\(answerPreview)\(truncated)\", sources: \(sources.count))"
    }
}

extension RAGStatistics: CustomStringConvertible {
    public var description: String {
        "RAGStatistics(documents: \(documentCount), chunks: \(chunkCount), " +
        "dimensions: \(embeddingDimensions), store: \(vectorStoreName), " +
        "embedder: \(embeddingProviderName))"
    }
}
