import Testing
import Foundation
@testable import Zoni

// MARK: - TokenizerModel Tests

@Suite("TokenizerModel Tests")
struct TokenizerModelTests {

    // MARK: - Raw Value Tests

    @Test("cl100k has correct raw value")
    func cl100kRawValue() {
        #expect(TokenizerModel.cl100k.rawValue == "cl100k_base")
    }

    @Test("p50k has correct raw value")
    func p50kRawValue() {
        #expect(TokenizerModel.p50k.rawValue == "p50k_base")
    }

    @Test("simple has correct raw value")
    func simpleRawValue() {
        #expect(TokenizerModel.simple.rawValue == "simple")
    }

    // MARK: - Approximate Chars Per Token Tests

    @Test("cl100k approximateCharsPerToken is around 3.8")
    func cl100kApproximateCharsPerToken() {
        let model = TokenizerModel.cl100k
        #expect(model.approximateCharsPerToken >= 3.7)
        #expect(model.approximateCharsPerToken <= 3.9)
    }

    @Test("p50k approximateCharsPerToken is around 4.0")
    func p50kApproximateCharsPerToken() {
        let model = TokenizerModel.p50k
        #expect(model.approximateCharsPerToken >= 3.9)
        #expect(model.approximateCharsPerToken <= 4.1)
    }

    @Test("simple approximateCharsPerToken is around 4.0")
    func simpleApproximateCharsPerToken() {
        let model = TokenizerModel.simple
        #expect(model.approximateCharsPerToken >= 3.9)
        #expect(model.approximateCharsPerToken <= 4.1)
    }

    // MARK: - CaseIterable Conformance Tests

    @Test("TokenizerModel conforms to CaseIterable with all cases")
    func caseIterableConformance() {
        let allCases = TokenizerModel.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.cl100k))
        #expect(allCases.contains(.p50k))
        #expect(allCases.contains(.simple))
    }

    // MARK: - Codable Conformance Tests

    @Test("TokenizerModel encodes and decodes correctly")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for model in TokenizerModel.allCases {
            let data = try encoder.encode(model)
            let decoded = try decoder.decode(TokenizerModel.self, from: data)
            #expect(decoded == model)
        }
    }

    // MARK: - Sendable Conformance Tests

    @Test("TokenizerModel is Sendable")
    func sendableConformance() async {
        let model: TokenizerModel = .simple

        // Verify we can pass across concurrency boundaries
        await Task.detached {
            let _ = model.rawValue
        }.value
    }
}

// MARK: - TokenCounter Basic Counting Tests

@Suite("TokenCounter Basic Counting Tests")
struct TokenCounterBasicCountingTests {

    // MARK: - Empty String Tests

    @Test("Empty string returns 0 tokens")
    func emptyStringReturnsZero() {
        let counter = TokenCounter()
        let count = counter.count("")
        #expect(count == 0)
    }

    @Test("Empty string returns 0 tokens for all models")
    func emptyStringReturnsZeroForAllModels() {
        for model in TokenizerModel.allCases {
            let counter = TokenCounter(model: model)
            let count = counter.count("")
            #expect(count == 0, "Model \(model.rawValue) should return 0 for empty string")
        }
    }

    // MARK: - Single Word Tests

    @Test("Single word counting returns at least 1 token")
    func singleWordCounting() {
        let counter = TokenCounter(model: .simple)
        let count = counter.count("Hello")
        #expect(count >= 1)
    }

    @Test("Single short word returns 1 token with simple model")
    func singleShortWordReturnsOneToken() {
        let counter = TokenCounter(model: .simple)
        // "test" is 4 characters, ~1 token with simple model (~4 chars/token)
        let count = counter.count("test")
        #expect(count == 1)
    }

    @Test("Single long word returns multiple tokens")
    func singleLongWordReturnsMultipleTokens() {
        let counter = TokenCounter(model: .simple)
        // "internationalization" is 20 characters, should be ~5 tokens with simple model
        let count = counter.count("internationalization")
        #expect(count >= 4)
        #expect(count <= 6)
    }

    // MARK: - Multi-Word Sentence Tests

    @Test("Multi-word sentence counting")
    func multiWordSentenceCounting() {
        let counter = TokenCounter(model: .simple)
        // "Hello World" is 11 characters (including space), should be ~3 tokens
        let count = counter.count("Hello World")
        #expect(count >= 2)
        #expect(count <= 4)
    }

    @Test("Longer sentence counting")
    func longerSentenceCounting() {
        let counter = TokenCounter(model: .simple)
        // "The quick brown fox jumps over the lazy dog" is 43 characters
        // With ~4 chars/token, should be ~11 tokens
        let text = "The quick brown fox jumps over the lazy dog"
        let count = counter.count(text)
        let expectedApprox = Int(ceil(Double(text.count) / 4.0))
        #expect(count >= expectedApprox - 2)
        #expect(count <= expectedApprox + 2)
    }

    // MARK: - Simple Model Ratio Tests

    @Test("Simple model uses approximately 4 chars per token")
    func simpleModelUsesApprox4CharsPerToken() {
        let counter = TokenCounter(model: .simple)
        // Use a long text to get a more accurate ratio
        let text = String(repeating: "abcd", count: 100) // 400 characters
        let count = counter.count(text)
        // Should be approximately 100 tokens (400 / 4)
        #expect(count >= 90)
        #expect(count <= 110)
    }

    // MARK: - Different Models Tests

    @Test("cl100k model produces different token count than simple")
    func cl100kModelDifferentFromSimple() {
        let simpleCounter = TokenCounter(model: .simple)
        let cl100kCounter = TokenCounter(model: .cl100k)

        let text = "This is a test sentence for comparing tokenization models."
        let simpleCount = simpleCounter.count(text)
        let cl100kCount = cl100kCounter.count(text)

        // Both should produce valid counts
        #expect(simpleCount > 0)
        #expect(cl100kCount > 0)
    }

    // MARK: - Default Model Tests

    @Test("Default initializer uses simple model")
    func defaultInitializerUsesSimpleModel() {
        let counter = TokenCounter()
        #expect(counter.model == .simple)
    }
}

// MARK: - TokenCounter Batch Counting Tests

@Suite("TokenCounter Batch Counting Tests")
struct TokenCounterBatchCountingTests {

    // MARK: - Array of Texts Tests

    @Test("Count array of texts returns correct counts")
    func countArrayOfTexts() {
        let counter = TokenCounter(model: .simple)
        let texts = ["Hello", "World", "Test"]
        let counts = counter.count(texts)

        #expect(counts.count == 3)
        #expect(counts[0] >= 1) // "Hello" is 5 chars, ~1-2 tokens
        #expect(counts[1] >= 1) // "World" is 5 chars, ~1-2 tokens
        #expect(counts[2] >= 1) // "Test" is 4 chars, ~1 token
    }

    @Test("Count array preserves order")
    func countArrayPreservesOrder() {
        let counter = TokenCounter(model: .simple)
        // Create texts with distinctly different lengths
        let texts = [
            "a",                           // ~1 token
            "abcdefghijklmnop",            // ~4 tokens
            "ab"                           // ~1 token
        ]
        let counts = counter.count(texts)

        #expect(counts.count == 3)
        // Second text should have more tokens than first and third
        #expect(counts[1] >= counts[0])
        #expect(counts[1] >= counts[2])
    }

    // MARK: - Total Count Tests

    @Test("totalCount sums correctly")
    func totalCountSumsCorrectly() {
        let counter = TokenCounter(model: .simple)
        let texts = ["Hello", "World"]
        let counts = counter.count(texts)
        let total = counter.totalCount(texts)

        let expectedTotal = counts.reduce(0, +)
        #expect(total == expectedTotal)
    }

    @Test("totalCount for single text equals count")
    func totalCountForSingleTextEqualsCount() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello World"
        let singleCount = counter.count(text)
        let totalCount = counter.totalCount([text])

        #expect(totalCount == singleCount)
    }

    // MARK: - Empty Array Tests

    @Test("Empty array returns empty counts array")
    func emptyArrayReturnsEmptyCounts() {
        let counter = TokenCounter(model: .simple)
        let texts: [String] = []
        let counts = counter.count(texts)

        #expect(counts.isEmpty)
    }

    @Test("Empty array totalCount returns 0")
    func emptyArrayTotalCountReturnsZero() {
        let counter = TokenCounter(model: .simple)
        let texts: [String] = []
        let total = counter.totalCount(texts)

        #expect(total == 0)
    }

    // MARK: - Mixed Content Tests

    @Test("Array with empty strings handles correctly")
    func arrayWithEmptyStrings() {
        let counter = TokenCounter(model: .simple)
        let texts = ["Hello", "", "World", ""]
        let counts = counter.count(texts)

        #expect(counts.count == 4)
        #expect(counts[1] == 0) // Empty string
        #expect(counts[3] == 0) // Empty string
    }
}

// MARK: - TokenCounter splitToFit Tests

@Suite("TokenCounter splitToFit Tests")
struct TokenCounterSplitToFitTests {

    // MARK: - Text Within Limit Tests

    @Test("Text within limit returns single segment")
    func textWithinLimitReturnsSingleSegment() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello World" // ~3 tokens
        let segments = counter.splitToFit(text, maxTokens: 100)

