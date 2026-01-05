// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// QueryTransformer.swift - Query transformation strategies for improved retrieval.

import Foundation

// MARK: - QueryTransformer Protocol

/// A protocol for transforming queries to improve retrieval quality.
///
/// Query transformers modify the user's original query before it is used for
/// retrieval. This can include expanding queries with synonyms, rephrasing for
/// better semantic matching, or decomposing complex questions into sub-questions.
///
/// ## Conformance Requirements
///
/// Types conforming to `QueryTransformer` must be `Sendable` to ensure thread-safe
/// usage in concurrent contexts. The transform method is asynchronous to support
/// LLM-based transformations.
///
/// ## Example Implementation
///
/// ```swift
/// struct UppercaseTransformer: QueryTransformer {
///     func transform(_ query: String) async throws -> String {
///         query.uppercased()
///     }
/// }
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let expander = QueryExpander(llmProvider: openAIProvider)
/// let expandedQuery = try await expander.transform("Swift concurrency")
/// // Returns: "Swift concurrency async await actors Task structured concurrency"
/// ```
public protocol QueryTransformer: Sendable {
    /// Transforms a query string to improve retrieval effectiveness.
    ///
    /// - Parameter query: The original query string to transform.
    /// - Returns: The transformed query string.
    /// - Throws: An error if transformation fails (e.g., LLM generation error).
    func transform(_ query: String) async throws -> String
}

// MARK: - QueryExpander

/// A query transformer that expands queries with synonyms and related terms.
///
/// `QueryExpander` uses an LLM to generate synonyms and related terms for the
/// input query, creating a richer query that can match more relevant documents.
/// This is particularly useful when documents may use different terminology than
/// the user's query.
///
/// ## How It Works
///
/// The expander prompts the LLM to identify key concepts in the query and
/// provide alternative phrasings, synonyms, and related terms. The result
/// is a single expanded query string combining all relevant terms.
///
/// ## Example Usage
///
/// ```swift
/// let expander = QueryExpander(llmProvider: openAIProvider)
/// let expanded = try await expander.transform("machine learning basics")
/// // Returns: "machine learning basics ML artificial intelligence AI
/// //          neural networks deep learning fundamentals introduction"
/// ```
///
/// ## Configuration
///
/// - Uses low temperature (0.3) for deterministic, focused expansions
/// - Limited to 100 tokens to keep expansions concise
public struct QueryExpander: QueryTransformer, Sendable {

    // MARK: - Properties

    /// The LLM provider used to generate query expansions.
    private let llmProvider: any LLMProvider

    // MARK: - Initialization

    /// Creates a new query expander with the specified LLM provider.
    ///
    /// - Parameter llmProvider: The LLM provider to use for generating expansions.
    public init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - QueryTransformer

    /// Expands the query with synonyms and related terms.
    ///
    /// - Parameter query: The original query to expand.
    /// - Returns: The expanded query containing synonyms and related terms.
    /// - Throws: `ZoniError.generationFailed` if LLM generation fails.
    public func transform(_ query: String) async throws -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return query  // Return original if empty (let caller handle validation)
        }

        let systemPrompt = """
            You are a query expansion assistant. Your task is to expand the given query \
            with synonyms, related terms, and alternative phrasings that could help find \
            relevant documents. Return ONLY the expanded query terms as a single line, \
            space-separated. Do not include explanations or formatting.
            """

        let prompt = """
            Expand this query with synonyms and related terms:

            Query: \(query)

            Expanded terms:
            """

        let options = LLMOptions(temperature: 0.3, maxTokens: 100)

        let expansion = try await llmProvider.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            options: options
        )

        // Combine original query with expansion for comprehensive coverage
        let trimmedExpansion = expansion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedExpansion.isEmpty else {
            return query  // Return original if LLM returned empty
        }
        return "\(query) \(trimmedExpansion)"
    }
}

// MARK: - QueryRephraser

/// A query transformer that rephrases queries for better retrieval.
///
/// `QueryRephraser` uses an LLM to rewrite the user's query in a way that is
/// more likely to match relevant documents in the knowledge base. This can
/// help when the user's phrasing is informal, ambiguous, or uses uncommon
/// terminology.
///
/// ## How It Works
///
/// The rephraser prompts the LLM to rewrite the query using clear, specific
/// language that is more suitable for semantic search. It preserves the
/// original intent while improving clarity and specificity.
///
/// ## Example Usage
///
/// ```swift
/// let rephraser = QueryRephraser(llmProvider: openAIProvider)
/// let rephrased = try await rephraser.transform("how do I make things run at the same time in swift")
/// // Returns: "How to implement concurrent execution and parallelism in Swift"
/// ```
///
/// ## Configuration
///
/// - Uses low temperature (0.3) for consistent, focused rephrasing
/// - Limited to 100 tokens to produce concise rephrased queries
public struct QueryRephraser: QueryTransformer, Sendable {

