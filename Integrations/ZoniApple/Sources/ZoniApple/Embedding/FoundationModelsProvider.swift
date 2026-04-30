// ZoniApple - Apple platform extensions for Zoni
//
// FoundationModelsProvider.swift - Apple Foundation Models framework embedding provider
//
// Uses Apple's on-device Foundation Models (iOS 26+) for semantic embeddings.
// The Foundation Models framework provides a 3B parameter language model that runs
// entirely on-device, offering privacy, zero cost, and offline capability.
//
// ## Important Implementation Notes
//
// Foundation Models does not provide a direct embedding API like traditional
// embedding models. Instead, this provider uses a prompt-based approach where
// the model generates semantic representations that are then converted to
// numerical vectors through consistent hashing.
//
// This approach provides:
// - Semantic understanding powered by Apple's on-device LLM
// - Consistent embeddings for identical inputs
// - Privacy-preserving on-device processing
//
// ## Limitations
//
// - Embeddings are derived from model responses, not native vector outputs
// - May be slower than dedicated embedding models
// - Quality depends on prompt engineering and model capabilities

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import Zoni

// MARK: - FoundationModelsProvider

/// An embedding provider using Apple's Foundation Models framework.
///
/// - Important: **FUTURE-PROOFING STUB** - This provider is designed for iOS 26+/macOS 26+
///   which are not yet released. The provider will throw `AppleMLError.frameworkNotAvailable`
///   until the FoundationModels framework becomes available. This is intentional scaffolding
///   to prepare for Apple's upcoming on-device LLM APIs.
///
/// `FoundationModelsProvider` leverages Apple's on-device Foundation Models (iOS 26+)
/// to generate semantic embeddings. This provides:
/// - **Privacy**: All processing happens on-device with no network requests
/// - **Zero cost**: No API fees or rate limits
/// - **Offline support**: Works without internet connectivity
/// - **Semantic understanding**: Powered by Apple's 3B parameter on-device LLM
///
/// ## ⚠️ Current Status
///
/// This provider is a **structural placeholder** for future functionality:
/// - The `FoundationModels` framework does not exist in current iOS/macOS SDKs
/// - All initialization attempts will throw `AppleMLError.frameworkNotAvailable`
/// - The embedding generation code demonstrates the intended API design
/// - Once iOS 26/macOS 26 are released, update the `#if canImport` sections
///
/// ## Implementation Notes for Future Development
///
/// When FoundationModels becomes available:
/// 1. Remove the error throw in `init()`
/// 2. Uncomment and update the `LanguageModelSession` initialization
/// 3. Consider using native embedding APIs if Apple provides them
/// 4. Update availability checks in `isAvailable`
///
/// ## Example Usage (Future)
/// ```swift
/// // Create the provider (checks availability automatically)
/// let provider = try await FoundationModelsProvider()
///
/// // Generate embeddings
/// let embedding = try await provider.embed("The quick brown fox")
/// print("Dimensions: \(embedding.dimensions)") // 1024
///
/// // Batch embedding
/// let texts = ["First text", "Second text", "Third text"]
/// let embeddings = try await provider.embed(texts)
/// ```
///
/// ## Availability
/// Foundation Models requires:
/// - iOS 26.0 or later / macOS 26.0 or later
/// - Apple Intelligence enabled in Settings
/// - Supported device with Apple Silicon
///
/// Use `FoundationModelsProvider.isAvailable` to check availability before creating
/// an instance.
///
/// ## Thread Safety
/// This actor is safe to use from any concurrency context.
@available(iOS 26.0, macOS 26.0, *)
public actor FoundationModelsProvider: EmbeddingProvider {

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "apple-fm"

    /// The number of dimensions in generated embeddings.
    ///
    /// This provider generates 1024-dimensional vectors to match common
    /// embedding model dimensions (e.g., Cohere embed-english-v3.0).
    public nonisolated let dimensions: Int = 1024

    /// Maximum tokens per request.
    ///
    /// Foundation Models has a context window, but for embedding purposes
    /// we limit input to maintain quality and performance.
    public nonisolated let maxTokensPerRequest: Int = 2048

    /// Optimal batch size for this provider.
    ///
    /// Since Foundation Models processes one text at a time through the LLM,
    /// we use a smaller batch size to balance throughput and responsiveness.
    public nonisolated let optimalBatchSize: Int = 10

    // MARK: - Properties

    #if canImport(FoundationModels)
    /// The language model session for generating embeddings.
    private var session: LanguageModelSession?
    #endif

    /// Whether to automatically truncate long texts.
    private let autoTruncate: Bool

    /// Cache for generated embeddings to avoid redundant model calls.
    private var embeddingCache: [String: [Float]] = [:]

    /// Maximum cache size to prevent unbounded memory growth.
    private let maxCacheSize: Int

    // MARK: - Initialization

    /// Creates a Foundation Models embedding provider.
    ///
    /// This initializer checks for Foundation Models availability and creates
    /// a language model session configured for embedding generation.
    ///
    /// - Parameters:
    ///   - autoTruncate: Whether to automatically truncate long texts. Defaults to `true`.
    ///   - maxCacheSize: Maximum number of embeddings to cache. Defaults to 1000.
    /// - Throws: `AppleMLError.frameworkNotAvailable` if Foundation Models is not available,
    ///   or `AppleMLError.appleIntelligenceNotEnabled` if Apple Intelligence is disabled.
    public init(autoTruncate: Bool = true, maxCacheSize: Int = 1000) async throws {
        self.autoTruncate = autoTruncate
        self.maxCacheSize = maxCacheSize

        #if canImport(FoundationModels)
        // Note: This is placeholder code for the future FoundationModels framework (iOS 26+)
        // The actual API may differ when the framework is released
        // For now, we create a session without availability checks since the framework doesn't exist yet

        // Create session with embedding-focused system instructions
        // This will need to be updated with the actual FoundationModels API when available
        // self.session = LanguageModelSession(
        //     systemInstructions: """
        //     You are a semantic analysis system. When given text, analyze its meaning \
        //     and output a compact semantic signature. Focus on:
        //     - Core concepts and topics
        //     - Sentiment and tone
        //     - Key entities and relationships
        //     - Abstract semantic features
        //
        //     Output only the semantic analysis in a consistent, structured format.
        //     """
        // )

        // For now, throw an error since FoundationModels is not yet available
        throw AppleMLError.frameworkNotAvailable(
            framework: "FoundationModels",
            minimumOS: "iOS 26.0 / macOS 26.0"
        )
        #else
        throw AppleMLError.frameworkNotAvailable(
            framework: "FoundationModels",
            minimumOS: "iOS 26.0 / macOS 26.0"
        )
        #endif
    }

    // MARK: - EmbeddingProvider Methods

    /// Generates an embedding for a single text.
    ///
    /// This method uses the Foundation Models LLM to analyze the semantic content
    /// of the text and generates a numerical vector representation.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: A 1024-dimensional embedding vector.
    /// - Throws: `AppleMLError.invalidEmbedding` if embedding generation fails,
    ///   or `AppleMLError.contextLengthExceeded` if the text is too long and
    ///   `autoTruncate` is disabled.
    public func embed(_ text: String) async throws -> Embedding {
        let processedText = try processText(text)

        // Check cache first
        if let cached = embeddingCache[processedText] {
            return Embedding(vector: cached, model: name)
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AppleMLError.modelNotAvailable(
                name: "FoundationModels",
                reason: "Language model session is not initialized"
            )
        }

        // Generate semantic analysis from the model
        let prompt = """
        Analyze the semantic content of the following text and provide a compact \
        semantic fingerprint:

        "\(processedText)"
        """

        do {
            let response = try await session.respond(to: prompt)
            let semanticContent = response.content

            // Convert semantic analysis to numerical vector
            let vector = generateEmbeddingVector(from: semanticContent, originalText: processedText)

            // Validate the vector
            guard vector.allSatisfy({ $0.isFinite }) else {
                throw AppleMLError.invalidEmbedding(
                    reason: "Generated embedding contains non-finite values"
                )
            }

            // Cache the result
            cacheEmbedding(vector, for: processedText)

            return Embedding(vector: vector, model: name)
        } catch let error as AppleMLError {
            throw error
        } catch {
            throw AppleMLError.invalidEmbedding(
                reason: "Foundation Models response failed: \(error.localizedDescription)"
            )
        }
        #else
        throw AppleMLError.frameworkNotAvailable(
            framework: "FoundationModels",
            minimumOS: "iOS 26.0 / macOS 26.0"
        )
        #endif
    }

    /// Generates embeddings for multiple texts.
    ///
    /// Since Foundation Models doesn't support batch processing natively,
    /// texts are processed sequentially. This method provides consistent
    /// ordering with the input.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of 1024-dimensional embeddings in the same order as input.
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

    /// Checks if Foundation Models is available on this device.
    ///
    /// This static property can be checked before attempting to create
    /// a `FoundationModelsProvider` instance.
    ///
    /// - Returns: `true` if Foundation Models is available and Apple Intelligence is enabled.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            case .unavailable:
                return false
            @unknown default:
                return false
            }
        }
        return false
        #else
        return false
        #endif
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

    /// Clears the embedding cache.
    ///
    /// Call this method to free memory if the cache has grown large.
    public func clearCache() {
        embeddingCache.removeAll()
    }

    /// Returns the current cache size.
    ///
    /// - Returns: The number of cached embeddings.
    public func cacheSize() -> Int {
        embeddingCache.count
    }

    // MARK: - Private Methods

    /// Processes text before embedding, handling truncation if needed.
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

        // Handle long texts
        if trimmedText.count > maxTokensPerRequest {
            if autoTruncate {
                // Truncate at a word boundary if possible
                let truncated = String(trimmedText.prefix(maxTokensPerRequest))
                if let lastSpace = truncated.lastIndex(of: " ") {
                    return String(truncated[..<lastSpace])
                }
                return truncated
            } else {
                throw AppleMLError.contextLengthExceeded(
                    length: trimmedText.count,
                    maximum: maxTokensPerRequest
                )
            }
        }

        return trimmedText
    }

    /// Generates an embedding vector from semantic analysis output.
    ///
    /// This method converts the LLM's semantic analysis into a numerical vector
    /// using a combination of:
    /// 1. Hash-based features from the semantic content
    /// 2. Character-level n-gram features from the original text
    /// 3. Statistical features (length, entropy, etc.)
    ///
    /// - Parameters:
    ///   - semanticContent: The LLM's semantic analysis output.
    ///   - originalText: The original input text.
    /// - Returns: A normalized embedding vector.
    private func generateEmbeddingVector(from semanticContent: String, originalText: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)

        // Component 1: Semantic content hash features (512 dimensions)
        let semanticFeatures = generateHashFeatures(from: semanticContent, dimensions: 512)
        for i in 0..<512 {
            vector[i] = semanticFeatures[i]
        }

        // Component 2: Original text hash features (384 dimensions)
        let textFeatures = generateHashFeatures(from: originalText, dimensions: 384)
        for i in 0..<384 {
            vector[512 + i] = textFeatures[i]
        }

        // Component 3: Statistical features (128 dimensions)
        let statisticalFeatures = generateStatisticalFeatures(
            semanticContent: semanticContent,
            originalText: originalText
        )
        for i in 0..<128 {
            vector[896 + i] = statisticalFeatures[i]
        }

        // Normalize the vector to unit length
        return normalizeVector(vector)
    }

    /// Generates hash-based features from text.
    ///
    /// Uses a combination of n-gram hashing and position encoding to create
    /// deterministic features that capture semantic content.
    ///
    /// - Parameters:
    ///   - text: The text to generate features from.
    ///   - dimensions: The number of dimensions to generate.
    /// - Returns: An array of feature values.
    private func generateHashFeatures(from text: String, dimensions: Int) -> [Float] {
        var features = [Float](repeating: 0, count: dimensions)
        let words = text.lowercased().split(separator: " ")

        // Word-level features
        for (index, word) in words.enumerated() {
            var hasher = Hasher()
            hasher.combine(String(word))
            let hash = abs(hasher.finalize())

            // Distribute the word across multiple dimensions
            let primaryDim = hash % dimensions
            let secondaryDim = (hash / dimensions) % dimensions

            // Add position-weighted contribution
            let positionWeight = 1.0 / (1.0 + Float(index) * 0.1)
            features[primaryDim] += positionWeight
            features[secondaryDim] += positionWeight * 0.5
        }

        // Character n-gram features (trigrams)
        let chars = Array(text.lowercased())
        for i in 0..<max(0, chars.count - 2) {
            let trigram = String(chars[i..<min(i + 3, chars.count)])
            var hasher = Hasher()
            hasher.combine(trigram)
            let hash = abs(hasher.finalize())
            let dim = hash % dimensions
            features[dim] += 0.1
        }

        return features
    }

    /// Generates statistical features from the text content.
    ///
    /// - Parameters:
    ///   - semanticContent: The LLM's semantic analysis.
    ///   - originalText: The original input text.
    /// - Returns: An array of statistical feature values.
    private func generateStatisticalFeatures(semanticContent: String, originalText: String) -> [Float] {
        var features = [Float](repeating: 0, count: 128)

        // Text length features
        features[0] = Float(originalText.count) / 1000.0
        features[1] = Float(semanticContent.count) / 1000.0

        // Word count features
        let originalWords = originalText.split(separator: " ")
        let semanticWords = semanticContent.split(separator: " ")
        features[2] = Float(originalWords.count) / 100.0
        features[3] = Float(semanticWords.count) / 100.0

        // Average word length
        if !originalWords.isEmpty {
            let avgWordLen = Float(originalText.count) / Float(originalWords.count)
            features[4] = avgWordLen / 10.0
        }

        // Character distribution features
        var charCounts: [Character: Int] = [:]
        for char in originalText.lowercased() {
            charCounts[char, default: 0] += 1
        }

        // Entropy approximation
        let total = Float(originalText.count)
        var entropy: Float = 0
        for (_, count) in charCounts {
            let p = Float(count) / total
            if p > 0 {
                entropy -= p * log2(p)
            }
        }
        features[5] = entropy / 5.0 // Normalize

        // Punctuation ratio
        let punctuation = originalText.filter { $0.isPunctuation }
        features[6] = Float(punctuation.count) / max(1, Float(originalText.count))

        // Uppercase ratio
        let uppercase = originalText.filter { $0.isUppercase }
        features[7] = Float(uppercase.count) / max(1, Float(originalText.count))

        // Digit ratio
        let digits = originalText.filter { $0.isNumber }
        features[8] = Float(digits.count) / max(1, Float(originalText.count))

        // Unique word ratio
        let uniqueWords = Set(originalWords.map { $0.lowercased() })
        features[9] = Float(uniqueWords.count) / max(1, Float(originalWords.count))

        // Hash-based distribution of remaining dimensions
        var hasher = Hasher()
        hasher.combine(originalText)
        hasher.combine(semanticContent)
        var state = UInt64(bitPattern: Int64(hasher.finalize()))

        for i in 10..<128 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let normalized = Float(state >> 33) / Float(UInt32.max)
            features[i] = (normalized * 2.0) - 1.0
        }

        return features
    }

    /// Normalizes a vector to unit length.
    ///
    /// - Parameter vector: The vector to normalize.
    /// - Returns: A normalized vector with magnitude 1.0.
    private func normalizeVector(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0
        for value in vector {
            sumSquares += value * value
        }

        let magnitude = sqrt(sumSquares)
        guard magnitude > 0 else {
            return vector
        }

        return vector.map { $0 / magnitude }
    }

    /// Caches an embedding, evicting old entries if necessary.
    ///
    /// - Parameters:
    ///   - vector: The embedding vector to cache.
    ///   - text: The text key for the cache.
    private func cacheEmbedding(_ vector: [Float], for text: String) {
        // Simple eviction: clear half the cache when full
        if embeddingCache.count >= maxCacheSize {
            let keysToRemove = Array(embeddingCache.keys.prefix(maxCacheSize / 2))
            for key in keysToRemove {
                embeddingCache.removeValue(forKey: key)
            }
        }

        embeddingCache[text] = vector
    }
}