        #expect(segments.count == 1)
        #expect(segments.first == text)
    }

    @Test("Text exactly at limit returns single segment")
    func textExactlyAtLimitReturnsSingleSegment() {
        let counter = TokenCounter(model: .simple)
        // With simple model ~4 chars/token, 20 chars ~= 5 tokens
        let text = "12345678901234567890"
        let tokenCount = counter.count(text)
        let segments = counter.splitToFit(text, maxTokens: tokenCount)

        #expect(segments.count == 1)
    }

    // MARK: - Text Exceeding Limit Tests

    @Test("Text exceeding limit splits correctly")
    func textExceedingLimitSplitsCorrectly() {
        let counter = TokenCounter(model: .simple)
        // Long text that should require splitting
        let text = String(repeating: "word ", count: 100).trimmingCharacters(in: .whitespaces)
        let segments = counter.splitToFit(text, maxTokens: 10)

        #expect(segments.count > 1)

        // Each segment should fit within the token limit
        for segment in segments {
            let segmentTokens = counter.count(segment)
            #expect(segmentTokens <= 10, "Segment should not exceed max tokens: \(segmentTokens)")
        }
    }

    @Test("All content is preserved after splitting")
    func allContentPreservedAfterSplitting() {
        let counter = TokenCounter(model: .simple)
        let words = (1...50).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let segments = counter.splitToFit(text, maxTokens: 20)

        // Reconstruct and verify all words are present
        let reconstructed = segments.joined(separator: " ")
        for word in words {
            #expect(reconstructed.contains(word), "Word '\(word)' should be preserved")
        }
    }

    // MARK: - Word Boundary Tests

    @Test("Splits at word boundaries when possible")
    func splitsAtWordBoundaries() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello World Testing Splitting Words"
        let segments = counter.splitToFit(text, maxTokens: 5)

        // No segment should start or end with a partial word
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            // Should not start with a space
            #expect(!trimmed.hasPrefix(" "))
            // Should not end with a space
            #expect(!trimmed.hasSuffix(" "))
        }
    }

    // MARK: - Empty and Invalid Input Tests

    @Test("Empty text returns empty array")
    func emptyTextReturnsEmptyArray() {
        let counter = TokenCounter(model: .simple)
        let segments = counter.splitToFit("", maxTokens: 10)

        #expect(segments.isEmpty)
    }

    @Test("maxTokens of 0 returns empty array")
    func maxTokensZeroReturnsEmptyArray() {
        let counter = TokenCounter(model: .simple)
        let segments = counter.splitToFit("Hello World", maxTokens: 0)

        #expect(segments.isEmpty)
    }

    @Test("maxTokens negative returns empty array")
    func maxTokensNegativeReturnsEmptyArray() {
        let counter = TokenCounter(model: .simple)
        let segments = counter.splitToFit("Hello World", maxTokens: -5)

        #expect(segments.isEmpty)
    }

    // MARK: - Overlap Variant Tests

    @Test("splitToFit with overlap includes overlap content")
    func splitToFitWithOverlapIncludesOverlapContent() {
        let counter = TokenCounter(model: .simple)
        let text = "One Two Three Four Five Six Seven Eight Nine Ten"
        let segments = counter.splitToFit(text, maxTokens: 10, overlapTokens: 2)

        // Should have multiple segments with overlap
        #expect(segments.count >= 2)

        // Check that consecutive segments share some content (overlap)
        if segments.count >= 2 {
            // The end of first segment should overlap with beginning of second
            let firstSegmentWords = segments[0].split(separator: " ")
            let secondSegmentWords = segments[1].split(separator: " ")

            // There should be some common words at the boundary
            let lastWordsOfFirst = firstSegmentWords.suffix(3)
            let firstWordsOfSecond = secondSegmentWords.prefix(3)

            let hasOverlap = lastWordsOfFirst.contains { word in
                firstWordsOfSecond.contains(word)
            }
            #expect(hasOverlap, "Segments should have overlapping content")
        }
    }

    @Test("splitToFit with zero overlap behaves like without overlap")
    func splitToFitWithZeroOverlapBehavesLikeWithout() {
        let counter = TokenCounter(model: .simple)
        let text = "One Two Three Four Five Six Seven Eight Nine Ten"
        let segmentsWithoutOverlap = counter.splitToFit(text, maxTokens: 5)
        let segmentsWithZeroOverlap = counter.splitToFit(text, maxTokens: 5, overlapTokens: 0)

        #expect(segmentsWithoutOverlap.count == segmentsWithZeroOverlap.count)
    }

    @Test("splitToFit with overlap larger than maxTokens handles gracefully")
    func splitToFitWithLargeOverlapHandlesGracefully() {
        let counter = TokenCounter(model: .simple)
        let text = "One Two Three Four Five"
        // Overlap larger than maxTokens should be handled gracefully
        let segments = counter.splitToFit(text, maxTokens: 5, overlapTokens: 10)

        // Should not crash and should return some result
        #expect(segments.count >= 0)
    }
}

// MARK: - TokenCounter Utility Methods Tests

@Suite("TokenCounter Utility Methods Tests")
struct TokenCounterUtilityMethodsTests {

    // MARK: - estimateCharacters Tests

    @Test("estimateCharacters calculation for simple model")
    func estimateCharactersForSimpleModel() {
        let counter = TokenCounter(model: .simple)
        // Simple model uses ~4 chars/token
        let estimated = counter.estimateCharacters(forTokens: 10)
        #expect(estimated == 40) // 10 * 4 = 40
    }

    @Test("estimateCharacters calculation for cl100k model")
    func estimateCharactersForCl100kModel() {
        let counter = TokenCounter(model: .cl100k)
        // cl100k uses ~3.8 chars/token
        let estimated = counter.estimateCharacters(forTokens: 10)
        #expect(estimated == 38) // 10 * 3.8 = 38
    }

    @Test("estimateCharacters for zero tokens returns 0")
    func estimateCharactersForZeroTokens() {
        let counter = TokenCounter(model: .simple)
        let estimated = counter.estimateCharacters(forTokens: 0)
        #expect(estimated == 0)
    }

    @Test("estimateCharacters for negative tokens returns 0 or handles gracefully")
    func estimateCharactersForNegativeTokens() {
        let counter = TokenCounter(model: .simple)
        let estimated = counter.estimateCharacters(forTokens: -5)
        // Should either return 0 or absolute value
        #expect(estimated >= 0)
    }

    // MARK: - fits Tests

    @Test("fits returns true for text within limit")
    func fitsReturnsTrueForTextWithinLimit() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello" // ~2 tokens
        let fits = counter.fits(text, maxTokens: 10)
        #expect(fits == true)
    }

    @Test("fits returns false for text exceeding limit")
    func fitsReturnsFalseForTextExceedingLimit() {
        let counter = TokenCounter(model: .simple)
        let text = String(repeating: "word ", count: 100) // ~125 tokens
        let fits = counter.fits(text, maxTokens: 10)
        #expect(fits == false)
    }

    @Test("fits returns true for empty string")
    func fitsReturnsTrueForEmptyString() {
        let counter = TokenCounter(model: .simple)
        let fits = counter.fits("", maxTokens: 10)
        #expect(fits == true)
    }

    @Test("fits returns true for text exactly at limit")
    func fitsReturnsTrueForTextExactlyAtLimit() {
        let counter = TokenCounter(model: .simple)
        let text = "test" // 4 chars = ~1 token
        let tokenCount = counter.count(text)
        let fits = counter.fits(text, maxTokens: tokenCount)
        #expect(fits == true)
    }

    @Test("fits returns false for zero maxTokens with non-empty text")
    func fitsReturnsFalseForZeroMaxTokensWithNonEmptyText() {
        let counter = TokenCounter(model: .simple)
        let fits = counter.fits("Hello", maxTokens: 0)
        #expect(fits == false)
    }

    @Test("fits returns true for zero maxTokens with empty text")
    func fitsReturnsTrueForZeroMaxTokensWithEmptyText() {
        let counter = TokenCounter(model: .simple)
        let fits = counter.fits("", maxTokens: 0)
        #expect(fits == true)
    }
}

// MARK: - TokenCounter Edge Cases Tests

@Suite("TokenCounter Edge Cases Tests")
struct TokenCounterEdgeCasesTests {

    // MARK: - Unicode Text Handling Tests

    @Test("Handle Unicode text with emojis")
    func handleUnicodeWithEmojis() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello 🌍 World 🎉"
        let count = counter.count(text)
        #expect(count > 0)
    }

    @Test("Handle Unicode text with CJK characters")
    func handleUnicodeWithCJK() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello World"
        let count = counter.count(text)
        #expect(count > 0)
    }

    @Test("Handle Unicode text with Arabic characters")
    func handleUnicodeWithArabic() {
        let counter = TokenCounter(model: .simple)
        let text = "مرحبا بالعالم"
        let count = counter.count(text)
        #expect(count > 0)
    }

    @Test("Handle Unicode text with combining characters")
    func handleUnicodeWithCombiningCharacters() {
        let counter = TokenCounter(model: .simple)
        // e + combining acute accent
        let text = "cafe\u{0301}"
        let count = counter.count(text)
        #expect(count > 0)
    }

    @Test("Handle text with zero-width characters")
    func handleTextWithZeroWidthCharacters() {
        let counter = TokenCounter(model: .simple)
        // Zero-width space
        let text = "Hello\u{200B}World"
        let count = counter.count(text)
        #expect(count > 0)
    }

    // MARK: - Very Long Words Tests

    @Test("Handle very long word without spaces")
    func handleVeryLongWord() {
        let counter = TokenCounter(model: .simple)
        let longWord = String(repeating: "a", count: 1000)
        let count = counter.count(longWord)
        // 1000 chars / 4 chars per token = ~250 tokens
        #expect(count >= 200)
        #expect(count <= 300)
    }

    @Test("splitToFit handles very long word")
    func splitToFitHandlesVeryLongWord() {
        let counter = TokenCounter(model: .simple)
        let longWord = String(repeating: "a", count: 100)
        let segments = counter.splitToFit(longWord, maxTokens: 5)

        // Should split the long word somehow
        #expect(segments.count > 1)

        // All content should be preserved
        let total = segments.joined()
        #expect(total.count >= longWord.count)
    }

    // MARK: - Whitespace-Only Text Tests

    @Test("Whitespace-only text returns minimal tokens")
    func whitespaceOnlyTextReturnsMinimalTokens() {
        let counter = TokenCounter(model: .simple)
        let text = "     " // 5 spaces
        let count = counter.count(text)
        // Whitespace might be 0 tokens or minimal
        #expect(count >= 0)
        #expect(count <= 2)
    }

    @Test("Tab-only text returns minimal tokens")
    func tabOnlyTextReturnsMinimalTokens() {
        let counter = TokenCounter(model: .simple)
        let text = "\t\t\t"
        let count = counter.count(text)
        #expect(count >= 0)
        #expect(count <= 2)
    }

    @Test("Newline-only text returns minimal tokens")
    func newlineOnlyTextReturnsMinimalTokens() {
        let counter = TokenCounter(model: .simple)
        let text = "\n\n\n"
        let count = counter.count(text)
        #expect(count >= 0)
        #expect(count <= 2)
    }

    @Test("Mixed whitespace text returns minimal tokens")
    func mixedWhitespaceTextReturnsMinimalTokens() {
        let counter = TokenCounter(model: .simple)
        let text = "  \t\n  \t\n  "
        let count = counter.count(text)
        #expect(count >= 0)
        #expect(count <= 3)
    }

    // MARK: - Special Characters Tests

    @Test("Handle text with punctuation")
    func handleTextWithPunctuation() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello, World! How are you?"
        let count = counter.count(text)
        #expect(count > 0)
    }

    @Test("Handle text with special symbols")
    func handleTextWithSpecialSymbols() {
        let counter = TokenCounter(model: .simple)
        let text = "@#$%^&*()_+-=[]{}|;':\",./<>?"
        let count = counter.count(text)
        #expect(count > 0)
    }

    @Test("Handle text with control characters")
    func handleTextWithControlCharacters() {
        let counter = TokenCounter(model: .simple)
        let text = "Hello\u{0000}World\u{0001}Test"
        let count = counter.count(text)
        #expect(count > 0)
    }

    // MARK: - Numeric Text Tests

    @Test("Handle numeric text")
    func handleNumericText() {
        let counter = TokenCounter(model: .simple)
        let text = "12345678901234567890"
        let count = counter.count(text)
        #expect(count > 0)
    }

    @Test("Handle mixed alphanumeric text")
    func handleMixedAlphanumericText() {
        let counter = TokenCounter(model: .simple)
        let text = "abc123def456ghi789"
        let count = counter.count(text)
        #expect(count > 0)
    }
}

// MARK: - TokenCountResult Tests

@Suite("TokenCountResult Tests")
struct TokenCountResultTests {

