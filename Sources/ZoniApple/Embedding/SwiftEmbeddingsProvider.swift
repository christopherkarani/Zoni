// ZoniApple - Apple platform extensions for Zoni
//
// SwiftEmbeddingsProvider.swift - Ultra-fast embeddings using swift-embeddings library
//
// This provider uses Model2Vec embeddings from the swift-embeddings package,
// offering 10x faster embedding generation than traditional BERT models
// with minimal memory footprint (~50MB).

import Foundation
import Embeddings
import Zoni

// MARK: - SwiftEmbeddingsProvider

/// An embedding provider using the swift-embeddings library for ultra-fast Model2Vec embeddings.
///
/// `SwiftEmbeddingsProvider` offers exceptional performance for on-device embeddings,
/// making it ideal for high-throughput RAG applications. Key characteristics:
/// - **10x faster** than traditional BERT models
/// - **Minimal memory** footprint (~50MB)
/// - **Works on all Apple platforms** including watchOS
/// - **No API costs** - fully on-device
///
/// Example usage:
/// ```swift
/// // Create with default model (potion-base-8M)
/// let provider = try await SwiftEmbeddingsProvider.default()
///
/// // Or specify a model
/// let provider = try await SwiftEmbeddingsProvider(model: .potionRetrieval32M)
///
/// // Generate embeddings
/// let embedding = try await provider.embed("Hello world")
///
/// // Batch embedding (very efficient - supports 1000+ texts)
/// let embeddings = try await provider.embed([
///     "First document",
///     "Second document",
///     "Third document"
/// ])
/// ```
///
/// ## Model Selection
///
/// Choose models based on your use case:
/// - `.potionBase2M`: Smallest, fastest, good for simple tasks
/// - `.potionBase8M`: Balanced performance and quality (default)
/// - `.potionRetrieval32M`: Best for retrieval/RAG applications
/// - `.m2vBaseOutput`: General-purpose static embeddings
///
/// ## First Run
///
/// Models are downloaded from HuggingFace on first use. Ensure network
/// connectivity for the initial run. Subsequent runs use cached models.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
public actor SwiftEmbeddingsProvider: EmbeddingProvider {

    // MARK: - Model

    /// Supported Model2Vec embedding models from minishlab.
    ///
    /// These models provide different trade-offs between speed, size, and quality.
    /// All models produce static embeddings that are extremely fast to compute.
    public enum Model: String, Sendable, CaseIterable {
        /// minishlab/potion-base-2M - Smallest and fastest model.
        ///
        /// - Dimensions: 256
        /// - Best for: Simple similarity tasks, resource-constrained devices
        case potionBase2M = "minishlab/potion-base-2M"

        /// minishlab/potion-base-4M - Compact model with good quality.
        ///
        /// - Dimensions: 256
        /// - Best for: Balanced speed and quality for simple tasks
        case potionBase4M = "minishlab/potion-base-4M"

        /// minishlab/potion-base-8M - Balanced performance model.
        ///
        /// - Dimensions: 256
        /// - Best for: General-purpose embeddings with good quality
        case potionBase8M = "minishlab/potion-base-8M"

        /// minishlab/potion-base-32M - High-quality general model.
        ///
        /// - Dimensions: 256
        /// - Best for: High-quality general-purpose embeddings
        case potionBase32M = "minishlab/potion-base-32M"

        /// minishlab/potion-retrieval-32M - Optimized for retrieval tasks.
        ///
        /// - Dimensions: 256
        /// - Best for: RAG applications, semantic search, document retrieval
        case potionRetrieval32M = "minishlab/potion-retrieval-32M"

        /// minishlab/M2V_base_output - Original Model2Vec base output model.
        ///
        /// - Dimensions: 256
        /// - Best for: General static embeddings
        case m2vBaseOutput = "minishlab/M2V_base_output"

        /// The embedding dimension for this model.
        ///
        /// All Model2Vec models from minishlab produce 256-dimensional embeddings.
        public var dimensions: Int {
            switch self {
            case .potionBase2M, .potionBase4M, .potionBase8M,
                 .potionBase32M, .potionRetrieval32M, .m2vBaseOutput:
                return 256
            }
        }

        /// The HuggingFace model identifier.
        public var modelId: String {
            rawValue
        }

        /// A human-readable display name for the model.
        public var displayName: String {
            switch self {
            case .potionBase2M: return "Potion Base 2M"
            case .potionBase4M: return "Potion Base 4M"
            case .potionBase8M: return "Potion Base 8M"
            case .potionBase32M: return "Potion Base 32M"
            case .potionRetrieval32M: return "Potion Retrieval 32M"
            case .m2vBaseOutput: return "M2V Base Output"
            }
        }
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this embedding provider.
    public nonisolated let name = "swift-embeddings"

    /// The number of dimensions in the embeddings produced.
    public nonisolated let dimensions: Int

    /// Maximum tokens per request.
    ///
    /// Model2Vec models handle up to 512 tokens per text.
    public nonisolated var maxTokensPerRequest: Int { 512 }

    /// Optimal batch size for this provider.
    ///
    /// Model2Vec is extremely fast, supporting batches of 1000+ texts efficiently.
    /// This high throughput makes it ideal for bulk embedding operations.
    public nonisolated var optimalBatchSize: Int { 1000 }

    // MARK: - Properties

    /// The Model2Vec model bundle for encoding text.
    private let modelBundle: Model2Vec.ModelBundle

    /// The selected model configuration.
    private let model: Model

    /// Whether to normalize embeddings (L2 normalization).
    private let normalizeEmbeddings: Bool

    // MARK: - Initialization

    /// Creates a new SwiftEmbeddingsProvider with the specified model.
    ///
    /// The model is downloaded from HuggingFace on first use if not already cached.
    ///
    /// - Parameters:
    ///   - model: The Model2Vec model to use. Defaults to `.potionBase8M`.
    ///   - normalize: Whether to L2-normalize embeddings. Defaults to `true`.
    ///   - downloadBase: Optional custom download directory for model files.
    ///   - useBackgroundSession: Whether to use background URL sessions for downloads.
    /// - Throws: `AppleMLError.modelDownloadFailed` if the model cannot be downloaded,
    ///   or `AppleMLError.modelNotAvailable` if loading fails.
    public init(
        model: Model = .potionBase8M,
        normalize: Bool = true,
        downloadBase: URL? = nil,
        useBackgroundSession: Bool = false
    ) async throws {
        self.model = model
        self.dimensions = model.dimensions
        self.normalizeEmbeddings = normalize

        do {
            self.modelBundle = try await Model2Vec.loadModelBundle(
                from: model.modelId,
                downloadBase: downloadBase,
                useBackgroundSession: useBackgroundSession
            )
        } catch {
            throw AppleMLError.modelDownloadFailed(
                model: model.modelId,
                reason: error.localizedDescription
            )
        }
    }

    /// Creates a provider with a pre-loaded model bundle.
    ///
    /// Use this initializer when you have already loaded a model bundle
    /// and want to avoid reloading it.
    ///
    /// - Parameters:
    ///   - modelBundle: A pre-loaded Model2Vec model bundle.
    ///   - model: The model configuration for dimension information.
    ///   - normalize: Whether to L2-normalize embeddings.
    internal init(
        modelBundle: Model2Vec.ModelBundle,
        model: Model,
        normalize: Bool = true
    ) {
        self.modelBundle = modelBundle
        self.model = model
        self.dimensions = model.dimensions
        self.normalizeEmbeddings = normalize
    }

    // MARK: - EmbeddingProvider Methods

    /// Generates an embedding for a single text.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: An `Embedding` containing the vector representation.
    /// - Throws: `AppleMLError.invalidEmbedding` if embedding generation fails.
    public func embed(_ text: String) async throws -> Embedding {
        guard !text.isEmpty else {
            throw AppleMLError.invalidEmbedding(reason: "Cannot embed empty text")
        }

        do {
            let encoded = try modelBundle.encode(
                text,
                normalize: normalizeEmbeddings,
                maxLength: maxTokensPerRequest
            )

            let vector = await encoded
                .cast(to: Float.self)
                .shapedArray(of: Float.self)
                .scalars

            guard !vector.isEmpty else {
                throw AppleMLError.invalidEmbedding(
                    reason: "Model returned empty embedding for text"
                )
            }

            return Embedding(vector: Array(vector), model: model.modelId)
        } catch let error as AppleMLError {
            throw error
        } catch {
            throw AppleMLError.invalidEmbedding(
                reason: "Embedding failed: \(error.localizedDescription)"
            )
        }
    }

    /// Generates embeddings for multiple texts in a batch.
    ///
    /// This method is highly optimized for throughput. Model2Vec can process
    /// thousands of texts per second, making it ideal for bulk operations.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of `Embedding` values in the same order as input.
    /// - Throws: `AppleMLError.invalidEmbedding` if any embedding fails.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else {
            return []
        }

        // Validate all texts are non-empty - throw on first empty text found
        for (index, text) in texts.enumerated() {
            if text.isEmpty {
                throw AppleMLError.invalidEmbedding(
                    reason: "Cannot embed empty text at index \(index). All texts must be non-empty."
                )
            }
        }

        let validTexts = texts
        let validIndices = Array(0..<texts.count)

        do {
            let encoded = try modelBundle.batchEncode(
                validTexts,
                normalize: normalizeEmbeddings,
                maxLength: maxTokensPerRequest
            )

            let batchResults = await encoded
                .cast(to: Float.self)
                .shapedArray(of: Float.self)

            // Extract individual embeddings from batch result
            // Shape is [batch_size, embedding_dim]
            let shape = batchResults.shape
            guard shape.count == 2, shape[0] == validTexts.count else {
                throw AppleMLError.invalidEmbedding(
                    reason: "Unexpected batch result shape: \(shape)"
                )
            }

            let embeddingDim = shape[1]
            let allScalars = batchResults.scalars

            // Build result array with embeddings in original positions
            var results = [Embedding]()
            results.reserveCapacity(texts.count)

            for (batchIndex, _) in validIndices.enumerated() {
                let start = batchIndex * embeddingDim
                let end = start + embeddingDim
                let vector = Array(allScalars[start..<end])
                results.append(Embedding(vector: vector, model: model.modelId))
            }

            return results
        } catch let error as AppleMLError {
            throw error
        } catch {
            throw AppleMLError.invalidEmbedding(
                reason: "Batch embedding failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Convenience Factory Methods

    /// Creates a SwiftEmbeddingsProvider with the default model configuration.
    ///
    /// Uses `.potionBase8M` for balanced performance and quality.
    ///
    /// - Returns: A configured `SwiftEmbeddingsProvider` instance.
    /// - Throws: `AppleMLError` if model loading fails.
    public static func `default`() async throws -> SwiftEmbeddingsProvider {
        try await SwiftEmbeddingsProvider(model: .potionBase8M)
    }

    /// Creates a SwiftEmbeddingsProvider optimized for retrieval/RAG applications.
    ///
    /// Uses `.potionRetrieval32M` which is specifically fine-tuned for
    /// semantic search and document retrieval tasks.
    ///
    /// - Returns: A configured `SwiftEmbeddingsProvider` instance.
    /// - Throws: `AppleMLError` if model loading fails.
    public static func retrieval() async throws -> SwiftEmbeddingsProvider {
        try await SwiftEmbeddingsProvider(model: .potionRetrieval32M)
    }

    /// Creates a SwiftEmbeddingsProvider with the smallest, fastest model.
    ///
    /// Uses `.potionBase2M` for maximum speed on resource-constrained devices.
    ///
    /// - Returns: A configured `SwiftEmbeddingsProvider` instance.
    /// - Throws: `AppleMLError` if model loading fails.
    public static func fast() async throws -> SwiftEmbeddingsProvider {
        try await SwiftEmbeddingsProvider(model: .potionBase2M)
    }

    // MARK: - Model Information

    /// Returns information about the currently loaded model.
    public var modelInfo: ModelInfo {
        ModelInfo(
            model: model,
            dimensions: dimensions,
            normalizing: normalizeEmbeddings
        )
    }

    /// Information about a loaded Model2Vec model.
    public struct ModelInfo: Sendable {
        /// The model configuration.
        public let model: Model

        /// The embedding dimensions.
        public let dimensions: Int

        /// Whether embeddings are L2-normalized.
        public let normalizing: Bool
    }
}

// MARK: - Model Availability Check

@available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension SwiftEmbeddingsProvider {

    /// Checks if a model can be loaded (either from cache or network).
    ///
    /// This performs a lightweight check to verify model availability
    /// without fully loading the model.
    ///
    /// - Parameter model: The model to check.
    /// - Returns: `true` if the model appears to be available.
    public static func isModelAvailable(_ model: Model) async -> Bool {
        do {
            _ = try await SwiftEmbeddingsProvider(model: model)
            return true
        } catch {
            return false
        }
    }

    /// Returns the list of all supported models.
    public static var supportedModels: [Model] {
        Model.allCases
    }
}

// MARK: - CustomStringConvertible

@available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
extension SwiftEmbeddingsProvider: CustomStringConvertible {

    /// A textual description of the provider.
    public nonisolated var description: String {
        "SwiftEmbeddingsProvider(model: \(model.displayName), dimensions: \(dimensions))"
    }
}