    // MARK: - Properties

    /// The LLM provider used to rephrase queries.
    private let llmProvider: any LLMProvider

    // MARK: - Initialization

    /// Creates a new query rephraser with the specified LLM provider.
    ///
    /// - Parameter llmProvider: The LLM provider to use for rephrasing.
    public init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - QueryTransformer

    /// Rephrases the query for improved retrieval effectiveness.
    ///
    /// - Parameter query: The original query to rephrase.
    /// - Returns: The rephrased query optimized for retrieval.
    /// - Throws: `ZoniError.generationFailed` if LLM generation fails.
    public func transform(_ query: String) async throws -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return query  // Return original if empty (let caller handle validation)
        }

        let systemPrompt = """
            You are a query optimization assistant. Your task is to rephrase the given \
            query to make it more suitable for semantic search and document retrieval. \
            Use clear, specific language. Preserve the original intent. Return ONLY the \
            rephrased query without explanations or formatting.
            """

        let prompt = """
            Rephrase this query for better document retrieval:

            Original query: \(query)

            Rephrased query:
            """

        let options = LLMOptions(temperature: 0.3, maxTokens: 100)

        let rephrased = try await llmProvider.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            options: options
        )

        let trimmed = rephrased.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return query  // Return original if rephrasing failed
        }
        return trimmed
    }
}

// MARK: - QueryDecomposer

/// A query transformer that breaks complex questions into sub-questions.
///
/// `QueryDecomposer` uses an LLM to analyze complex, multi-part questions and
/// decompose them into simpler sub-questions. The sub-questions are then
/// combined into a single search string that captures all aspects of the
/// original query.
///
/// ## How It Works
///
/// The decomposer identifies distinct aspects or components of the original
/// question and generates targeted sub-questions for each. These are combined
/// to create a comprehensive search query that addresses all parts of the
/// user's question.
///
/// ## Example Usage
///
/// ```swift
/// let decomposer = QueryDecomposer(llmProvider: openAIProvider)
/// let decomposed = try await decomposer.transform(
///     "What are the benefits and drawbacks of using actors in Swift, and when should I use them?"
/// )
/// // Returns: "What are the benefits of actors in Swift? What are the drawbacks of actors in Swift?
/// //          When should actors be used in Swift? Actor use cases and limitations"
/// ```
///
/// ## Configuration
///
/// - Uses low temperature (0.3) for consistent decomposition
/// - Limited to 200 tokens to allow for multiple sub-questions
public struct QueryDecomposer: QueryTransformer, Sendable {

    // MARK: - Properties

    /// The LLM provider used to decompose queries.
    private let llmProvider: any LLMProvider

    // MARK: - Initialization

    /// Creates a new query decomposer with the specified LLM provider.
    ///
    /// - Parameter llmProvider: The LLM provider to use for decomposition.
    public init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - QueryTransformer

    /// Decomposes a complex query into sub-questions combined for search.
    ///
    /// - Parameter query: The complex query to decompose.
    /// - Returns: A combined search string containing all sub-questions.
    /// - Throws: `ZoniError.generationFailed` if LLM generation fails.
    public func transform(_ query: String) async throws -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return query  // Return original if empty (let caller handle validation)
        }

        let systemPrompt = """
            You are a query decomposition assistant. Your task is to break down complex \
            questions into simpler, focused sub-questions. Each sub-question should address \
            a specific aspect of the original query. Return the sub-questions on separate \
            lines without numbering or bullet points.
            """

        let prompt = """
            Decompose this complex question into simpler sub-questions:

            Question: \(query)

            Sub-questions:
            """

        let options = LLMOptions(temperature: 0.3, maxTokens: 200)

        let decomposed = try await llmProvider.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            options: options
        )

        // Combine sub-questions into a single search string
        let subQuestions = decomposed
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if subQuestions.isEmpty {
            return query  // Return original if decomposition failed
        }

        // Include original query and all sub-questions for comprehensive coverage
        let combined = ([query] + subQuestions).joined(separator: " ")
        return combined
    }
}

// MARK: - ChainedTransformer

/// A query transformer that chains multiple transformers sequentially.
///
/// `ChainedTransformer` applies a sequence of query transformers in order,
/// passing the output of each transformer as input to the next. This enables
/// building complex transformation pipelines from simpler components.
///
/// ## How It Works
///
/// Transformers are applied in the order they appear in the array. The original
/// query is passed to the first transformer, and each subsequent transformer
/// receives the output from the previous one.
///
/// ## Example Usage
///
/// ```swift
/// let chain = ChainedTransformer(transformers: [
///     QueryRephraser(llmProvider: provider),
///     QueryExpander(llmProvider: provider)
/// ])
/// let result = try await chain.transform("swift async stuff")
/// // First rephrases to clearer language, then expands with synonyms
/// ```
///
/// ## Error Handling
///
/// If any transformer in the chain throws an error, the entire chain fails
/// and the error is propagated to the caller.
public struct ChainedTransformer: QueryTransformer, Sendable {

