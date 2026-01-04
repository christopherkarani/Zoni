// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// OpenAIEmbedding.swift - OpenAI embedding API integration

import Foundation
import AsyncHTTPClient
import NIOCore

// MARK: - OpenAIEmbedding

/// An embedding provider using the OpenAI Embeddings API.
///
/// `OpenAIEmbedding` integrates with OpenAI's text-embedding models to generate
/// high-quality vector representations of text. It supports:
/// - Multiple embedding models with different dimension/quality tradeoffs
/// - Batch embedding for efficient processing
/// - Built-in rate limiting to prevent API throttling
///
/// Example usage:
/// ```swift
/// let openai = OpenAIEmbedding(
///     apiKey: "sk-...",
///     model: .textEmbedding3Small
/// )
///
/// // Single embedding
/// let embedding = try await openai.embed("Hello world")
///
/// // Batch embedding (more efficient)
/// let embeddings = try await openai.embed([
///     "First document",
///     "Second document"
/// ])
/// ```
///
/// ## Security
/// Never log or expose the API key. It is stored privately and only used
/// in the Authorization header of API requests.
///
/// ## Thread Safety
/// Implemented as an actor for safe concurrent use.
public actor OpenAIEmbedding: EmbeddingProvider {

    // MARK: - Types

    /// Available OpenAI embedding models.
    public enum Model: String, Sendable, CaseIterable {
        /// text-embedding-3-small: 1536 dimensions, $0.02 per 1M tokens
        /// Best for most use cases - good quality at low cost.
        case textEmbedding3Small = "text-embedding-3-small"

        /// text-embedding-3-large: 3072 dimensions, $0.13 per 1M tokens
        /// Higher quality for demanding applications.
        case textEmbedding3Large = "text-embedding-3-large"

        /// text-embedding-ada-002: 1536 dimensions (legacy)
        /// Previous generation model, still supported.
        case textEmbeddingAda002 = "text-embedding-ada-002"

        /// The number of dimensions for this model.
        public var dimensions: Int {
            switch self {
            case .textEmbedding3Small, .textEmbeddingAda002:
                return 1536
            case .textEmbedding3Large:
                return 3072
            }
        }

        /// Human-readable description of the model.
        public var description: String {
            switch self {
            case .textEmbedding3Small:
                return "OpenAI text-embedding-3-small (1536 dims)"
            case .textEmbedding3Large:
                return "OpenAI text-embedding-3-large (3072 dims)"
            case .textEmbeddingAda002:
                return "OpenAI text-embedding-ada-002 (1536 dims, legacy)"
            }
        }
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "openai"

    /// The number of dimensions in embeddings.
    public nonisolated let dimensions: Int

    /// Maximum tokens per request (OpenAI limit).
    public nonisolated var maxTokensPerRequest: Int { 8191 }

    // MARK: - Private Properties

    /// The OpenAI API key.
    private let apiKey: String

    /// The embedding model to use.
    private let model: Model

    /// HTTP client for API requests.
    private let httpClient: HTTPClient

    /// Rate limiter to prevent API throttling.
    private let rateLimiter: RateLimiter

    /// Base URL for the OpenAI API.
    private let baseURL: String

    // MARK: - Initialization

    /// Creates an OpenAI embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenAI API key. Keep this secret!
    ///   - model: The embedding model to use. Defaults to text-embedding-3-small.
    ///   - httpClient: Optional custom HTTP client. Defaults to shared client.
    ///   - baseURL: Optional custom base URL (useful for proxies).
    public init(
        apiKey: String,
        model: Model = .textEmbedding3Small,
        httpClient: HTTPClient? = nil,
        baseURL: String = "https://api.openai.com/v1"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.dimensions = model.dimensions
        self.httpClient = httpClient ?? HTTPClient.shared
        self.rateLimiter = RateLimiter.forOpenAI()
        self.baseURL = baseURL
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
            throw ZoniError.embeddingFailed(reason: "No embedding returned from OpenAI")
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
        try await rateLimiter.acquire(permits: texts.count)

        // Build request
        var request = HTTPClientRequest(url: "\(baseURL)/embeddings")
        request.method = .POST
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.headers.add(name: "Content-Type", value: "application/json")

        let requestBody = OpenAIEmbeddingRequest(
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
            throw ZoniError.embeddingFailed(reason: "OpenAI API error (\(response.status.code)): \(errorMessage)")
        }

        // Parse response
        let responseData = try await response.body.collect(upTo: 50 * 1024 * 1024)
        let responseBody: OpenAIEmbeddingResponse
        do {
            responseBody = try JSONDecoder().decode(OpenAIEmbeddingResponse.self, from: responseData)
        } catch {
            throw ZoniError.embeddingFailed(reason: "Failed to parse OpenAI response: \(error.localizedDescription)")
        }

        // Sort by index (OpenAI may return in different order) and convert to Embeddings
        return responseBody.data
            .sorted { $0.index < $1.index }
            .map { Embedding(vector: $0.embedding, model: model.rawValue) }
    }

    // MARK: - Private Methods

    /// Parses an error response body for a human-readable message.
    private func parseErrorResponse(_ response: HTTPClientResponse) async -> String {
        do {
            let data = try await response.body.collect(upTo: 10 * 1024)
            let errorResponse = try JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            return errorResponse.error.message
        } catch {
            return "Unknown error"
        }
    }
}

// MARK: - Request/Response Types

/// OpenAI embedding request body.
struct OpenAIEmbeddingRequest: Encodable {
    let model: String
    let input: [String]
}

/// OpenAI embedding response body.
struct OpenAIEmbeddingResponse: Decodable {
    let data: [EmbeddingData]
    let usage: Usage

    struct EmbeddingData: Decodable {
        let embedding: [Float]
        let index: Int
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

/// OpenAI error response body.
struct OpenAIErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
        let type: String?
        let code: String?
    }
}
