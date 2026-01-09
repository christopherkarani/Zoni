// ZoniServer - Server-side extensions for Zoni
//
// ServerDTOs.swift - Data Transfer Objects for server API serialization.
//
// This file defines all request/response DTOs for the ZoniServer APIs,
// providing clean JSON serialization for HTTP endpoints while maintaining
// type-safe conversions to and from Zoni's core types.

import Foundation
import Zoni

// MARK: - Helper Types

/// A box type to provide indirection for recursive structures.
///
/// This works around Swift compiler limitations with recursive value types
/// by providing a reference type wrapper that introduces indirection.
///
/// ## Thread Safety
/// The `Box` type is `Sendable` when its contained value is `Sendable`.
/// Since the value is immutable (`let`), there are no data race concerns.
///
/// ## Example Usage
/// ```swift
/// // Use Box to break recursive structure cycles
/// struct TreeNode: Codable, Sendable {
///     let value: String
///     let children: [Box<TreeNode>]?
/// }
/// ```
public final class Box<T: Sendable>: Sendable {
    /// The wrapped value. Immutable to ensure thread safety.
    public let value: T

    /// Creates a new box containing the given value.
    ///
    /// - Parameter value: The value to wrap.
    public init(_ value: T) {
        self.value = value
    }
}

extension Box: Codable where T: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(T.self)
        self.init(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension Box: Equatable where T: Equatable {
    public static func == (lhs: Box<T>, rhs: Box<T>) -> Bool {
        lhs.value == rhs.value
    }
}

extension Box: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

// MARK: - MetadataValueDTO

/// A JSON-compatible metadata value for API serialization.
///
/// `MetadataValueDTO` mirrors `Zoni.MetadataValue` with custom `Codable` implementation
/// that produces clean JSON output suitable for REST APIs.
///
/// Example JSON output:
/// ```json
/// {
///     "title": "Swift Guide",
///     "pageCount": 42,
///     "rating": 4.5,
///     "published": true
/// }
/// ```
public enum MetadataValueDTO: Sendable, Equatable {
    /// Represents a null/nil value.
    case null

    /// A boolean value.
    case bool(Bool)

    /// An integer value.
    case int(Int)

    /// A floating-point value.
    case double(Double)

    /// A string value.
    case string(String)

    /// An array of metadata values.
    case array([MetadataValueDTO])

    /// A dictionary of string keys to metadata values.
    case dictionary([String: MetadataValueDTO])
}

// MARK: - MetadataValueDTO Codable

extension MetadataValueDTO: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum TypeTag: String, Codable {
        case null
        case bool
        case int
        case double
        case string
        case array
        case dictionary
    }

    public init(from decoder: Decoder) throws {
        // Try to decode as a tagged structure first (for preserving type info)
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let typeTag = try? container.decode(TypeTag.self, forKey: .type) {

            switch typeTag {
            case .null:
                self = .null
            case .bool:
                let value = try container.decode(Bool.self, forKey: .value)
                self = .bool(value)
            case .int:
                let value = try container.decode(Int.self, forKey: .value)
                self = .int(value)
            case .double:
                let value = try container.decode(Double.self, forKey: .value)
                self = .double(value)
            case .string:
                let value = try container.decode(String.self, forKey: .value)
                self = .string(value)
            case .array:
                let value = try container.decode([MetadataValueDTO].self, forKey: .value)
                self = .array(value)
            case .dictionary:
                let value = try container.decode([String: MetadataValueDTO].self, forKey: .value)
                self = .dictionary(value)
            }
            return
        }

        // Fallback to untagged decoding for backwards compatibility
        let container = try decoder.singleValueContainer()

        // Try null first
        if container.decodeNil() {
            self = .null
            return
        }

        // Try Bool before Int/Double (JSON booleans are distinct)
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }

        // Try Int before Double (to preserve integer precision)
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }

        // Try Double
        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
            return
        }

        // Try String
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        // Try Array
        if let arrayValue = try? container.decode([MetadataValueDTO].self) {
            self = .array(arrayValue)
            return
        }

        // Try Dictionary
        if let dictValue = try? container.decode([String: MetadataValueDTO].self) {
            self = .dictionary(dictValue)
            return
        }

        throw DecodingError.typeMismatch(
            MetadataValueDTO.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unable to decode MetadataValueDTO from the given data"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .null:
            try container.encode(TypeTag.null, forKey: .type)
        case .bool(let value):
            try container.encode(TypeTag.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(TypeTag.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(TypeTag.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(TypeTag.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .array(let value):
            try container.encode(TypeTag.array, forKey: .type)
            try container.encode(value, forKey: .value)
        case .dictionary(let value):
            try container.encode(TypeTag.dictionary, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

// MARK: - MetadataValueDTO Conversions

extension MetadataValueDTO {
    /// Creates a DTO from a Zoni `MetadataValue`.
    ///
    /// - Parameter value: The Zoni metadata value to convert.
    public init(from value: MetadataValue) {
        switch value {
        case .null:
            self = .null
        case .bool(let v):
            self = .bool(v)
        case .int(let v):
            self = .int(v)
        case .double(let v):
            self = .double(v)
        case .string(let v):
            self = .string(v)
        case .array(let values):
            self = .array(values.map { MetadataValueDTO(from: $0) })
        case .dictionary(let dict):
            self = .dictionary(dict.mapValues { MetadataValueDTO(from: $0) })
        }
    }

    /// Converts this DTO to a Zoni `MetadataValue`.
    ///
    /// - Returns: The corresponding Zoni metadata value.
    public func toMetadataValue() -> MetadataValue {
        switch self {
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
        case .array(let values):
            return .array(values.map { $0.toMetadataValue() })
        case .dictionary(let dict):
            return .dictionary(dict.mapValues { $0.toMetadataValue() })
        }
    }
}

// MARK: - MetadataValueDTO Hashable

extension MetadataValueDTO: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0)
        case .bool(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .int(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .double(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .array(let values):
            hasher.combine(5)
            hasher.combine(values)
        case .dictionary(let dict):
            hasher.combine(6)
            hasher.combine(dict)
        }
    }
}

// MARK: - MetadataFilterDTO

/// A JSON-serializable representation of a metadata filter for API requests.
///
/// `MetadataFilterDTO` provides a flat structure suitable for JSON serialization
/// that can be converted to Zoni's `MetadataFilter` type.
///
/// Example JSON:
/// ```json
/// {
///     "type": "equals",
///     "field": "category",
///     "value": "documentation"
/// }
/// ```
///
/// Compound filter example:
/// ```json
/// {
///     "type": "and",
///     "filters": [
///         {"type": "equals", "field": "status", "value": "published"},
///         {"type": "greaterThan", "field": "rating", "value": 4.0}
///     ]
/// }
/// ```
public struct MetadataFilterDTO: Codable, Sendable {
    /// The filter operator type.
    ///
    /// Supported values:
    /// - Comparison: `equals`, `notEquals`, `greaterThan`, `lessThan`,
    ///   `greaterThanOrEqual`, `lessThanOrEqual`
    /// - Set operations: `in`, `notIn`
    /// - String operations: `contains`, `startsWith`, `endsWith`
    /// - Existence: `exists`, `notExists`
    /// - Logical: `and`, `or`, `not`
    public let type: String

    /// The metadata field name for comparison operations.
    public let field: String?

    /// The comparison value for single-value operations.
    public let value: MetadataValueDTO?

    /// The comparison values for set operations (`in`, `notIn`).
    public let values: [MetadataValueDTO]?

    /// Child filters for logical operations (`and`, `or`).
    public let filters: [MetadataFilterDTO]?

    /// The child filter for the `not` operation.
    /// Boxed to provide indirection and avoid infinite size issues.
    public let filter: Box<MetadataFilterDTO>?

    /// Creates a new metadata filter DTO.
    ///
    /// - Parameters:
    ///   - type: The filter operator type.
    ///   - field: The metadata field name for comparison operations.
    ///   - value: The comparison value for single-value operations.
    ///   - values: The comparison values for set operations.
    ///   - filters: Child filters for logical operations.
    ///   - filter: The child filter for negation.
    public init(
        type: String,
        field: String? = nil,
        value: MetadataValueDTO? = nil,
        values: [MetadataValueDTO]? = nil,
        filters: [MetadataFilterDTO]? = nil,
        filter: MetadataFilterDTO? = nil
    ) {
        self.type = type
        self.field = field
        self.value = value
        self.values = values
        self.filters = filters
        self.filter = filter.map(Box.init)
    }

    /// Converts this DTO to a Zoni `MetadataFilter`.
    ///
    /// - Returns: The corresponding metadata filter, or `nil` if the DTO is invalid.
    public func toMetadataFilter() -> MetadataFilter? {
        switch type.lowercased() {
        case "equals":
            guard let field, let value else { return nil }
            return .equals(field, value.toMetadataValue())

        case "notequals":
            guard let field, let value else { return nil }
            return .notEquals(field, value.toMetadataValue())

        case "greaterthan":
            guard let field, let value, let doubleValue = extractDouble(from: value) else { return nil }
            return .greaterThan(field, doubleValue)

        case "lessthan":
            guard let field, let value, let doubleValue = extractDouble(from: value) else { return nil }
            return .lessThan(field, doubleValue)

        case "greaterthanorequal":
            guard let field, let value, let doubleValue = extractDouble(from: value) else { return nil }
            return .greaterThanOrEqual(field, doubleValue)

        case "lessthanorequal":
            guard let field, let value, let doubleValue = extractDouble(from: value) else { return nil }
            return .lessThanOrEqual(field, doubleValue)

        case "in":
            guard let field, let values else { return nil }
            return .in(field, values.map { $0.toMetadataValue() })

        case "notin":
            guard let field, let values else { return nil }
            return .notIn(field, values.map { $0.toMetadataValue() })

        case "contains":
            guard let field, let value, case .string(let substring) = value else { return nil }
            return .contains(field, substring)

        case "startswith":
            guard let field, let value, case .string(let prefix) = value else { return nil }
            return .startsWith(field, prefix)

        case "endswith":
            guard let field, let value, case .string(let suffix) = value else { return nil }
            return .endsWith(field, suffix)

        case "exists":
            guard let field else { return nil }
            return .exists(field)

        case "notexists":
            guard let field else { return nil }
            return .notExists(field)

        case "and":
            guard let filters else { return nil }
            let converted = filters.compactMap { $0.toMetadataFilter() }
            guard converted.count == filters.count else { return nil }
            return .and(converted)

        case "or":
            guard let filters else { return nil }
            let converted = filters.compactMap { $0.toMetadataFilter() }
            guard converted.count == filters.count else { return nil }
            return .or(converted)

        case "not":
            guard let filter, let converted = filter.value.toMetadataFilter() else { return nil }
            return .not(converted)

        default:
            return nil
        }
    }

    /// Extracts a double value from a metadata value DTO.
    private func extractDouble(from value: MetadataValueDTO) -> Double? {
        switch value {
        case .double(let v):
            return v
        case .int(let v):
            return Double(v)
        default:
            return nil
        }
    }
}

// MARK: - MetadataFilterDTO Factory Methods

extension MetadataFilterDTO {
    /// Creates a DTO from a Zoni `MetadataFilter`.
    ///
    /// - Parameter filter: The Zoni metadata filter to convert.
    /// - Returns: The corresponding DTO.
    public static func from(_ filter: MetadataFilter) -> MetadataFilterDTO {
        // Handle single-condition filters
        guard filter.conditions.count == 1, let condition = filter.conditions.first else {
            // Multiple conditions are implicitly AND'd
            let childDTOs = filter.conditions.map { conditionToDTO($0) }
            return MetadataFilterDTO(type: "and", filters: childDTOs)
        }

        return conditionToDTO(condition)
    }

    /// Converts a single filter operator to a DTO.
    private static func conditionToDTO(_ condition: MetadataFilter.Operator) -> MetadataFilterDTO {
        switch condition {
        case .equals(let field, let value):
            return MetadataFilterDTO(type: "equals", field: field, value: MetadataValueDTO(from: value))

        case .notEquals(let field, let value):
            return MetadataFilterDTO(type: "notEquals", field: field, value: MetadataValueDTO(from: value))

        case .greaterThan(let field, let value):
            return MetadataFilterDTO(type: "greaterThan", field: field, value: .double(value))

        case .lessThan(let field, let value):
            return MetadataFilterDTO(type: "lessThan", field: field, value: .double(value))

        case .greaterThanOrEqual(let field, let value):
            return MetadataFilterDTO(type: "greaterThanOrEqual", field: field, value: .double(value))

        case .lessThanOrEqual(let field, let value):
            return MetadataFilterDTO(type: "lessThanOrEqual", field: field, value: .double(value))

        case .in(let field, let values):
            return MetadataFilterDTO(
                type: "in",
                field: field,
                values: values.map { MetadataValueDTO(from: $0) }
            )

        case .notIn(let field, let values):
            return MetadataFilterDTO(
                type: "notIn",
                field: field,
                values: values.map { MetadataValueDTO(from: $0) }
            )

        case .contains(let field, let substring):
            return MetadataFilterDTO(type: "contains", field: field, value: .string(substring))

        case .startsWith(let field, let prefix):
            return MetadataFilterDTO(type: "startsWith", field: field, value: .string(prefix))

        case .endsWith(let field, let suffix):
            return MetadataFilterDTO(type: "endsWith", field: field, value: .string(suffix))

        case .exists(let field):
            return MetadataFilterDTO(type: "exists", field: field)

        case .notExists(let field):
            return MetadataFilterDTO(type: "notExists", field: field)

        case .and(let filters):
            return MetadataFilterDTO(type: "and", filters: filters.map { from($0) })

        case .or(let filters):
            return MetadataFilterDTO(type: "or", filters: filters.map { from($0) })

        case .not(let filter):
            return MetadataFilterDTO(type: "not", filter: from(filter))
        }
    }
}

// MARK: - Query DTOs

/// Configuration options for a query request.
///
/// All fields are optional, allowing clients to override only specific settings
/// while using defaults for the rest.
///
/// Example JSON:
/// ```json
/// {
///     "retrievalLimit": 10,
///     "temperature": 0.7,
///     "includeMetadata": true
/// }
/// ```
public struct QueryRequestOptions: Codable, Sendable {
    /// The maximum number of chunks to retrieve for context.
    public var retrievalLimit: Int?

    /// An optional system prompt to use for generation.
    public var systemPrompt: String?

    /// The sampling temperature for generation.
    public var temperature: Double?

    /// An optional metadata filter to apply during retrieval.
    public var filter: MetadataFilterDTO?

    /// The maximum number of tokens to include in the context.
    public var maxContextTokens: Int?

    /// Whether to include metadata in the response sources.
    public var includeMetadata: Bool?

    /// Creates new query request options.
    ///
    /// - Parameters:
    ///   - retrievalLimit: Maximum chunks to retrieve.
    ///   - systemPrompt: Optional system prompt override.
    ///   - temperature: Optional temperature override.
    ///   - filter: Optional metadata filter.
    ///   - maxContextTokens: Maximum context tokens.
    ///   - includeMetadata: Whether to include metadata in sources.
    public init(
        retrievalLimit: Int? = nil,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        filter: MetadataFilterDTO? = nil,
        maxContextTokens: Int? = nil,
        includeMetadata: Bool? = nil
    ) {
        self.retrievalLimit = retrievalLimit
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.filter = filter
        self.maxContextTokens = maxContextTokens
        self.includeMetadata = includeMetadata
    }
}

/// A query request from an API client.
///
/// Example JSON:
/// ```json
/// {
///     "query": "How do I use async/await in Swift?",
///     "options": {
///         "retrievalLimit": 5,
///         "temperature": 0.5
///     }
/// }
/// ```
public struct QueryRequest: Codable, Sendable {
    /// The user's query text.
    public let query: String

    /// Optional configuration for the query.
    public let options: QueryRequestOptions?

    /// Creates a new query request.
    ///
    /// - Parameters:
    ///   - query: The user's query text.
    ///   - options: Optional configuration for the query.
    public init(query: String, options: QueryRequestOptions? = nil) {
        self.query = query
        self.options = options
    }

    /// Converts this request to Zoni `QueryOptions`.
    ///
    /// - Returns: The corresponding query options with defaults applied.
    public func toQueryOptions() -> QueryOptions {
        var queryOptions = QueryOptions.default

        if let retrievalLimit = options?.retrievalLimit {
            queryOptions.retrievalLimit = retrievalLimit
        }
        if let systemPrompt = options?.systemPrompt {
            queryOptions.systemPrompt = systemPrompt
        }
        if let temperature = options?.temperature {
            queryOptions.temperature = temperature
        }
        if let filterDTO = options?.filter {
            queryOptions.filter = filterDTO.toMetadataFilter()
        }
        if let maxContextTokens = options?.maxContextTokens {
            queryOptions.maxContextTokens = maxContextTokens
        }
        if let includeMetadata = options?.includeMetadata {
            queryOptions.includeMetadata = includeMetadata
        }

        return queryOptions
    }
}

/// A source chunk returned in a query response.
///
/// Example JSON:
/// ```json
/// {
///     "id": "chunk-123",
///     "content": "Swift's async/await provides structured concurrency...",
///     "score": 0.92,
///     "documentId": "doc-456",
///     "source": "swift-guide.md",
///     "metadata": {"section": "Concurrency"}
/// }
/// ```
public struct SourceDTO: Codable, Sendable, Equatable {
    /// The unique identifier of the source chunk.
    public let id: String

    /// The text content of the chunk.
    public let content: String

    /// The relevance score (higher = more relevant).
    public let score: Float

    /// The ID of the document this chunk belongs to.
    public let documentId: String

    /// The original source identifier (e.g., file path).
    public let source: String?

    /// Additional metadata associated with this chunk.
    public let metadata: [String: MetadataValueDTO]?

    /// Creates a new source DTO.
    ///
    /// - Parameters:
    ///   - id: The unique identifier of the source chunk.
    ///   - content: The text content of the chunk.
    ///   - score: The relevance score.
    ///   - documentId: The ID of the source document.
    ///   - source: The original source identifier.
    ///   - metadata: Additional metadata.
    public init(
        id: String,
        content: String,
        score: Float,
        documentId: String,
        source: String?,
        metadata: [String: MetadataValueDTO]?
    ) {
        self.id = id
        self.content = content
        self.score = score
        self.documentId = documentId
        self.source = source
        self.metadata = metadata
    }

    /// Creates a source DTO from a Zoni `RetrievalResult`.
    ///
    /// - Parameters:
    ///   - result: The retrieval result to convert.
    ///   - includeMetadata: Whether to include metadata in the DTO.
    public init(from result: RetrievalResult, includeMetadata: Bool = true) {
        self.id = result.chunk.id
        self.content = result.chunk.content
        self.score = result.score
        self.documentId = result.chunk.metadata.documentId
        self.source = result.chunk.metadata.source

        if includeMetadata {
            var combinedMetadata: [String: MetadataValueDTO] = [:]

            // Include chunk custom metadata
            for (key, value) in result.chunk.metadata.custom {
                combinedMetadata[key] = MetadataValueDTO(from: value)
            }

            // Include retrieval metadata
            for (key, value) in result.metadata {
                combinedMetadata["retrieval_\(key)"] = MetadataValueDTO(from: value)
            }

            self.metadata = combinedMetadata.isEmpty ? nil : combinedMetadata
        } else {
            self.metadata = nil
        }
    }
}

/// Metadata about a query response for observability.
///
/// Example JSON:
/// ```json
/// {
///     "retrievalTimeMs": 45.2,
///     "generationTimeMs": 1250.5,
///     "totalTimeMs": 1295.7,
///     "model": "gpt-4",
///     "chunksRetrieved": 5
/// }
/// ```
public struct QueryMetadataDTO: Codable, Sendable, Equatable {
    /// Time spent on retrieval in milliseconds.
    public let retrievalTimeMs: Double?

    /// Time spent on generation in milliseconds.
    public let generationTimeMs: Double?

    /// Total query time in milliseconds.
    public let totalTimeMs: Double?

    /// The model identifier used for generation.
    public let model: String?

    /// The number of chunks retrieved.
    public let chunksRetrieved: Int?

    /// Creates new query metadata DTO.
    ///
    /// - Parameters:
    ///   - retrievalTimeMs: Retrieval time in milliseconds.
    ///   - generationTimeMs: Generation time in milliseconds.
    ///   - totalTimeMs: Total time in milliseconds.
    ///   - model: The model identifier.
    ///   - chunksRetrieved: Number of chunks retrieved.
    public init(
        retrievalTimeMs: Double? = nil,
        generationTimeMs: Double? = nil,
        totalTimeMs: Double? = nil,
        model: String? = nil,
        chunksRetrieved: Int? = nil
    ) {
        self.retrievalTimeMs = retrievalTimeMs
        self.generationTimeMs = generationTimeMs
        self.totalTimeMs = totalTimeMs
        self.model = model
        self.chunksRetrieved = chunksRetrieved
    }

    /// Creates a metadata DTO from Zoni `RAGResponseMetadata`.
    ///
    /// - Parameter metadata: The response metadata to convert.
    public init(from metadata: RAGResponseMetadata) {
        self.retrievalTimeMs = metadata.retrievalTime.map { durationToMilliseconds($0) }
        self.generationTimeMs = metadata.generationTime.map { durationToMilliseconds($0) }
        self.totalTimeMs = metadata.totalTime.map { durationToMilliseconds($0) }
        self.model = metadata.model
        self.chunksRetrieved = metadata.chunksRetrieved
    }
}

/// The complete response from a RAG query.
///
/// Example JSON:
/// ```json
/// {
///     "answer": "To use async/await in Swift...",
///     "sources": [...],
///     "metadata": {...}
/// }
/// ```
public struct QueryResponse: Codable, Sendable, Equatable {
    /// The generated answer text.
    public let answer: String

    /// The source chunks used to generate the answer.
    public let sources: [SourceDTO]

    /// Metadata about the response generation.
    public let metadata: QueryMetadataDTO

    /// Creates a new query response.
    ///
    /// - Parameters:
    ///   - answer: The generated answer text.
    ///   - sources: The source chunks used.
    ///   - metadata: Response metadata.
    public init(answer: String, sources: [SourceDTO], metadata: QueryMetadataDTO) {
        self.answer = answer
        self.sources = sources
        self.metadata = metadata
    }

    /// Creates a query response from a Zoni `RAGResponse`.
    ///
    /// - Parameters:
    ///   - response: The RAG response to convert.
    ///   - includeMetadata: Whether to include chunk metadata in sources.
    public init(from response: RAGResponse, includeMetadata: Bool = true) {
        self.answer = response.answer
        self.sources = response.sources.map { SourceDTO(from: $0, includeMetadata: includeMetadata) }
        self.metadata = QueryMetadataDTO(from: response.metadata)
    }
}

#if HUMMINGBIRD
import Hummingbird
import NIOCore

extension QueryResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: buffer))
    }
}
#endif

// MARK: - Ingest DTOs

/// A document to be ingested via the API.
///
/// Example JSON:
/// ```json
/// {
///     "content": "Swift is a powerful programming language...",
///     "source": "swift-guide.md",
///     "title": "Swift Programming Guide",
///     "metadata": {"category": "documentation"}
/// }
/// ```
public struct DocumentDTO: Codable, Sendable, Equatable {
    /// The text content of the document.
    public let content: String

    /// The source identifier (e.g., file path or URL).
    public let source: String?

    /// The document title.
    public let title: String?

    /// Additional metadata for the document.
    public let metadata: [String: MetadataValueDTO]?

    /// Creates a new document DTO.
    ///
    /// - Parameters:
    ///   - content: The text content.
    ///   - source: The source identifier.
    ///   - title: The document title.
    ///   - metadata: Additional metadata.
    public init(
        content: String,
        source: String? = nil,
        title: String? = nil,
        metadata: [String: MetadataValueDTO]? = nil
    ) {
        self.content = content
        self.source = source
        self.title = title
        self.metadata = metadata
    }

    /// Converts this DTO to a Zoni `Document`.
    ///
    /// - Parameter id: Optional document ID. Defaults to a new UUID.
    /// - Returns: The corresponding Zoni document.
    public func toDocument(id: String = UUID().uuidString) -> Document {
        var documentMetadata = DocumentMetadata(
            source: source,
            title: title
        )

        if let metadata {
            documentMetadata.custom = metadata.mapValues { $0.toMetadataValue() }
        }

        return Document(
            id: id,
            content: content,
            metadata: documentMetadata
        )
    }
}

/// Configuration options for document ingestion.
///
/// Example JSON:
/// ```json
/// {
///     "chunkSize": 512,
///     "chunkOverlap": 50,
///     "async": true
/// }
/// ```
public struct IngestOptions: Codable, Sendable, Equatable {
    /// The target size for each chunk in characters.
    public var chunkSize: Int?

    /// The number of characters to overlap between chunks.
    public var chunkOverlap: Int?

    /// Whether to process ingestion asynchronously.
    ///
    /// When true, the request returns immediately with a job ID
    /// that can be used to track progress.
    public var async: Bool?

    /// Creates new ingest options.
    ///
    /// - Parameters:
    ///   - chunkSize: Target chunk size in characters.
    ///   - chunkOverlap: Overlap between chunks in characters.
    ///   - async: Whether to process asynchronously.
    public init(
        chunkSize: Int? = nil,
        chunkOverlap: Int? = nil,
        async: Bool? = nil
    ) {
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.async = async
    }
}

/// A request to ingest documents into the RAG system.
///
/// Supports three ingestion modes:
/// 1. Direct content: Provide `content` directly
/// 2. URL-based: Provide a `url` to fetch content from
/// 3. Batch: Provide an array of `documents`
///
/// Example JSON (direct content):
/// ```json
/// {
///     "content": "Document content here...",
///     "options": {"chunkSize": 512}
/// }
/// ```
///
/// Example JSON (batch):
/// ```json
/// {
///     "documents": [
///         {"content": "First document...", "title": "Doc 1"},
///         {"content": "Second document...", "title": "Doc 2"}
///     ]
/// }
/// ```
public struct IngestRequest: Codable, Sendable, Equatable {
    /// Direct content to ingest (single document mode).
    public let content: String?

    /// URL to fetch content from (URL mode).
    public let url: String?

    /// Array of documents to ingest (batch mode).
    public let documents: [DocumentDTO]?

    /// Optional ingestion configuration.
    public let options: IngestOptions?

    /// Creates a new ingest request.
    ///
    /// - Parameters:
    ///   - content: Direct content to ingest.
    ///   - url: URL to fetch content from.
    ///   - documents: Array of documents to ingest.
    ///   - options: Optional ingestion configuration.
    public init(
        content: String? = nil,
        url: String? = nil,
        documents: [DocumentDTO]? = nil,
        options: IngestOptions? = nil
    ) {
        self.content = content
        self.url = url
        self.documents = documents
        self.options = options
    }
}

/// The response from a document ingestion request.
///
/// Example JSON:
/// ```json
/// {
///     "success": true,
///     "documentIds": ["doc-123", "doc-456"],
///     "chunksCreated": 42,
///     "message": "Successfully ingested 2 documents"
/// }
/// ```
///
/// Async response example:
/// ```json
/// {
///     "success": true,
///     "documentIds": [],
///     "chunksCreated": 0,
///     "jobId": "job-789",
///     "message": "Ingestion started. Track progress with job ID."
/// }
/// ```
public struct IngestResponse: Codable, Sendable, Equatable {
    /// Whether the ingestion was successful.
    public let success: Bool

    /// The IDs of the ingested documents.
    public let documentIds: [String]

    /// The total number of chunks created.
    public let chunksCreated: Int

    /// Job ID for async ingestion (only present when async=true).
    public let jobId: String?

    /// An optional human-readable message.
    public let message: String?

    /// Creates a new ingest response.
    ///
    /// - Parameters:
    ///   - success: Whether the ingestion was successful.
    ///   - documentIds: The IDs of ingested documents.
    ///   - chunksCreated: The number of chunks created.
    ///   - jobId: Optional job ID for async operations.
    ///   - message: Optional human-readable message.
    public init(
        success: Bool,
        documentIds: [String],
        chunksCreated: Int,
        jobId: String? = nil,
        message: String? = nil
    ) {
        self.success = success
        self.documentIds = documentIds
        self.chunksCreated = chunksCreated
        self.jobId = jobId
        self.message = message
    }
}

#if HUMMINGBIRD
extension IngestResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: buffer))
    }
}
#endif

