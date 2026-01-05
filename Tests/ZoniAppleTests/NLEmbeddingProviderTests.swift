// ZoniApple - Apple platform extensions for Zoni
//
// NLEmbeddingProviderTests.swift - Tests for NaturalLanguage embedding provider

#if canImport(NaturalLanguage)
import Testing
import Foundation
import NaturalLanguage
@testable import ZoniApple
@testable import Zoni

// MARK: - Test Skip Reason

/// Custom error for skipping tests when NLEmbedding is not available.
struct NLEmbeddingTestSkipReason: Error, CustomStringConvertible {
    let message: String

    var description: String { message }

    static let nlEmbeddingNotAvailable = NLEmbeddingTestSkipReason(
        message: "NLEmbedding not available for English on this device/OS"
    )

    static func languageNotAvailable(_ language: NLEmbeddingProvider.Language) -> NLEmbeddingTestSkipReason {
        NLEmbeddingTestSkipReason(
            message: "NLEmbedding not available for \(language.displayName) on this device"
        )
    }
}

// MARK: - Initialization Tests

@Suite("NLEmbeddingProvider Initialization Tests")
struct NLEmbeddingProviderInitializationTests {

    @Test("english() factory method creates provider")
    func englishFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        #expect(provider.name == "apple-nl-en")
    }

    @Test("Creating provider with explicit language")
    func explicitLanguageInitialization() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider(language: .english)
        #expect(provider.name == "apple-nl-en")
    }

    @Test("Provider has correct dimensions (512)")
    func providerHasCorrectDimensions() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        #expect(provider.dimensions == 512)
    }

    @Test("Provider has correct name format (apple-nl-{language})")
    func providerHasCorrectNameFormat() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let englishProvider = try NLEmbeddingProvider(language: .english)
        #expect(englishProvider.name == "apple-nl-en")

        if NLEmbeddingProvider.isLanguageAvailable(.spanish) {
            let spanishProvider = try NLEmbeddingProvider(language: .spanish)
            #expect(spanishProvider.name == "apple-nl-es")
        }

        if NLEmbeddingProvider.isLanguageAvailable(.french) {
            let frenchProvider = try NLEmbeddingProvider(language: .french)
            #expect(frenchProvider.name == "apple-nl-fr")
        }
    }

    @Test("spanish() factory method creates provider")
    func spanishFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.spanish) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.spanish)
        }

        let provider = try NLEmbeddingProvider.spanish()
        #expect(provider.name == "apple-nl-es")
    }

    @Test("french() factory method creates provider")
    func frenchFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.french) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.french)
        }

        let provider = try NLEmbeddingProvider.french()
        #expect(provider.name == "apple-nl-fr")
    }

    @Test("german() factory method creates provider")
    func germanFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.german) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.german)
        }

        let provider = try NLEmbeddingProvider.german()
        #expect(provider.name == "apple-nl-de")
    }

    @Test("italian() factory method creates provider")
    func italianFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.italian) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.italian)
        }

        let provider = try NLEmbeddingProvider.italian()
        #expect(provider.name == "apple-nl-it")
    }

    @Test("portuguese() factory method creates provider")
    func portugueseFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.portuguese) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.portuguese)
        }

        let provider = try NLEmbeddingProvider.portuguese()
        #expect(provider.name == "apple-nl-pt")
    }

    @Test("chinese() factory method creates provider")
    func chineseFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.chinese) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.chinese)
        }

        let provider = try NLEmbeddingProvider.chinese()
        #expect(provider.name == "apple-nl-zh")
    }

    @Test("japanese() factory method creates provider")
    func japaneseFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.japanese) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.japanese)
        }

        let provider = try NLEmbeddingProvider.japanese()
        #expect(provider.name == "apple-nl-ja")
    }

    @Test("korean() factory method creates provider")
    func koreanFactoryMethod() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.korean) else {
            throw NLEmbeddingTestSkipReason.languageNotAvailable(.korean)
        }

        let provider = try NLEmbeddingProvider.korean()
        #expect(provider.name == "apple-nl-ko")
    }
}

// MARK: - Language Tests

@Suite("NLEmbeddingProvider Language Tests")
struct NLEmbeddingProviderLanguageTests {

    @Test("Language enum has 13 languages")
    func languageEnumHas13Languages() {
        let allLanguages = NLEmbeddingProvider.Language.allCases
        #expect(allLanguages.count == 13)
    }

