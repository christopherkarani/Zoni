// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGConfiguration - Central configuration for RAG pipeline behavior

// MARK: - RAGConfiguration

/// Configuration options for the RAG pipeline.
///
/// `RAGConfiguration` provides centralized control over all aspects of the RAG pipeline,
/// including chunking, embedding, retrieval, and generation settings.
///
/// ## Usage
///
/// Create a configuration with custom settings:
/// ```swift
/// let config = RAGConfiguration(
///     defaultChunkSize: 1024,
///     defaultRetrievalLimit: 10,
///     enableLogging: true
/// )
/// ```
///
/// Or use the default configuration:
/// ```swift
/// let config = RAGConfiguration.default
/// ```
public struct RAGConfiguration: Sendable {

    // MARK: - Chunking Settings

    /// The default size of text chunks in tokens or characters.
    ///
    /// This value determines how documents are split during indexing.
    /// Smaller chunks provide more precise retrieval but may lose context.
    /// Larger chunks preserve context but may include irrelevant information.
    ///
    /// Default: `512`
    public var defaultChunkSize: Int

    /// The number of overlapping tokens or characters between adjacent chunks.
    ///
    /// Overlap helps preserve context at chunk boundaries and improves
    /// retrieval quality for queries that span chunk boundaries.
    ///
    /// Default: `50`
    public var defaultChunkOverlap: Int

    // MARK: - Embedding Settings

    /// The maximum number of texts to embed in a single batch.
    ///
    /// Batching improves embedding throughput. Larger batches are more efficient
    /// but consume more memory. Adjust based on available resources.
    ///
    /// Default: `100`
    public var embeddingBatchSize: Int

    /// Whether to cache computed embeddings for reuse.
    ///
    /// Enabling caching reduces redundant embedding computations
    /// but increases memory usage.
    ///
    /// Default: `true`
    public var cacheEmbeddings: Bool

    // MARK: - Retrieval Settings

    /// The default maximum number of chunks to retrieve for a query.
    ///
    /// More chunks provide broader context but may introduce noise
    /// and increase token usage in generation.
    ///
    /// Default: `5`
    public var defaultRetrievalLimit: Int

    /// The minimum similarity score required for a chunk to be included in results.
    ///
    /// When set, chunks with similarity scores below this threshold are excluded.
    /// A value of `nil` disables threshold filtering.
    ///
    /// The similarity score range depends on the embedding model and distance metric.
    /// Typical cosine similarity scores range from 0.0 to 1.0.
    ///
    /// Default: `nil` (no threshold)
    public var similarityThreshold: Float?

    // MARK: - Generation Settings

    /// The default system prompt for the language model.
    ///
    /// This prompt sets the behavior and context for the LLM
    /// when generating responses.
    ///
    /// Default: `"You are a helpful assistant. Answer questions based on the provided context."`
    public var defaultSystemPrompt: String

    /// The maximum number of tokens to include in the context window.
    ///
    /// This limits how much retrieved content is passed to the LLM.
    /// Should be set based on the model's context window size,
    /// leaving room for the system prompt, query, and response.
    ///
    /// Default: `4000`
    public var maxContextTokens: Int

    /// The maximum number of tokens for the generated response.
    ///
    /// When set, limits the length of LLM responses.
    /// A value of `nil` uses the model's default.
    ///
    /// Default: `nil` (model default)
    public var responseMaxTokens: Int?

    // MARK: - Performance Settings

    /// Whether logging is enabled for pipeline operations.
    ///
    /// When enabled, the pipeline logs operations according to `logLevel`.
    ///
    /// Default: `true`
    public var enableLogging: Bool

    /// The verbosity level for logging.
    ///
    /// Controls which messages are logged when `enableLogging` is `true`.
    ///
    /// Default: `.info`
    public var logLevel: LogLevel

    // MARK: - Log Level