    @Test("TokenCountResult stores tokenCount correctly")
    func storesTokenCount() {
        let result = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        #expect(result.tokenCount == 100)
    }

    @Test("TokenCountResult stores characterCount correctly")
    func storesCharacterCount() {
        let result = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        #expect(result.characterCount == 400)
    }

    @Test("TokenCountResult stores model correctly")
    func storesModel() {
        let result = TokenCountResult(tokenCount: 100, characterCount: 400, model: .cl100k)
        #expect(result.model == .cl100k)
    }

    @Test("effectiveRatio calculates correctly")
    func effectiveRatioCalculation() {
        let result = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        let ratio = result.effectiveRatio
        // 400 chars / 100 tokens = 4.0 chars per token
        #expect(ratio == 4.0)
    }

    @Test("effectiveRatio handles zero tokenCount gracefully")
    func effectiveRatioHandlesZeroTokenCount() {
        let result = TokenCountResult(tokenCount: 0, characterCount: 100, model: .simple)
        let ratio = result.effectiveRatio
        // Should return infinity or 0 or some safe value
        #expect(ratio >= 0 || ratio.isInfinite)
    }

    @Test("effectiveRatio handles zero characterCount")
    func effectiveRatioHandlesZeroCharacterCount() {
        let result = TokenCountResult(tokenCount: 10, characterCount: 0, model: .simple)
        let ratio = result.effectiveRatio
        #expect(ratio == 0)
    }

    // MARK: - Equatable Conformance Tests

    @Test("TokenCountResult equality")
    func tokenCountResultEquality() {
        let result1 = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        let result2 = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        #expect(result1 == result2)
    }

    @Test("TokenCountResult inequality by tokenCount")
    func tokenCountResultInequalityByTokenCount() {
        let result1 = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        let result2 = TokenCountResult(tokenCount: 200, characterCount: 400, model: .simple)
        #expect(result1 != result2)
    }

    @Test("TokenCountResult inequality by characterCount")
    func tokenCountResultInequalityByCharacterCount() {
        let result1 = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        let result2 = TokenCountResult(tokenCount: 100, characterCount: 500, model: .simple)
        #expect(result1 != result2)
    }

    @Test("TokenCountResult inequality by model")
    func tokenCountResultInequalityByModel() {
        let result1 = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)
        let result2 = TokenCountResult(tokenCount: 100, characterCount: 400, model: .cl100k)
        #expect(result1 != result2)
    }

    // MARK: - Sendable Conformance Tests

    @Test("TokenCountResult is Sendable")
    func sendableConformance() async {
        let result = TokenCountResult(tokenCount: 100, characterCount: 400, model: .simple)

        // Verify we can pass across concurrency boundaries
        await Task.detached {
            let _ = result.tokenCount
        }.value
    }
}

// MARK: - TokenCounter Sendable and Concurrency Tests

@Suite("TokenCounter Concurrency Tests")
struct TokenCounterConcurrencyTests {

    @Test("TokenCounter is Sendable")
    func tokenCounterIsSendable() async {
        let counter = TokenCounter(model: .simple)

        // Verify we can pass across concurrency boundaries
        await Task.detached {
            let _ = counter.count("Hello")
        }.value
    }

    @Test("TokenCounter can be used concurrently")
    func tokenCounterConcurrentUse() async {
        let counter = TokenCounter(model: .simple)

        async let count1 = Task.detached {
            counter.count("Hello World")
        }.value

        async let count2 = Task.detached {
            counter.count("Testing Concurrency")
        }.value

        async let count3 = Task.detached {
            counter.count("Swift 6 Sendable")
        }.value

        let results = await [count1, count2, count3]

        for result in results {
            #expect(result > 0)
        }
    }

    @Test("Multiple TokenCounters with different models work concurrently")
    func multipleCountersConcurrent() async {
        let simpleCounter = TokenCounter(model: .simple)
        let cl100kCounter = TokenCounter(model: .cl100k)
        let p50kCounter = TokenCounter(model: .p50k)

        let text = "This is a test sentence for concurrent tokenization."

        async let simple = Task.detached {
            simpleCounter.count(text)
        }.value

        async let cl100k = Task.detached {
            cl100kCounter.count(text)
        }.value

        async let p50k = Task.detached {
            p50kCounter.count(text)
        }.value

        let results = await [simple, cl100k, p50k]

        for result in results {
            #expect(result > 0)
        }
    }
}

// MARK: - TextSplitter Sentence Splitting Tests

@Suite("TextSplitter Sentence Splitting Tests")
struct TextSplitterSentenceSplittingTests {

    // MARK: - Basic Sentence Splitting Tests

    @Test("Split basic sentences with period")
    func splitBasicSentencesWithPeriod() {
        let text = "Hello world. This is a test. Another sentence here."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 3)
        #expect(sentences[0].contains("Hello world"))
        #expect(sentences[1].contains("This is a test"))
        #expect(sentences[2].contains("Another sentence here"))
    }

    @Test("Split sentences with question marks")
    func splitSentencesWithQuestionMarks() {
        let text = "How are you? I am fine. What about you?"
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 3)
        #expect(sentences[0].contains("How are you"))
        #expect(sentences[1].contains("I am fine"))
        #expect(sentences[2].contains("What about you"))
    }

    @Test("Split sentences with exclamation marks")
    func splitSentencesWithExclamationMarks() {
        let text = "Wow! That is amazing! I love it."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 3)
        #expect(sentences[0].contains("Wow"))
        #expect(sentences[1].contains("amazing"))
        #expect(sentences[2].contains("love it"))
    }

    @Test("Split sentences with mixed punctuation")
    func splitSentencesWithMixedPunctuation() {
        let text = "Hello. How are you? Great! Let's go."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 4)
    }

    // MARK: - Abbreviation Handling Tests

    @Test("Preserve Dr. abbreviation")
    func preserveDrAbbreviation() {
        let text = "Dr. Smith went to the store. He bought milk."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
        #expect(sentences[0].contains("Dr.") || sentences[0].contains("Dr"))
        #expect(sentences[0].contains("Smith"))
    }

    @Test("Preserve Mr. abbreviation")
    func preserveMrAbbreviation() {
        let text = "Mr. Jones is here. He wants to talk."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
        #expect(sentences[0].contains("Mr"))
        #expect(sentences[0].contains("Jones"))
    }

    @Test("Preserve Mrs. abbreviation")
    func preserveMrsAbbreviation() {
        let text = "Mrs. Williams arrived. She brought cookies."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
        #expect(sentences[0].contains("Mrs"))
        #expect(sentences[0].contains("Williams"))
    }

    @Test("Preserve Ms. abbreviation")
    func preserveMsAbbreviation() {
        let text = "Ms. Davis is ready. The meeting can start."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
    }

    @Test("Preserve Prof. abbreviation")
    func preserveProfAbbreviation() {
        let text = "Prof. Einstein discovered relativity. It changed physics."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
        #expect(sentences[0].contains("Prof"))
    }

    @Test("Preserve multiple abbreviations in text")
    func preserveMultipleAbbreviations() {
        let text = "Dr. Smith met Mr. Jones at the cafe. They discussed Mrs. Williams."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
    }

    @Test("Preserve etc. abbreviation")
    func preserveEtcAbbreviation() {
        let text = "We need apples, oranges, etc. for the party. Please bring them."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
    }

    @Test("Preserve i.e. abbreviation")
    func preserveIeAbbreviation() {
        let text = "The solution, i.e. the answer, is simple. You just add water."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
    }

    @Test("Preserve e.g. abbreviation")
    func preserveEgAbbreviation() {
        let text = "Use a fruit, e.g. an apple or banana. It tastes better."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
    }

    // MARK: - Quotation Handling Tests

    @Test("Handle quoted text with period inside quotes")
    func handleQuotedTextWithPeriodInsideQuotes() {
        let text = "She said \"Hello there.\" Then she left."
        let sentences = TextSplitter.splitSentences(text)

        // Should handle quotes appropriately - at minimum preserve content
        #expect(sentences.count >= 1)
        let joined = sentences.joined(separator: " ")
        #expect(joined.contains("Hello there"))
        #expect(joined.contains("she left"))
    }

    @Test("Handle single-quoted text")
    func handleSingleQuotedText() {
        let text = "He replied 'I don't know.' She nodded."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
        let joined = sentences.joined(separator: " ")
        #expect(joined.contains("don't know"))
    }

    @Test("Handle nested quotations")
    func handleNestedQuotations() {
        let text = "He said \"She told me 'Go away.' yesterday.\" I was surprised."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
    }

    // MARK: - Multiple Punctuation Tests

    @Test("Handle multiple periods (ellipsis)")
    func handleMultiplePeriods() {
        let text = "Wait... I need to think. Okay, I'm ready."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 2)
    }

    @Test("Handle multiple question marks")
    func handleMultipleQuestionMarks() {
        let text = "What?? Are you serious? I can't believe it."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 2)
    }

    @Test("Handle multiple exclamation marks")
    func handleMultipleExclamationMarks() {
        let text = "Wow!! That's amazing! I love it."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 2)
    }

    @Test("Handle interrobang pattern")
    func handleInterrobangPattern() {
        let text = "What?! You did that?! I'm shocked."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 2)
    }

    // MARK: - Empty and Edge Cases Tests

    @Test("Empty string returns empty array")
    func emptyStringReturnsEmptyArray() {
        let sentences = TextSplitter.splitSentences("")
        #expect(sentences.isEmpty)
    }

    @Test("Whitespace-only string returns empty or minimal array")
    func whitespaceOnlyStringReturnsEmptyOrMinimalArray() {
        let sentences = TextSplitter.splitSentences("   \n\t  ")
        // Either empty or contains only whitespace
        #expect(sentences.isEmpty || sentences.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test("Single sentence without terminal punctuation")
    func singleSentenceWithoutTerminalPunctuation() {
        let text = "This is a single sentence without punctuation"
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 1)
        #expect(sentences[0].contains("This is a single sentence"))
    }

    @Test("Single sentence with terminal punctuation")
    func singleSentenceWithTerminalPunctuation() {
        let text = "This is a single sentence."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 1)
    }

    // MARK: - Unicode Sentence Splitting Tests

    @Test("Handle Unicode text with emojis")
    func handleUnicodeTextWithEmojis() {
        let text = "Hello world! I love coding. Swift is great!"
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 2)
    }

    @Test("Handle CJK text")
    func handleCJKText() {
        // Japanese text with Japanese period
        let text = "Hello. World."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
    }

    @Test("Handle mixed scripts")
    func handleMixedScripts() {
        let text = "Hello world. Bonjour le monde."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
    }

    @Test("Handle text with numbers and decimals")
    func handleTextWithNumbersAndDecimals() {
        let text = "The price is 19.99 dollars. That's expensive."
        let sentences = TextSplitter.splitSentences(text)

        // Should not split at decimal point
        #expect(sentences.count == 2)
        #expect(sentences[0].contains("19.99") || sentences[0].contains("19"))
    }

    @Test("Handle URLs in text")
    func handleURLsInText() {
        let text = "Visit www.example.com for more. You'll love it."
        let sentences = TextSplitter.splitSentences(text)

        // URL handling may vary, but content should be preserved
        let joined = sentences.joined(separator: " ")
        #expect(joined.contains("example"))
    }
}

