// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// QdrantStore.swift - A Qdrant cloud vector store implementation.

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

// MARK: - QdrantStore

/// A Qdrant cloud vector store implementation for high-performance similarity search.
///
/// `QdrantStore` provides integration with Qdrant, a modern vector database designed
/// for production-ready similarity search. This implementation uses the Qdrant REST API
/// via `AsyncHTTPClient` for non-blocking network operations.
///
/// ## Key Features
///
/// - **Cloud-Ready**: Connect to Qdrant Cloud or self-hosted instances
/// - **High Performance**: Optimized for large-scale vector operations
/// - **Filtering**: Full support for metadata filtering during search
/// - **Async/Await**: Built with Swift concurrency for efficient resource usage
///
/// ## Thread Safety
///
/// This store is implemented as an `actor`, ensuring safe concurrent access
/// from multiple tasks. All operations are serialized through the actor's
/// isolation, preventing data races.
///
/// ## Qdrant REST API Endpoints Used
///
/// - `PUT /collections/{name}` - Create collection
/// - `PUT /collections/{name}/points` - Upsert points (add/update vectors)
/// - `POST /collections/{name}/points/search` - Similarity search
/// - `POST /collections/{name}/points/delete` - Delete points
/// - `POST /collections/{name}/points/count` - Count points
///
/// ## Example Usage
///
/// ```swift
/// // Create a Qdrant store connected to Qdrant Cloud
/// let store = QdrantStore(
///     baseURL: URL(string: "https://your-cluster.qdrant.io")!,
///     collectionName: "documents",
///     apiKey: "your-api-key"
/// )
///
/// // Ensure the collection exists with the correct dimensions
/// try await store.ensureCollection(dimensions: 1536)
///
/// // Add chunks with embeddings
/// let chunks = [
///     Chunk(content: "Swift is a powerful language...",
///           metadata: ChunkMetadata(documentId: "doc1", index: 0)),
///     Chunk(content: "Concurrency in Swift uses async/await...",
///           metadata: ChunkMetadata(documentId: "doc1", index: 1))
/// ]
/// let embeddings = try await embedder.embed(chunks.map { $0.content })
/// try await store.add(chunks, embeddings: embeddings)
///
/// // Search for similar chunks
/// let queryEmbedding = try await embedder.embed("How does Swift handle concurrency?")
/// let results = try await store.search(query: queryEmbedding, limit: 5, filter: nil)
///
/// for result in results {
///     print("Score: \(result.score), Content: \(result.chunk.content)")
/// }
///
/// // Filter by metadata
/// let filter = MetadataFilter.equals("documentId", "doc1")
/// let filteredResults = try await store.search(query: queryEmbedding, limit: 5, filter: filter)
/// ```
///
/// ## Connection Configuration
///
/// For Qdrant Cloud:
/// ```swift
/// let store = QdrantStore(
///     baseURL: URL(string: "https://your-cluster-id.qdrant.io:6333")!,
///     collectionName: "my_collection",
///     apiKey: "your-qdrant-cloud-api-key"
/// )
/// ```
///
/// For self-hosted Qdrant:
/// ```swift
/// let store = QdrantStore(
///     baseURL: URL(string: "http://localhost:6333")!,
///     collectionName: "my_collection"
/// )
/// ```
///
/// ## Performance Considerations
///
/// - **Batch Operations**: The `add` method handles batches efficiently
/// - **Connection Pooling**: Uses shared `HTTPClient` for connection reuse
/// - **Timeouts**: Configurable timeouts for different operation types
public actor QdrantStore: VectorStore {

    // MARK: - Properties

    /// The name identifier for this vector store implementation.
    ///
    /// This is used for logging, debugging, and configuration purposes.
    public nonisolated let name = "qdrant"

    /// The base URL of the Qdrant server.
    ///
    /// For Qdrant Cloud, this is typically `https://your-cluster.qdrant.io`.
    /// For self-hosted instances, this might be `http://localhost:6333`.
    private let baseURL: URL

    /// The name of the Qdrant collection to use.
    ///
    /// A collection in Qdrant is similar to a table in a relational database.
    /// It stores vectors with their payloads and supports similarity search.
    private let collectionName: String

    /// Optional API key for authenticating with Qdrant Cloud.
    ///
    /// Required for Qdrant Cloud deployments. For self-hosted instances
    /// without authentication, this can be `nil`.
    private let apiKey: String?

    /// The HTTP client used for making requests to the Qdrant API.
    ///
    /// By default, uses `HTTPClient.shared` for connection pooling benefits.
    /// A custom client can be provided for testing or specific configurations.
    private let httpClient: HTTPClient

    // MARK: - Initialization

    /// Creates a Qdrant vector store.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL of the Qdrant server (e.g., "https://your-cluster.qdrant.io").
    ///   - collectionName: Name of the collection to use. Will be created if it doesn't exist
    ///     when `ensureCollection(dimensions:)` is called.
    ///   - apiKey: Optional API key for authentication. Required for Qdrant Cloud.
    ///   - httpClient: HTTPClient instance. Uses `HTTPClient.shared` if not provided.
    ///
    /// ## Example
    /// ```swift
    /// // Connect to Qdrant Cloud
    /// let cloudStore = QdrantStore(
    ///     baseURL: URL(string: "https://cluster.qdrant.io")!,
    ///     collectionName: "documents",
    ///     apiKey: "your-api-key"
    /// )
    ///
    /// // Connect to local Qdrant
    /// let localStore = QdrantStore(
    ///     baseURL: URL(string: "http://localhost:6333")!,
    ///     collectionName: "test_collection"
    /// )
    /// ```
    public init(
        baseURL: URL,
        collectionName: String,
        apiKey: String? = nil,
        httpClient: HTTPClient? = nil
    ) {
        self.baseURL = baseURL
        self.collectionName = collectionName
        self.apiKey = apiKey
        self.httpClient = httpClient ?? HTTPClient.shared
    }

    // MARK: - Collection Management

    /// Ensures the collection exists, creating it if necessary.
    ///
    /// This method should be called before performing any operations on the collection.
    /// It uses idempotent semantics: if the collection already exists, the operation
    /// succeeds without error.
    ///
    /// - Parameter dimensions: The number of dimensions for the vectors stored in the
    ///   collection. This must match the dimensions of embeddings you'll be adding.
    ///
    /// - Throws: `ZoniError.vectorStoreConnectionFailed` if the collection cannot be
    ///   created due to connection issues or invalid configuration.
    ///
    /// ## Example
    /// ```swift
    /// // For OpenAI text-embedding-3-small (1536 dimensions)
    /// try await store.ensureCollection(dimensions: 1536)
    ///
    /// // For OpenAI text-embedding-3-large (3072 dimensions)
    /// try await store.ensureCollection(dimensions: 3072)
    ///
    /// // For Voyage AI embeddings (1024 dimensions)
    /// try await store.ensureCollection(dimensions: 1024)
    /// ```
    ///
    /// - Note: The collection is configured to use cosine similarity for distance
    ///   calculations, which is appropriate for most text embedding models.
    public func ensureCollection(dimensions: Int) async throws {
        let url = baseURL.appendingPathComponent("collections/\(collectionName)")
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .PUT
        addHeaders(to: &request)

        let body: [String: Any] = [
            "vectors": [
                "size": dimensions,
                "distance": "Cosine"
            ]
        ]
        request.body = .bytes(ByteBuffer(data: try JSONSerialization.data(withJSONObject: body)))

        let response = try await httpClient.execute(request, timeout: .seconds(30))

        // 200 OK or 409 Conflict (already exists) are both acceptable
        guard response.status == .ok || response.status == .conflict else {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Failed to create collection '\(collectionName)': HTTP \(response.status.code)"
            )
        }
    }

    // MARK: - VectorStore Protocol

    /// Adds chunks with their corresponding embeddings to the store.
    ///
    /// This method uses Qdrant's upsert semantics: if a chunk with the same ID
    /// already exists, it will be replaced with the new chunk and embedding.
    ///
    /// - Parameters:
    ///   - chunks: The chunks to store. Each chunk must have a unique ID.
    ///   - embeddings: Corresponding embeddings for each chunk. Must be in the
    ///     same order and have the same count as `chunks`.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the chunk count does not match
    ///   the embedding count, or if the Qdrant API returns an error.
    ///
    /// - Complexity: O(n) where n is the number of chunks being added, plus
    ///   network latency.
    ///
    /// ## Example
    /// ```swift
    /// let chunks = [
    ///     Chunk(content: "Document content...",
    ///           metadata: ChunkMetadata(documentId: "doc-123", index: 0))
    /// ]
    /// let embeddings = [Embedding(vector: [0.1, 0.2, 0.3, ...])]
    ///
    /// try await store.add(chunks, embeddings: embeddings)
    /// ```
    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        guard chunks.count == embeddings.count else {
            throw ZoniError.insertionFailed(
                reason: "Chunk count (\(chunks.count)) does not match embedding count (\(embeddings.count))"
            )
        }

        guard !chunks.isEmpty else {
            return // Nothing to add
        }

        let url = baseURL.appendingPathComponent("collections/\(collectionName)/points")
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .PUT
        addHeaders(to: &request)

        // Build points array for Qdrant
        var pointsArray: [[String: Any]] = []
        for (chunk, embedding) in zip(chunks, embeddings) {
            let point: [String: Any] = [
                "id": chunk.id,
                "vector": embedding.vector,
                "payload": chunkToPayload(chunk)
            ]
            pointsArray.append(point)
        }

        let body: [String: Any] = ["points": pointsArray]
        request.body = .bytes(ByteBuffer(data: try JSONSerialization.data(withJSONObject: body)))

        let response = try await httpClient.execute(request, timeout: .seconds(60))
        guard response.status == .ok else {
            throw ZoniError.insertionFailed(
                reason: "Qdrant upsert failed: HTTP \(response.status.code)"
            )
        }
    }

    /// Searches for chunks similar to the given query embedding.
    ///
    /// This method performs a similarity search using cosine distance, returning
    /// the most similar chunks to the query embedding. Results are sorted by
    /// similarity score in descending order (highest similarity first).
    ///
    /// - Parameters:
    ///   - query: The query embedding to search for similar vectors.
    ///   - limit: Maximum number of results to return. Must be positive.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///     Only chunks matching the filter will be considered.
    ///
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance
    ///   score in descending order (most relevant first).
    ///
    /// - Throws: `ZoniError.searchFailed` if the search fails due to
    ///   connection issues, invalid query, or other Qdrant errors.
    ///
    /// ## Example
    /// ```swift
    /// // Basic search
    /// let results = try await store.search(
    ///     query: queryEmbedding,
    ///     limit: 10,
    ///     filter: nil
    /// )
    ///
    /// // Search with metadata filter
    /// let filter = MetadataFilter.and([
    ///     .equals("documentId", "doc-123"),
    ///     .greaterThan("index", 5.0)
    /// ])
    /// let filteredResults = try await store.search(
    ///     query: queryEmbedding,
    ///     limit: 5,
    ///     filter: filter
    /// )
    /// ```
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        let url = baseURL.appendingPathComponent("collections/\(collectionName)/points/search")
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        addHeaders(to: &request)

        var body: [String: Any] = [
            "vector": query.vector,
            "limit": limit,
            "with_payload": true
        ]

        if let filter = filter {
            body["filter"] = try filterToQdrant(filter)
        }

        request.body = .bytes(ByteBuffer(data: try JSONSerialization.data(withJSONObject: body)))

        let searchResponse: QdrantSearchResponse = try await executeWithRetry {
            let response = try await self.httpClient.execute(request, timeout: .seconds(30))
            guard response.status == .ok else {
                throw ZoniError.searchFailed(
                    reason: "Qdrant search failed: HTTP \(response.status.code)"
                )
            }

            // Collect response body with 10MB limit
            let responseData = try await response.body.collect(upTo: 10 * 1024 * 1024)
            return try JSONDecoder().decode(
                QdrantSearchResponse.self,
                from: Data(buffer: responseData)
            )
        }

        return searchResponse.result.map { point in
            RetrievalResult(
                chunk: payloadToChunk(id: point.id, payload: point.payload),
                score: point.score
            )
        }
    }

    /// Deletes chunks with the specified IDs from the store.
    ///
    /// IDs that do not exist in the store are silently ignored.
    ///
    /// - Parameter ids: The IDs of chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the deletion fails due to
    ///   connection issues or other Qdrant errors.
    ///
    /// - Complexity: O(k) network calls where k is the number of IDs.
    ///
    /// ## Example
    /// ```swift
    /// // Delete specific chunks by ID
    /// try await store.delete(ids: ["chunk-1", "chunk-2", "chunk-3"])
    /// ```
    public func delete(ids: [String]) async throws {
        guard !ids.isEmpty else {
            return // Nothing to delete
        }

        let url = baseURL.appendingPathComponent("collections/\(collectionName)/points/delete")
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        addHeaders(to: &request)

        let body: [String: Any] = ["points": ids]
        request.body = .bytes(ByteBuffer(data: try JSONSerialization.data(withJSONObject: body)))

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        guard response.status == .ok else {
            throw ZoniError.insertionFailed(
                reason: "Qdrant delete failed: HTTP \(response.status.code)"
            )
        }
    }

    /// Deletes all chunks matching the specified metadata filter.
    ///
    /// This is useful for bulk deletion operations, such as removing all chunks
    /// from a specific document or clearing chunks with certain attributes.
    ///
    /// - Parameter filter: The metadata filter specifying which chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the deletion fails due to
    ///   connection issues or other Qdrant errors.
    ///
    /// ## Example
    /// ```swift
    /// // Delete all chunks from a specific document
    /// let filter = MetadataFilter.equals("documentId", "doc-to-remove")
    /// try await store.delete(filter: filter)
    ///
    /// // Delete chunks matching multiple criteria
    /// let complexFilter = MetadataFilter.and([
    ///     .equals("source", "outdated.txt"),
    ///     .lessThan("index", 10.0)
    /// ])
    /// try await store.delete(filter: complexFilter)
    /// ```
    public func delete(filter: MetadataFilter) async throws {
        let url = baseURL.appendingPathComponent("collections/\(collectionName)/points/delete")
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        addHeaders(to: &request)

        let body: [String: Any] = ["filter": try filterToQdrant(filter)]
        request.body = .bytes(ByteBuffer(data: try JSONSerialization.data(withJSONObject: body)))

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        guard response.status == .ok else {
            throw ZoniError.insertionFailed(
                reason: "Qdrant delete by filter failed: HTTP \(response.status.code)"
            )
        }
    }

    /// Returns the total number of chunks stored in the vector store.
    ///
    /// - Returns: The count of chunks currently in the collection.
    ///
    /// - Throws: `ZoniError.vectorStoreConnectionFailed` if the count cannot
    ///   be determined due to connection issues or other Qdrant errors.
    ///
    /// ## Example
    /// ```swift
    /// let totalChunks = try await store.count()
    /// print("Store contains \(totalChunks) chunks")
    /// ```
    public func count() async throws -> Int {
        let url = baseURL.appendingPathComponent("collections/\(collectionName)/points/count")
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        addHeaders(to: &request)

        let body: [String: Any] = ["exact": true]
        request.body = .bytes(ByteBuffer(data: try JSONSerialization.data(withJSONObject: body)))

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        guard response.status == .ok else {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Qdrant count failed: HTTP \(response.status.code)"
            )
        }

        let responseData = try await response.body.collect(upTo: 1024 * 1024)
        let countResponse = try JSONDecoder().decode(
            QdrantCountResponse.self,
            from: Data(buffer: responseData)
        )
        return countResponse.result.count
    }

    // MARK: - Private Helpers

    /// Adds common HTTP headers to a request.
    ///
    /// This includes the Content-Type header and optional API key authentication.
    ///
    /// - Parameter request: The HTTP request to modify.
    private func addHeaders(to request: inout HTTPClientRequest) {
        request.headers.add(name: "Content-Type", value: "application/json")
        if let apiKey = apiKey {
            request.headers.add(name: "api-key", value: apiKey)
        }
    }

    /// Converts a Chunk to a Qdrant payload dictionary.
    ///
    /// The payload stores all chunk metadata in a format that Qdrant can index
    /// and filter. Custom metadata keys are prefixed with "custom_" to avoid
    /// conflicts with standard fields.
    ///
    /// - Parameter chunk: The chunk to convert.
    /// - Returns: A dictionary suitable for Qdrant's payload format.
    private func chunkToPayload(_ chunk: Chunk) -> [String: Any] {
        var payload: [String: Any] = [
            "content": chunk.content,
            "documentId": chunk.metadata.documentId,
            "index": chunk.metadata.index,
            "startOffset": chunk.metadata.startOffset,
            "endOffset": chunk.metadata.endOffset
        ]

        if let source = chunk.metadata.source {
            payload["source"] = source
        }

        // Add custom metadata with prefix to avoid conflicts
        for (key, value) in chunk.metadata.custom {
            payload["custom_\(key)"] = metadataValueToAny(value)
        }

        return payload
    }

    /// Reconstructs a Chunk from a Qdrant payload dictionary.
    ///
    /// This reverses the `chunkToPayload` conversion, extracting all metadata
    /// including custom fields.
    ///
    /// - Parameters:
    ///   - id: The chunk ID from Qdrant.
    ///   - payload: The payload dictionary from Qdrant.
    /// - Returns: A reconstructed Chunk instance.
    private func payloadToChunk(id: String, payload: [String: Any]) -> Chunk {
        // Extract custom metadata (keys prefixed with "custom_")
        var custom: [String: MetadataValue] = [:]
        for (key, value) in payload where key.hasPrefix("custom_") {
            let customKey = String(key.dropFirst("custom_".count))
            custom[customKey] = anyToMetadataValue(value)
        }

        return Chunk(
            id: id,
            content: payload["content"] as? String ?? "",
            metadata: ChunkMetadata(
                documentId: payload["documentId"] as? String ?? "",
                index: payload["index"] as? Int ?? 0,
                startOffset: payload["startOffset"] as? Int ?? 0,
                endOffset: payload["endOffset"] as? Int ?? 0,
                source: payload["source"] as? String,
                custom: custom
            )
        )
    }

    /// Converts a MetadataFilter to Qdrant's filter format.
    ///
    /// Qdrant uses a specific JSON structure for filters with "must", "should",
    /// and "must_not" arrays for different logical operations.
    ///
    /// - Parameter filter: The MetadataFilter to convert.
    /// - Returns: A dictionary in Qdrant's filter format.
    /// - Throws: If the filter contains unsupported operations.
    private func filterToQdrant(_ filter: MetadataFilter) throws -> [String: Any] {
        var must: [[String: Any]] = []

        for condition in filter.conditions {
            must.append(try conditionToQdrant(condition))
        }

        return ["must": must]
    }

    /// Converts a single filter condition to Qdrant's format.
    ///
    /// - Parameter condition: The filter operator to convert.
    /// - Returns: A dictionary representing the condition in Qdrant format.
    /// - Throws: If the condition type is not supported.
    private func conditionToQdrant(_ condition: MetadataFilter.Operator) throws -> [String: Any] {
        switch condition {
        case .equals(let field, let value):
            return ["key": field, "match": ["value": metadataValueToAny(value)]]

        case .notEquals(let field, let value):
            return [
                "must_not": [
                    ["key": field, "match": ["value": metadataValueToAny(value)]]
                ]
            ]

        case .greaterThan(let field, let value):
            return ["key": field, "range": ["gt": value]]

        case .lessThan(let field, let value):
            return ["key": field, "range": ["lt": value]]

        case .greaterThanOrEqual(let field, let value):
            return ["key": field, "range": ["gte": value]]

        case .lessThanOrEqual(let field, let value):
            return ["key": field, "range": ["lte": value]]

        case .in(let field, let values):
            return ["key": field, "match": ["any": values.map { metadataValueToAny($0) }]]

        case .notIn(let field, let values):
            return [
                "must_not": [
                    ["key": field, "match": ["any": values.map { metadataValueToAny($0) }]]
                ]
            ]

        case .and(let filters):
            return [
                "must": try filters.flatMap { try $0.conditions.map { try conditionToQdrant($0) } }
            ]

        case .or(let filters):
            return [
                "should": try filters.flatMap { try $0.conditions.map { try conditionToQdrant($0) } }
            ]

        case .not(let filter):
            return [
                "must_not": try filter.conditions.map { try conditionToQdrant($0) }
            ]

        case .contains, .startsWith, .endsWith:
            throw ZoniError.searchFailed(
                reason: "String pattern operators (contains/startsWith/endsWith) are not supported by Qdrant. Use equals or full-text search instead."
            )

        case .exists(let field):
            return ["is_null": ["key": field, "is_null": false]]

        case .notExists(let field):
            return ["is_null": ["key": field, "is_null": true]]
        }
    }

    /// Converts a MetadataValue to a JSON-compatible Any type.
    ///
    /// - Parameter value: The MetadataValue to convert.
    /// - Returns: A JSON-compatible value.
    private func metadataValueToAny(_ value: MetadataValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let v):
            return v
        case .int(let v):
            return v
        case .double(let v):
            return v
        case .string(let v):
            return v
        case .array(let v):
            return v.map { metadataValueToAny($0) }
        case .dictionary(let v):
            return v.mapValues { metadataValueToAny($0) }
        }
    }

    /// Converts a JSON Any value to a MetadataValue.
    ///
    /// - Parameter value: The JSON value to convert.
    /// - Returns: A MetadataValue representation.
    private func anyToMetadataValue(_ value: Any) -> MetadataValue {
        switch value {
        case let v as Bool:
            return .bool(v)
        case let v as Int:
            return .int(v)
        case let v as Double:
            return .double(v)
        case let v as String:
            return .string(v)
        case let v as [Any]:
            return .array(v.map { anyToMetadataValue($0) })
        case let v as [String: Any]:
            return .dictionary(v.mapValues { anyToMetadataValue($0) })
        default:
            return .null
        }
    }

    /// Executes an operation with exponential backoff retry logic.
    ///
    /// This helper method retries failed operations with increasing delays between
    /// attempts, which is useful for handling transient network failures or
    /// rate limiting from the Qdrant server.
    ///
    /// - Parameters:
    ///   - operation: The async throwing closure to execute.
    ///   - maxRetries: Maximum number of retry attempts (default: 3).
    /// - Returns: The result of the successful operation.
    /// - Throws: The last error encountered if all retries fail.
    private func executeWithRetry<T>(
        _ operation: @escaping () async throws -> T,
        maxRetries: Int = 3
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    try await Task.sleep(for: .milliseconds(100 * (1 << attempt)))
                }
            }
        }
        throw lastError ?? ZoniError.vectorStoreConnectionFailed(reason: "Max retries exceeded")
    }
}