// MARK: - Index DTOs

/// A request to create a new vector index.
///
/// Example JSON:
/// ```json
/// {
///     "name": "my-knowledge-base",
///     "dimensions": 1536,
///     "indexType": "hnsw"
/// }
/// ```
public struct CreateIndexRequest: Codable, Sendable, Equatable {
    /// The unique name for the index.
    public let name: String

    /// The dimensionality of embedding vectors.
    ///
    /// Must match the embedding model's output dimensions.
    /// Common values: 384 (MiniLM), 768 (BERT), 1536 (OpenAI ada-002).
    public let dimensions: Int?

    /// The type of index to create.
    ///
    /// Supported values depend on the vector store implementation.
    /// Common types: "flat", "hnsw", "ivf".
    public let indexType: String?

    /// Creates a new create index request.
    ///
    /// - Parameters:
    ///   - name: The unique name for the index.
    ///   - dimensions: The embedding vector dimensions.
    ///   - indexType: The type of index to create.
    public init(name: String, dimensions: Int? = nil, indexType: String? = nil) {
        self.name = name
        self.dimensions = dimensions
        self.indexType = indexType
    }
}

/// Information about an existing vector index.
///
/// Example JSON:
/// ```json
/// {
///     "name": "my-knowledge-base",
///     "documentCount": 150,
///     "chunkCount": 2340,
///     "dimensions": 1536,
///     "createdAt": "2024-01-15T10:30:00Z"
/// }
/// ```
public struct IndexInfo: Codable, Sendable, Equatable {
    /// The unique name of the index.
    public let name: String