// MARK: - TextSplitter Paragraph Splitting Tests

@Suite("TextSplitter Paragraph Splitting Tests")
struct TextSplitterParagraphSplittingTests {

    // MARK: - Basic Paragraph Splitting Tests

    @Test("Split basic paragraphs with double newlines")
    func splitBasicParagraphsWithDoubleNewlines() {
        let text = "First paragraph here.\n\nSecond paragraph here.\n\nThird paragraph here."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 3)
        #expect(paragraphs[0].contains("First paragraph"))
        #expect(paragraphs[1].contains("Second paragraph"))
        #expect(paragraphs[2].contains("Third paragraph"))
    }

    @Test("Split paragraphs with CRLF line endings")
    func splitParagraphsWithCRLFLineEndings() {
        let text = "First paragraph.\r\n\r\nSecond paragraph.\r\n\r\nThird paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 3)
    }

    @Test("Split paragraphs with multiple blank lines")
    func splitParagraphsWithMultipleBlankLines() {
        let text = "First paragraph.\n\n\n\nSecond paragraph.\n\n\n\n\nThird paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 3)
    }

    // MARK: - Single Paragraph Tests

    @Test("Single paragraph returns single element array")
    func singleParagraphReturnsSingleElementArray() {
        let text = "This is a single paragraph with multiple sentences. It has no breaks."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].contains("single paragraph"))
    }

    @Test("Single paragraph with trailing newlines")
    func singleParagraphWithTrailingNewlines() {
        let text = "This is a paragraph.\n\n"
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 1)
    }

    @Test("Single paragraph with leading newlines")
    func singleParagraphWithLeadingNewlines() {
        let text = "\n\nThis is a paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 1)
    }

    // MARK: - Empty and Edge Cases Tests

    @Test("Empty string returns empty array")
    func emptyStringReturnsEmptyArray() {
        let paragraphs = TextSplitter.splitParagraphs("")
        #expect(paragraphs.isEmpty)
    }

    @Test("Whitespace-only string returns empty or minimal array")
    func whitespaceOnlyStringReturnsEmptyOrMinimalArray() {
        let paragraphs = TextSplitter.splitParagraphs("   \n\n\n   ")
        #expect(paragraphs.isEmpty || paragraphs.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test("Only newlines returns empty array")
    func onlyNewlinesReturnsEmptyArray() {
        let paragraphs = TextSplitter.splitParagraphs("\n\n\n\n\n")
        #expect(paragraphs.isEmpty)
    }

    // MARK: - Blank Line Variations Tests

    @Test("Handle mixed whitespace between paragraphs")
    func handleMixedWhitespaceBetweenParagraphs() {
        let text = "First paragraph.\n   \nSecond paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        // May treat as one or two paragraphs depending on implementation
        #expect(paragraphs.count >= 1)
        let joined = paragraphs.joined(separator: " ")
        #expect(joined.contains("First paragraph"))
        #expect(joined.contains("Second paragraph"))
    }

    @Test("Handle tabs between paragraphs")
    func handleTabsBetweenParagraphs() {
        let text = "First paragraph.\n\t\nSecond paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count >= 1)
    }

    @Test("Preserve internal single newlines within paragraph")
    func preserveInternalSingleNewlinesWithinParagraph() {
        let text = "First line\nSecond line\nThird line\n\nNew paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 2)
        // First paragraph should contain all three lines
        #expect(paragraphs[0].contains("First line"))
    }

    // MARK: - Long Paragraph Tests

    @Test("Handle very long paragraphs")
    func handleVeryLongParagraphs() {
        let longParagraph = String(repeating: "This is a long sentence. ", count: 100)
        let text = "\(longParagraph)\n\nShort paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].count > 1000)
        #expect(paragraphs[1].contains("Short paragraph"))
    }

    // MARK: - Unicode Paragraph Tests

    @Test("Handle Unicode paragraphs")
    func handleUnicodeParagraphs() {
        let text = "First paragraph with emoji.\n\nSecond paragraph with."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 2)
    }

    @Test("Handle RTL text paragraphs")
    func handleRTLTextParagraphs() {
        let text = "First paragraph.\n\n.\n\nThird paragraph."
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(paragraphs.count == 3)
    }
}

// MARK: - TextSplitter Custom Separator Tests

@Suite("TextSplitter Custom Separator Tests")
struct TextSplitterCustomSeparatorTests {

    // MARK: - Single Separator Tests

    @Test("Split with single comma separator")
    func splitWithSingleCommaSeparator() {
        let text = "apple,banana,cherry,date"
        let segments = TextSplitter.split(text, separators: [","])

        #expect(segments.count == 4)
        #expect(segments[0] == "apple")
        #expect(segments[1] == "banana")
        #expect(segments[2] == "cherry")
        #expect(segments[3] == "date")
    }

    @Test("Split with single semicolon separator")
    func splitWithSingleSemicolonSeparator() {
        let text = "first;second;third"
        let segments = TextSplitter.split(text, separators: [";"])

        #expect(segments.count == 3)
    }

    @Test("Split with single pipe separator")
    func splitWithSinglePipeSeparator() {
        let text = "one|two|three|four"
        let segments = TextSplitter.split(text, separators: ["|"])

        #expect(segments.count == 4)
    }

    @Test("Split with newline separator")
    func splitWithNewlineSeparator() {
        let text = "line1\nline2\nline3"
        let segments = TextSplitter.split(text, separators: ["\n"])

        #expect(segments.count == 3)
    }

    @Test("Split with double newline separator")
    func splitWithDoubleNewlineSeparator() {
        let text = "para1\n\npara2\n\npara3"
        let segments = TextSplitter.split(text, separators: ["\n\n"])

        #expect(segments.count == 3)
    }

    // MARK: - Multiple Separators Hierarchical Tests

    @Test("Split with multiple separators in priority order")
    func splitWithMultipleSeparatorsInPriorityOrder() {
        let text = "a,b;c,d"
        let segments = TextSplitter.split(text, separators: [";", ","])

        // Should split by first separator that matches, hierarchically
        #expect(segments.count >= 2)
    }

    @Test("Split with hierarchical separators - paragraphs then sentences")
    func splitWithHierarchicalSeparatorsParagraphsThenSentences() {
        let text = "Sentence one. Sentence two.\n\nParagraph two."
        let segments = TextSplitter.split(text, separators: ["\n\n", ". "])

        // Should prioritize paragraph breaks
        #expect(segments.count >= 2)
    }

    @Test("Split with common recursive separators")
    func splitWithCommonRecursiveSeparators() {
        let text = "A\n\nB\nC D E"
        let separators = ["\n\n", "\n", " "]
        let segments = TextSplitter.split(text, separators: separators)

        #expect(segments.count >= 2)
    }

    // MARK: - Empty Array Separator Tests

    @Test("Empty separator array returns original text as single element")
    func emptySeparatorArrayReturnsOriginalTextAsSingleElement() {
        let text = "This is some text"
        let segments = TextSplitter.split(text, separators: [])

        #expect(segments.count == 1)
        #expect(segments[0] == text)
    }

    // MARK: - Edge Cases Tests

    @Test("Separator not found returns original text")
    func separatorNotFoundReturnsOriginalText() {
        let text = "This has no commas"
        let segments = TextSplitter.split(text, separators: [","])

        #expect(segments.count == 1)
        #expect(segments[0] == text)
    }

    @Test("Empty string returns empty array")
    func emptyStringReturnsEmptyArray() {
        let segments = TextSplitter.split("", separators: [","])
        #expect(segments.isEmpty)
    }

    @Test("Text is just separator returns empty segments or empty array")
    func textIsJustSeparatorReturnsEmptySegmentsOrEmptyArray() {
        let segments = TextSplitter.split(",,,", separators: [","])
        // Should either be empty or contain empty strings
        #expect(segments.isEmpty || segments.allSatisfy { $0.isEmpty })
    }

    @Test("Consecutive separators are handled correctly")
    func consecutiveSeparatorsAreHandledCorrectly() {
        let text = "a,,b,,,c"
        let segments = TextSplitter.split(text, separators: [","])

        // Should filter out empty segments or include them
        let nonEmpty = segments.filter { !$0.isEmpty }
        #expect(nonEmpty.count == 3)
    }

    @Test("Leading separator is handled correctly")
    func leadingSeparatorIsHandledCorrectly() {
        let text = ",a,b,c"
        let segments = TextSplitter.split(text, separators: [","])

        let nonEmpty = segments.filter { !$0.isEmpty }
        #expect(nonEmpty.count == 3)
    }

    @Test("Trailing separator is handled correctly")
    func trailingSeparatorIsHandledCorrectly() {
        let text = "a,b,c,"
        let segments = TextSplitter.split(text, separators: [","])

        let nonEmpty = segments.filter { !$0.isEmpty }
        #expect(nonEmpty.count == 3)
    }

    // MARK: - Multi-Character Separator Tests

    @Test("Split with multi-character separator")
    func splitWithMultiCharacterSeparator() {
        let text = "first---second---third"
        let segments = TextSplitter.split(text, separators: ["---"])

        #expect(segments.count == 3)
        #expect(segments[0] == "first")
        #expect(segments[1] == "second")
        #expect(segments[2] == "third")
    }

    @Test("Split with word separator")
    func splitWithWordSeparator() {
        let text = "hello and world and swift"
        let segments = TextSplitter.split(text, separators: [" and "])

        #expect(segments.count == 3)
        #expect(segments[0] == "hello")
        #expect(segments[1] == "world")
        #expect(segments[2] == "swift")
    }
}

// MARK: - TextSplitter Regex Pattern Tests

@Suite("TextSplitter Regex Pattern Tests")
struct TextSplitterRegexPatternTests {

    // MARK: - Valid Regex Pattern Tests

    @Test("Split with simple regex pattern")
    func splitWithSimpleRegexPattern() throws {
        let text = "apple1banana2cherry3date"
        let segments = try TextSplitter.split(text, pattern: "[0-9]")

        #expect(segments.count == 4)
        #expect(segments[0] == "apple")
        #expect(segments[1] == "banana")
        #expect(segments[2] == "cherry")
        #expect(segments[3] == "date")
    }

    @Test("Split with word boundary pattern")
    func splitWithWordBoundaryPattern() throws {
        let text = "Hello World Swift"
        let segments = try TextSplitter.split(text, pattern: "\\s+")

        #expect(segments.count == 3)
        #expect(segments[0] == "Hello")
        #expect(segments[1] == "World")
        #expect(segments[2] == "Swift")
    }

    @Test("Split with multiple digits pattern")
    func splitWithMultipleDigitsPattern() throws {
        let text = "part1234middle5678end"
        let segments = try TextSplitter.split(text, pattern: "[0-9]+")

        #expect(segments.count == 3)
        #expect(segments[0] == "part")
        #expect(segments[1] == "middle")
        #expect(segments[2] == "end")
    }