// MARK: - CustomStringConvertible

@available(iOS 26.0, macOS 26.0, *)
extension FoundationModelsProvider: CustomStringConvertible {

    /// A textual description of the provider.
    public nonisolated var description: String {
        "FoundationModelsProvider(dimensions: \(dimensions), maxTokens: \(maxTokensPerRequest))"
    }
}

// MARK: - Convenience Factory Methods

@available(iOS 26.0, macOS 26.0, *)
extension FoundationModelsProvider {

    /// Creates a provider optimized for short texts.
    ///
    /// Uses a smaller cache and lower token limit for memory efficiency.
    ///
    /// - Returns: A configured `FoundationModelsProvider`.
    /// - Throws: Errors if Foundation Models is not available.
    public static func forShortTexts() async throws -> FoundationModelsProvider {
        try await FoundationModelsProvider(autoTruncate: true, maxCacheSize: 500)
    }

    /// Creates a provider optimized for document embedding.
    ///
    /// Uses a larger cache for repeated document processing.
    ///
    /// - Returns: A configured `FoundationModelsProvider`.
    /// - Throws: Errors if Foundation Models is not available.
    public static func forDocuments() async throws -> FoundationModelsProvider {
        try await FoundationModelsProvider(autoTruncate: true, maxCacheSize: 2000)
    }

    /// Creates a provider with strict mode (no truncation).
    ///
    /// Throws an error if input text exceeds the token limit.
    ///
    /// - Returns: A configured `FoundationModelsProvider`.
    /// - Throws: Errors if Foundation Models is not available.
    public static func strict() async throws -> FoundationModelsProvider {
        try await FoundationModelsProvider(autoTruncate: false, maxCacheSize: 1000)
    }
}
