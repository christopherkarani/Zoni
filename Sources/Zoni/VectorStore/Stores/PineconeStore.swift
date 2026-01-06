// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// PineconeStore.swift - A Pinecone cloud vector database implementation.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - PineconeStore

/// A Pinecone cloud vector store implementation using the Pinecone REST API.
///
/// `PineconeStore` provides integration with Pinecone, a managed vector database
/// service optimized for ML applications. This store communicates with Pinecone
/// via its REST API using Foundation's URLSession.
///
/// ## Features
///
/// - **Managed infrastructure**: No need to manage database servers
/// - **High performance**: Optimized for vector similarity search at scale
/// - **Namespace isolation**: Organize vectors into separate namespaces
/// - **Metadata filtering**: Filter searches by metadata attributes
/// - **Automatic scaling**: Handles large datasets with ease
///
/// ## Thread Safety
///
/// This store is implemented as an `actor`, ensuring safe concurrent access
/// from multiple tasks. All network operations are isolated through the actor.
///
/// ## Requirements
///
/// - A Pinecone account and API key
/// - An existing Pinecone index with appropriate dimensions
/// - The index host URL (found in the Pinecone console)
///
/// ## Example Usage
///
/// ```swift
/// // Create a Pinecone store
/// let store = PineconeStore(
///     apiKey: "your-api-key",
///     indexHost: "your-index-abc123.svc.us-east1-gcp.pinecone.io",
///     namespace: "production"
/// )
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
/// ## Pinecone REST API
///
/// This implementation uses the following Pinecone REST API endpoints:
/// - `POST /vectors/upsert` - Add or update vectors
/// - `POST /query` - Search for similar vectors
/// - `POST /vectors/delete` - Delete vectors by ID or filter
/// - `POST /describe_index_stats` - Get index statistics
///
/// ## Metadata Handling
///
/// Chunk metadata is automatically converted to Pinecone's metadata format:
/// - Standard fields: `content`, `documentId`, `index`, `startOffset`, `endOffset`, `source`
/// - Custom fields are prefixed with `custom_` to avoid conflicts
///
/// Note that Pinecone does not support nested objects in metadata. Nested
/// dictionaries in custom metadata will be converted to null values.
///
/// ## Error Handling
///
/// Network and API errors are wrapped in `ZoniError` types:
/// - `ZoniError.insertionFailed` - For upsert and delete failures
/// - `ZoniError.searchFailed` - For query failures
/// - `ZoniError.vectorStoreConnectionFailed` - For connection and stats failures
public actor PineconeStore: VectorStore {

    // MARK: - Properties

    /// The name identifier for this vector store implementation.
    ///
    /// Used for logging, debugging, and configuration purposes.
    public nonisolated let name = "pinecone"

    /// The Pinecone API key for authentication.
    private let apiKey: String

    /// The full host URL for the Pinecone index.
    ///
    /// This should be the complete URL including the protocol, e.g.,
    /// "https://your-index-abc123.svc.us-east1-gcp.pinecone.io"
    private let indexHost: String

    /// Optional namespace for vector isolation within the index.
    ///
    /// Namespaces allow you to partition vectors within a single index,
    /// useful for multi-tenant applications or separating environments.
    private let namespace: String?

    /// The URLSession used for HTTP requests.
    private let session: URLSession

    /// Timeout for HTTP requests in seconds.
    private let timeoutInterval: TimeInterval

    // MARK: - Initialization

    /// Creates a Pinecone vector store with the specified configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Your Pinecone API key. Find this in the Pinecone console
    ///     under API Keys.
    ///   - indexHost: The host URL for your index. This is shown in the Pinecone
    ///     console when you select an index. Can be provided with or without
    ///     the `https://` prefix.
    ///   - namespace: Optional namespace to isolate vectors. Vectors in different
    ///     namespaces are completely separate and cannot be queried together.
    ///   - session: Custom URLSession for HTTP requests. Defaults to `.shared`.
    ///   - timeoutInterval: Timeout for HTTP requests in seconds. Defaults to 60.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Basic initialization
    /// let store = PineconeStore(
    ///     apiKey: ProcessInfo.processInfo.environment["PINECONE_API_KEY"]!,
    ///     indexHost: "my-index-abc123.svc.us-east1-gcp.pinecone.io"
    /// )
    ///
    /// // With namespace for multi-tenant isolation
    /// let tenantStore = PineconeStore(
    ///     apiKey: apiKey,
    ///     indexHost: indexHost,
    ///     namespace: "tenant-\(tenantId)"
    /// )
    ///
    /// // With custom session configuration
    /// let config = URLSessionConfiguration.default
    /// config.timeoutIntervalForRequest = 30
    /// let customSession = URLSession(configuration: config)
    ///
    /// let customStore = PineconeStore(
    ///     apiKey: apiKey,
    ///     indexHost: indexHost,
    ///     session: customSession,
    ///     timeoutInterval: 30
    /// )
    /// ```
    public init(
        apiKey: String,
        indexHost: String,
        namespace: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 60
    ) {
        self.apiKey = apiKey
        // Ensure the host includes the protocol
        self.indexHost = indexHost.hasPrefix("https://") ? indexHost : "https://\(indexHost)"
        self.namespace = namespace
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    // MARK: - VectorStore Protocol

    /// Adds chunks with their corresponding embeddings to the Pinecone index.
    ///
    /// This method uses upsert semantics: if a vector with the same ID already
    /// exists, it will be replaced with the new vector and metadata.
    ///
    /// - Parameters:
    ///   - chunks: The chunks to store. Each chunk must have a unique ID.
    ///   - embeddings: Corresponding embeddings for each chunk. Must be in the
    ///     same order and have the same count as `chunks`.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the chunk count does not match
    ///   the embedding count, or if the Pinecone API returns an error.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let chunks = [
    ///     Chunk(content: "First chunk content",
    ///           metadata: ChunkMetadata(documentId: "doc-1", index: 0)),
    ///     Chunk(content: "Second chunk content",
    ///           metadata: ChunkMetadata(documentId: "doc-1", index: 1))
    /// ]
    /// let embeddings = try await embedder.embed(chunks.map { $0.content })
    ///
    /// try await store.add(chunks, embeddings: embeddings)
    /// ```
    ///
    /// - Note: Pinecone has a limit on the number of vectors per upsert request
    ///   (typically 100). For large batches, consider splitting into smaller
    ///   requests.
    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        // Validate that counts match
        guard chunks.count == embeddings.count else {
            throw ZoniError.insertionFailed(
                reason: "Chunk count (\(chunks.count)) does not match embedding count (\(embeddings.count))"
            )
        }

        // Handle empty input
        guard !chunks.isEmpty else { return }

        // Build the upsert request
        guard let url = URL(string: "\(indexHost)/vectors/upsert") else {
            throw ZoniError.insertionFailed(reason: "Invalid Pinecone URL: \(indexHost)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        addHeaders(to: &request)

        // Convert chunks and embeddings to Pinecone vector format
        let vectors = zip(chunks, embeddings).map { chunk, embedding in
            PineconeVector(
                id: chunk.id,
                values: embedding.vector,
                metadata: chunkToMetadata(chunk)
            )
        }

        var body = PineconeUpsertRequest(vectors: vectors)
        body.namespace = namespace

        request.httpBody = try JSONEncoder().encode(body)

        // Execute the request
        let (data, response) = try await executeRequest(request)

        // Check for errors
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoniError.insertionFailed(reason: "Invalid response type from Pinecone")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ZoniError.insertionFailed(
                reason: "Pinecone upsert failed with status \(httpResponse.statusCode): \(errorMessage)"
            )
        }
    }

    /// Searches for chunks similar to the given query embedding.
    ///
    /// Results are ranked by similarity score, with higher scores indicating
    /// greater relevance to the query.
    ///
    /// - Parameters:
    ///   - query: The query embedding to search for similar vectors.
    ///   - limit: Maximum number of results to return. Must be positive.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///     Converted to Pinecone's filter format.
    ///
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance
    ///   score in descending order (most relevant first).
    ///
    /// - Throws: `ZoniError.searchFailed` if the Pinecone API returns an error.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Basic search
    /// let queryEmbedding = try await embedder.embed("What is Swift concurrency?")
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
    ///
    /// // Process results
    /// for result in results {
    ///     print("Score: \(result.score)")
    ///     print("Content: \(result.chunk.content)")
    ///     print("Document: \(result.chunk.metadata.documentId)")
    /// }
    /// ```
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Validate limit parameter
        guard limit > 0 else {
            throw ZoniError.searchFailed(reason: "Limit must be greater than 0, got \(limit)")
        }

        // Build the query request
        guard let url = URL(string: "\(indexHost)/query") else {
            throw ZoniError.searchFailed(reason: "Invalid Pinecone URL: \(indexHost)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        addHeaders(to: &request)

        var queryRequest = PineconeQueryRequest(
            vector: query.vector,
            topK: limit,
            includeMetadata: true
        )
        queryRequest.namespace = namespace

        // Convert filter if provided
        if let filter = filter {
            queryRequest.filter = try filterToPinecone(filter)
        }

        request.httpBody = try encodeQueryRequest(queryRequest)

        // Execute the request with retry logic
        return try await executeWithRetry {
            let (data, response) = try await self.executeRequest(request)

            // Check for errors
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZoniError.searchFailed(reason: "Invalid response type from Pinecone")
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ZoniError.searchFailed(
                    reason: "Pinecone query failed with status \(httpResponse.statusCode): \(errorMessage)"
                )
            }

            // Decode the response
            let queryResponse = try JSONDecoder().decode(PineconeQueryResponse.self, from: data)

            // Convert matches to RetrievalResult objects
            return queryResponse.matches.map { match in
                RetrievalResult(
                    chunk: self.metadataToChunk(id: match.id, metadata: match.metadata ?? [:]),
                    score: match.score
                )
            }
        }
    }

    /// Deletes chunks with the specified IDs from the Pinecone index.
    ///
    /// IDs that do not exist in the index are silently ignored.
    ///
    /// - Parameter ids: The IDs of chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the Pinecone API returns an error.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Delete specific chunks by ID
    /// try await store.delete(ids: ["chunk-1", "chunk-2", "chunk-3"])
    /// ```
    public func delete(ids: [String]) async throws {
        // Handle empty input
        guard !ids.isEmpty else { return }

        // Build the delete request
        guard let url = URL(string: "\(indexHost)/vectors/delete") else {
            throw ZoniError.insertionFailed(reason: "Invalid Pinecone URL: \(indexHost)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        addHeaders(to: &request)

        var deleteRequest = PineconeDeleteRequest(ids: ids)
        deleteRequest.namespace = namespace

        request.httpBody = try JSONEncoder().encode(deleteRequest)

        // Execute the request
        let (data, response) = try await executeRequest(request)

        // Check for errors
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoniError.insertionFailed(reason: "Invalid response type from Pinecone")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ZoniError.insertionFailed(
                reason: "Pinecone delete failed with status \(httpResponse.statusCode): \(errorMessage)"
            )
        }
    }

    /// Deletes all chunks matching the specified metadata filter.
    ///
    /// This is useful for bulk deletion operations, such as removing all chunks
    /// from a specific document.
    ///
    /// - Parameter filter: The metadata filter specifying which chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the Pinecone API returns an error.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Delete all chunks from a specific document
    /// let filter = MetadataFilter.equals("documentId", "doc-to-remove")
    /// try await store.delete(filter: filter)
    ///
    /// // Delete chunks matching multiple criteria
    /// let complexFilter = MetadataFilter.and([
    ///     .equals("custom_source", "outdated.txt"),
    ///     .lessThan("index", 10.0)
    /// ])
    /// try await store.delete(filter: complexFilter)
    /// ```
    ///
    /// - Note: Delete by filter may not be instantaneous for large datasets.
    ///   Pinecone processes these deletions asynchronously.
    public func delete(filter: MetadataFilter) async throws {
        // Build the delete request
        guard let url = URL(string: "\(indexHost)/vectors/delete") else {
            throw ZoniError.insertionFailed(reason: "Invalid Pinecone URL: \(indexHost)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        addHeaders(to: &request)

        let pineconeFilter = try filterToPinecone(filter)

        var deleteRequest = PineconeDeleteByFilterRequest()
        deleteRequest.namespace = namespace
        deleteRequest.filter = pineconeFilter

        request.httpBody = try encodeDeleteByFilterRequest(deleteRequest)

        // Execute the request
        let (data, response) = try await executeRequest(request)

        // Check for errors
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoniError.insertionFailed(reason: "Invalid response type from Pinecone")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ZoniError.insertionFailed(
                reason: "Pinecone delete by filter failed with status \(httpResponse.statusCode): \(errorMessage)"
            )
        }
    }

    /// Returns the total number of vectors stored in the Pinecone index.
    ///
    /// If a namespace was specified during initialization, returns the count
    /// for that namespace only. Otherwise, returns the total count across all
    /// namespaces.
    ///
    /// - Returns: The count of vectors in the index (or namespace).
    ///
    /// - Throws: `ZoniError.vectorStoreConnectionFailed` if the Pinecone API
    ///   returns an error.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let totalVectors = try await store.count()
    /// print("Index contains \(totalVectors) vectors")
    /// ```
    public func count() async throws -> Int {
        // Build the describe_index_stats request
        guard let url = URL(string: "\(indexHost)/describe_index_stats") else {
            throw ZoniError.vectorStoreConnectionFailed(
                store: name,
                reason: "Invalid Pinecone URL: \(indexHost)"
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        addHeaders(to: &request)

        // Empty JSON body required
        request.httpBody = "{}".data(using: .utf8)

        // Execute the request
        let (data, response) = try await executeRequest(request)

        // Check for errors
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoniError.vectorStoreConnectionFailed(reason: "Invalid response type from Pinecone")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Pinecone describe_index_stats failed with status \(httpResponse.statusCode): \(errorMessage)"
            )
        }

        // Decode the response
        let statsResponse = try JSONDecoder().decode(PineconeStatsResponse.self, from: data)

        // If namespace is specified, return that namespace's count
        if let namespace = namespace,
           let namespaceStats = statsResponse.namespaces?[namespace] {
            return namespaceStats.vectorCount
        }

        // Otherwise return total count
        return statsResponse.totalVectorCount
    }

    // MARK: - Private Helpers

    /// Adds required HTTP headers to a request.
    ///
    /// - Parameter request: The request to modify.
    private func addHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
    }

    /// Executes an HTTP request and returns the response data.
    ///
    /// - Parameter request: The request to execute.
    /// - Returns: A tuple containing the response data and URL response.
    /// - Throws: Network errors from URLSession.
    private func executeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    /// Executes an operation with exponential backoff retry logic.
    ///
    /// - Parameters:
    ///   - operation: The async throwing operation to execute.
    ///   - maxRetries: Maximum number of retry attempts. Defaults to 3.
    /// - Returns: The result of the operation if successful.
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

    /// Converts a Chunk to Pinecone metadata format.
    ///
    /// Standard chunk metadata fields are stored directly, while custom
    /// metadata is prefixed with `custom_` to avoid naming conflicts.
    ///
    /// - Parameter chunk: The chunk to convert.
    /// - Returns: A dictionary of Pinecone metadata values.
    private func chunkToMetadata(_ chunk: Chunk) -> [String: PineconeMetadataValue] {
        var metadata: [String: PineconeMetadataValue] = [
            "content": .string(chunk.content),
            "documentId": .string(chunk.metadata.documentId),
            "index": .int(chunk.metadata.index),
            "startOffset": .int(chunk.metadata.startOffset),
            "endOffset": .int(chunk.metadata.endOffset)
        ]

        // Add source if present
        if let source = chunk.metadata.source {
            metadata["source"] = .string(source)
        }

        // Add custom metadata with prefix
        for (key, value) in chunk.metadata.custom {
            metadata["custom_\(key)"] = metadataValueToPinecone(value)
        }

        return metadata
    }

    /// Converts Pinecone metadata back to a Chunk.
    ///
    /// - Parameters:
    ///   - id: The chunk ID.
    ///   - metadata: The Pinecone metadata dictionary.
    /// - Returns: A reconstructed Chunk.
    private func metadataToChunk(id: String, metadata: [String: PineconeMetadataValue]) -> Chunk {
        // Extract custom metadata (fields prefixed with "custom_")
        var custom: [String: MetadataValue] = [:]
        for (key, value) in metadata where key.hasPrefix("custom_") {
            let customKey = String(key.dropFirst("custom_".count))
            custom[customKey] = pineconeToMetadataValue(value)
        }

        return Chunk(
            id: id,
            content: metadata["content"]?.stringValue ?? "",
            metadata: ChunkMetadata(
                documentId: metadata["documentId"]?.stringValue ?? "",
                index: metadata["index"]?.intValue ?? 0,
                startOffset: metadata["startOffset"]?.intValue ?? 0,
                endOffset: metadata["endOffset"]?.intValue ?? 0,
                source: metadata["source"]?.stringValue,
                custom: custom
            )
        )
    }

    /// Converts a MetadataValue to Pinecone's metadata format.
    ///
    /// - Parameter value: The metadata value to convert.
    /// - Returns: The equivalent Pinecone metadata value.
    private func metadataValueToPinecone(_ value: MetadataValue) -> PineconeMetadataValue {
        switch value {
        case .null:
            return .null
        case .bool(let v):
            return .bool(v)
        case .int(let v):
            return .int(v)
        case .double(let v):
            return .double(v)
        case .string(let v):
            return .string(v)
        case .array(let v):
            return .array(v.map { metadataValueToPinecone($0) })
        case .dictionary:
            // Pinecone doesn't support nested objects
            return .null
        }
    }

    /// Converts Pinecone metadata back to a MetadataValue.
    ///
    /// - Parameter value: The Pinecone metadata value to convert.
    /// - Returns: The equivalent MetadataValue.
    private func pineconeToMetadataValue(_ value: PineconeMetadataValue) -> MetadataValue {
        switch value {
        case .null:
            return .null
        case .bool(let v):
            return .bool(v)
        case .int(let v):
            return .int(v)
        case .double(let v):
            return .double(v)
        case .string(let v):
            return .string(v)
        case .array(let v):
            return .array(v.map { pineconeToMetadataValue($0) })
        }
    }

    /// Converts a MetadataFilter to Pinecone's filter format.
    ///
    /// - Parameter filter: The filter to convert.
    /// - Returns: A dictionary representing the Pinecone filter.
    /// - Throws: If the filter contains unsupported operators.
    private func filterToPinecone(_ filter: MetadataFilter) throws -> [String: Any] {
        // If single condition, convert directly
        if filter.conditions.count == 1 {
            return try conditionToPinecone(filter.conditions[0])
        }

        // Multiple conditions are combined with $and
        return ["$and": try filter.conditions.map { try conditionToPinecone($0) }]
    }

    /// Converts a single filter condition to Pinecone format.
    ///
    /// - Parameter condition: The condition to convert.
    /// - Returns: A dictionary representing the Pinecone condition.
    /// - Throws: If the condition type is not supported.
    private func conditionToPinecone(_ condition: MetadataFilter.Operator) throws -> [String: Any] {
        switch condition {
        case .equals(let field, let value):
            return [field: ["$eq": metadataValueToAny(value)]]

        case .notEquals(let field, let value):
            return [field: ["$ne": metadataValueToAny(value)]]

        case .greaterThan(let field, let value):
            return [field: ["$gt": value]]

        case .lessThan(let field, let value):
            return [field: ["$lt": value]]

        case .greaterThanOrEqual(let field, let value):
            return [field: ["$gte": value]]

        case .lessThanOrEqual(let field, let value):
            return [field: ["$lte": value]]

        case .in(let field, let values):
            return [field: ["$in": values.map { metadataValueToAny($0) }]]

        case .notIn(let field, let values):
            return [field: ["$nin": values.map { metadataValueToAny($0) }]]

        case .and(let filters):
            let conditions = try filters.flatMap { filter in
                try filter.conditions.map { try conditionToPinecone($0) }
            }
            return ["$and": conditions]

        case .or(let filters):
            let conditions = try filters.flatMap { filter in
                try filter.conditions.map { try conditionToPinecone($0) }
            }
            return ["$or": conditions]

        case .contains, .startsWith, .endsWith:
            throw ZoniError.searchFailed(
                reason: "String pattern operators (contains/startsWith/endsWith) are not supported by Pinecone"
            )

        case .exists, .notExists:
            throw ZoniError.searchFailed(
                reason: "Field existence operators (exists/notExists) are not supported by Pinecone"
            )

        case .not:
            throw ZoniError.searchFailed(
                reason: "NOT operator is not directly supported by Pinecone. Use notEquals or notIn instead."
            )
        }
    }

    /// Converts a MetadataValue to Any for JSON serialization.
    ///
    /// - Parameter value: The metadata value to convert.
    /// - Returns: The equivalent Any value.
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

    /// Encodes a query request to JSON data.
    ///
    /// This custom encoding is needed because the filter field contains
    /// arbitrary dictionaries that cannot be directly encoded with Codable.
    ///
    /// - Parameter queryRequest: The query request to encode.
    /// - Returns: JSON data representing the request.
    /// - Throws: Encoding errors.
    private func encodeQueryRequest(_ queryRequest: PineconeQueryRequest) throws -> Data {
        var dict: [String: Any] = [
            "vector": queryRequest.vector,
            "topK": queryRequest.topK,
            "includeMetadata": queryRequest.includeMetadata
        ]

        if let namespace = queryRequest.namespace {
            dict["namespace"] = namespace
        }

        if let filter = queryRequest.filter {
            dict["filter"] = filter
        }

        return try JSONSerialization.data(withJSONObject: dict)
    }

    /// Encodes a delete-by-filter request to JSON data.
    ///
    /// - Parameter request: The delete request to encode.
    /// - Returns: JSON data representing the request.
    /// - Throws: Encoding errors.
    private func encodeDeleteByFilterRequest(_ request: PineconeDeleteByFilterRequest) throws -> Data {
        var dict: [String: Any] = [:]

        if let namespace = request.namespace {
            dict["namespace"] = namespace
        }

        if let filter = request.filter {
            dict["filter"] = filter
        }

        return try JSONSerialization.data(withJSONObject: dict)
    }
}

// MARK: - CustomStringConvertible

extension PineconeStore: CustomStringConvertible {
    /// A textual representation of the store for debugging.
    nonisolated public var description: String {
        "PineconeStore(name: \"\(name)\")"
    }
}

// MARK: - Pinecone API Models

/// A metadata value that can be stored in Pinecone.
///
/// Pinecone supports null, boolean, integer, double, string, and array values.
/// Nested objects are not supported.
private enum PineconeMetadataValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([PineconeMetadataValue])

    /// Extracts the string value if this is a string type.
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Extracts the integer value if this is an integer type.
    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([PineconeMetadataValue].self) {
            self = .array(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        }
    }
}

/// A vector to be upserted into Pinecone.
private struct PineconeVector: Encodable, Sendable {
    /// The unique identifier for the vector.
    let id: String

    /// The embedding values.
    let values: [Float]

    /// Metadata associated with the vector.
    let metadata: [String: PineconeMetadataValue]
}

/// Request body for the Pinecone upsert endpoint.
private struct PineconeUpsertRequest: Encodable, Sendable {
    /// The vectors to upsert.
    var vectors: [PineconeVector]

    /// Optional namespace to upsert into.
    var namespace: String?
}

/// Request parameters for the Pinecone query endpoint.
///
/// Note: This struct is not directly Encodable because the filter
/// field contains arbitrary dictionaries.
private struct PineconeQueryRequest {
    /// The query vector.
    let vector: [Float]

    /// Maximum number of results to return.
    let topK: Int

    /// Whether to include metadata in results.
    let includeMetadata: Bool

    /// Optional namespace to query.
    var namespace: String?

    /// Optional metadata filter.
    var filter: [String: Any]?
}

/// Response from the Pinecone query endpoint.
private struct PineconeQueryResponse: Decodable, Sendable {
    /// The matching vectors.
    let matches: [PineconeMatch]
}

/// A single match from a Pinecone query.
private struct PineconeMatch: Decodable, Sendable {
    /// The vector ID.
    let id: String

    /// The similarity score.
    let score: Float

    /// Metadata associated with the vector.
    let metadata: [String: PineconeMetadataValue]?
}

/// Request body for the Pinecone delete endpoint (by IDs).
private struct PineconeDeleteRequest: Encodable, Sendable {
    /// The IDs to delete.
    var ids: [String]

    /// Optional namespace to delete from.
    var namespace: String?
}

/// Request body for the Pinecone delete endpoint (by filter).
///
/// Note: This struct is not directly Encodable because the filter
/// field contains arbitrary dictionaries.
private struct PineconeDeleteByFilterRequest {
    /// Optional namespace to delete from.
    var namespace: String?

    /// Metadata filter for deletion.
    var filter: [String: Any]?
}

/// Response from the Pinecone describe_index_stats endpoint.
private struct PineconeStatsResponse: Decodable, Sendable {
    /// Total number of vectors across all namespaces.
    let totalVectorCount: Int

    /// Per-namespace statistics.
    let namespaces: [String: PineconeNamespaceStats]?
}

/// Statistics for a single Pinecone namespace.
private struct PineconeNamespaceStats: Decodable, Sendable {
    /// Number of vectors in this namespace.
    let vectorCount: Int
}