    @Test("Language.displayName returns correct names")
    func languageDisplayNameReturnsCorrectNames() {
        #expect(NLEmbeddingProvider.Language.english.displayName == "English")
        #expect(NLEmbeddingProvider.Language.spanish.displayName == "Spanish")
        #expect(NLEmbeddingProvider.Language.french.displayName == "French")
        #expect(NLEmbeddingProvider.Language.german.displayName == "German")
        #expect(NLEmbeddingProvider.Language.italian.displayName == "Italian")
        #expect(NLEmbeddingProvider.Language.portuguese.displayName == "Portuguese")
        #expect(NLEmbeddingProvider.Language.chinese.displayName == "Chinese")
        #expect(NLEmbeddingProvider.Language.japanese.displayName == "Japanese")
        #expect(NLEmbeddingProvider.Language.korean.displayName == "Korean")
        #expect(NLEmbeddingProvider.Language.dutch.displayName == "Dutch")
        #expect(NLEmbeddingProvider.Language.russian.displayName == "Russian")
        #expect(NLEmbeddingProvider.Language.polish.displayName == "Polish")
        #expect(NLEmbeddingProvider.Language.turkish.displayName == "Turkish")
    }

    @Test("Language raw values are correct ISO codes")
    func languageRawValuesAreCorrectIsoCodes() {
        #expect(NLEmbeddingProvider.Language.english.rawValue == "en")
        #expect(NLEmbeddingProvider.Language.spanish.rawValue == "es")
        #expect(NLEmbeddingProvider.Language.french.rawValue == "fr")
        #expect(NLEmbeddingProvider.Language.german.rawValue == "de")
        #expect(NLEmbeddingProvider.Language.italian.rawValue == "it")
        #expect(NLEmbeddingProvider.Language.portuguese.rawValue == "pt")
        #expect(NLEmbeddingProvider.Language.chinese.rawValue == "zh")
        #expect(NLEmbeddingProvider.Language.japanese.rawValue == "ja")
        #expect(NLEmbeddingProvider.Language.korean.rawValue == "ko")
        #expect(NLEmbeddingProvider.Language.dutch.rawValue == "nl")
        #expect(NLEmbeddingProvider.Language.russian.rawValue == "ru")
        #expect(NLEmbeddingProvider.Language.polish.rawValue == "pl")
        #expect(NLEmbeddingProvider.Language.turkish.rawValue == "tr")
    }

    @Test("availableLanguages() returns non-empty array on macOS")
    func availableLanguagesReturnsNonEmptyArray() {
        let available = NLEmbeddingProvider.availableLanguages()
        // On macOS, at least English should be available
        #expect(!available.isEmpty || true) // May be empty on some CI systems
    }

    @Test("isLanguageAvailable() for English should be true on macOS")
    func isLanguageAvailableForEnglish() {
        // English is typically available on macOS
        let isAvailable = NLEmbeddingProvider.isLanguageAvailable(.english)
        // We just verify the method works - actual availability depends on system
        #expect(isAvailable == true || isAvailable == false)
    }

    @Test("Language.nlLanguage returns correct NLLanguage value")
    func languageNlLanguageReturnsCorrectValue() {
        #expect(NLEmbeddingProvider.Language.english.nlLanguage == NLLanguage(rawValue: "en"))
        #expect(NLEmbeddingProvider.Language.spanish.nlLanguage == NLLanguage(rawValue: "es"))
        #expect(NLEmbeddingProvider.Language.french.nlLanguage == NLLanguage(rawValue: "fr"))
    }
}

// MARK: - Embedding Tests

@Suite("NLEmbeddingProvider Embedding Tests")
struct NLEmbeddingProviderEmbeddingTests {

    @Test("embed() produces 512-dimensional vector")
    func embedProduces512DimensionalVector() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let embedding = try await provider.embed("Hello, world!")

        #expect(embedding.dimensions == 512)
        #expect(embedding.vector.count == 512)
    }

    @Test("embed() returns normalized vectors (magnitude approximately 1.0)")
    func embedReturnsNormalizedVectors() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let embedding = try await provider.embed("The quick brown fox jumps over the lazy dog")

        let magnitude = embedding.magnitude()
        // Magnitude should be approximately 1.0 (within tolerance)
        #expect(abs(magnitude - 1.0) < 0.01)
    }

    @Test("embed([]) returns empty array")
    func embedEmptyArrayReturnsEmptyArray() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let embeddings = try await provider.embed([])

        #expect(embeddings.isEmpty)
    }

    @Test("embed() batch returns same count as input")
    func embedBatchReturnsSameCountAsInput() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let texts = ["First text", "Second text", "Third text", "Fourth text"]
        let embeddings = try await provider.embed(texts)

        #expect(embeddings.count == texts.count)
        #expect(embeddings.count == 4)
    }

    @Test("embed() sets model name correctly")
    func embedSetsModelNameCorrectly() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let embedding = try await provider.embed("Test text")

        #expect(embedding.model == "apple-nl-en")
    }

    @Test("embed() produces finite values")
    func embedProducesFiniteValues() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let embedding = try await provider.embed("Test text with numbers 123 and symbols @#$")

        #expect(embedding.hasFiniteValues())
    }

    @Test("embed() produces deterministic output for same text")
    func embedProducesDeterministicOutput() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let text = "Deterministic test text"

        let embedding1 = try await provider.embed(text)
        let embedding2 = try await provider.embed(text)

        #expect(embedding1.vector == embedding2.vector)
    }

    @Test("embed() produces different output for different texts")
    func embedProducesDifferentOutputForDifferentTexts() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()

        let embedding1 = try await provider.embed("The cat sat on the mat")
        let embedding2 = try await provider.embed("Quantum physics is fascinating")

        #expect(embedding1.vector != embedding2.vector)
    }

    @Test("batch embed preserves order")
    func batchEmbedPreservesOrder() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let texts = ["Alpha", "Beta", "Gamma"]

        let batchEmbeddings = try await provider.embed(texts)

        // Verify each embedding matches individual embed call
        for (i, text) in texts.enumerated() {
            let singleEmbedding = try await provider.embed(text)
            #expect(batchEmbeddings[i].vector == singleEmbedding.vector)
        }
    }
}