    /// The number of documents in the index.
    public let documentCount: Int

    /// The number of chunks (vectors) in the index.
    public let chunkCount: Int

    /// The dimensionality of vectors in this index.
    public let dimensions: Int

    /// The timestamp when the index was created.
    public let createdAt: Date

    /// Creates new index info.
    ///
    /// - Parameters:
    ///   - name: The index name.
    ///   - documentCount: Number of documents.
    ///   - chunkCount: Number of chunks.
    ///   - dimensions: Vector dimensions.
    ///   - createdAt: Creation timestamp.
    public init(
        name: String,
        documentCount: Int,
        chunkCount: Int,
        dimensions: Int,
        createdAt: Date
    ) {
        self.name = name
        self.documentCount = documentCount
        self.chunkCount = chunkCount
        self.dimensions = dimensions
        self.createdAt = createdAt
    }
}

// MARK: - Job DTOs

/// The status of an asynchronous job.
public enum JobStatus: String, Codable, Sendable {
    /// The job is queued but has not started.
    case pending

    /// The job is currently executing.
    case running

    /// The job completed successfully.
    case completed

    /// The job failed with an error.
    case failed

    /// The job was cancelled before completion.
    case cancelled
}

/// The result of a completed job.
///
/// Example JSON:
/// ```json
/// {
///     "documentIds": ["doc-123", "doc-456"],
///     "chunksCreated": 42,
///     "message": "Successfully processed 2 documents"
/// }
/// ```
public struct JobResultDTO: Codable, Sendable, Equatable {
    /// The IDs of documents created by the job.
    public let documentIds: [String]?

