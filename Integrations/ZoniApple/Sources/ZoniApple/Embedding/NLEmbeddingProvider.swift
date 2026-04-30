// ZoniApple - Apple platform extensions for Zoni
//
// NLEmbeddingProvider.swift - Apple NaturalLanguage framework embedding provider

import Foundation
import NaturalLanguage
import Zoni

// MARK: - NLEmbeddingProvider

/// An embedding provider using Apple's NaturalLanguage framework.
///
/// `NLEmbeddingProvider` leverages Apple's on-device sentence embeddings through
/// the `NLEmbedding` API. This provides:
/// - **Privacy**: All processing happens on-device with no network requests
/// - **Zero cost**: No API fees or rate limits
/// - **Offline support**: Works without internet connectivity
/// - **Low latency**: No network round-trips required
///
/// ## Example Usage
/// ```swift
/// // Create an English embedding provider
/// let provider = try NLEmbeddingProvider.english()
///
/// // Generate embeddings
/// let embedding = try await provider.embed("Hello, world!")
/// print("Dimensions: \(embedding.dimensions)") // 512
///
/// // Batch embedding
/// let texts = ["First text", "Second text", "Third text"]
/// let embeddings = try await provider.embed(texts)
/// ```
///
/// ## Supported Languages
/// The following languages have sentence embedding models available:
/// - English (en)
/// - Spanish (es)
/// - French (fr)
/// - German (de)
/// - Italian (it)
/// - Portuguese (pt)
/// - Chinese (zh)
/// - Japanese (ja)
/// - Korean (ko)
/// - Dutch (nl)
/// - Russian (ru)
/// - Polish (pl)
/// - Turkish (tr)
///
/// ## Performance Notes
/// - NLEmbedding processes one text at a time (no native batching)
/// - Embeddings are 512-dimensional vectors
/// - Long texts are automatically truncated by the framework
/// - First embedding may take longer as the model loads
///
/// ## Thread Safety
/// This actor is safe to use from any concurrency context.
public actor NLEmbeddingProvider: EmbeddingProvider {

    // MARK: - Language

    /// Languages supported by Apple's NLEmbedding framework.
    ///
    /// Each language has its own trained sentence embedding model that captures
    /// semantic meaning specific to that language.
    public enum Language: String, Sendable, CaseIterable {
        /// English language embeddings.
        case english = "en"

        /// Spanish language embeddings.
        case spanish = "es"

        /// French language embeddings.
        case french = "fr"

        /// German language embeddings.
        case german = "de"

        /// Italian language embeddings.
        case italian = "it"

        /// Portuguese language embeddings.
        case portuguese = "pt"

        /// Chinese language embeddings.
        case chinese = "zh"

        /// Japanese language embeddings.
        case japanese = "ja"

        /// Korean language embeddings.
        case korean = "ko"

        /// Dutch language embeddings.
        case dutch = "nl"

        /// Russian language embeddings.
        case russian = "ru"

        /// Polish language embeddings.
        case polish = "pl"

        /// Turkish language embeddings.
        case turkish = "tr"

        /// The NLLanguage value for this language.
        public var nlLanguage: NLLanguage {
            NLLanguage(rawValue: rawValue)
        }

        /// A human-readable name for the language.
        public var displayName: String {
            switch self {
            case .english: return "English"
            case .spanish: return "Spanish"
            case .french: return "French"
            case .german: return "German"
            case .italian: return "Italian"
            case .portuguese: return "Portuguese"
            case .chinese: return "Chinese"
            case .japanese: return "Japanese"
            case .korean: return "Korean"
            case .dutch: return "Dutch"
            case .russian: return "Russian"
            case .polish: return "Polish"
            case .turkish: return "Turkish"
            }
        }
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name: String

    /// The number of dimensions in NLEmbedding vectors.
    ///
    /// Apple's NLEmbedding always produces 512-dimensional vectors.
    public nonisolated let dimensions: Int = 512

    /// Maximum tokens per request.
    ///
    /// NLEmbedding handles truncation internally, but we set a reasonable
    /// character limit to maintain embedding quality.
    public nonisolated let maxTokensPerRequest: Int = 2048

    /// Optimal batch size for this provider.
    ///
    /// Since NLEmbedding processes one text at a time, we use a smaller
    /// batch size to provide better progress feedback.
    public nonisolated let optimalBatchSize: Int = 50

    // MARK: - Properties

    /// The language for embeddings.
    private let language: Language

    /// The NLEmbedding instance for generating vectors.
    ///
    /// Lazily initialized on first use to avoid loading the model until needed.
    private var nlEmbedding: NLEmbedding?

    /// Whether to automatically truncate long texts.
    ///
    /// If `true`, texts exceeding `maxTokensPerRequest` are truncated.
    /// If `false`, an error is thrown for texts that are too long.
    private let autoTruncate: Bool

    // MARK: - Initialization

    /// Creates an NLEmbedding provider for the specified language.
    ///
    /// - Parameters:
    ///   - language: The language for embeddings.
    ///   - autoTruncate: Whether to automatically truncate long texts. Defaults to `true`.
    /// - Throws: `AppleMLError.modelNotAvailable` if the embedding model for the
    ///   specified language is not available on this device.
    public init(language: Language, autoTruncate: Bool = true) throws {
        self.language = language
        self.autoTruncate = autoTruncate
        self.name = "apple-nl-\(language.rawValue)"

        // Verify the embedding model is available
        guard NLEmbedding.sentenceEmbedding(for: language.nlLanguage) != nil else {
            throw AppleMLError.modelNotAvailable(
                name: "NLEmbedding-\(language.displayName)",
                reason: "Sentence embedding model for \(language.displayName) is not available on this device"
            )
        }
    }

    // MARK: - Static Factory Methods

    /// Creates an English embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for English.
    /// - Throws: `AppleMLError.modelNotAvailable` if the English model is unavailable.
    public static func english(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .english, autoTruncate: autoTruncate)
    }

    /// Creates a Spanish embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for Spanish.
    /// - Throws: `AppleMLError.modelNotAvailable` if the Spanish model is unavailable.
    public static func spanish(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .spanish, autoTruncate: autoTruncate)
    }

    /// Creates a French embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for French.
    /// - Throws: `AppleMLError.modelNotAvailable` if the French model is unavailable.
    public static func french(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .french, autoTruncate: autoTruncate)
    }

    /// Creates a German embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for German.
    /// - Throws: `AppleMLError.modelNotAvailable` if the German model is unavailable.
    public static func german(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .german, autoTruncate: autoTruncate)
    }

    /// Creates an Italian embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for Italian.
    /// - Throws: `AppleMLError.modelNotAvailable` if the Italian model is unavailable.
    public static func italian(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .italian, autoTruncate: autoTruncate)
    }

    /// Creates a Portuguese embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for Portuguese.
    /// - Throws: `AppleMLError.modelNotAvailable` if the Portuguese model is unavailable.
    public static func portuguese(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .portuguese, autoTruncate: autoTruncate)
    }

    /// Creates a Chinese embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for Chinese.
    /// - Throws: `AppleMLError.modelNotAvailable` if the Chinese model is unavailable.
    public static func chinese(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .chinese, autoTruncate: autoTruncate)
    }

    /// Creates a Japanese embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for Japanese.
    /// - Throws: `AppleMLError.modelNotAvailable` if the Japanese model is unavailable.
    public static func japanese(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .japanese, autoTruncate: autoTruncate)
    }

    /// Creates a Korean embedding provider.
    ///
    /// - Parameter autoTruncate: Whether to automatically truncate long texts.
    /// - Returns: An `NLEmbeddingProvider` configured for Korean.
    /// - Throws: `AppleMLError.modelNotAvailable` if the Korean model is unavailable.
    public static func korean(autoTruncate: Bool = true) throws -> NLEmbeddingProvider {
        try NLEmbeddingProvider(language: .korean, autoTruncate: autoTruncate)
    }

    // MARK: - EmbeddingProvider Methods

    /// Generates an embedding for a single text.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: A 512-dimensional embedding vector.
    /// - Throws: `AppleMLError.invalidEmbedding` if embedding generation fails,
    ///   or `AppleMLError.contextLengthExceeded` if the text is too long and
    ///   `autoTruncate` is disabled.
    public func embed(_ text: String) async throws -> Embedding {
        let embedding = try getEmbedding()
        let processedText = try processText(text)

        guard let vector = embedding.vector(for: processedText) else {
            throw AppleMLError.invalidEmbedding(
                reason: "NLEmbedding returned nil for the input text. The text may be empty or contain only whitespace."
            )
        }

        // Convert [Double] to [Float] for Embedding type
        let floatVector = vector.map { Float($0) }

        return Embedding(vector: floatVector, model: name)
    }

    /// Generates embeddings for multiple texts.
    ///
    /// Since NLEmbedding doesn't support batch processing, texts are processed
    /// sequentially. This method provides consistent ordering with the input.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of 512-dimensional embeddings in the same order as input.
    /// - Throws: `AppleMLError.invalidEmbedding` if any embedding generation fails,
    ///   or `AppleMLError.contextLengthExceeded` if any text is too long.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        var embeddings: [Embedding] = []
        embeddings.reserveCapacity(texts.count)

        for text in texts {
            let embedding = try await embed(text)
            embeddings.append(embedding)
        }

        return embeddings
    }

    // MARK: - Availability & Health

    /// Checks if NLEmbedding is available for the configured language.
    ///
    /// - Returns: `true` if the embedding model is loaded and ready.
    public func isAvailable() -> Bool {
        NLEmbedding.sentenceEmbedding(for: language.nlLanguage) != nil
    }

    /// Performs a health check by generating a test embedding.
    ///
    /// - Returns: `true` if embedding generation succeeds, `false` otherwise.
    public func healthCheck() async -> Bool {
        do {
            _ = try await embed("health check")
            return true
        } catch {
            return false
        }
    }

    /// Returns a list of languages that have embedding models available on this device.
    ///
    /// - Returns: An array of available languages.
    public static func availableLanguages() -> [Language] {
        Language.allCases.filter { language in
            NLEmbedding.sentenceEmbedding(for: language.nlLanguage) != nil
        }
    }

    /// Checks if a specific language is available for embeddings.
    ///
    /// - Parameter language: The language to check.
    /// - Returns: `true` if the language's embedding model is available.
    public static func isLanguageAvailable(_ language: Language) -> Bool {
        NLEmbedding.sentenceEmbedding(for: language.nlLanguage) != nil
    }

    // MARK: - Private Methods

    /// Gets or creates the NLEmbedding instance.
    ///
    /// - Returns: The NLEmbedding instance for the configured language.
    /// - Throws: `AppleMLError.modelNotAvailable` if the model cannot be loaded.
    private func getEmbedding() throws -> NLEmbedding {
        if let existing = nlEmbedding {
            return existing
        }

        guard let embedding = NLEmbedding.sentenceEmbedding(for: language.nlLanguage) else {
            throw AppleMLError.modelNotAvailable(
                name: "NLEmbedding-\(language.displayName)",
                reason: "The sentence embedding model is no longer available"
            )
        }

        nlEmbedding = embedding
        return embedding
    }

    /// Processes text before embedding, handling truncation if needed.
    ///
    /// This method uses `NLTokenizer` for accurate token counting rather than
    /// character count, ensuring proper handling across all languages.
    ///
    /// - Parameter text: The input text.
    /// - Returns: The processed text ready for embedding.
    /// - Throws: `AppleMLError.contextLengthExceeded` if the text is too long
    ///   and `autoTruncate` is disabled.
    private func processText(_ text: String) throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for empty text
        guard !trimmedText.isEmpty else {
            return trimmedText
        }

        // Use NLTokenizer for accurate token counting
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmedText

        // Collect token ranges
        var tokenRanges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: trimmedText.startIndex..<trimmedText.endIndex) { range, _ in
            tokenRanges.append(range)
            return true
        }

        let tokenCount = tokenRanges.count

        // Handle long texts based on actual token count
        if tokenCount > maxTokensPerRequest {
            if autoTruncate {
                // Truncate at the last valid token boundary
                guard maxTokensPerRequest > 0, maxTokensPerRequest <= tokenRanges.count else {
                    return trimmedText
                }

                // Get the end index of the last allowed token
                let lastAllowedTokenIndex = maxTokensPerRequest - 1
                let endIndex = tokenRanges[lastAllowedTokenIndex].upperBound

                return String(trimmedText[..<endIndex])
            } else {
                throw AppleMLError.contextLengthExceeded(
                    length: tokenCount,
                    maximum: maxTokensPerRequest
                )
            }
        }

        return trimmedText
    }
}

// MARK: - CustomStringConvertible

extension NLEmbeddingProvider: CustomStringConvertible {

    /// A textual description of the provider.
    public nonisolated var description: String {
        "NLEmbeddingProvider(language: \(language.displayName), dimensions: \(dimensions))"
    }
}
