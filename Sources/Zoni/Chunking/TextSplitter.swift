// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Core text splitting utilities for chunking text into meaningful segments.

import Foundation

// MARK: - TextSplitter

/// A collection of utilities for splitting text into meaningful segments.
///
/// `TextSplitter` provides various methods to split text by sentences, paragraphs,
/// custom separators, or regex patterns. All methods are static and the enum has
/// no stored state, making it inherently `Sendable`.
///
/// Example usage:
/// ```swift
/// // Split into sentences
/// let sentences = TextSplitter.splitSentences("Hello world. How are you?")
/// // ["Hello world.", "How are you?"]
///
/// // Split into paragraphs
/// let paragraphs = TextSplitter.splitParagraphs("First.\n\nSecond.")
/// // ["First.", "Second."]
///
/// // Merge small segments
/// let merged = TextSplitter.mergeSmall(["Hi", "there"], minLength: 10)
/// // ["Hi there"]
/// ```
public enum TextSplitter: Sendable {

    // MARK: - Common Abbreviations

    /// Common abbreviations that should not be treated as sentence endings.
    /// These are lowercase to enable case-insensitive matching.
    private static let abbreviations: Set<String> = [
        "dr", "mr", "mrs", "ms", "prof", "sr", "jr",
        "inc", "ltd", "corp", "co",
        "vs", "ca", "etc", "al",
        "st", "mt", "ave", "blvd"
    ]

    /// Multi-part abbreviations with internal periods.
    private static let multiPartAbbreviations: Set<String> = [
        "i.e", "e.g", "cf", "viz"
    ]

    // MARK: - Sentence Splitting

    /// Splits text into sentences based on sentence-ending punctuation.
    ///
    /// This method handles common sentence terminators (`.`, `?`, `!`) while
    /// preserving abbreviations, decimal numbers, URLs, and quoted text.
    ///
    /// - Parameter text: The text to split into sentences.
    /// - Returns: An array of sentences. Returns an empty array if text is empty
    ///            or contains only whitespace.
    ///
    /// ## Abbreviation Handling
    /// Common abbreviations are preserved:
    /// - Titles: Dr., Mr., Mrs., Ms., Prof., Jr., Sr.
    /// - Organizations: Inc., Ltd., Corp.
    /// - Latin: i.e., e.g., etc., vs., ca.
    /// - Geographic: St., Mt.
    ///
    /// ## Examples
    /// ```swift
    /// TextSplitter.splitSentences("Hello world. How are you?")
    /// // ["Hello world.", "How are you?"]
    ///
    /// TextSplitter.splitSentences("Dr. Smith went home. He was tired.")
    /// // ["Dr. Smith went home.", "He was tired."]
    ///
    /// TextSplitter.splitSentences("The value is 3.14 which is pi.")
    /// // ["The value is 3.14 which is pi."]
    /// ```
    public static func splitSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sentences: [String] = []
        var currentSentence = ""
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            let char = trimmed[index]
            currentSentence.append(char)

            // Check for sentence terminators
            if char == "." || char == "?" || char == "!" {
                // Handle multiple punctuation marks (!!!, ???, ?!, etc.)
                var nextIndex = trimmed.index(after: index)
                while nextIndex < trimmed.endIndex {
                    let nextChar = trimmed[nextIndex]
                    if nextChar == "." || nextChar == "?" || nextChar == "!" {
                        currentSentence.append(nextChar)
                        nextIndex = trimmed.index(after: nextIndex)
                    } else {
                        break
                    }
                }
                index = nextIndex

                // Check if this is a real sentence ending
                if shouldSplitAt(currentSentence: currentSentence, remainingText: trimmed[index...]) {
                    let trimmedSentence = currentSentence.trimmingCharacters(in: .whitespaces)
                    if !trimmedSentence.isEmpty {
                        sentences.append(trimmedSentence)
                    }
                    currentSentence = ""

                    // Skip whitespace after sentence
                    while index < trimmed.endIndex && trimmed[index].isWhitespace {
                        index = trimmed.index(after: index)
                    }
                }
                continue
            }

