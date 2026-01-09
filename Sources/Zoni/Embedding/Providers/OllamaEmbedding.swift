// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// OllamaEmbedding.swift - Ollama local embedding integration

import Foundation
import AsyncHTTPClient
import NIOCore

// MARK: - OllamaEmbedding

/// An embedding provider using locally-hosted Ollama.
///
/// `OllamaEmbedding` integrates with Ollama for self-hosted embeddings,
/// offering complete privacy and no API costs. It supports:
/// - Various open-source embedding models
/// - Health checking and availability verification
///
/// Example usage:
/// ```swift
/// let ollama = OllamaEmbedding(
///     baseURL: URL(string: "http://localhost:11434")!,
///     model: OllamaEmbedding.KnownModel.nomicEmbedText
/// )
///
/// // Check if Ollama is running
/// if await ollama.healthCheck() {
///     let embedding = try await ollama.embed("Hello world")
/// }
/// ```
///
/// ## Prerequisites
/// 1. Install Ollama: https://ollama.ai
/// 2. Pull an embedding model: `ollama pull nomic-embed-text`
/// 3. Start Ollama (usually runs automatically)
///
/// ## Performance Notes
/// - Ollama processes one text at a time (no native batching)
/// - Batch calls are executed sequentially
/// - Local models are typically slower than cloud APIs but have no rate limits
public actor OllamaEmbedding: EmbeddingProvider {

    // MARK: - Known Models

    /// Well-known Ollama embedding models with their dimensions.
    public enum KnownModel: Sendable {
        /// nomic-embed-text: 768 dimensions, good general-purpose model.
        public static let nomicEmbedText = "nomic-embed-text"

        /// all-minilm: 384 dimensions, smaller and faster.
        public static let allMiniLM = "all-minilm"

        /// mxbai-embed-large: 1024 dimensions, higher quality.
        public static let mxbaiEmbedLarge = "mxbai-embed-large"

        /// snowflake-arctic-embed: 1024 dimensions, retrieval-optimized.
        public static let snowflakeArcticEmbed = "snowflake-arctic-embed"

        /// bge-large: 1024 dimensions, BAAI general embedding.
        public static let bgeLarge = "bge-large"

        /// bge-m3: 1024 dimensions, multilingual.
        public static let bgeM3 = "bge-m3"

        /// Returns the expected dimensions for a known model name.
        public static func dimensions(for model: String) -> Int {
            switch model {
            case allMiniLM:
                return 384
            case mxbaiEmbedLarge, snowflakeArcticEmbed, bgeLarge, bgeM3:
                return 1024
            case nomicEmbedText:
                return 768
            default:
                return 768  // Common default for unknown models
            }
        }
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "ollama"

    /// The expected dimensions based on the configured model.
    public nonisolated let dimensions: Int

    /// Maximum texts per request (Ollama processes one at a time).
    public nonisolated var maxTokensPerRequest: Int { 1 }

    // MARK: - Properties

    /// The base URL of the Ollama server.
    private let baseURL: URL

    /// The model name to use.
    private let model: String

    /// HTTP client for API requests.
    private let httpClient: HTTPClient

    /// Request timeout duration.
    private let timeout: Duration

    // MARK: - Initialization

    /// Creates an Ollama embedding provider.
    ///
    /// - Parameters:
    ///   - baseURL: The Ollama server URL. Defaults to localhost:11434.
    ///   - model: The model name. Defaults to nomic-embed-text.
    ///   - dimensions: Override the expected dimensions. If nil, uses known model defaults.
    ///   - httpClient: Optional custom HTTP client.
    ///   - timeout: Request timeout. Defaults to 120 seconds for local processing.
    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = KnownModel.nomicEmbedText,
        dimensions: Int? = nil,
        httpClient: HTTPClient? = nil,
        timeout: Duration = .seconds(120)
    ) {
        self.baseURL = baseURL
        self.model = model
        self.dimensions = dimensions ?? KnownModel.dimensions(for: model)
        self.httpClient = httpClient ?? HTTPClient.shared
        self.timeout = timeout
    }

    // MARK: - EmbeddingProvider Methods

    /// Generates an embedding for a single text.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: The embedding vector.
    /// - Throws: `ZoniError.embeddingFailed` or `ZoniError.embeddingProviderUnavailable`.
    public func embed(_ text: String) async throws -> Embedding {
        var request = HTTPClientRequest(url: "\(baseURL.absoluteString)/api/embeddings")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")

        let requestBody = OllamaEmbedRequest(model: model, prompt: text)
        let bodyData = try JSONEncoder().encode(requestBody)
        request.body = .bytes(ByteBuffer(data: bodyData))

        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(
                request,
                timeout: .seconds(Int64(timeout.components.seconds))
            )
        } catch {
            throw ZoniError.embeddingProviderUnavailable(
                name: "ollama (\(baseURL.host ?? "localhost"):\(baseURL.port ?? 11434))"
            )
        }

        guard response.status == .ok else {
            let errorMessage = await parseErrorResponse(response)
            throw ZoniError.embeddingFailed(reason: "Ollama error (\(response.status.code)): \(errorMessage)")
        }

        let responseData = try await response.body.collect(upTo: 10 * 1024 * 1024)
        let responseBody: OllamaEmbedResponse
        do {
            responseBody = try JSONDecoder().decode(OllamaEmbedResponse.self, from: responseData)
        } catch {
            throw ZoniError.embeddingFailed(reason: "Failed to parse Ollama response: \(error.localizedDescription)")
        }

        return Embedding(vector: responseBody.embedding, model: model)
    }

    /// Generates embeddings for multiple texts.
    ///
    /// Note: Ollama doesn't support batch embedding, so texts are processed sequentially.
    /// Cancellation is checked between each embedding to support cooperative cancellation.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of embeddings in the same order as input.
    /// - Throws: `CancellationError` if the task is cancelled during processing.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        var embeddings: [Embedding] = []
        embeddings.reserveCapacity(texts.count)

        for text in texts {
            // Check for cancellation between each embedding request
            try Task.checkCancellation()

            let embedding = try await embed(text)
            embeddings.append(embedding)
        }

        return embeddings
    }

    // MARK: - Health & Availability

    /// Checks if Ollama is running and the model is available.
    ///
    /// - Returns: `true` if Ollama responds successfully, `false` otherwise.
    public func healthCheck() async -> Bool {
        do {
            _ = try await embed("health check")
            return true
        } catch {
            return false
        }
    }

    /// Checks if a specific model is available on the Ollama server.
    ///
    /// - Parameter modelName: The model to check. Defaults to the configured model.
    /// - Returns: `true` if the model is available.
    public func isModelAvailable(_ modelName: String? = nil) async -> Bool {
        let targetModel = modelName ?? model

        var request = HTTPClientRequest(url: "\(baseURL.absoluteString)/api/tags")
        request.method = .GET

        do {
            let response = try await httpClient.execute(request, timeout: .seconds(10))
            guard response.status == .ok else { return false }

            let data = try await response.body.collect(upTo: 1024 * 1024)
            let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)

            return tagsResponse.models.contains { $0.name.hasPrefix(targetModel) }
        } catch {
            return false
        }
    }

    /// Gets information about available models on the Ollama server.
    ///
    /// - Returns: A list of available model names.
    public func listModels() async -> [String] {
        var request = HTTPClientRequest(url: "\(baseURL.absoluteString)/api/tags")
        request.method = .GET

        do {
            let response = try await httpClient.execute(request, timeout: .seconds(10))
            guard response.status == .ok else { return [] }

            let data = try await response.body.collect(upTo: 1024 * 1024)
            let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)

            return tagsResponse.models.map { $0.name }
        } catch {
            return []
        }
    }

    // MARK: - Private Methods

    private func parseErrorResponse(_ response: HTTPClientResponse) async -> String {
        do {
            let data = try await response.body.collect(upTo: 10 * 1024)
            if let errorString = String(data: Data(buffer: data), encoding: .utf8) {
                return errorString
            }
            return "Unknown error"
        } catch {
            return "Unknown error"
        }
    }
}

// MARK: - Request/Response Types

struct OllamaEmbedRequest: Encodable {
    let model: String
    let prompt: String
}

struct OllamaEmbedResponse: Decodable {
    let embedding: [Float]
}

struct OllamaTagsResponse: Decodable {
    let models: [ModelInfo]

    struct ModelInfo: Decodable {
        let name: String
    }
}
