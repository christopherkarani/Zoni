// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// VoyageEmbedding.swift - Voyage AI embedding API integration

import Foundation
import AsyncHTTPClient
import NIOCore

// MARK: - VoyageEmbedding

/// An embedding provider using the Voyage AI Embeddings API.
///
/// `VoyageEmbedding` integrates with Voyage AI's embedding models, which are
/// specifically optimized for retrieval tasks. It offers:
/// - Domain-specific models (code, law, finance)
/// - High-quality retrieval-optimized embeddings
/// - Input type distinction for documents vs queries
///
/// Example usage:
/// ```swift
/// let voyage = VoyageEmbedding(
///     apiKey: "...",
///     model: .voyage3
/// )
///
/// // Embed documents
/// let embeddings = try await voyage.embed([
///     "First document content",
///     "Second document content"
/// ])
///
/// // Embed query
/// let queryEmbedding = try await voyage.embedQuery("search query")
/// ```
///
/// ## Domain-Specific Models
/// Voyage offers specialized models for specific domains:
/// - `voyageCode2`: Optimized for code and technical documentation
/// - `voyageFinance2`: Optimized for financial documents
/// - `voyageLaw2`: Optimized for legal documents
public actor VoyageEmbedding: EmbeddingProvider {

    // MARK: - Types

    /// Available Voyage AI embedding models.
    public enum Model: String, Sendable, CaseIterable {
        /// voyage-3: 1024 dimensions, best quality general model.
        case voyage3 = "voyage-3"

        /// voyage-3-lite: 512 dimensions, faster and cheaper.
        case voyage3Lite = "voyage-3-lite"

        /// voyage-2: 1024 dimensions, previous generation.
        case voyage2 = "voyage-2"

        /// voyage-code-2: 1024 dimensions, optimized for code.
        case voyageCode2 = "voyage-code-2"

        /// voyage-finance-2: 1024 dimensions, optimized for finance.
        case voyageFinance2 = "voyage-finance-2"

        /// voyage-law-2: 1024 dimensions, optimized for legal.
        case voyageLaw2 = "voyage-law-2"

        /// The number of dimensions for this model.
        public var dimensions: Int {
            switch self {
            case .voyage3Lite:
                return 512
            default:
                return 1024
            }
        }

        /// Whether this model is domain-specific.
        public var isDomainSpecific: Bool {
            switch self {
            case .voyageCode2, .voyageFinance2, .voyageLaw2:
                return true
            default:
                return false
            }
        }

        /// The domain this model is optimized for.
        public var domain: String? {
            switch self {
            case .voyageCode2:
                return "code"
            case .voyageFinance2:
                return "finance"
            case .voyageLaw2:
                return "legal"
            default:
                return nil
            }
        }
    }

    /// Input type for Voyage embeddings.
    public enum InputType: String, Sendable {
        /// For documents being indexed.
        case document = "document"

        /// For search queries.
        case query = "query"
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "voyage"

    /// The number of dimensions in embeddings.
    public nonisolated let dimensions: Int

    /// Maximum texts per batch (Voyage limit).
    public nonisolated var maxTokensPerRequest: Int { 128 }

    // MARK: - Private Properties

    /// The Voyage API key.
    private let apiKey: String

    /// The embedding model to use.
    private let model: Model

    /// The input type for embeddings.
    private let inputType: InputType

    /// HTTP client for API requests.
    private let httpClient: HTTPClient

    /// Rate limiter to prevent API throttling.
    private let rateLimiter: RateLimiter

    // MARK: - Initialization

    /// Creates a Voyage AI embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: Your Voyage AI API key.
    ///   - model: The embedding model to use. Defaults to voyage-3.
    ///   - inputType: The type of input being embedded. Defaults to document.
    ///   - httpClient: Optional custom HTTP client.
    public init(
        apiKey: String,
        model: Model = .voyage3,
        inputType: InputType = .document,
        httpClient: HTTPClient? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.dimensions = model.dimensions
        self.inputType = inputType
        self.httpClient = httpClient ?? HTTPClient.shared
        self.rateLimiter = RateLimiter.forVoyage()
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
            throw ZoniError.embeddingFailed(reason: "No embedding returned from Voyage")
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

        var request = HTTPClientRequest(url: "https://api.voyageai.com/v1/embeddings")
        request.method = .POST
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.headers.add(name: "Content-Type", value: "application/json")

        let requestBody = VoyageEmbedRequest(
            input: texts,
            model: model.rawValue,
            inputType: inputType.rawValue
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
            let retryAfter = response.headers.first(name: "Retry-After")
                .flatMap { Double($0) }
                .map { Duration.seconds($0) }
            throw ZoniError.rateLimited(retryAfter: retryAfter)
        }

        guard response.status == .ok else {
            let errorMessage = await parseErrorResponse(response)
            throw ZoniError.embeddingFailed(reason: "Voyage API error (\(response.status.code)): \(errorMessage)")
        }

        let responseData = try await response.body.collect(upTo: 50 * 1024 * 1024)
        let responseBody: VoyageEmbedResponse
        do {
            responseBody = try JSONDecoder().decode(VoyageEmbedResponse.self, from: responseData)
        } catch {
            throw ZoniError.embeddingFailed(reason: "Failed to parse Voyage response: \(error.localizedDescription)")
        }

        // Sort by index to ensure correct order
        return responseBody.data
            .sorted { $0.index < $1.index }
            .map { Embedding(vector: $0.embedding, model: model.rawValue) }
    }

    // MARK: - Query Embedding

    /// Embeds a query text using the query input type.
    ///
    /// - Parameter text: The query text to embed.
    /// - Returns: The embedding optimized for query matching.
    public func embedQuery(_ text: String) async throws -> Embedding {
        let queryProvider = VoyageEmbedding(
            apiKey: apiKey,
            model: model,
            inputType: .query,
            httpClient: httpClient
        )
        return try await queryProvider.embed(text)
    }

    // MARK: - Private Methods

    private func parseErrorResponse(_ response: HTTPClientResponse) async -> String {
        do {
            let data = try await response.body.collect(upTo: 10 * 1024)
            let errorResponse = try JSONDecoder().decode(VoyageErrorResponse.self, from: data)
            return errorResponse.detail ?? "Unknown error"
        } catch {
            return "Unknown error"
        }
    }
}

// MARK: - Request/Response Types

struct VoyageEmbedRequest: Encodable {
    let input: [String]
    let model: String
    let inputType: String

    enum CodingKeys: String, CodingKey {
        case input, model
        case inputType = "input_type"
    }
}

struct VoyageEmbedResponse: Decodable {
    let data: [EmbeddingData]

    struct EmbeddingData: Decodable {
        let embedding: [Float]
        let index: Int
    }
}

struct VoyageErrorResponse: Decodable {
    let detail: String?
}