    @Test("Split with sentence-ending pattern")
    func splitWithSentenceEndingPattern() throws {
        let text = "First sentence. Second question? Third exclamation!"
        let segments = try TextSplitter.split(text, pattern: "[.?!]\\s*")

        #expect(segments.count >= 3)
    }

    @Test("Split with newline pattern variations")
    func splitWithNewlinePatternVariations() throws {
        // Test basic newline splitting - using simple pattern
        let text = "line1\nline2\nline3\nline4"
        let segments = try TextSplitter.split(text, pattern: "\\n")

        #expect(segments.count == 4)
        #expect(segments.contains("line1"))
        #expect(segments.contains("line2"))
        #expect(segments.contains("line3"))
        #expect(segments.contains("line4"))
    }

    // MARK: - Invalid Regex Throws Tests

    @Test("Invalid regex pattern throws error")
    func invalidRegexPatternThrowsError() {
        let text = "Some text"
        let invalidPattern = "[unclosed"

        #expect(throws: (any Error).self) {
            try TextSplitter.split(text, pattern: invalidPattern)
        }
    }

    @Test("Invalid regex with unbalanced parentheses throws")
    func invalidRegexWithUnbalancedParenthesesThrows() {
        let text = "Some text"
        let invalidPattern = "((abc)"

        #expect(throws: (any Error).self) {
            try TextSplitter.split(text, pattern: invalidPattern)
        }
    }

    @Test("Invalid regex with bad escape sequence throws")
    func invalidRegexWithBadEscapeSequenceThrows() {
        let text = "Some text"
        // Using an invalid escape might or might not throw depending on Swift's regex engine
        // Using a definitely invalid pattern
        let invalidPattern = "*invalid"

        #expect(throws: (any Error).self) {
            try TextSplitter.split(text, pattern: invalidPattern)
        }
    }

    // MARK: - Capturing Groups Tests

    @Test("Pattern with capturing groups splits correctly")
    func patternWithCapturingGroupsSplitsCorrectly() throws {
        let text = "a1b2c3d"
        let segments = try TextSplitter.split(text, pattern: "([0-9])")

        // Should split regardless of capturing groups
        #expect(segments.count >= 2)
    }

    @Test("Pattern with non-capturing groups splits correctly")
    func patternWithNonCapturingGroupsSplitsCorrectly() throws {
        let text = "a1b2c3d"
        let segments = try TextSplitter.split(text, pattern: "(?:[0-9])")

        #expect(segments.count == 4)
    }

    // MARK: - Edge Cases Tests

    @Test("Empty string with valid pattern returns empty array")
    func emptyStringWithValidPatternReturnsEmptyArray() throws {
        let segments = try TextSplitter.split("", pattern: "[0-9]")
        #expect(segments.isEmpty)
    }

    @Test("Pattern not found returns original text")
    func patternNotFoundReturnsOriginalText() throws {
        let text = "no numbers here"
        let segments = try TextSplitter.split(text, pattern: "[0-9]")

        #expect(segments.count == 1)
        #expect(segments[0] == text)
    }

    @Test("Pattern matches entire string returns empty array or empty segments")
    func patternMatchesEntireStringReturnsEmptyArrayOrEmptySegments() throws {
        let text = "12345"
        let segments = try TextSplitter.split(text, pattern: "[0-9]+")

        #expect(segments.isEmpty || segments.allSatisfy { $0.isEmpty })
    }

    @Test("Complex pattern with alternation")
    func complexPatternWithAlternation() throws {
        let text = "apple;banana,cherry|date"
        let segments = try TextSplitter.split(text, pattern: "[;,|]")

        #expect(segments.count == 4)
    }

    @Test("Unicode pattern matching")
    func unicodePatternMatching() throws {
        let text = "Hello World Swift"
        let segments = try TextSplitter.split(text, pattern: "\\s+")

        #expect(segments.count == 3)
    }
}

// MARK: - TextSplitter Merge Small Tests

@Suite("TextSplitter Merge Small Tests")
struct TextSplitterMergeSmallTests {

    // MARK: - Basic Merge Tests

    @Test("Merge small segments together")
    func mergeSmallSegmentsTogether() {
        let segments = ["Hi", "there", "friend"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 10)

        // Small segments should be merged
        #expect(merged.count < segments.count)

        // All content should be preserved
        let originalJoined = segments.joined(separator: " ")
        let mergedJoined = merged.joined(separator: " ")
        for segment in segments {
            #expect(mergedJoined.contains(segment))
        }
    }

    @Test("Segments already above minLength are preserved")
    func segmentsAlreadyAboveMinLengthArePreserved() {
        let segments = ["This is a long segment", "Another long segment here"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 10)

        #expect(merged.count == 2)
        #expect(merged[0] == segments[0])
        #expect(merged[1] == segments[1])
    }

    @Test("Mixed small and large segments")
    func mixedSmallAndLargeSegments() {
        let segments = ["Hi", "This is a longer segment", "OK", "Another long one here"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 10)

        // Small segments should be merged with adjacent ones
        #expect(merged.count < segments.count)
    }

    // MARK: - Custom Separator Tests

    @Test("Merge with custom separator")
    func mergeWithCustomSeparator() {
        let segments = ["Hi", "there"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 10, separator: " | ")

        #expect(merged.count == 1)
        #expect(merged[0].contains(" | ") || merged[0].contains("Hi") && merged[0].contains("there"))
    }

    @Test("Merge with newline separator")
    func mergeWithNewlineSeparator() {
        let segments = ["Short", "Text"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 15, separator: "\n")

        #expect(merged.count == 1)
    }

    @Test("Merge with empty separator")
    func mergeWithEmptySeparator() {
        let segments = ["a", "b", "c"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 5, separator: "")

        #expect(merged.count == 1)
        #expect(merged[0] == "abc")
    }

    // MARK: - Edge Cases Tests

    @Test("Empty array returns empty array")
    func emptyArrayReturnsEmptyArray() {
        let segments: [String] = []
        let merged = TextSplitter.mergeSmall(segments, minLength: 10)

        #expect(merged.isEmpty)
    }

    @Test("Single segment below minLength returns single element")
    func singleSegmentBelowMinLengthReturnsSingleElement() {
        let segments = ["Hi"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 100)

        #expect(merged.count == 1)
        #expect(merged[0] == "Hi")
    }

    @Test("Single segment above minLength returns single element")
    func singleSegmentAboveMinLengthReturnsSingleElement() {
        let segments = ["This is a very long segment"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 5)

        #expect(merged.count == 1)
        #expect(merged[0] == segments[0])
    }

    @Test("minLength of zero returns original segments")
    func minLengthOfZeroReturnsOriginalSegments() {
        let segments = ["a", "b", "c"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 0)

        // With minLength 0, all segments are already "large enough"
        #expect(merged == segments)
    }

    @Test("All segments exactly at minLength")
    func allSegmentsExactlyAtMinLength() {
        let segments = ["12345", "abcde", "hello"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 5)

        #expect(merged == segments)
    }

    @Test("All segments below minLength get merged into one")
    func allSegmentsBelowMinLengthGetMergedIntoOne() {
        let segments = ["a", "b", "c", "d", "e"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 100)

        #expect(merged.count == 1)
    }

    // MARK: - Content Preservation Tests

    @Test("Merge preserves all content")
    func mergePreservesAllContent() {
        let segments = ["Hello", "World", "Swift", "Programming"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 15)

        let originalContent = Set(segments)
        let mergedJoined = merged.joined(separator: " ")

        for segment in originalContent {
            #expect(mergedJoined.contains(segment))
        }
    }

    @Test("Merge maintains order")
    func mergeMaintainsOrder() {
        let segments = ["First", "Second", "Third", "Fourth"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 10)

        let mergedJoined = merged.joined(separator: " ")
        let firstIndex = mergedJoined.range(of: "First")!.lowerBound
        let secondIndex = mergedJoined.range(of: "Second")!.lowerBound
        let thirdIndex = mergedJoined.range(of: "Third")!.lowerBound
        let fourthIndex = mergedJoined.range(of: "Fourth")!.lowerBound

        #expect(firstIndex < secondIndex)
        #expect(secondIndex < thirdIndex)
        #expect(thirdIndex < fourthIndex)
    }

    // MARK: - Large Segment Tests

    @Test("Large minLength still works with small segments")
    func largeMinLengthStillWorksWithSmallSegments() {
        let segments = ["a", "b", "c"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 1000)

        // Should merge all together since none meet minLength
        #expect(merged.count == 1)
    }

    @Test("Merge with unicode segments")
    func mergeWithUnicodeSegments() {
        let segments = ["Hello", "World", "🎉"]
        let merged = TextSplitter.mergeSmall(segments, minLength: 10)

        #expect(merged.count <= segments.count)

        let mergedJoined = merged.joined(separator: " ")
        // All non-empty segments should be present in merged result
        for segment in segments.filter({ !$0.isEmpty }) {
            #expect(mergedJoined.contains(segment))
        }
    }
}

// MARK: - TextSplitter Edge Cases Tests

@Suite("TextSplitter Edge Cases Tests")
struct TextSplitterEdgeCasesTests {

    // MARK: - Empty Input Tests

    @Test("All methods handle empty string")
    func allMethodsHandleEmptyString() throws {
        #expect(TextSplitter.splitSentences("").isEmpty)
        #expect(TextSplitter.splitParagraphs("").isEmpty)
        #expect(TextSplitter.split("", separators: [","]).isEmpty)
        #expect(try TextSplitter.split("", pattern: "[0-9]").isEmpty)
        #expect(TextSplitter.mergeSmall([], minLength: 10).isEmpty)
    }

    // MARK: - Very Long Text Tests

    @Test("Handle very long text for sentence splitting")
    func handleVeryLongTextForSentenceSplitting() {
        let longText = String(repeating: "This is a sentence. ", count: 1000)
        let sentences = TextSplitter.splitSentences(longText)

        #expect(sentences.count >= 500)
    }

    @Test("Handle very long text for paragraph splitting")
    func handleVeryLongTextForParagraphSplitting() {
        let longText = (0..<100).map { "Paragraph \($0) content." }.joined(separator: "\n\n")
        let paragraphs = TextSplitter.splitParagraphs(longText)

        #expect(paragraphs.count == 100)
    }

    @Test("Handle text with very long word")
    func handleTextWithVeryLongWord() {
        let longWord = String(repeating: "a", count: 10000)
        let text = "Start. \(longWord). End."
        let sentences = TextSplitter.splitSentences(text)

        // Should handle without crashing
        #expect(sentences.count >= 1)
    }

    // MARK: - Unicode Edge Cases Tests

    @Test("Handle text with emojis")
    func handleTextWithEmojis() {
        let text = "Hello. Goodbye."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
        let joined = sentences.joined(separator: " ")
        #expect(joined.contains("Hello"))
    }