    /// The number of chunks created by the job.
    public let chunksCreated: Int?

    /// An optional result message.
    public let message: String?

    /// Creates a new job result DTO.
    ///
    /// - Parameters:
    ///   - documentIds: Document IDs created.
    ///   - chunksCreated: Number of chunks created.
    ///   - message: Optional result message.
    public init(
        documentIds: [String]? = nil,
        chunksCreated: Int? = nil,
        message: String? = nil
    ) {
        self.documentIds = documentIds
        self.chunksCreated = chunksCreated
        self.message = message
    }
}

/// The status response for an asynchronous job.
///
/// Example JSON (running):
/// ```json
/// {
///     "jobId": "job-123",
///     "status": "running",
///     "progress": 0.45,
///     "createdAt": "2024-01-15T10:30:00Z"
/// }
/// ```
///
/// Example JSON (completed):
/// ```json
/// {
///     "jobId": "job-123",
///     "status": "completed",
///     "progress": 1.0,
///     "result": {...},
///     "createdAt": "2024-01-15T10:30:00Z",
///     "completedAt": "2024-01-15T10:31:30Z"
/// }
/// ```
public struct JobStatusResponse: Codable, Sendable, Equatable {
    /// The unique identifier of the job.
    public let jobId: String

    /// The current status of the job.
    public let status: JobStatus

