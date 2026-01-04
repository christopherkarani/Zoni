// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Token counting utilities for text chunking and token limit management.

import Foundation

// MARK: - TokenizerModel

/// Represents different tokenizer models with their approximate character-to-token ratios.
///
/// Different language models use different tokenization algorithms, resulting in varying
/// token counts for the same text. This enum provides approximate ratios that can be used
/// for estimation purposes when exact tokenization is not required.
///
/// Example usage:
/// ```swift
/// let model = TokenizerModel.cl100k
/// let approximateTokens = Int(Double(text.count) / model.approximateCharsPerToken)
/// ```
public enum TokenizerModel: String, Sendable, Codable, CaseIterable {
    /// OpenAI's cl100k_base tokenizer used by GPT-4 models.
    ///
    /// This tokenizer has an average of approximately 3.8 characters per token
    /// for English text.
    case cl100k = "cl100k_base"

    /// OpenAI's p50k_base tokenizer used by GPT-3 models.
    ///
    /// This tokenizer has an average of approximately 4.0 characters per token
    /// for English text.
    case p50k = "p50k_base"

    /// A simple character-based estimation model.
    ///
    /// Uses a fixed ratio of approximately 4.0 characters per token,
    /// suitable for quick estimations when exact counts are not critical.
    case simple

    /// The approximate number of characters per token for this model.
    ///
    /// These values are approximations based on typical English text.
    /// Actual ratios may vary significantly based on content type,
    /// language, and specific vocabulary used.
    public var approximateCharsPerToken: Double {
        switch self {
        case .cl100k:
            return 3.8
        case .p50k, .simple:
            return 4.0
        }
    }
}

// MARK: - TokenCountResult

/// The result of a token counting operation with detailed metrics.
///
/// This struct provides both the token count and additional information
/// about the counted text, including character count and the effective
/// character-to-token ratio.
///
/// Example usage:
/// ```swift
/// let counter = TokenCounter(model: .simple)
/// let result = counter.countWithDetails("Hello World")
/// print("Tokens: \(result.tokenCount), Characters: \(result.characterCount)")
/// print("Effective ratio: \(result.effectiveRatio) chars/token")
/// ```
public struct TokenCountResult: Sendable, Equatable {
    /// The estimated number of tokens in the counted text.
    public let tokenCount: Int

    /// The number of characters in the counted text.
    public let characterCount: Int

    /// The tokenizer model used for counting.
    public let model: TokenizerModel

    /// The effective character-to-token ratio for the counted text.
    ///
    /// This is calculated as `characterCount / tokenCount`.
    /// Returns `0` if the token count is zero to avoid division by zero.
    public var effectiveRatio: Double {
        guard tokenCount > 0 else { return 0 }
        return Double(characterCount) / Double(tokenCount)
    }

    /// Creates a new token count result.
    ///
    /// - Parameters:
    ///   - tokenCount: The number of tokens counted.
    ///   - characterCount: The number of characters in the text.
    ///   - model: The tokenizer model used for counting.
    public init(tokenCount: Int, characterCount: Int, model: TokenizerModel) {
        self.tokenCount = tokenCount
        self.characterCount = characterCount
        self.model = model
    }
}

// MARK: - TokenCounter

/// A utility for estimating token counts in text based on tokenizer model characteristics.
///
/// `TokenCounter` provides approximate token counts without requiring access to
/// the actual tokenizer. This is useful for:
/// - Estimating context window usage before API calls
/// - Chunking text to fit within token limits
/// - Quick validation of text sizes
///
/// The estimation uses a character-to-token ratio that varies by model.
/// For exact token counts, use the actual tokenizer from the respective API.
///
/// Example usage:
/// ```swift
/// let counter = TokenCounter(model: .cl100k)
///
/// // Count tokens in text
/// let tokens = counter.count("Hello, world!")
///
/// // Check if text fits within a limit
/// if counter.fits(text, maxTokens: 4096) {
///     // Safe to send to API
/// }
///
/// // Split text to fit within token limits
/// let chunks = counter.splitToFit(longText, maxTokens: 1000)
/// ```
public struct TokenCounter: Sendable {

    // MARK: - Properties

    /// The tokenizer model used for estimation.
    public let model: TokenizerModel

    // MARK: - Initialization