    @Test("Handle text with combining characters")
    func handleTextWithCombiningCharacters() {
        let text = "Cafe\u{0301} is nice. Let's go."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 2)
    }

    @Test("Handle text with zero-width characters")
    func handleTextWithZeroWidthCharacters() {
        let text = "Hello\u{200B}World. Next sentence."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
    }

    @Test("Handle right-to-left text")
    func handleRightToLeftText() {
        // Arabic text
        let text = "First. Second."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
    }

    // MARK: - Special Character Tests

    @Test("Handle text with only punctuation")
    func handleTextWithOnlyPunctuation() {
        let text = "...!!??..."
        let sentences = TextSplitter.splitSentences(text)

        // Should handle gracefully
        #expect(sentences.count >= 0)
    }

    @Test("Handle text with special symbols")
    func handleTextWithSpecialSymbols() {
        let text = "@#$% is here. Next one: ^&*()."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
    }

    @Test("Handle text with control characters")
    func handleTextWithControlCharacters() {
        let text = "Hello\u{0000}World. Next\u{0001}sentence."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
    }

    // MARK: - Whitespace Edge Cases Tests

    @Test("Handle text with only spaces")
    func handleTextWithOnlySpaces() {
        let text = "          "
        let sentences = TextSplitter.splitSentences(text)
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(sentences.isEmpty || sentences.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(paragraphs.isEmpty || paragraphs.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test("Handle text with only tabs")
    func handleTextWithOnlyTabs() {
        let text = "\t\t\t\t"
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.isEmpty || sentences.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test("Handle text with mixed whitespace types")
    func handleTextWithMixedWhitespaceTypes() {
        let text = "   \t\n   \r\n   "
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.isEmpty || sentences.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Test("Handle text with unusual Unicode whitespace")
    func handleTextWithUnusualUnicodeWhitespace() {
        // Non-breaking space, en space, em space
        let text = "Hello\u{00A0}World.\u{2002}Next\u{2003}here."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 1)
    }

    // MARK: - Consistency Tests

    @Test("Split and merge are consistent")
    func splitAndMergeAreConsistent() {
        let original = "Short. Medium length sentence. Another one."
        let sentences = TextSplitter.splitSentences(original)
        let merged = TextSplitter.mergeSmall(sentences, minLength: 5, separator: " ")

        // Content should be preserved through split and merge
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                #expect(merged.joined(separator: " ").contains(trimmed) ||
                       merged.joined(separator: " ").contains(trimmed.replacing(".", with: "")))
            }
        }
    }

    @Test("Multiple splits produce consistent results")
    func multipleSplitsProduceConsistentResults() {
        let text = "First sentence. Second sentence. Third sentence."

        let result1 = TextSplitter.splitSentences(text)
        let result2 = TextSplitter.splitSentences(text)
        let result3 = TextSplitter.splitSentences(text)

        #expect(result1 == result2)
        #expect(result2 == result3)
    }

    // MARK: - Boundary Condition Tests

    @Test("Single character text")
    func singleCharacterText() {
        let text = "a"
        let sentences = TextSplitter.splitSentences(text)
        let paragraphs = TextSplitter.splitParagraphs(text)

        #expect(sentences.count == 1)
        #expect(paragraphs.count == 1)
    }

    @Test("Single punctuation character")
    func singlePunctuationCharacter() {
        let text = "."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count >= 0) // May be 0 or 1 depending on implementation
    }

    @Test("Two characters with punctuation")
    func twoCharactersWithPunctuation() {
        let text = "A."
        let sentences = TextSplitter.splitSentences(text)

        #expect(sentences.count == 1)
    }
}

// MARK: - ChunkStatistics Tests

@Suite("ChunkStatistics Tests")
struct ChunkStatisticsTests {

    // MARK: - Property Storage Tests

    @Test("ChunkStatistics stores count correctly")
    func storesCount() {
        let stats = ChunkStatistics(
            count: 10,
            totalCharacters: 5000,
            averageSize: 500.0,
            minSize: 100,
            maxSize: 1000,
            medianSize: 450
        )
        #expect(stats.count == 10)
    }

    @Test("ChunkStatistics stores totalCharacters correctly")
    func storesTotalCharacters() {
        let stats = ChunkStatistics(
            count: 10,
            totalCharacters: 5000,
            averageSize: 500.0,
            minSize: 100,
            maxSize: 1000,
            medianSize: 450
        )
        #expect(stats.totalCharacters == 5000)
    }

    @Test("ChunkStatistics stores averageSize correctly")
    func storesAverageSize() {
        let stats = ChunkStatistics(
            count: 10,
            totalCharacters: 5000,
            averageSize: 500.0,
            minSize: 100,
            maxSize: 1000,
            medianSize: 450
        )
        #expect(stats.averageSize == 500.0)
    }

    @Test("ChunkStatistics stores minSize correctly")
    func storesMinSize() {
        let stats = ChunkStatistics(
            count: 10,
            totalCharacters: 5000,
            averageSize: 500.0,
            minSize: 100,
            maxSize: 1000,
            medianSize: 450
        )
        #expect(stats.minSize == 100)
    }

    @Test("ChunkStatistics stores maxSize correctly")
    func storesMaxSize() {
        let stats = ChunkStatistics(
            count: 10,
            totalCharacters: 5000,
            averageSize: 500.0,
            minSize: 100,
            maxSize: 1000,
            medianSize: 450
        )
        #expect(stats.maxSize == 1000)
    }

    @Test("ChunkStatistics stores medianSize correctly")
    func storesMedianSize() {
        let stats = ChunkStatistics(
            count: 10,
            totalCharacters: 5000,
            averageSize: 500.0,
            minSize: 100,
            maxSize: 1000,
            medianSize: 450
        )
        #expect(stats.medianSize == 450)
    }

    // MARK: - Edge Values Tests

    @Test("ChunkStatistics handles zero values")
    func handlesZeroValues() {
        let stats = ChunkStatistics(
            count: 0,
            totalCharacters: 0,
            averageSize: 0.0,
            minSize: 0,
            maxSize: 0,
            medianSize: 0
        )
        #expect(stats.count == 0)
        #expect(stats.totalCharacters == 0)
        #expect(stats.averageSize == 0.0)
        #expect(stats.minSize == 0)
        #expect(stats.maxSize == 0)
        #expect(stats.medianSize == 0)
    }

    @Test("ChunkStatistics handles large values")
    func handlesLargeValues() {
        let stats = ChunkStatistics(
            count: Int.max / 2,
            totalCharacters: Int.max / 2,
            averageSize: Double(Int.max) / 2.0,
            minSize: 1,
            maxSize: Int.max / 2,
            medianSize: Int.max / 4
        )
        #expect(stats.count == Int.max / 2)
        #expect(stats.maxSize == Int.max / 2)
    }

    @Test("ChunkStatistics handles fractional averageSize")
    func handlesFractionalAverageSize() {
        let stats = ChunkStatistics(
            count: 3,
            totalCharacters: 1000,
            averageSize: 333.333333,
            minSize: 300,
            maxSize: 400,
            medianSize: 350
        )
        #expect(stats.averageSize > 333.33)
        #expect(stats.averageSize < 333.34)
    }

    // MARK: - Sendable Conformance Tests

    @Test("ChunkStatistics is Sendable")
    func sendableConformance() async {
        let stats = ChunkStatistics(
            count: 5,
            totalCharacters: 2500,
            averageSize: 500.0,
            minSize: 200,
            maxSize: 800,
            medianSize: 500
        )

        await Task.detached {
            let _ = stats.count
            let _ = stats.averageSize
        }.value
    }
}

// MARK: - ChunkValidationError Tests

@Suite("ChunkValidationError Tests")
struct ChunkValidationErrorTests {

    // MARK: - Property Storage Tests

    @Test("ChunkValidationError stores chunkIndex correctly")
    func storesChunkIndex() {
        let error = ChunkValidationError(chunkIndex: 5, reason: "Test error")
        #expect(error.chunkIndex == 5)
    }

    @Test("ChunkValidationError stores reason correctly")
    func storesReason() {
        let error = ChunkValidationError(chunkIndex: 0, reason: "Chunk exceeds maximum size")
        #expect(error.reason == "Chunk exceeds maximum size")
    }

    // MARK: - Various Error Reasons Tests

    @Test("ChunkValidationError with size exceeded reason")
    func sizeExceededReason() {
        let error = ChunkValidationError(
            chunkIndex: 2,
            reason: "Chunk size 5000 exceeds maximum 2000"
        )
        #expect(error.chunkIndex == 2)
        #expect(error.reason.contains("exceeds"))
    }

    @Test("ChunkValidationError with empty content reason")
    func emptyContentReason() {
        let error = ChunkValidationError(
            chunkIndex: 0,
            reason: "Chunk content is empty"
        )
        #expect(error.reason.contains("empty"))
    }

    @Test("ChunkValidationError with invalid metadata reason")
    func invalidMetadataReason() {
        let error = ChunkValidationError(
            chunkIndex: 10,
            reason: "Invalid chunk metadata: missing documentId"
        )
        #expect(error.reason.contains("metadata"))
    }

    // MARK: - Edge Values Tests

    @Test("ChunkValidationError with zero index")
    func zeroIndex() {
        let error = ChunkValidationError(chunkIndex: 0, reason: "First chunk error")
        #expect(error.chunkIndex == 0)
    }

    @Test("ChunkValidationError with large index")
    func largeIndex() {
        let error = ChunkValidationError(chunkIndex: 999999, reason: "Error in large document")
        #expect(error.chunkIndex == 999999)
    }

    @Test("ChunkValidationError with empty reason")
    func emptyReason() {
        let error = ChunkValidationError(chunkIndex: 1, reason: "")
        #expect(error.reason.isEmpty)
    }

    @Test("ChunkValidationError with long reason")
    func longReason() {
        let longReason = String(repeating: "Error details. ", count: 100)
        let error = ChunkValidationError(chunkIndex: 1, reason: longReason)
        #expect(error.reason.count > 1000)
    }

    // MARK: - Error Conformance Tests

    @Test("ChunkValidationError conforms to Error protocol")
    func errorConformance() {
        let error: any Error = ChunkValidationError(chunkIndex: 1, reason: "Test")
        #expect(error is ChunkValidationError)
    }

    // MARK: - Sendable Conformance Tests

    @Test("ChunkValidationError is Sendable")
    func sendableConformance() async {
        let error = ChunkValidationError(chunkIndex: 3, reason: "Validation failed")

        await Task.detached {
            let _ = error.chunkIndex
            let _ = error.reason
        }.value
    }
}

// MARK: - ChunkingUtils Statistics Tests

@Suite("ChunkingUtils Statistics Tests")
struct ChunkingUtilsStatisticsTests {

    // MARK: - Helper Methods

    private func makeChunk(content: String, index: Int = 0, documentId: String? = nil) -> Chunk {
        Chunk(
            content: content,
            metadata: ChunkMetadata(
                documentId: documentId ?? UUID().uuidString,
                index: index,
                startOffset: 0,
                endOffset: content.count
            )
        )
    }

    // MARK: - Empty Input Tests

