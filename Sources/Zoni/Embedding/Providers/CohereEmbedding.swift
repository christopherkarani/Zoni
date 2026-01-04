// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// CohereEmbedding.swift - Cohere embedding API integration

import Foundation
import AsyncHTTPClient
import NIOCore

// MARK: - CohereEmbedding

/// An embedding provider using the Cohere Embed API.
///
/// `CohereEmbedding` integrates with Cohere's embedding models, which offer
/// excellent multilingual support and retrieval-optimized embeddings. It supports:
/// - Multiple embedding models for different use cases
/// - Input type specification (document vs query)
/// - Batch embedding with automatic truncation
///
/// Example usage:
/// ```swift
/// let cohere = CohereEmbedding(
///     apiKey: "...",
///     model: .embedMultilingualV3,
///     inputType: .searchDocument
/// )
///
/// // Embed documents for indexing
/// let docEmbeddings = try await cohere.embed([
///     "Premier document en français",
///     "Second document in English"
/// ])
///
/// // Embed query for search (uses different input type)
/// let queryEmbedding = try await cohere.embedQuery("recherche multilingue")
/// ```
///
/// ## Input Types
/// Cohere recommends using different input types for documents vs queries:
/// - `searchDocument`: For documents being indexed
/// - `searchQuery`: For search queries
/// - `classification`: For text classification
/// - `clustering`: For clustering tasks
public actor CohereEmbedding: EmbeddingProvider {

    // MARK: - Types

    /// Available Cohere embedding models.
    public enum Model: String, Sendable, CaseIterable {
        /// embed-english-v3.0: 1024 dimensions, optimized for English.
        case embedEnglishV3 = "embed-english-v3.0"

        /// embed-multilingual-v3.0: 1024 dimensions, 100+ languages.
        case embedMultilingualV3 = "embed-multilingual-v3.0"

        /// embed-english-light-v3.0: 384 dimensions, faster and cheaper.
        case embedEnglishLightV3 = "embed-english-light-v3.0"

        /// embed-multilingual-light-v3.0: 384 dimensions, multilingual light.
        case embedMultilingualLightV3 = "embed-multilingual-light-v3.0"

        /// The number of dimensions for this model.
        public var dimensions: Int {
            switch self {
            case .embedEnglishV3, .embedMultilingualV3:
                return 1024
            case .embedEnglishLightV3, .embedMultilingualLightV3:
                return 384
            }
        }

        /// Whether this model supports multiple languages.
        public var isMultilingual: Bool {
            switch self {
            case .embedMultilingualV3, .embedMultilingualLightV3:
                return true
            case .embedEnglishV3, .embedEnglishLightV3:
                return false
            }
        }
    }

    /// Input type for Cohere embeddings.
    ///
    /// Using the correct input type improves retrieval quality.
    public enum InputType: String, Sendable {
        /// For documents being indexed for search.
        case searchDocument = "search_document"

        /// For search queries.
        case searchQuery = "search_query"

        /// For text classification tasks.
        case classification = "classification"

        /// For clustering tasks.
        case clustering = "clustering"
    }

    /// Truncation strategy for long texts.
    public enum Truncate: String, Sendable {
        /// Truncate from the end (keep beginning).
        case end = "END"

        /// Truncate from the start (keep end).
        case start = "START"

        /// Do not truncate (may error on long texts).
        case none = "NONE"
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "cohere"

    /// The number of dimensions in embeddings.
    public nonisolated let dimensions: Int

    /// Maximum texts per batch (Cohere limit).
    public nonisolated var maxTokensPerRequest: Int { 96 }

    // MARK: - Private Properties

    /// The Cohere API key.
    private let apiKey: String

    /// The embedding model to use.
    private let model: Model

    /// The input type for embeddings.
    private let inputType: InputType

    /// Truncation strategy.
    private let truncate: Truncate

    /// HTTP client for API requests.
    private let httpClient: HTTPClient

    /// Rate limiter to prevent API throttling.
    private let rateLimiter: RateLimiter

    // MARK: - Initialization

    /// Creates a Cohere embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: Your Cohere API key.
    ///   - model: The embedding model to use. Defaults to embed-english-v3.0.
    ///   - inputType: The type of input being embedded. Defaults to searchDocument.
    ///   - truncate: Truncation strategy for long texts. Defaults to end.
    ///   - httpClient: Optional custom HTTP client.
    public init(
        apiKey: String,
        model: Model = .embedEnglishV3,
        inputType: InputType = .searchDocument,
        truncate: Truncate = .end,
        httpClient: HTTPClient? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.dimensions = model.dimensions
        self.inputType = inputType
        self.truncate = truncate
        self.httpClient = httpClient ?? HTTPClient.shared
        self.rateLimiter = RateLimiter.forCohere()
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
            throw ZoniError.embeddingFailed(reason: "No embedding returned from Cohere")
        }
        return first
    }

    /// Generates embeddings for multiple texts in a batch.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of embeddings in the same order as input.
    /// - Throws: `ZoniError.embeddingFailed` or `ZoniError.rateLimited` on failure.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }

        try await rateLimiter.acquire(permits: 1)

        var request = HTTPClientRequest(url: "https://api.cohere.ai/v1/embed")
        request.method = .POST
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.headers.add(name: "Content-Type", value: "application/json")

        let requestBody = CohereEmbedRequest(
            texts: texts,
            model: model.rawValue,
            inputType: inputType.rawValue,
            truncate: truncate.rawValue
        )
        let bodyData = try JSONEncoder().encode(requestBody)
        request.body = .bytes(ByteBuffer(data: bodyData))

        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(request, timeout: .seconds(60))
        } catch {
            throw ZoniError.embeddingFailed(reason: "Network error: \(error.localizedDescription)")
        }

        if response.status == .tooManyRequests {
            throw ZoniError.rateLimited(retryAfter: nil)
        }

        guard response.status == .ok else {
            let errorMessage = await parseErrorResponse(response)
            throw ZoniError.embeddingFailed(reason: "Cohere API error (\(response.status.code)): \(errorMessage)")
        }

        let responseData = try await response.body.collect(upTo: 50 * 1024 * 1024)
        let responseBody: CohereEmbedResponse
        do {
            responseBody = try JSONDecoder().decode(CohereEmbedResponse.self, from: responseData)
        } catch {
            throw ZoniError.embeddingFailed(reason: "Failed to parse Cohere response: \(error.localizedDescription)")
        }

        // Cohere returns embeddings in the same order as input
        return responseBody.embeddings.map { Embedding(vector: $0, model: model.rawValue) }
    }

    // MARK: - Query Embedding

    /// Embeds a query text using the searchQuery input type.
    ///
    /// This is a convenience method that creates a temporary provider
    /// with `inputType: .searchQuery` for embedding search queries.
    ///
    /// - Parameter text: The query text to embed.
    /// - Returns: The embedding optimized for query matching.
    public func embedQuery(_ text: String) async throws -> Embedding {
        // Create a query-specific provider
        let queryProvider = CohereEmbedding(
            apiKey: apiKey,
            model: model,
            inputType: .searchQuery,
            truncate: truncate,
            httpClient: httpClient
        )
        return try await queryProvider.embed(text)
    }

    // MARK: - Private Methods

    private func parseErrorResponse(_ response: HTTPClientResponse) async -> String {
        do {
            let data = try await response.body.collect(upTo: 10 * 1024)
            let errorResponse = try JSONDecoder().decode(CohereErrorResponse.self, from: data)
            return errorResponse.message
        } catch {
            return "Unknown error"
        }
    }
}

// MARK: - Request/Response Types

struct CohereEmbedRequest: Encodable {
    let texts: [String]
    let model: String
    let inputType: String
    let truncate: String

    enum CodingKeys: String, CodingKey {
        case texts, model, truncate
        case inputType = "input_type"
    }
}

struct CohereEmbedResponse: Decodable {
    let embeddings: [[Float]]
}

struct CohereErrorResponse: Decodable {
    let message: String
}