    /// Creates a new token counter with the specified tokenizer model.
    ///
    /// - Parameter model: The tokenizer model to use for estimation. Defaults to `.simple`.
    public init(model: TokenizerModel = .simple) {
        self.model = model
    }

    // MARK: - Public Methods

    /// Counts the approximate number of tokens in the given text.
    ///
    /// The count is calculated using the model's character-to-token ratio.
    /// Empty strings return 0, and non-empty strings return at least 1 token.
    ///
    /// - Parameter text: The text to count tokens for.
    /// - Returns: The estimated number of tokens.
    public func count(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let charCount = text.count
        return max(1, Int(Double(charCount) / model.approximateCharsPerToken))
    }

    /// Counts the approximate number of tokens for each text in an array.
    ///
    /// - Parameter texts: An array of texts to count tokens for.
    /// - Returns: An array of token counts, in the same order as the input texts.
    public func count(_ texts: [String]) -> [Int] {
        texts.map { count($0) }
    }

    /// Calculates the total token count across all texts.
    ///
    /// - Parameter texts: An array of texts to count tokens for.
    /// - Returns: The sum of token counts across all texts.
    public func totalCount(_ texts: [String]) -> Int {
        count(texts).reduce(0, +)
    }

    /// Counts tokens in the text and returns detailed results.
    ///
    /// - Parameter text: The text to count tokens for.
    /// - Returns: A `TokenCountResult` containing the token count and additional metrics.
    public func countWithDetails(_ text: String) -> TokenCountResult {
        TokenCountResult(
            tokenCount: count(text),
            characterCount: text.count,
            model: model
        )
    }

    /// Splits text into segments that each fit within the specified token limit.
    ///
    /// The method attempts to split at word boundaries (spaces) when possible.
    /// If a word exceeds the token limit, it will be split at character boundaries.
    ///
    /// - Parameters:
    ///   - text: The text to split.
    ///   - maxTokens: The maximum number of tokens per segment.
    /// - Returns: An array of text segments, each fitting within the token limit.
    ///            Returns an empty array if the text is empty or maxTokens is non-positive.
    public func splitToFit(_ text: String, maxTokens: Int) -> [String] {
        guard !text.isEmpty, maxTokens > 0 else { return [] }

        // If text already fits, return it as single segment
        if fits(text, maxTokens: maxTokens) {
            return [text]
        }

        let maxChars = estimateCharacters(forTokens: maxTokens)

        // Try splitting at word boundaries first
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var segments: [String] = []
        var currentSegment = ""

        for word in words {
            let wordString = String(word)
            let testSegment = currentSegment.isEmpty ? wordString : currentSegment + " " + wordString

            if count(testSegment) <= maxTokens {
                currentSegment = testSegment
            } else {
                // Current segment is full, save it if non-empty
                if !currentSegment.isEmpty {
                    segments.append(currentSegment.trimmingCharacters(in: .whitespaces))
                    currentSegment = ""
                }

                // Check if the single word fits
                if count(wordString) <= maxTokens {
                    currentSegment = wordString
                } else {
                    // Word is too long, need to split by characters
                    let wordSegments = splitWordByCharacters(wordString, maxChars: maxChars)
                    if let last = wordSegments.last {
                        segments.append(contentsOf: wordSegments.dropLast())
                        currentSegment = last
                    }
                }
            }
        }

        // Add the last segment if non-empty
        if !currentSegment.isEmpty {
            let trimmed = currentSegment.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                segments.append(trimmed)
            }
        }