    /// The progress percentage (0.0 to 1.0).
    public let progress: Double?

    /// The result when the job completes successfully.
    public let result: JobResultDTO?

    /// The error message if the job failed.
    public let error: String?

    /// The timestamp when the job was created.
    public let createdAt: Date

    /// The timestamp when the job completed (success or failure).
    public let completedAt: Date?

    /// Creates a new job status response.
    ///
    /// - Parameters:
    ///   - jobId: The job identifier.
    ///   - status: The current status.
    ///   - progress: The progress percentage.
    ///   - result: The result (for completed jobs).
    ///   - error: The error message (for failed jobs).
    ///   - createdAt: The creation timestamp.
    ///   - completedAt: The completion timestamp.
    public init(
        jobId: String,
        status: JobStatus,
        progress: Double? = nil,
        result: JobResultDTO? = nil,
        error: String? = nil,
        createdAt: Date,
        completedAt: Date? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.result = result
        self.error = error
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

#if HUMMINGBIRD
extension JobStatusResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: buffer))
    }
}
#endif

// MARK: - Health DTOs

/// The health status response from the server.
///
/// Example JSON:
/// ```json
/// {
///     "status": "healthy",
///     "version": "1.0.0",
///     "timestamp": "2024-01-15T10:30:00Z"
/// }
/// ```
public struct HealthResponse: Codable, Sendable, Equatable {
    /// The overall health status.
    ///
    /// Common values: "healthy", "degraded", "unhealthy".
    public let status: String