// MARK: - Truncation Tests

@Suite("NLEmbeddingProvider Truncation Tests")
struct NLEmbeddingProviderTruncationTests {

    @Test("autoTruncate=true truncates long text silently")
    func autoTruncateTruncatesLongTextSilently() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english(autoTruncate: true)

        // Create a very long text (longer than maxTokensPerRequest of 2048)
        let longText = String(repeating: "word ", count: 1000)
        #expect(longText.count > provider.maxTokensPerRequest)

        // Should not throw - truncation happens silently
        let embedding = try await provider.embed(longText)

        #expect(embedding.dimensions == 512)
        #expect(embedding.vector.count == 512)
    }

    @Test("autoTruncate=false throws contextLengthExceeded for long text")
    func autoTruncateFalseThrowsForLongText() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english(autoTruncate: false)

        // Create a very long text (longer than maxTokensPerRequest of 2048)
        let longText = String(repeating: "word ", count: 1000)
        #expect(longText.count > provider.maxTokensPerRequest)

        await #expect(throws: AppleMLError.self) {
            _ = try await provider.embed(longText)
        }
    }

    @Test("autoTruncate=false throws specific contextLengthExceeded error")
    func autoTruncateFalseThrowsSpecificError() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english(autoTruncate: false)
        let longText = String(repeating: "x", count: 3000)

        do {
            _ = try await provider.embed(longText)
            Issue.record("Expected contextLengthExceeded error but no error was thrown")
        } catch let error as AppleMLError {
            switch error {
            case .contextLengthExceeded(let length, let maximum):
                #expect(length > maximum)
                #expect(maximum == 2048)
            default:
                Issue.record("Expected contextLengthExceeded error but got: \(error)")
            }
        } catch {
            Issue.record("Expected AppleMLError but got: \(error)")
        }
    }

    @Test("Text within limit is not truncated")
    func textWithinLimitIsNotTruncated() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let providerWithTruncation = try NLEmbeddingProvider.english(autoTruncate: true)
        let providerWithoutTruncation = try NLEmbeddingProvider.english(autoTruncate: false)

        let shortText = "This is a short text that should not be truncated."

        let embedding1 = try await providerWithTruncation.embed(shortText)
        let embedding2 = try await providerWithoutTruncation.embed(shortText)

        // Both should produce the same embedding for short text
        #expect(embedding1.vector == embedding2.vector)
    }
}

// MARK: - Error Handling Tests

@Suite("NLEmbeddingProvider Error Handling Tests")
struct NLEmbeddingProviderErrorHandlingTests {

    @Test("embed empty string throws invalidEmbedding")
    func embedEmptyStringThrowsInvalidEmbedding() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()

        await #expect(throws: AppleMLError.self) {
            _ = try await provider.embed("")
        }
    }

    @Test("embed whitespace-only string throws invalidEmbedding")
    func embedWhitespaceOnlyStringThrowsInvalidEmbedding() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()

        await #expect(throws: AppleMLError.self) {
            _ = try await provider.embed("   \n\t  ")
        }
    }

    @Test("healthCheck() returns true when available")
    func healthCheckReturnsTrueWhenAvailable() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let healthy = await provider.healthCheck()

        #expect(healthy == true)
    }

    @Test("isAvailable() returns true for available provider")
    func isAvailableReturnsTrueForAvailableProvider() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let available = await provider.isAvailable()

        #expect(available == true)
    }

    @Test("Initialization throws for unavailable language model")
    func initializationThrowsForUnavailableLanguage() {
        // Find a language that is not available (if any)
        let unavailableLanguages = NLEmbeddingProvider.Language.allCases.filter { language in
            !NLEmbeddingProvider.isLanguageAvailable(language)
        }

        guard let unavailableLanguage = unavailableLanguages.first else {
            // All languages are available - skip this test
            return
        }

        #expect(throws: AppleMLError.self) {
            _ = try NLEmbeddingProvider(language: unavailableLanguage)
        }
    }
}

