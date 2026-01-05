// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RetrievalUtils.swift - Shared utilities for retrieval operations

import Foundation

// MARK: - RetrievalUtils

/// Shared utilities for retrieval operations.
///
/// `RetrievalUtils` provides common text processing functions used by
/// retrieval strategies, particularly for keyword-based search.
public enum RetrievalUtils {

    // MARK: - Tokenization

    /// Common English stopwords to filter from queries and documents.
    public static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "shall", "can", "this",
        "that", "these", "those", "it", "its", "they", "them", "their",
        "what", "which", "who", "whom", "when", "where", "why", "how",
        "all", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so",
        "than", "too", "very", "just", "also", "now", "here", "there"
    ]

    /// Tokenizes text into normalized terms for indexing or searching.
    ///
    /// The tokenization process:
    /// 1. Converts text to lowercase
    /// 2. Splits on non-alphanumeric characters
    /// 3. Filters out tokens shorter than `minLength`
    /// 4. Optionally filters stopwords
    ///
    /// - Parameters:
    ///   - text: The text to tokenize.
    ///   - minLength: Minimum token length to include. Defaults to 3.
    ///   - filterStopwords: Whether to filter common stopwords. Defaults to true.
    /// - Returns: An array of normalized tokens.
    public static func tokenize(
        _ text: String,
        minLength: Int = 3,
        filterStopwords: Bool = true
    ) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                !token.isEmpty &&
                token.count >= minLength &&
                (!filterStopwords || !stopWords.contains(token))
            }
    }

    // MARK: - Score Normalization

    /// Normalizes a score to the range [0, 1].
    ///
    /// - Parameters:
    ///   - score: The score to normalize.
    ///   - min: The minimum possible score.
    ///   - max: The maximum possible score.
    /// - Returns: The normalized score, or 0 if min equals max.
    public static func normalizeScore(_ score: Float, min: Float, max: Float) -> Float {
        guard max > min else { return 0 }
        return (score - min) / (max - min)
    }

    /// Computes the term frequency of a term in a list of tokens.
    ///
    /// - Parameters:
    ///   - term: The term to count.
    ///   - tokens: The list of tokens to search.
    /// - Returns: The number of times the term appears.
    public static func termFrequency(_ term: String, in tokens: [String]) -> Int {
        tokens.filter { $0 == term }.count
    }
}