    /// Logging verbosity levels for the RAG pipeline.
    ///
    /// Log levels are ordered by verbosity, from `.none` (silent) to `.debug` (most verbose).
    /// Each level includes all messages from less verbose levels.
    public enum LogLevel: Int, Sendable, Comparable {
        /// No logging output.
        case none = 0

        /// Only error messages are logged.
        case error = 1

        /// Warnings and errors are logged.
        case warning = 2

        /// Informational messages, warnings, and errors are logged.
        case info = 3

        /// All messages including debug information are logged.
        case debug = 4

        /// Compares two log levels by their verbosity.
        ///
        /// - Parameters:
        ///   - lhs: The left-hand side log level.
        ///   - rhs: The right-hand side log level.
        /// - Returns: `true` if `lhs` is less verbose than `rhs`.
        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Initialization

    /// Creates a new RAG configuration with the specified settings.
    ///
    /// All parameters have sensible defaults, allowing you to customize
    /// only the settings relevant to your use case.
    ///
    /// - Parameters:
    ///   - defaultChunkSize: The default size of text chunks. Default: `512`.
    ///   - defaultChunkOverlap: The overlap between adjacent chunks. Default: `50`.
    ///   - embeddingBatchSize: Maximum texts per embedding batch. Default: `100`.
    ///   - cacheEmbeddings: Whether to cache embeddings. Default: `true`.
    ///   - defaultRetrievalLimit: Maximum chunks to retrieve. Default: `5`.
    ///   - similarityThreshold: Minimum similarity score for retrieval. Default: `nil`.
    ///   - defaultSystemPrompt: System prompt for the LLM. Default: Standard assistant prompt.
    ///   - maxContextTokens: Maximum tokens in context. Default: `4000`.
    ///   - responseMaxTokens: Maximum tokens in response. Default: `nil`.
    ///   - enableLogging: Whether logging is enabled. Default: `true`.
    ///   - logLevel: The logging verbosity level. Default: `.info`.
    public init(
        defaultChunkSize: Int = 512,
        defaultChunkOverlap: Int = 50,
        embeddingBatchSize: Int = 100,
        cacheEmbeddings: Bool = true,
        defaultRetrievalLimit: Int = 5,
        similarityThreshold: Float? = nil,
        defaultSystemPrompt: String = "You are a helpful assistant. Answer questions based on the provided context.",
        maxContextTokens: Int = 4000,
        responseMaxTokens: Int? = nil,
        enableLogging: Bool = true,
        logLevel: LogLevel = .info
    ) {
        self.defaultChunkSize = defaultChunkSize
        self.defaultChunkOverlap = defaultChunkOverlap
        self.embeddingBatchSize = embeddingBatchSize
        self.cacheEmbeddings = cacheEmbeddings
        self.defaultRetrievalLimit = defaultRetrievalLimit
        self.similarityThreshold = similarityThreshold
        self.defaultSystemPrompt = defaultSystemPrompt
        self.maxContextTokens = maxContextTokens
        self.responseMaxTokens = responseMaxTokens
        self.enableLogging = enableLogging
        self.logLevel = logLevel
    }

    // MARK: - Default Configuration

    /// The default RAG configuration with balanced settings.
    ///
    /// This configuration provides sensible defaults for most use cases:
    /// - Chunk size: 512 tokens with 50-token overlap
    /// - Embedding batches of 100 with caching enabled
    /// - Retrieves top 5 chunks with no similarity threshold
    /// - 4000-token context window
    /// - Info-level logging enabled
    public static let `default` = RAGConfiguration(
        defaultChunkSize: 512,
        defaultChunkOverlap: 50,
        embeddingBatchSize: 100,
        cacheEmbeddings: true,
        defaultRetrievalLimit: 5,
        similarityThreshold: nil,
        defaultSystemPrompt: "You are a helpful assistant. Answer questions based on the provided context.",
        maxContextTokens: 4000,
        responseMaxTokens: nil,
        enableLogging: true,
        logLevel: .info
    )
}