    /// The server version string.
    public let version: String

    /// The timestamp of the health check.
    public let timestamp: Date

    /// Creates a new health response.
    ///
    /// - Parameters:
    ///   - status: The overall health status.
    ///   - version: The server version.
    ///   - timestamp: The health check timestamp.
    public init(status: String, version: String, timestamp: Date) {
        self.status = status
        self.version = version
        self.timestamp = timestamp
    }
}

#if HUMMINGBIRD
extension HealthResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: buffer))
    }
}
#endif

/// The readiness status response from the server.
///
/// Readiness indicates whether the server is ready to accept traffic.
/// This is typically used by load balancers and orchestrators.
///
/// Example JSON:
/// ```json
/// {
///     "ready": true,
///     "checks": {
///         "database": true,
///         "vectorStore": true,
///         "embeddingService": true
///     }
/// }
/// ```
public struct ReadinessResponse: Codable, Sendable, Equatable {
    /// Whether the server is ready to accept requests.
    public let ready: Bool

    /// Individual readiness checks by component name.
    public let checks: [String: Bool]

    /// Creates a new readiness response.
    ///
    /// - Parameters:
    ///   - ready: Whether the server is ready.
    ///   - checks: Individual component checks.
    public init(ready: Bool, checks: [String: Bool]) {
        self.ready = ready
        self.checks = checks
    }
}

