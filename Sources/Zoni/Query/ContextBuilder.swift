// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ContextBuilder.swift - Builds context strings from retrieval results for LLM prompts.

// MARK: - ContextChunk

/// A structured representation of a context chunk for LLM prompts.
///
/// `ContextChunk` provides a structured view of retrieved content that can be
/// used for custom formatting or further processing before sending to an LLM.
///
/// Example usage:
/// ```swift
/// let builder = ContextBuilder()
/// let chunks = builder.buildStructured(query: "What is Swift?", results: results)
///
/// for chunk in chunks {
///     print("[\(chunk.index)] \(chunk.source ?? "Unknown")")
///     print("Score: \(chunk.score)")
///     print(chunk.content)
/// }
/// ```
public struct ContextChunk: Sendable, Equatable {
    /// The index of this chunk in the context (1-based for display).
    public let index: Int

    /// The text content of this chunk.
    public let content: String

    /// The source identifier for this chunk, if available.
    ///
    /// This typically corresponds to a file path, URL, or document identifier.
    public let source: String?

    /// The relevance score from the retrieval operation.
    ///
    /// Higher scores indicate greater relevance to the query.
    public let score: Float

    /// Creates a new context chunk.
    ///
    /// - Parameters:
    ///   - index: The index of this chunk in the context.
    ///   - content: The text content of this chunk.
    ///   - source: The optional source identifier.
    ///   - score: The relevance score from retrieval.
    public init(
        index: Int,
        content: String,
        source: String?,
        score: Float
    ) {
        self.index = index
        self.content = content
        self.source = source
        self.score = score
    }
}

// MARK: - ContextChunk CustomStringConvertible

extension ContextChunk: CustomStringConvertible {
    public var description: String {
        let preview = content.prefix(40)
        let truncated = content.count > 40 ? "..." : ""
        let sourceStr = source.map { " from \($0)" } ?? ""
        return "ContextChunk(index: \(index), score: \(String(format: "%.4f", score))\(sourceStr), content: \"\(preview)\(truncated)\")"
    }
}

// MARK: - ContextBuilder

/// Builds formatted context strings from retrieval results for LLM prompts.
///
/// `ContextBuilder` takes retrieval results and formats them into a context string
/// suitable for inclusion in LLM prompts. It handles token limits, metadata inclusion,
/// and source attribution.
///
/// Example usage:
/// ```swift
/// let builder = ContextBuilder(
///     includeMetadata: true,
///     includeScores: false,
///     chunkSeparator: "\n\n---\n\n"
/// )
///
/// // Build context with token limit
/// let context = builder.build(
///     query: "What is Swift concurrency?",
///     results: retrievalResults,
///     maxTokens: 4000
/// )
///
/// // Use in prompt
/// let prompt = """
///     Context:
///     \(context)
///
///     Question: What is Swift concurrency?
///     """
/// ```
public struct ContextBuilder: Sendable {

    // MARK: - Properties

    /// Whether to include metadata (source attribution) in the output.
    ///
    /// When `true`, each chunk is prefixed with `[Source N] (source_name)`.
    public let includeMetadata: Bool

    /// Whether to include relevance scores in the output.
    ///
    /// When `true`, scores are included in the source attribution line.
    public let includeScores: Bool

    /// The separator used between chunks in the formatted output.
    public let chunkSeparator: String

    /// Optional limit on the number of chunks to include per source.
    ///
    /// When set, limits how many chunks from the same source document
    /// are included in the context, helping ensure diversity.
    public let maxChunksPerSource: Int?

    /// The token counter used for estimating token usage.
    private let tokenCounter: TokenCounter

    // MARK: - Initialization

    /// Creates a new context builder with the specified configuration.
    ///
    /// - Parameters:
    ///   - includeMetadata: Whether to include source metadata. Defaults to `true`.
    ///   - includeScores: Whether to include relevance scores. Defaults to `false`.
    ///   - chunkSeparator: The separator between chunks. Defaults to `"\n\n---\n\n"`.
    ///   - maxChunksPerSource: Optional limit on chunks per source. Defaults to `nil`.
    public init(
        includeMetadata: Bool = true,
        includeScores: Bool = false,
        chunkSeparator: String = "\n\n---\n\n",
        maxChunksPerSource: Int? = nil
    ) {
        if let maxPerSource = maxChunksPerSource {
            precondition(maxPerSource > 0, "maxChunksPerSource must be positive if set, got \(maxPerSource)")
        }
        self.includeMetadata = includeMetadata
        self.includeScores = includeScores
        self.chunkSeparator = chunkSeparator
        self.maxChunksPerSource = maxChunksPerSource
        self.tokenCounter = TokenCounter(model: .simple)
    }

    // MARK: - Public Methods