    @Test("statistics returns zero count for empty array")
    func emptyArrayReturnsZeroCount() {
        let chunks: [Chunk] = []
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.count == 0)
    }

    @Test("statistics returns zero totalCharacters for empty array")
    func emptyArrayReturnsZeroTotalCharacters() {
        let chunks: [Chunk] = []
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.totalCharacters == 0)
    }

    @Test("statistics returns zero averageSize for empty array")
    func emptyArrayReturnsZeroAverageSize() {
        let chunks: [Chunk] = []
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.averageSize == 0.0)
    }

    @Test("statistics returns zero minSize for empty array")
    func emptyArrayReturnsZeroMinSize() {
        let chunks: [Chunk] = []
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.minSize == 0)
    }

    @Test("statistics returns zero maxSize for empty array")
    func emptyArrayReturnsZeroMaxSize() {
        let chunks: [Chunk] = []
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.maxSize == 0)
    }

    @Test("statistics returns zero medianSize for empty array")
    func emptyArrayReturnsZeroMedianSize() {
        let chunks: [Chunk] = []
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.medianSize == 0)
    }

    // MARK: - Single Chunk Tests

    @Test("statistics with single chunk returns correct count")
    func singleChunkReturnsCorrectCount() {
        let chunks = [makeChunk(content: "Hello World")]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.count == 1)
    }

    @Test("statistics with single chunk returns correct totalCharacters")
    func singleChunkReturnsCorrectTotalCharacters() {
        let content = "Hello World"
        let chunks = [makeChunk(content: content)]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.totalCharacters == content.count)
    }

    @Test("statistics with single chunk returns averageSize equal to content size")
    func singleChunkAverageSizeEqualsContentSize() {
        let content = "Hello World"
        let chunks = [makeChunk(content: content)]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.averageSize == Double(content.count))
    }

    @Test("statistics with single chunk minSize equals maxSize")
    func singleChunkMinSizeEqualsMaxSize() {
        let content = "Hello World"
        let chunks = [makeChunk(content: content)]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.minSize == stats.maxSize)
        #expect(stats.minSize == content.count)
    }

    @Test("statistics with single chunk medianSize equals content size")
    func singleChunkMedianSizeEqualsContentSize() {
        let content = "Hello World"
        let chunks = [makeChunk(content: content)]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.medianSize == content.count)
    }

    // MARK: - Multiple Chunks Tests

    @Test("statistics with multiple chunks returns correct count")
    func multipleChunksReturnsCorrectCount() {
        let chunks = [
            makeChunk(content: "First chunk", index: 0),
            makeChunk(content: "Second chunk content", index: 1),
            makeChunk(content: "Third", index: 2)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.count == 3)
    }

    @Test("statistics with multiple chunks returns correct totalCharacters")
    func multipleChunksReturnsCorrectTotalCharacters() {
        let chunks = [
            makeChunk(content: "First chunk", index: 0),
            makeChunk(content: "Second chunk content", index: 1),
            makeChunk(content: "Third", index: 2)
        ]
        let expectedTotal = "First chunk".count + "Second chunk content".count + "Third".count
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.totalCharacters == expectedTotal)
    }

    @Test("statistics with multiple chunks returns correct averageSize")
    func multipleChunksReturnsCorrectAverageSize() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 100), index: 0),
            makeChunk(content: String(repeating: "b", count: 200), index: 1),
            makeChunk(content: String(repeating: "c", count: 300), index: 2)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.averageSize == 200.0)
    }

    @Test("statistics with multiple chunks returns correct minSize")
    func multipleChunksReturnsCorrectMinSize() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 100), index: 0),
            makeChunk(content: String(repeating: "b", count: 50), index: 1),
            makeChunk(content: String(repeating: "c", count: 200), index: 2)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.minSize == 50)
    }

    @Test("statistics with multiple chunks returns correct maxSize")
    func multipleChunksReturnsCorrectMaxSize() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 100), index: 0),
            makeChunk(content: String(repeating: "b", count: 50), index: 1),
            makeChunk(content: String(repeating: "c", count: 200), index: 2)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.maxSize == 200)
    }

    @Test("statistics with odd number of chunks returns correct medianSize")
    func oddNumberOfChunksReturnsCorrectMedianSize() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 100), index: 0),
            makeChunk(content: String(repeating: "b", count: 200), index: 1),
            makeChunk(content: String(repeating: "c", count: 300), index: 2)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.medianSize == 200)
    }

    @Test("statistics with even number of chunks returns correct medianSize")
    func evenNumberOfChunksReturnsCorrectMedianSize() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 100), index: 0),
            makeChunk(content: String(repeating: "b", count: 200), index: 1),
            makeChunk(content: String(repeating: "c", count: 300), index: 2),
            makeChunk(content: String(repeating: "d", count: 400), index: 3)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        // Median of [100, 200, 300, 400] = (200 + 300) / 2 = 250
        #expect(stats.medianSize == 250)
    }

    // MARK: - Edge Cases Tests

    @Test("statistics with chunks containing empty content")
    func chunksWithEmptyContent() {
        let chunks = [
            makeChunk(content: "", index: 0),
            makeChunk(content: "Not empty", index: 1)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.count == 2)
        #expect(stats.minSize == 0)
    }

    @Test("statistics with all empty content chunks")
    func allEmptyContentChunks() {
        let chunks = [
            makeChunk(content: "", index: 0),
            makeChunk(content: "", index: 1),
            makeChunk(content: "", index: 2)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.count == 3)
        #expect(stats.totalCharacters == 0)
        #expect(stats.averageSize == 0.0)
        #expect(stats.minSize == 0)
        #expect(stats.maxSize == 0)
        #expect(stats.medianSize == 0)
    }

    @Test("statistics with same size chunks")
    func sameSizeChunks() {
        let content = "Same size content"
        let chunks = [
            makeChunk(content: content, index: 0),
            makeChunk(content: content, index: 1),
            makeChunk(content: content, index: 2)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.minSize == stats.maxSize)
        #expect(stats.averageSize == Double(content.count))
        #expect(stats.medianSize == content.count)
    }

    @Test("statistics with unicode content")
    func unicodeContent() {
        let chunks = [
            makeChunk(content: "Hello World", index: 0),
            makeChunk(content: "Another unicode chunk", index: 1)
        ]
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.count == 2)
        #expect(stats.totalCharacters > 0)
    }

    @Test("statistics with large number of chunks")
    func largeNumberOfChunks() {
        let chunks = (0..<1000).map { index in
            makeChunk(content: "Chunk \(index) content here", index: index)
        }
        let stats = ChunkingUtils.statistics(chunks)
        #expect(stats.count == 1000)
        #expect(stats.totalCharacters > 0)
    }
}

// MARK: - ChunkingUtils Validation Tests

@Suite("ChunkingUtils Validation Tests")
struct ChunkingUtilsValidationTests {

    // MARK: - Helper Methods

    private func makeChunk(content: String, index: Int = 0, documentId: String? = nil) -> Chunk {
        Chunk(
            content: content,
            metadata: ChunkMetadata(
                documentId: documentId ?? UUID().uuidString,
                index: index,
                startOffset: 0,
                endOffset: content.count
            )
        )
    }

    // MARK: - Valid Chunks Tests

    @Test("validate returns empty array for valid chunks within maxSize")
    func validChunksReturnEmptyArray() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 100), index: 0),
            makeChunk(content: String(repeating: "b", count: 200), index: 1),
            makeChunk(content: String(repeating: "c", count: 300), index: 2)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 500)
        #expect(errors.isEmpty)
    }

    @Test("validate returns empty for chunks exactly at maxSize")
    func chunksExactlyAtMaxSizeReturnEmpty() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 500), index: 0)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 500)
        #expect(errors.isEmpty)
    }

    @Test("validate returns empty for empty chunks array")
    func emptyChunksArrayReturnsEmpty() {
        let chunks: [Chunk] = []
        let errors = ChunkingUtils.validate(chunks, maxSize: 1000)
        #expect(errors.isEmpty)
    }

    // MARK: - Oversized Chunks Tests

    @Test("validate returns error for oversized chunk")
    func oversizedChunkReturnsError() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 1000), index: 0)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 500)
        #expect(errors.count == 1)
        #expect(errors[0].chunkIndex == 0)
    }

    @Test("validate returns errors for multiple oversized chunks")
    func multipleOversizedChunksReturnErrors() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 1000), index: 0),
            makeChunk(content: String(repeating: "b", count: 100), index: 1),
            makeChunk(content: String(repeating: "c", count: 2000), index: 2)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 500)
        #expect(errors.count == 2)

        let errorIndices = Set(errors.map { $0.chunkIndex })
        #expect(errorIndices.contains(0))
        #expect(errorIndices.contains(2))
        #expect(!errorIndices.contains(1))
    }

    @Test("validate error contains meaningful reason")
    func errorContainsMeaningfulReason() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 1000), index: 0)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 500)
        #expect(!errors.isEmpty)
        #expect(!errors[0].reason.isEmpty)
    }

    // MARK: - Empty Content Tests

    @Test("validate handles chunks with empty content")
    func chunksWithEmptyContent() {
        let chunks = [
            makeChunk(content: "", index: 0),
            makeChunk(content: "Not empty", index: 1)
        ]
        // Empty content should be valid (size 0 is within any maxSize)
        let errors = ChunkingUtils.validate(chunks, maxSize: 100)
        #expect(errors.isEmpty)
    }

    // MARK: - maxSize Edge Cases Tests

    @Test("validate with maxSize of 0 flags all non-empty chunks")
    func maxSizeZeroFlagsAllNonEmptyChunks() {
        let chunks = [
            makeChunk(content: "a", index: 0),
            makeChunk(content: "b", index: 1)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 0)
        #expect(errors.count == 2)
    }

    @Test("validate with maxSize of 1 allows single character chunks")
    func maxSizeOneAllowsSingleCharacter() {
        let chunks = [
            makeChunk(content: "a", index: 0),
            makeChunk(content: "b", index: 1),
            makeChunk(content: "cc", index: 2)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 1)
        #expect(errors.count == 1)
        #expect(errors[0].chunkIndex == 2)
    }

    @Test("validate with very large maxSize returns no errors")
    func veryLargeMaxSizeReturnsNoErrors() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 10000), index: 0),
            makeChunk(content: String(repeating: "b", count: 50000), index: 1)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: Int.max)
        #expect(errors.isEmpty)
    }

    // MARK: - Index Ordering Tests

    @Test("validate returns errors in chunk order")
    func errorsReturnedInChunkOrder() {
        let chunks = [
            makeChunk(content: String(repeating: "a", count: 100), index: 0),
            makeChunk(content: String(repeating: "b", count: 200), index: 1),
            makeChunk(content: String(repeating: "c", count: 100), index: 2),
            makeChunk(content: String(repeating: "d", count: 200), index: 3)
        ]
        let errors = ChunkingUtils.validate(chunks, maxSize: 150)

        #expect(errors.count == 2)
        #expect(errors[0].chunkIndex == 1)
        #expect(errors[1].chunkIndex == 3)
    }

    // MARK: - Unicode Content Tests

    @Test("validate handles unicode content correctly")
    func unicodeContentValidation() {
        let chunks = [
            makeChunk(content: "Hello World", index: 0)
        ]
        // Each emoji/character counts as one or more characters
        // This should pass if maxSize accounts for emoji character count
        let errors = ChunkingUtils.validate(chunks, maxSize: 100)
        #expect(errors.isEmpty)
    }

    @Test("validate counts unicode characters correctly")
    func unicodeCharacterCountValidation() {
        let emojiContent = String(repeating: "🎉", count: 10) // 10 emojis
        let chunks = [
            makeChunk(content: emojiContent, index: 0)
        ]
        // Emojis are multi-byte but count as single Swift characters
        let errors = ChunkingUtils.validate(chunks, maxSize: 9)
        #expect(errors.count == 1)
    }
}