// MARK: - Qdrant API Response Models

/// Response structure for Qdrant search operations.
///
/// This models the JSON response from the `/points/search` endpoint.
private struct QdrantSearchResponse: Decodable {
    /// The array of search results.
    let result: [QdrantSearchResult]
}

/// A single search result from Qdrant.
///
/// Contains the point ID, similarity score, and payload data.
private struct QdrantSearchResult: Decodable {
    /// The unique identifier of the point.
    let id: String

    /// The similarity score (higher = more similar for cosine distance).
    let score: Float

    /// The payload data associated with the point.
    let payload: [String: Any]

    /// Custom decoding to handle the dynamic payload dictionary.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Qdrant can return IDs as either strings or integers
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected string or integer ID"
                )
            )
        }

        score = try container.decode(Float.self, forKey: .score)

        // Decode payload as dynamic dictionary
        let payloadContainer = try container.nestedContainer(
            keyedBy: DynamicCodingKey.self,
            forKey: .payload
        )
        var dict: [String: Any] = [:]
        for key in payloadContainer.allKeys {
            if let value = try? payloadContainer.decode(String.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? payloadContainer.decode(Int.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? payloadContainer.decode(Double.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? payloadContainer.decode(Bool.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? payloadContainer.decode([String].self, forKey: key) {
                dict[key.stringValue] = value
            }
        }
        payload = dict
    }

    enum CodingKeys: String, CodingKey {
        case id, score, payload
    }
}

/// Response structure for Qdrant count operations.
///
/// This models the JSON response from the `/points/count` endpoint.
private struct QdrantCountResponse: Decodable {
    /// The count result.
    let result: QdrantCount
}

/// The count value from a Qdrant count response.
private struct QdrantCount: Decodable {
    /// The number of points in the collection.
    let count: Int
}

/// A dynamic coding key for decoding arbitrary JSON keys.
///
/// This is used to decode Qdrant's payload dictionaries which have
/// user-defined keys that aren't known at compile time.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - CustomStringConvertible

extension QdrantStore: CustomStringConvertible {
    /// A textual representation of the store for debugging.
    nonisolated public var description: String {
        "QdrantStore(name: \"\(name)\", collection: \"\(collectionName)\")"
    }
}