    /// Builds a formatted context string from retrieval results.
    ///
    /// This method formats each retrieval result into a string with optional
    /// source attribution, respecting the specified token limit. Chunks are
    /// processed in order until the token limit would be exceeded.
    ///
    /// The output format for each chunk (when metadata is included):
    /// ```
    /// [Source N] (source_name)
    /// chunk content here...
    /// ```
    ///
    /// - Parameters:
    ///   - query: The original query (for reference, not included in output).
    ///   - results: The retrieval results to format.
    ///   - maxTokens: The maximum number of tokens for the context.
    ///   - includeMetadata: Override for metadata inclusion. Defaults to the builder's setting.
    /// - Returns: A formatted context string suitable for LLM prompts.
    public func build(
        query: String,
        results: [RetrievalResult],
        maxTokens: Int,
        includeMetadata: Bool? = nil
    ) -> String {
        guard maxTokens > 0 else {
            preconditionFailure("maxTokens must be positive, got \(maxTokens)")
        }
        guard !results.isEmpty else {
            return ""  // Explicit empty return
        }

        let shouldIncludeMetadata = includeMetadata ?? self.includeMetadata
        let filteredResults = applySourceLimit(to: results)

        var formattedChunks: [String] = []
        var currentTokens = 0
        let separatorTokens = tokenCounter.count(chunkSeparator)

        for (index, result) in filteredResults.enumerated() {
            let formattedChunk = formatChunk(
                result: result,
                index: index + 1,
                includeMetadata: shouldIncludeMetadata
            )

            let chunkTokens = tokenCounter.count(formattedChunk)
            let currentSeparatorTokens = formattedChunks.isEmpty ? 0 : separatorTokens

            // Check if adding this chunk would exceed the limit
            if currentTokens + currentSeparatorTokens + chunkTokens > maxTokens {
                break
            }

            formattedChunks.append(formattedChunk)
            currentTokens += currentSeparatorTokens + chunkTokens
        }

        return formattedChunks.joined(separator: chunkSeparator)
    }

    /// Builds structured context chunks from retrieval results.
    ///
    /// This method returns an array of `ContextChunk` objects that can be
    /// used for custom formatting or further processing.
    ///
    /// - Parameters:
    ///   - query: The original query (for reference).
    ///   - results: The retrieval results to structure.
    /// - Returns: An array of structured context chunks.
    public func buildStructured(
        query: String,
        results: [RetrievalResult]
    ) -> [ContextChunk] {
        let filteredResults = applySourceLimit(to: results)

        return filteredResults.enumerated().map { index, result in
            ContextChunk(
                index: index + 1,
                content: result.chunk.content,
                source: result.chunk.metadata.source,
                score: result.score
            )
        }
    }

    // MARK: - Private Methods

    /// Formats a single retrieval result into a string.
    ///
    /// - Parameters:
    ///   - result: The retrieval result to format.
    ///   - index: The 1-based index for source attribution.
    ///   - includeMetadata: Whether to include source metadata.
    /// - Returns: The formatted chunk string.
    private func formatChunk(
        result: RetrievalResult,
        index: Int,
        includeMetadata: Bool
    ) -> String {
        let content = result.chunk.content

        guard includeMetadata else {
            return content
        }

        let sourceName = result.chunk.metadata.source ?? "Unknown"
        var header = "[Source \(index)] (\(sourceName))"

        if includeScores {
            header += " [score: \(String(format: "%.4f", result.score))]"
        }

        return "\(header)\n\(content)"
    }

    /// Applies the maxChunksPerSource limit to the results.
    ///
    /// - Parameter results: The original retrieval results.
    /// - Returns: Filtered results respecting the per-source limit.
    private func applySourceLimit(to results: [RetrievalResult]) -> [RetrievalResult] {
        guard let maxPerSource = maxChunksPerSource, maxPerSource > 0 else {
            return results
        }

        var sourceCounts: [String: Int] = [:]
        var filtered: [RetrievalResult] = []

        for result in results {
            let sourceKey = result.chunk.metadata.source ?? result.chunk.metadata.documentId
            let currentCount = sourceCounts[sourceKey, default: 0]

            if currentCount < maxPerSource {
                filtered.append(result)
                sourceCounts[sourceKey] = currentCount + 1
            }
        }

        return filtered
    }
}

// MARK: - CustomStringConvertible

extension ContextBuilder: CustomStringConvertible {
    public var description: String {
        var parts = ["ContextBuilder("]
        parts.append("includeMetadata: \(includeMetadata)")
        parts.append(", includeScores: \(includeScores)")
        if let maxPerSource = maxChunksPerSource {
            parts.append(", maxChunksPerSource: \(maxPerSource)")
        }
        parts.append(")")
        return parts.joined()
    }
}