    // MARK: - Properties

    /// The ordered list of transformers to apply.
    private let transformers: [any QueryTransformer]

    // MARK: - Initialization

    /// Creates a new chained transformer with the specified transformers.
    ///
    /// - Parameter transformers: The transformers to chain, applied in order.
    /// - Precondition: The transformers array must not be empty.
    public init(transformers: [any QueryTransformer]) {
        precondition(!transformers.isEmpty, "ChainedTransformer requires at least one transformer")
        self.transformers = transformers
    }

    // MARK: - QueryTransformer

    /// Applies all transformers in sequence to the query.
    ///
    /// - Parameter query: The original query to transform.
    /// - Returns: The query after all transformers have been applied.
    /// - Throws: An error if any transformer in the chain fails.
    public func transform(_ query: String) async throws -> String {
        var currentQuery = query

        for transformer in transformers {
            currentQuery = try await transformer.transform(currentQuery)
        }

        return currentQuery
    }
}

// MARK: - HyDETransformer

/// A query transformer implementing Hypothetical Document Embeddings (HyDE).
///
/// `HyDETransformer` generates a hypothetical answer passage that would satisfy
/// the user's query, then uses that passage for retrieval instead of the original
/// query. This technique, introduced in the HyDE paper, often improves retrieval
/// by matching the embedding space of documents rather than questions.
///
/// ## How It Works
///
/// Instead of embedding the question directly, HyDE:
/// 1. Generates a hypothetical document that would answer the question
/// 2. Uses this hypothetical document for similarity search
/// 3. The hypothetical document's embedding is closer to actual relevant documents
///
/// ## Research Background
///
/// HyDE (Hypothetical Document Embeddings) was introduced by Gao et al. (2022).
/// The key insight is that questions and their answers often have different
/// semantic representations, so generating a hypothetical answer bridges this gap.
///
/// ## Example Usage
///
/// ```swift
/// let hyde = HyDETransformer(llmProvider: openAIProvider)
/// let hypothetical = try await hyde.transform("What is Swift concurrency?")
/// // Returns a passage like: "Swift concurrency is a modern approach to
/// //          asynchronous programming introduced in Swift 5.5. It includes
/// //          async/await syntax, actors for safe mutable state..."
/// ```
///
/// ## Configuration
///
/// - Uses moderate temperature (0.5) for diverse but relevant hypothetical answers
/// - Limited to 200 tokens for a substantial but focused hypothetical passage
public struct HyDETransformer: QueryTransformer, Sendable {

    // MARK: - Properties

    /// The LLM provider used to generate hypothetical documents.
    private let llmProvider: any LLMProvider

    // MARK: - Initialization

    /// Creates a new HyDE transformer with the specified LLM provider.
    ///
    /// - Parameter llmProvider: The LLM provider to use for generating
    ///   hypothetical documents.
    public init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - QueryTransformer

    /// Generates a hypothetical document that would answer the query.
    ///
    /// - Parameter query: The original query to transform.
    /// - Returns: A hypothetical passage that would answer the query.
    /// - Throws: `ZoniError.generationFailed` if LLM generation fails.
    public func transform(_ query: String) async throws -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return query  // Return original if empty (let caller handle validation)
        }

        let systemPrompt = """
            You are a helpful assistant. Your task is to write a short passage that \
            directly answers the given question. Write as if you are creating a \
            document that would be found in a knowledge base. Be informative and \
            factual. Do not include phrases like "I think" or "Based on my knowledge". \
            Just provide the answer content directly.
            """

        let prompt = """
            Write a short informative passage that answers this question:

            Question: \(query)

            Passage:
            """

        let options = LLMOptions(temperature: 0.5, maxTokens: 200)

        let hypotheticalDocument = try await llmProvider.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            options: options
        )

        return hypotheticalDocument.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

// MARK: - CustomStringConvertible Extensions

extension QueryExpander: CustomStringConvertible {
    public var description: String {
        "QueryExpander(provider: \(llmProvider.name))"
    }
}

extension QueryRephraser: CustomStringConvertible {
    public var description: String {
        "QueryRephraser(provider: \(llmProvider.name))"
    }
}

extension QueryDecomposer: CustomStringConvertible {
    public var description: String {
        "QueryDecomposer(provider: \(llmProvider.name))"
    }
}

extension ChainedTransformer: CustomStringConvertible {
    public var description: String {
        "ChainedTransformer(count: \(transformers.count))"
    }
}

extension HyDETransformer: CustomStringConvertible {
    public var description: String {
        "HyDETransformer(provider: \(llmProvider.name))"
    }
}