#if HUMMINGBIRD
extension ReadinessResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: buffer))
    }
}
#endif

// MARK: - Streaming DTOs

/// Events emitted during a streaming query response.
///
/// This enum provides JSON-serializable representations of streaming events
/// for Server-Sent Events (SSE) or WebSocket communication.
public enum StreamEventDTO: Codable, Sendable, Equatable {
    /// Emitted when retrieval begins.
    case retrievalStarted

    /// Emitted when retrieval completes with sources.
    case retrievalComplete([SourceDTO])

    /// Emitted when LLM generation begins.
    case generationStarted

    /// Emitted for each chunk of generated text.
    case generationChunk(String)

    /// Emitted when generation completes with the full answer.
    case generationComplete(String)

    /// Emitted when the entire operation completes.
    case complete(QueryResponse)

    /// Emitted when an error occurs.
    case error(String)

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum EventType: String, Codable {
        case retrievalStarted
        case retrievalComplete
        case generationStarted
        case generationChunk
        case generationComplete
        case complete
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)

        switch type {
        case .retrievalStarted:
            self = .retrievalStarted
        case .retrievalComplete:
            let sources = try container.decode([SourceDTO].self, forKey: .data)
            self = .retrievalComplete(sources)
        case .generationStarted:
            self = .generationStarted
        case .generationChunk:
            let text = try container.decode(String.self, forKey: .data)
            self = .generationChunk(text)
        case .generationComplete:
            let answer = try container.decode(String.self, forKey: .data)
            self = .generationComplete(answer)
        case .complete:
            let response = try container.decode(QueryResponse.self, forKey: .data)
            self = .complete(response)
        case .error:
            let message = try container.decode(String.self, forKey: .data)
            self = .error(message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .retrievalStarted:
            try container.encode(EventType.retrievalStarted, forKey: .type)
        case .retrievalComplete(let sources):
            try container.encode(EventType.retrievalComplete, forKey: .type)
            try container.encode(sources, forKey: .data)
        case .generationStarted:
            try container.encode(EventType.generationStarted, forKey: .type)
        case .generationChunk(let text):
            try container.encode(EventType.generationChunk, forKey: .type)
            try container.encode(text, forKey: .data)
        case .generationComplete(let answer):
            try container.encode(EventType.generationComplete, forKey: .type)
            try container.encode(answer, forKey: .data)
        case .complete(let response):
            try container.encode(EventType.complete, forKey: .type)
            try container.encode(response, forKey: .data)
        case .error(let message):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(message, forKey: .data)
        }
    }
}

