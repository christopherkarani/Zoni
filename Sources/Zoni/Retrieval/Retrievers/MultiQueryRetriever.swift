// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MultiQueryRetriever.swift - LLM-based query expansion retrieval

import Foundation

// MARK: - MultiQueryRetriever

/// A retriever that expands queries using an LLM for improved recall.
///
/// `MultiQueryRetriever` uses a language model to generate variations
/// of the original query, retrieves results for each variation, and
/// merges them to improve recall.
///
/// ## How It Works
///
/// 1. Generates query variations using the LLM
/// 2. Retrieves results for original query + variations
/// 3. Merges results, keeping highest score for duplicates
/// 4. Returns top-k merged results
///
/// ## Example Usage
///
/// ```swift
/// let multiQuery = MultiQueryRetriever(
///     baseRetriever: vectorRetriever,
///     llmProvider: openAI,
///     numQueries: 3
/// )
///
/// let results = try await multiQuery.retrieve(
///     query: "What is Swift?",
///     limit: 10,
///     filter: nil
/// )
/// ```
public actor MultiQueryRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "multi_query"

    /// The base retriever to search with each query.
    private let baseRetriever: any Retriever

    /// The LLM provider for generating query variations.
    private let llmProvider: any LLMProvider

    /// Number of alternative queries to generate.
    public var numQueries: Int

    /// Custom prompt template for query generation.
    ///
    /// If `nil`, uses the default prompt.
    public var queryGenerationPrompt: String?

    // MARK: - Initialization

    /// Creates a new multi-query retriever.
    ///
    /// - Parameters:
    ///   - baseRetriever: The retriever to search with each query.
    ///   - llmProvider: The LLM for generating variations.
    ///   - numQueries: Number of variations to generate. Default: 3
    public init(
        baseRetriever: any Retriever,
        llmProvider: any LLMProvider,
        numQueries: Int = 3
    ) {
        self.baseRetriever = baseRetriever
        self.llmProvider = llmProvider
        self.numQueries = numQueries
    }

    // MARK: - Configuration

    /// Sets a custom prompt for query generation.
    ///
    /// Use `{query}` as placeholder for the original query.
    public func setQueryGenerationPrompt(_ prompt: String?) {
        self.queryGenerationPrompt = prompt
    }

    /// Sets the number of queries to generate.
    ///
    /// - Parameter num: Number of query variations. Must be between 1 and 10.
    public func setNumQueries(_ num: Int) {
        self.numQueries = min(10, max(1, num))
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant chunks using multi-query expansion.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to apply.
    /// - Returns: Merged results from all query variations.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Input validation
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        guard limit > 0 else {
            return []
        }

        // Generate query variations
        let queries = try await generateQueries(original: query)

        // Retrieve for each query
        var allResults: [String: RetrievalResult] = [:]  // Deduplicate by ID

        for q in queries {
            let results = try await baseRetriever.retrieve(
                query: q,
                limit: limit,
                filter: filter
            )

            for result in results {
                if let existing = allResults[result.id] {
                    // Keep higher score
                    if result.score > existing.score {
                        allResults[result.id] = result
                    }
                } else {
                    allResults[result.id] = result
                }
            }
        }

        // Sort by score and return top results
        return allResults.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Query Generation

    /// Maximum query length to prevent excessive token usage.
    private static let maxQueryLength = 1000

    /// Sanitizes user query to prevent prompt injection.
    private func sanitizeQuery(_ query: String) -> String {
        // Remove control characters and limit length
        let sanitized = query
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maxQueryLength)
        return String(sanitized)
    }

    /// Generates query variations using the LLM.
    private func generateQueries(original: String) async throws -> [String] {
        let sanitizedQuery = sanitizeQuery(original)

        let prompt: String
        if let customPrompt = queryGenerationPrompt {
            prompt = customPrompt.replacingOccurrences(of: "{query}", with: sanitizedQuery)
        } else {
            // Use structured format with clear delimiters to reduce injection risk
            prompt = """
                Generate \(numQueries) different versions of the user's question below.
                Each version should ask for the same information but with different wording.
                Return only the questions, one per line, without numbering or bullet points.

                <user_query>
                \(sanitizedQuery)
                </user_query>

                Alternative questions:
                """
        }

        let response: String
        do {
            response = try await llmProvider.generate(
                prompt: prompt,
                systemPrompt: nil,
                options: LLMOptions(temperature: 0.7, maxTokens: 200)
            )
        } catch {
            // If LLM fails, just use original query
            return [original]
        }

        // Parse response into queries
        var queries = response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            // Remove common prefixes like "1.", "- ", etc.
            .map { line -> String in
                var cleaned = line
                // Remove numbering like "1.", "2.", etc.
                if let dotIndex = cleaned.firstIndex(of: "."),
                   let _ = Int(String(cleaned[..<dotIndex])) {
                    cleaned = String(cleaned[cleaned.index(after: dotIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                }
                // Remove bullet points
                if cleaned.hasPrefix("-") || cleaned.hasPrefix("*") {
                    cleaned = String(cleaned.dropFirst())
                        .trimmingCharacters(in: .whitespaces)
                }
                return cleaned
            }
            .filter { !$0.isEmpty }

        // Always include original query first
        queries.insert(original, at: 0)

        // Limit to numQueries + 1 (including original)
        return Array(queries.prefix(numQueries + 1))
    }
}