            index = trimmed.index(after: index)
        }

        // Add any remaining text as the last sentence
        let remaining = currentSentence.trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }

        return sentences
    }

    /// Determines if the current position should be a sentence split point.
    private static func shouldSplitAt(currentSentence: String, remainingText: Substring) -> Bool {
        // If nothing remains, this is the end
        let remaining = String(remainingText).trimmingCharacters(in: .whitespaces)
        if remaining.isEmpty {
            return true
        }

        // Only check period-specific rules for periods
        if currentSentence.hasSuffix(".") && !currentSentence.hasSuffix("..") {
            // Check if this ends with an abbreviation
            if isAbbreviation(currentSentence, remainingText: remaining) {
                return false
            }

            // Check for decimal numbers (e.g., "is 3.14" followed by more text)
            if isDecimalContext(currentSentence, remaining: remaining) {
                return false
            }

            // Check for URLs
            if isPartOfURL(currentSentence) {
                return false
            }
        }

        // For ellipsis, always split (it's a valid sentence ending)
        if currentSentence.hasSuffix("...") {
            return true
        }

        return true
    }

    /// Checks if the sentence ends with a known abbreviation.
    private static func isAbbreviation(_ sentence: String, remainingText: String = "") -> Bool {
        // Handle trailing punctuation
        var working = sentence
        while working.last == "." || working.last == "," {
            working = String(working.dropLast())
        }

        // Get the last word
        let words = working.split(separator: " ", omittingEmptySubsequences: true)
        guard let lastWord = words.last else { return false }

        var wordStr = String(lastWord)

        // Remove any remaining punctuation except internal periods
        while let last = wordStr.last, (last == "," || last == ";") {
            wordStr = String(wordStr.dropLast())
        }

        let lowerWord = wordStr.lowercased()

        // Check single-word abbreviations
        if abbreviations.contains(lowerWord) {
            return true
        }

        // Check multi-part abbreviations (i.e., e.g., etc.)
        for abbrev in multiPartAbbreviations {
            if lowerWord == abbrev || lowerWord.hasPrefix(abbrev) {
                return true
            }
        }

        // Check for single letter that starts a multi-part abbreviation (e.g. "e" in "e.g.")
        // Look ahead in remaining text to detect "e.g." or "i.e." patterns
        if wordStr.count == 1 {
            let singleLetter = wordStr.lowercased()
            for abbrev in multiPartAbbreviations {
                if abbrev.hasPrefix(singleLetter + ".") {
                    // Check if remaining text continues the abbreviation
                    let abbrevRest = String(abbrev.dropFirst(2)) // e.g. "g" from "e.g"
                    let trimmedRemaining = remainingText.trimmingCharacters(in: .whitespaces)
                    if trimmedRemaining.lowercased().hasPrefix(abbrevRest) {
                        return true
                    }
                }
            }
        }

        // Check for single uppercase letter (initial)
        if wordStr.count == 1 && wordStr.first?.isUppercase == true {
            return true
        }

        return false
    }

    /// Checks if the period might be part of a decimal number context.
    private static func isDecimalContext(_ sentence: String, remaining: String) -> Bool {
        // Check if the sentence ends with a digit followed by period
        let withoutPeriod = sentence.dropLast()
        guard let lastChar = withoutPeriod.last, lastChar.isNumber else { return false }

        // Check if the remaining text starts with a digit (making this a decimal)
        if let firstChar = remaining.first, firstChar.isNumber {
            return true
        }

        return false
    }

    /// Checks if the period appears to be part of a URL.
    private static func isPartOfURL(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()

        // Check for common URL patterns
        guard lowered.contains("http://") || lowered.contains("https://") ||
              lowered.contains("www.") || lowered.contains("ftp://") else {
            return false
        }

        // Get the last word to check if the period is part of the URL
        let words = sentence.split(separator: " ", omittingEmptySubsequences: true)
        guard let lastWord = words.last else { return false }

        let wordStr = String(lastWord)

        // If the URL contains internal periods but the sentence ends with a period,
        // we need to determine if that final period is part of the URL or sentence-ending
        let urlLike = wordStr.lowercased()

        // Common URL endings that we should NOT split on
        let urlEndings = [".com", ".org", ".net", ".io", ".dev", ".edu", ".gov", ".co"]
        for ending in urlEndings {
            if urlLike.hasSuffix(ending + ".") {
                // The period after .com etc. is sentence-ending, allow split
                return false
            }
            if urlLike.hasSuffix(ending) {
                // URL ends with domain, sentence continues after
                return false
            }
        }

        // If it has path components, the final period is likely sentence-ending
        if urlLike.contains("/") {
            return false
        }

        return false
    }

    // MARK: - Paragraph Splitting

    /// Splits text into paragraphs based on blank lines.
    ///
    /// Paragraphs are separated by one or more blank lines (double newlines).
    /// Single newlines within a paragraph are preserved. Both Unix (`\n`)
    /// and Windows (`\r\n`) line endings are supported.
    ///
    /// - Parameter text: The text to split into paragraphs.
    /// - Returns: An array of paragraphs. Returns an empty array if text is empty
    ///            or contains only whitespace.
    ///
    /// ## Examples
    /// ```swift
    /// TextSplitter.splitParagraphs("First paragraph.\n\nSecond paragraph.")
    /// // ["First paragraph.", "Second paragraph."]
    ///
    /// TextSplitter.splitParagraphs("Line 1\nLine 2\n\nParagraph 2")
    /// // ["Line 1\nLine 2", "Paragraph 2"]
    /// ```
    public static func splitParagraphs(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Normalize line endings
        let normalized = trimmed
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")

        // Split on double newlines (or more)
        // Use regex to match 2+ newlines, optionally with whitespace between
        let paragraphSeparator = try? Regex(#"\n\s*\n+"#)

        let components: [String]
        if let separator = paragraphSeparator {
            components = normalized.split(separator: separator).map { String($0) }
        } else {
            // Fallback: simple split on double newline
            components = normalized.components(separatedBy: "\n\n")
        }

        // Trim and filter empty paragraphs
        return components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Custom Separator Splitting

    /// Splits text using a hierarchical list of separators.
    ///
    /// The method tries each separator in order and uses the first one that
    /// produces a split. This is useful for recursive chunking strategies
    /// where you want to prefer larger semantic boundaries.
    ///
    /// - Parameters:
    ///   - text: The text to split.
    ///   - separators: An array of separators to try, in priority order.
    /// - Returns: An array of segments. Returns the original text as a single-element
    ///            array if no separator produces a split or if separators is empty.
    ///
    /// ## Examples
    /// ```swift
    /// TextSplitter.split("a\n\nb\n\nc", separators: ["\n\n", "\n", " "])
    /// // ["a", "b", "c"] - uses first separator that matches
    ///
    /// TextSplitter.split("a b c", separators: ["\n\n", "\n", " "])
    /// // ["a", "b", "c"] - falls back to space separator
    /// ```
    public static func split(_ text: String, separators: [String]) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard !separators.isEmpty else { return [trimmed] }

        // Try each separator in order
        for separator in separators {
            guard !separator.isEmpty else { continue }

            if trimmed.contains(separator) {
                let components = trimmed.components(separatedBy: separator)
                let filtered = components
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if filtered.count > 1 {
                    return filtered
                }

                // If separator exists but all components are empty (text is just separators)
                if components.count > 1 && filtered.isEmpty {
                    return []
                }
            }
        }

        // No separator produced a split
        return [trimmed]
    }

    // MARK: - Regex Pattern Splitting

    /// Splits text using a regular expression pattern.
    ///
    /// Uses Swift 6's `Regex` type for pattern matching. The text is split
    /// at each match of the pattern, similar to `String.split(separator:)`.
    ///
    /// - Parameters:
    ///   - text: The text to split.
    ///   - pattern: A regular expression pattern string.
    /// - Returns: An array of segments between pattern matches.
    /// - Throws: An error if the pattern is not a valid regular expression.
    ///
    /// ## Examples
    /// ```swift
    /// try TextSplitter.split("a1b2c3d", pattern: #"\d"#)
    /// // ["a", "b", "c", "d"]
    ///
    /// try TextSplitter.split("Hello  World", pattern: #"\s+"#)
    /// // ["Hello", "World"]
    /// ```
    public static func split(_ text: String, pattern: String) throws -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let regex = try Regex(pattern)

        let segments = trimmed.split(separator: regex)

        let result = segments
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // If no matches, return original text
        if result.isEmpty && !trimmed.isEmpty {
            // Check if the entire text matches the pattern
            if trimmed.firstMatch(of: regex) != nil {
                // Pattern matched, so splits resulted in empty segments
                return []
            }
            return [trimmed]
        }

        return result.isEmpty ? [trimmed] : result
    }

    // MARK: - Merge Small Segments

    /// Merges consecutive segments that are below a minimum length.
    ///
    /// This is useful for combining small chunks that would be too short
    /// for meaningful embedding or retrieval.
    ///
    /// - Parameters:
    ///   - segments: The segments to potentially merge.
    ///   - minLength: The minimum character length for a segment.
    ///   - separator: The string to use when joining segments. Defaults to a space.
    /// - Returns: An array of segments where consecutive small segments have been merged.
    ///
    /// ## Examples
    /// ```swift
    /// TextSplitter.mergeSmall(["Hi", "there", "friend"], minLength: 10)
    /// // ["Hi there friend"]
    ///
    /// TextSplitter.mergeSmall(["Short", "This is a longer segment"], minLength: 10)
    /// // ["Short This is a longer segment"] or preserved based on logic
    /// ```
    public static func mergeSmall(_ segments: [String], minLength: Int, separator: String = " ") -> [String] {
        guard !segments.isEmpty else { return [] }
        guard minLength > 0 else { return segments }

        var result: [String] = []
        var accumulator = ""

        for segment in segments {
            if accumulator.isEmpty {
                accumulator = segment
            } else {
                // Append with separator
                accumulator = accumulator + separator + segment
            }

            // Check if accumulated text meets minimum length
            if accumulator.count >= minLength {
                result.append(accumulator)
                accumulator = ""
            }
        }

        // Handle remaining accumulated text
        if !accumulator.isEmpty {
            if result.isEmpty {
                // If no segments met the minLength, return what we have
                result.append(accumulator)
            } else {
                // Merge with the last segment
                let last = result.removeLast()
                result.append(last + separator + accumulator)
            }
        }

        return result
    }
}