// MARK: - StreamEventDTO Conversions

extension StreamEventDTO {
    /// Creates a stream event DTO from a Zoni `RAGStreamEvent`.
    ///
    /// - Parameters:
    ///   - event: The RAG stream event to convert.
    ///   - includeMetadata: Whether to include metadata in sources.
    /// - Returns: The corresponding stream event DTO.
    public static func from(_ event: RAGStreamEvent, includeMetadata: Bool = true) -> StreamEventDTO {
        switch event {
        case .retrievalStarted:
            return .retrievalStarted
        case .retrievalComplete(let results):
            let sources = results.map { SourceDTO(from: $0, includeMetadata: includeMetadata) }
            return .retrievalComplete(sources)
        case .generationStarted:
            return .generationStarted
        case .generationChunk(let text):
            return .generationChunk(text)
        case .generationComplete(let answer):
            return .generationComplete(answer)
        case .complete(let response):
            return .complete(QueryResponse(from: response, includeMetadata: includeMetadata))
        case .error(let error):
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - Error DTOs

/// A standardized error response for API errors.
///
/// Example JSON:
/// ```json
/// {
///     "error": "ValidationError",
///     "message": "Query text cannot be empty",
///     "code": "VALIDATION_ERROR",
///     "details": {"field": "query"}
/// }
/// ```
public struct ErrorResponse: Codable, Sendable, Equatable {
    /// The error type or category.
    public let error: String

    /// A human-readable error message.
    public let message: String

    /// An optional machine-readable error code.
    public let code: String?

    /// Additional error details.
    public let details: [String: MetadataValueDTO]?

    /// Creates a new error response.
    ///
    /// - Parameters:
    ///   - error: The error type.
    ///   - message: The error message.
    ///   - code: Optional error code.
    ///   - details: Optional error details.
    public init(
        error: String,
        message: String,
        code: String? = nil,
        details: [String: MetadataValueDTO]? = nil
    ) {
        self.error = error
        self.message = message
        self.code = code
        self.details = details
    }
}

// MARK: - Helper Functions

/// Converts a Duration to milliseconds.
///
/// - Parameter duration: The duration to convert.
/// - Returns: The duration in milliseconds.
private func durationToMilliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    let seconds = Double(components.seconds)
    let attoseconds = Double(components.attoseconds)
    return (seconds * 1000) + (attoseconds / 1_000_000_000_000_000)
}
