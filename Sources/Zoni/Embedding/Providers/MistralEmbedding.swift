// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MistralEmbedding.swift - Mistral AI embedding API integration

import Foundation
import AsyncHTTPClient
import NIOCore

// MARK: - MistralEmbedding

/// An embedding provider using the Mistral AI Embeddings API.
///
/// `MistralEmbedding` integrates with Mistral AI's embedding models to generate
/// high-quality vector representations of text. It supports:
/// - The mistral-embed model optimized for retrieval tasks
/// - Batch embedding for efficient processing
/// - Built-in rate limiting to prevent API throttling
///
/// Example usage:
/// ```swift
/// let mistral = MistralEmbedding(apiKey: "...")
///
/// // Single embedding
/// let embedding = try await mistral.embed("Hello world")
///
/// // Batch embedding (more efficient)
/// let embeddings = try await mistral.embed([
///     "First document",
///     "Second document"
/// ])
/// ```
///
/// ## Important Note on Response Ordering
/// Mistral may return embeddings in a different order than the input texts.
/// This provider automatically sorts responses by their index to ensure
/// the returned embeddings match the input order.
///
/// ## Security
/// Never log or expose the API key. It is stored privately and only used
/// in the Authorization header of API requests.
///
/// ## Thread Safety
/// Implemented as an actor for safe concurrent use.
public actor MistralEmbedding: EmbeddingProvider {

    // MARK: - Types

    /// Available Mistral embedding models.
    public enum Model: String, Sendable, CaseIterable {
        /// mistral-embed: 1024 dimensions, optimized for retrieval.
        /// Best for semantic search and RAG applications.
        case mistralEmbed = "mistral-embed"

        /// The number of dimensions for this model.
        public var dimensions: Int {
            switch self {
            case .mistralEmbed:
                return 1024
            }
        }

        /// Human-readable description of the model.
        public var description: String {
            switch self {
            case .mistralEmbed:
                return "Mistral mistral-embed (1024 dims)"
            }
        }
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "mistral"

    /// The number of dimensions in embeddings.
    ///
    /// The mistral-embed model produces 1024-dimensional vectors.
    public nonisolated let dimensions: Int

    /// Maximum tokens per request (Mistral limit).
    ///
    /// Mistral supports up to 8192 tokens per request.
    public nonisolated var maxTokensPerRequest: Int { 8192 }

    /// The optimal batch size for this provider.
    ///
    /// Mistral recommends batches of up to 32 texts for optimal throughput.
    public nonisolated var optimalBatchSize: Int { 32 }

    // MARK: - Private Properties

    /// The Mistral API key.
    private let apiKey: String

    /// The embedding model to use.
    private let model: Model

    /// Base URL for the Mistral API.
    private let baseURL: URL

    /// HTTP client for API requests.
    private let httpClient: HTTPClient

    /// Rate limiter to prevent API throttling.
    private let rateLimiter: RateLimiter

    // MARK: - Initialization

    /// Creates a Mistral AI embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: Your Mistral AI API key. Keep this secret!
    ///   - model: The embedding model to use. Defaults to mistral-embed.
    ///   - httpClient: Optional custom HTTP client. Defaults to shared client.
    public init(
        apiKey: String,
        model: Model = .mistralEmbed,
        httpClient: HTTPClient? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.dimensions = model.dimensions
        self.baseURL = URL(string: "https://api.mistral.ai/v1/embeddings")!
        self.httpClient = httpClient ?? HTTPClient.shared
        self.rateLimiter = RateLimiter.forMistral()
    }

    // MARK: - EmbeddingProvider Methods

    /// Generates an embedding for a single text.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: The embedding vector.
    /// - Throws: `ZoniError.embeddingFailed` or `ZoniError.rateLimited` on failure.
    public func embed(_ text: String) async throws -> Embedding {
        let embeddings = try await embed([text])
        guard let first = embeddings.first else {
            throw ZoniError.embeddingFailed(reason: "No embedding returned from Mistral")
        }
        return first
    }

    /// Generates embeddings for multiple texts in a batch.
    ///
    /// Batch embedding is more efficient than calling `embed(_:)` repeatedly.
    /// The returned embeddings are in the same order as the input texts.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of embeddings in the same order as input.
    /// - Throws: `ZoniError.embeddingFailed` or `ZoniError.rateLimited` on failure.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }

        // Acquire rate limit permits
        try await rateLimiter.acquire(permits: 1)

        // Build request
        var request = HTTPClientRequest(url: baseURL.absoluteString)
        request.method = .POST
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.headers.add(name: "Content-Type", value: "application/json")

        let requestBody = MistralEmbedRequest(
            model: model.rawValue,
            input: texts
        )
        let bodyData = try JSONEncoder().encode(requestBody)
        request.body = .bytes(ByteBuffer(data: bodyData))

        // Execute request
        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(request, timeout: .seconds(60))
        } catch {
            throw ZoniError.embeddingFailed(reason: "Network error: \(error.localizedDescription)")
        }

        // Handle rate limiting
        if response.status == .tooManyRequests {
            let retryAfter = response.headers.first(name: "Retry-After")
                .flatMap { Double($0) }
                .map { Duration.seconds($0) }
            throw ZoniError.rateLimited(retryAfter: retryAfter)
        }

        // Handle errors
        guard response.status == .ok else {
            let errorMessage = await parseErrorResponse(response)
            throw ZoniError.embeddingFailed(reason: "Mistral API error (\(response.status.code)): \(errorMessage)")
        }

        // Parse response
        let responseData = try await response.body.collect(upTo: 50 * 1024 * 1024)
        let responseBody: MistralEmbedResponse
        do {
            responseBody = try JSONDecoder().decode(MistralEmbedResponse.self, from: responseData)
        } catch {
            throw ZoniError.embeddingFailed(reason: "Failed to parse Mistral response: \(error.localizedDescription)")
        }

        // Sort by index (Mistral may return in different order) and convert to Embeddings
        return responseBody.data
            .sorted { $0.index < $1.index }
            .map { Embedding(vector: $0.embedding, model: model.rawValue) }
    }

    // MARK: - Private Methods

    /// Parses an error response body for a human-readable message.
    private func parseErrorResponse(_ response: HTTPClientResponse) async -> String {
        do {
            let data = try await response.body.collect(upTo: 10 * 1024)
            let errorResponse = try JSONDecoder().decode(MistralErrorResponse.self, from: data)
            return errorResponse.message ?? errorResponse.detail ?? "Unknown error"
        } catch {
            return "Unknown error"
        }
    }
}

// MARK: - Request/Response Types

/// Mistral embedding request body.
struct MistralEmbedRequest: Encodable {
    let model: String
    let input: [String]
}

/// Mistral embedding response body.
struct MistralEmbedResponse: Decodable {
    let data: [EmbeddingData]

    struct EmbeddingData: Decodable {
        let embedding: [Float]
        let index: Int
    }
}

/// Mistral error response body.
struct MistralErrorResponse: Decodable {
    let message: String?
    let detail: String?
}