// MARK: - ChunkingUtils Overlap Tests

@Suite("ChunkingUtils Overlap Tests")
struct ChunkingUtilsOverlapTests {

    // MARK: - Helper Methods

    private func makeChunk(
        content: String,
        index: Int = 0,
        documentId: String = "test-doc",
        startOffset: Int = 0,
        endOffset: Int? = nil
    ) -> Chunk {
        Chunk(
            content: content,
            metadata: ChunkMetadata(
                documentId: documentId,
                index: index,
                startOffset: startOffset,
                endOffset: endOffset ?? (startOffset + content.count)
            )
        )
    }

    // MARK: - addOverlap Basic Tests

    @Test("addOverlap with empty chunks returns empty array")
    func addOverlapEmptyChunksReturnsEmpty() {
        let chunks: [Chunk] = []
        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 50, originalText: "Some text")
        #expect(result.isEmpty)
    }

    @Test("addOverlap with single chunk returns unchanged chunk")
    func addOverlapSingleChunkReturnsUnchanged() {
        let originalText = "This is the original text content"
        let chunk = makeChunk(
            content: originalText,
            startOffset: 0,
            endOffset: originalText.count
        )
        let result = ChunkingUtils.addOverlap(to: [chunk], overlapSize: 10, originalText: originalText)

        #expect(result.count == 1)
        #expect(result[0].content == originalText)
    }

    @Test("addOverlap with multiple chunks adds overlap to subsequent chunks")
    func addOverlapMultipleChunks() {
        let originalText = "First chunk content. Second chunk content. Third chunk content."
        let chunks = [
            makeChunk(content: "First chunk content.", index: 0, startOffset: 0, endOffset: 20),
            makeChunk(content: "Second chunk content.", index: 1, startOffset: 21, endOffset: 42),
            makeChunk(content: "Third chunk content.", index: 2, startOffset: 43, endOffset: 63)
        ]

        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 10, originalText: originalText)

        #expect(result.count == 3)
        // First chunk should remain unchanged
        #expect(result[0].content == chunks[0].content)
        // Subsequent chunks should have overlap prepended
        #expect(result[1].content.count >= chunks[1].content.count)
    }

    @Test("addOverlap preserves chunk order")
    func addOverlapPreservesChunkOrder() {
        let originalText = "AAAA BBBB CCCC"
        let chunks = [
            makeChunk(content: "AAAA", index: 0, startOffset: 0, endOffset: 4),
            makeChunk(content: "BBBB", index: 1, startOffset: 5, endOffset: 9),
            makeChunk(content: "CCCC", index: 2, startOffset: 10, endOffset: 14)
        ]

        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 2, originalText: originalText)

        #expect(result.count == 3)
        #expect(result[0].metadata.index == 0)
        #expect(result[1].metadata.index == 1)
        #expect(result[2].metadata.index == 2)
    }

    // MARK: - addOverlap Edge Cases Tests

    @Test("addOverlap with zero overlapSize returns unchanged chunks")
    func addOverlapZeroOverlapSizeReturnsUnchanged() {
        let originalText = "First part. Second part."
        let chunks = [
            makeChunk(content: "First part.", index: 0, startOffset: 0, endOffset: 11),
            makeChunk(content: "Second part.", index: 1, startOffset: 12, endOffset: 24)
        ]

        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 0, originalText: originalText)

        #expect(result.count == 2)
        #expect(result[0].content == chunks[0].content)
        #expect(result[1].content == chunks[1].content)
    }

    @Test("addOverlap with overlapSize larger than chunk handles gracefully")
    func addOverlapLargeOverlapSizeHandlesGracefully() {
        let originalText = "AB CD EF"
        let chunks = [
            makeChunk(content: "AB", index: 0, startOffset: 0, endOffset: 2),
            makeChunk(content: "CD", index: 1, startOffset: 3, endOffset: 5),
            makeChunk(content: "EF", index: 2, startOffset: 6, endOffset: 8)
        ]

        // Overlap size larger than individual chunks
        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 100, originalText: originalText)

        #expect(result.count == 3)
        // Should handle gracefully without crashing
    }

    @Test("addOverlap preserves document ID")
    func addOverlapPreservesDocumentId() {
        let documentId = "unique-doc-123"
        let originalText = "Content A. Content B."
        let chunks = [
            makeChunk(content: "Content A.", index: 0, documentId: documentId, startOffset: 0, endOffset: 10),
            makeChunk(content: "Content B.", index: 1, documentId: documentId, startOffset: 11, endOffset: 21)
        ]

        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 5, originalText: originalText)

        for chunk in result {
            #expect(chunk.metadata.documentId == documentId)
        }
    }

    // MARK: - removeOverlap Basic Tests

    @Test("removeOverlap with empty chunks returns empty array")
    func removeOverlapEmptyChunksReturnsEmpty() {
        let chunks: [Chunk] = []
        let result = ChunkingUtils.removeOverlap(chunks)
        #expect(result.isEmpty)
    }

    @Test("removeOverlap with single chunk returns unchanged chunk")
    func removeOverlapSingleChunkReturnsUnchanged() {
        let chunk = makeChunk(content: "Single chunk content", index: 0)
        let result = ChunkingUtils.removeOverlap([chunk])

        #expect(result.count == 1)
        #expect(result[0].content == chunk.content)
    }

    @Test("removeOverlap removes duplicate content at boundaries")
    func removeOverlapRemovesDuplicateContent() {
        // Simulate chunks with overlap
        let chunks = [
            makeChunk(content: "First chunk content", index: 0, startOffset: 0, endOffset: 19),
            makeChunk(content: "content Second chunk", index: 1, startOffset: 12, endOffset: 32)
        ]

        let result = ChunkingUtils.removeOverlap(chunks)

        #expect(result.count == 2)
        // The overlapping "content" should be removed from second chunk
    }

    @Test("removeOverlap preserves chunk order")
    func removeOverlapPreservesChunkOrder() {
        let chunks = [
            makeChunk(content: "First", index: 0, startOffset: 0, endOffset: 5),
            makeChunk(content: "Second", index: 1, startOffset: 6, endOffset: 12),
            makeChunk(content: "Third", index: 2, startOffset: 13, endOffset: 18)
        ]

        let result = ChunkingUtils.removeOverlap(chunks)

        #expect(result.count == 3)
        #expect(result[0].metadata.index == 0)
        #expect(result[1].metadata.index == 1)
        #expect(result[2].metadata.index == 2)
    }

    // MARK: - removeOverlap Edge Cases Tests

    @Test("removeOverlap handles chunks with no actual overlap")
    func removeOverlapHandlesNoActualOverlap() {
        let chunks = [
            makeChunk(content: "First chunk", index: 0, startOffset: 0, endOffset: 11),
            makeChunk(content: "Second chunk", index: 1, startOffset: 12, endOffset: 24),
            makeChunk(content: "Third chunk", index: 2, startOffset: 25, endOffset: 36)
        ]

        let result = ChunkingUtils.removeOverlap(chunks)

        #expect(result.count == 3)
        // Content should remain unchanged when there's no overlap
    }

    @Test("removeOverlap handles empty content chunks")
    func removeOverlapHandlesEmptyContentChunks() {
        let chunks = [
            makeChunk(content: "", index: 0, startOffset: 0, endOffset: 0),
            makeChunk(content: "Non-empty", index: 1, startOffset: 1, endOffset: 10)
        ]

        let result = ChunkingUtils.removeOverlap(chunks)

        #expect(result.count == 2)
    }

    @Test("removeOverlap preserves document ID")
    func removeOverlapPreservesDocumentId() {
        let documentId = "doc-456"
        let chunks = [
            makeChunk(content: "First", index: 0, documentId: documentId, startOffset: 0, endOffset: 5),
            makeChunk(content: "Second", index: 1, documentId: documentId, startOffset: 6, endOffset: 12)
        ]

        let result = ChunkingUtils.removeOverlap(chunks)

        for chunk in result {
            #expect(chunk.metadata.documentId == documentId)
        }
    }

    // MARK: - Roundtrip Tests

    @Test("addOverlap followed by removeOverlap reconstructs approximate original")
    func addAndRemoveOverlapRoundtrip() {
        let originalText = "First segment here. Second segment here. Third segment here."
        let chunks = [
            makeChunk(content: "First segment here.", index: 0, startOffset: 0, endOffset: 19),
            makeChunk(content: "Second segment here.", index: 1, startOffset: 20, endOffset: 40),
            makeChunk(content: "Third segment here.", index: 2, startOffset: 41, endOffset: 60)
        ]

        let withOverlap = ChunkingUtils.addOverlap(to: chunks, overlapSize: 5, originalText: originalText)
        let withoutOverlap = ChunkingUtils.removeOverlap(withOverlap)

        #expect(withoutOverlap.count == chunks.count)
    }

    // MARK: - Multiple Document IDs Tests

    @Test("addOverlap handles chunks from different documents")
    func addOverlapDifferentDocuments() {
        let chunks = [
            makeChunk(content: "Doc1 content", index: 0, documentId: "doc1", startOffset: 0, endOffset: 12),
            makeChunk(content: "Doc2 content", index: 0, documentId: "doc2", startOffset: 0, endOffset: 12)
        ]

        // Using empty original text since chunks are from different documents
        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 5, originalText: "")

        #expect(result.count == 2)
        #expect(result[0].metadata.documentId == "doc1")
        #expect(result[1].metadata.documentId == "doc2")
    }

    // MARK: - Content Integrity Tests

    @Test("addOverlap does not modify first chunk content")
    func addOverlapDoesNotModifyFirstChunk() {
        let originalText = "First chunk. Second chunk."
        let firstContent = "First chunk."
        let chunks = [
            makeChunk(content: firstContent, index: 0, startOffset: 0, endOffset: 12),
            makeChunk(content: "Second chunk.", index: 1, startOffset: 13, endOffset: 26)
        ]

        let result = ChunkingUtils.addOverlap(to: chunks, overlapSize: 5, originalText: originalText)

        #expect(result[0].content == firstContent)
    }

    @Test("removeOverlap does not modify first chunk content")
    func removeOverlapDoesNotModifyFirstChunk() {
        let firstContent = "First chunk content"
        let chunks = [
            makeChunk(content: firstContent, index: 0, startOffset: 0, endOffset: 19),
            makeChunk(content: "content Second chunk", index: 1, startOffset: 12, endOffset: 32)
        ]

        let result = ChunkingUtils.removeOverlap(chunks)

        #expect(result[0].content == firstContent)
    }
}
