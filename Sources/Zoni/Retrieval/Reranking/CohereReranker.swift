// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// CohereReranker.swift - Cohere Rerank API integration

import Foundation
import AsyncHTTPClient
import NIOCore

// MARK: - CohereReranker

/// A reranker using the Cohere Rerank API.
///
/// `CohereReranker` uses Cohere's cross-encoder models to rerank
/// retrieval results for improved relevance.
///
/// ## Supported Models
///
/// - `rerank-english-v3.0`: Latest English model (recommended)
/// - `rerank-multilingual-v3.0`: Multilingual model
/// - `rerank-english-v2.0`: Legacy English model
///
/// ## Example Usage
///
/// ```swift
/// let reranker = CohereReranker(
///     apiKey: "your-api-key",
///     model: .rerankEnglishV3
/// )
///
/// let reranked = try await reranker.rerank(
///     query: "What is Swift?",
///     results: retrievalResults
/// )
/// ```
public actor CohereReranker: Reranker {

    // MARK: - Model Enum

    /// Cohere rerank model options.
    public enum Model: String, Sendable, CaseIterable {
        case rerankEnglishV3 = "rerank-english-v3.0"
        case rerankMultilingualV3 = "rerank-multilingual-v3.0"
        case rerankEnglishV2 = "rerank-english-v2.0"
    }

    // MARK: - Properties

    /// The name of this reranker.
    public nonisolated let name = "cohere"

    /// The API key for Cohere.
    private let apiKey: String

    /// The model to use for reranking.
    private let model: Model

    /// HTTP client for API requests.
    private let httpClient: HTTPClient

    /// Rate limiter to prevent throttling.
    private let rateLimiter: RateLimiter

    /// API endpoint URL.
    private static let apiURL = "https://api.cohere.ai/v1/rerank"

    // MARK: - Initialization

    /// Creates a new Cohere reranker.
    ///
    /// - Parameters:
    ///   - apiKey: Your Cohere API key.
    ///   - model: The rerank model to use. Default: `.rerankEnglishV3`
    ///   - httpClient: Optional custom HTTP client.
    public init(
        apiKey: String,
        model: Model = .rerankEnglishV3,
        httpClient: HTTPClient? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = httpClient ?? HTTPClient.shared
        self.rateLimiter = RateLimiter.forCohere()
    }

    // MARK: - Reranker Protocol

    /// Reranks results using the Cohere Rerank API.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - results: The results to rerank.
    /// - Returns: Reranked results with updated scores.
    /// - Throws: `ZoniError.retrievalFailed` if the API call fails.
    public func rerank(
        query: String,
        results: [RetrievalResult]
    ) async throws -> [RetrievalResult] {
        guard !results.isEmpty else { return [] }

        // Rate limit
        try await rateLimiter.acquire()

        // Prepare request
        let documents = results.map { $0.chunk.content }

        var request = HTTPClientRequest(url: Self.apiURL)
        request.method = .POST
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.headers.add(name: "Content-Type", value: "application/json")

        let body = CohereRerankRequest(
            query: query,
            documents: documents,
            model: model.rawValue,
            topN: results.count,
            returnDocuments: false
        )

        let bodyData = try JSONEncoder().encode(body)
        request.body = .bytes(ByteBuffer(data: bodyData))

        // Execute request
        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(request, timeout: .seconds(30))
        } catch {
            throw ZoniError.retrievalFailed(reason: "Cohere API request failed: \(error.localizedDescription)")
        }

        // Check for rate limiting with Retry-After header parsing
        if response.status == .tooManyRequests {
            let retryAfter: Duration?
            if let retryAfterHeader = response.headers.first(name: "Retry-After"),
               let seconds = Int(retryAfterHeader) {
                retryAfter = .seconds(seconds)
            } else if let resetHeader = response.headers.first(name: "X-RateLimit-Reset"),
                      let timestamp = TimeInterval(resetHeader) {
                let waitTime = timestamp - Date().timeIntervalSince1970
                retryAfter = waitTime > 0 ? .seconds(Int64(waitTime)) : nil
            } else {
                retryAfter = nil
            }
            throw ZoniError.rateLimited(retryAfter: retryAfter)
        }

        // Check status
        guard response.status == .ok else {
            let errorMessage = await parseErrorResponse(response)
            throw ZoniError.retrievalFailed(reason: "Cohere API error (\(response.status.code)): \(errorMessage)")
        }

        // Parse response
        let responseBody = try await response.body.collect(upTo: 10 * 1024 * 1024)
        let rerankResponse: CohereRerankResponse
        do {
            rerankResponse = try JSONDecoder().decode(CohereRerankResponse.self, from: responseBody)
        } catch {
            throw ZoniError.retrievalFailed(reason: "Failed to parse Cohere response: \(error.localizedDescription)")
        }

        // Map results back with new scores (with bounds checking)
        let rerankedResults = rerankResponse.results.compactMap { item -> RetrievalResult? in
            // Validate index is within bounds
            guard item.index >= 0, item.index < results.count else {
                // Skip invalid indices from API response
                return nil
            }
            return RetrievalResult(
                chunk: results[item.index].chunk,
                score: item.relevanceScore,
                metadata: results[item.index].metadata
            )
        }

        // Ensure we got valid results
        guard !rerankedResults.isEmpty else {
            throw ZoniError.retrievalFailed(reason: "Cohere API returned no valid results")
        }

        return rerankedResults
    }

    // MARK: - Private Methods

    private func parseErrorResponse(_ response: HTTPClientResponse) async -> String {
        do {
            let data = try await response.body.collect(upTo: 10 * 1024)
            let errorResponse = try JSONDecoder().decode(CohereRerankErrorResponse.self, from: data)
            return errorResponse.message
        } catch {
            return "Unknown error"
        }
    }
}

// MARK: - API Types

/// Request body for Cohere Rerank API.
private struct CohereRerankRequest: Encodable {
    let query: String
    let documents: [String]
    let model: String
    let topN: Int
    let returnDocuments: Bool

    enum CodingKeys: String, CodingKey {
        case query, documents, model
        case topN = "top_n"
        case returnDocuments = "return_documents"
    }
}

/// Response from Cohere Rerank API.
private struct CohereRerankResponse: Decodable {
    let results: [CohereRerankResult]
}

/// Individual result from Cohere Rerank API.
private struct CohereRerankResult: Decodable {
    let index: Int
    let relevanceScore: Float

    enum CodingKeys: String, CodingKey {
        case index
        case relevanceScore = "relevance_score"
    }
}

/// Error response from Cohere API.
private struct CohereRerankErrorResponse: Decodable {
    let message: String
}