        return segments
    }

    /// Splits text into segments with overlap between consecutive segments.
    ///
    /// Overlap is useful for maintaining context across chunk boundaries,
    /// which can improve retrieval quality in RAG systems.
    ///
    /// - Parameters:
    ///   - text: The text to split.
    ///   - maxTokens: The maximum number of tokens per segment.
    ///   - overlapTokens: The number of tokens to overlap between segments.
    ///                    If this equals or exceeds `maxTokens`, behavior is gracefully handled.
    /// - Returns: An array of text segments with the specified overlap.
    public func splitToFit(_ text: String, maxTokens: Int, overlapTokens: Int) -> [String] {
        guard !text.isEmpty, maxTokens > 0 else { return [] }

        // Handle edge cases for overlap
        let effectiveOverlap = max(0, min(overlapTokens, maxTokens - 1))

        // If no effective overlap, use the standard split
        if effectiveOverlap == 0 {
            return splitToFit(text, maxTokens: maxTokens)
        }

        // If text fits in one segment, no overlap needed
        if fits(text, maxTokens: maxTokens) {
            return [text]
        }

        // Calculate effective tokens per non-overlapping portion
        let effectiveStride = maxTokens - effectiveOverlap
        guard effectiveStride > 0 else {
            // Overlap is too large, fall back to standard split
            return splitToFit(text, maxTokens: maxTokens)
        }

        let overlapChars = estimateCharacters(forTokens: effectiveOverlap)
        let strideChars = estimateCharacters(forTokens: effectiveStride)
        let maxChars = estimateCharacters(forTokens: maxTokens)

        var segments: [String] = []
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            // Calculate end position for this segment
            var endIndex = text.index(startIndex, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex

            // Try to find a word boundary near the end
            if endIndex < text.endIndex {
                let searchRange = text.index(endIndex, offsetBy: -min(20, text.distance(from: startIndex, to: endIndex)), limitedBy: startIndex) ?? startIndex
                if let spaceIndex = text[searchRange..<endIndex].lastIndex(of: " ") {
                    endIndex = spaceIndex
                }
            }

            let segment = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
            if !segment.isEmpty {
                segments.append(segment)
            }

            // Move start position forward by stride amount (accounting for overlap)
            let nextStartOffset = text.distance(from: text.startIndex, to: startIndex) + strideChars
            if nextStartOffset >= text.count {
                break
            }

            let nextStart = text.index(text.startIndex, offsetBy: nextStartOffset, limitedBy: text.endIndex) ?? text.endIndex

            // Try to start at a word boundary
            if nextStart < text.endIndex, text[nextStart] != " " {
                // Look for the previous space
                if let spaceIndex = text[startIndex..<nextStart].lastIndex(of: " ") {
                    startIndex = text.index(after: spaceIndex)
                } else {
                    startIndex = nextStart
                }
            } else if nextStart < text.endIndex {
                // Skip the space
                startIndex = text.index(after: nextStart)
            } else {
                break
            }

            // Safety check to prevent infinite loops
            if startIndex >= text.endIndex {
                break
            }
        }

        return segments
    }

    /// Estimates the number of characters that would fit in the given token count.
    ///
    /// - Parameter tokens: The target number of tokens.
    /// - Returns: The estimated number of characters. Returns 0 for non-positive token counts.
    public func estimateCharacters(forTokens tokens: Int) -> Int {
        guard tokens > 0 else { return 0 }
        return Int(Double(tokens) * model.approximateCharsPerToken)
    }

    /// Checks whether the text fits within the specified token limit.
    ///
    /// - Parameters:
    ///   - text: The text to check.
    ///   - maxTokens: The maximum allowed tokens.
    /// - Returns: `true` if the text fits within the limit, `false` otherwise.
    public func fits(_ text: String, maxTokens: Int) -> Bool {
        count(text) <= maxTokens
    }

    // MARK: - Private Methods

    /// Splits a word into segments by character count when it exceeds the token limit.
    ///
    /// - Parameters:
    ///   - word: The word to split.
    ///   - maxChars: The maximum characters per segment.
    /// - Returns: An array of character-based segments.
    private func splitWordByCharacters(_ word: String, maxChars: Int) -> [String] {
        guard maxChars > 0 else { return [word] }

        var segments: [String] = []
        var currentIndex = word.startIndex

        while currentIndex < word.endIndex {
            let endIndex = word.index(currentIndex, offsetBy: maxChars, limitedBy: word.endIndex) ?? word.endIndex
            let segment = String(word[currentIndex..<endIndex])
            segments.append(segment)
            currentIndex = endIndex
        }

        return segments
    }
}

// MARK: - CustomStringConvertible

extension TokenCounter: CustomStringConvertible {
    public var description: String {
        "TokenCounter(model: \(model.rawValue), ~\(model.approximateCharsPerToken) chars/token)"
    }
}

extension TokenCountResult: CustomStringConvertible {
    public var description: String {
        "TokenCountResult(tokens: \(tokenCount), characters: \(characterCount), ratio: \(String(format: "%.2f", effectiveRatio)))"
    }
}