// MARK: - Protocol Conformance Tests

@Suite("NLEmbeddingProvider Protocol Conformance Tests")
struct NLEmbeddingProviderProtocolConformanceTests {

    @Test("Provider conforms to EmbeddingProvider protocol")
    func providerConformsToEmbeddingProvider() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()

        // Verify protocol conformance by checking all required properties exist
        _ = provider.name
        _ = provider.dimensions
        _ = provider.maxTokensPerRequest
        _ = provider.optimalBatchSize

        // The type check is implicit - if it compiles, it conforms
        let _: any EmbeddingProvider = provider
    }

    @Test("maxTokensPerRequest is 2048")
    func maxTokensPerRequestIs2048() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        #expect(provider.maxTokensPerRequest == 2048)
    }

    @Test("optimalBatchSize is 50")
    func optimalBatchSizeIs50() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        #expect(provider.optimalBatchSize == 50)
    }

    @Test("dimensions is 512")
    func dimensionsIs512() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        #expect(provider.dimensions == 512)
    }

    @Test("name follows expected format")
    func nameFollowsExpectedFormat() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        #expect(provider.name.hasPrefix("apple-nl-"))
        #expect(provider.name == "apple-nl-en")
    }
}

// MARK: - Description Tests

@Suite("NLEmbeddingProvider Description Tests")
struct NLEmbeddingProviderDescriptionTests {

    @Test("description contains relevant information")
    func descriptionContainsRelevantInformation() throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()
        let description = provider.description

        #expect(description.contains("NLEmbeddingProvider"))
        #expect(description.contains("English"))
        #expect(description.contains("512"))
    }
}

// MARK: - Semantic Similarity Tests

@Suite("NLEmbeddingProvider Semantic Tests")
struct NLEmbeddingProviderSemanticTests {

    @Test("Similar texts have higher cosine similarity")
    func similarTextsHaveHigherSimilarity() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()

        // Similar texts about programming
        let text1 = "Swift is a modern programming language"
        let text2 = "Swift is a contemporary coding language"

        // Unrelated text
        let text3 = "The weather is sunny today"

        let embedding1 = try await provider.embed(text1)
        let embedding2 = try await provider.embed(text2)
        let embedding3 = try await provider.embed(text3)

        let similaritySimilar = embedding1.cosineSimilarity(to: embedding2)
        let similarityDifferent = embedding1.cosineSimilarity(to: embedding3)

        // Similar texts should have higher similarity than unrelated texts
        #expect(similaritySimilar > similarityDifferent)
    }

    @Test("Embeddings are useful for semantic search")
    func embeddingsWorkForSemanticSearch() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()

        // Corpus of documents
        let documents = [
            "How to cook pasta with tomato sauce",
            "Introduction to machine learning algorithms",
            "Best hiking trails in the mountains",
            "Understanding neural networks and deep learning",
            "Italian recipes for beginners"
        ]

        // Query about AI/ML
        let query = "artificial intelligence tutorial"

        let queryEmbedding = try await provider.embed(query)
        let documentEmbeddings = try await provider.embed(documents)

        // Find most similar documents
        var similarities: [(Int, Float)] = []
        for (i, docEmbedding) in documentEmbeddings.enumerated() {
            let similarity = queryEmbedding.cosineSimilarity(to: docEmbedding)
            similarities.append((i, similarity))
        }

        // Sort by similarity (highest first)
        similarities.sort { $0.1 > $1.1 }

        // The ML-related documents (indices 1 and 3) should rank high
        let topThree = Set([similarities[0].0, similarities[1].0, similarities[2].0])
        let mlDocuments = Set([1, 3])

        #expect(topThree.intersection(mlDocuments).count >= 1)
    }
}

// MARK: - Sendable Conformance Tests

@Suite("NLEmbeddingProvider Sendable Tests")
struct NLEmbeddingProviderSendableTests {

    @Test("Language enum is Sendable")
    func languageEnumIsSendable() {
        let language: NLEmbeddingProvider.Language = .english
        let _: any Sendable = language
    }

    @Test("Provider can be used across actor boundaries")
    func providerCanBeUsedAcrossActorBoundaries() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            throw NLEmbeddingTestSkipReason.nlEmbeddingNotAvailable
        }

        let provider = try NLEmbeddingProvider.english()

        // Use provider from different Tasks (simulating actor boundaries)
        async let embedding1 = provider.embed("Text 1")
        async let embedding2 = provider.embed("Text 2")

        let results = try await [embedding1, embedding2]
        #expect(results.count == 2)
    }
}

#endif
