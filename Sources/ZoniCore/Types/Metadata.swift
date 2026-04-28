// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Metadata types for document annotation and filtering in vector stores.

// MARK: - MetadataValue

/// A flexible value type for storing document metadata.
///
/// `MetadataValue` supports common JSON-compatible types and provides
/// seamless encoding/decoding for storage in vector databases.
///
/// Example usage:
/// ```swift
/// let metadata: [String: MetadataValue] = [
///     "title": "Swift Concurrency Guide",
///     "pageCount": 42,
///     "rating": 4.5,
///     "published": true,
///     "tags": ["swift", "concurrency", "async"]
/// ]
/// ```
public enum MetadataValue: Sendable, Equatable {
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
    case array([MetadataValue])

    /// A dictionary of string keys to metadata values.
    case dictionary([String: MetadataValue])
}

// MARK: - Codable Conformance

extension MetadataValue: Codable {
    public init(from decoder: Decoder) throws {
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
        if let arrayValue = try? container.decode([MetadataValue].self) {
            self = .array(arrayValue)
            return
        }

        // Try Dictionary
        if let dictValue = try? container.decode([String: MetadataValue].self) {
            self = .dictionary(dictValue)
            return
        }

        throw DecodingError.typeMismatch(
            MetadataValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unable to decode MetadataValue from the given data"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Literal Conformances

extension MetadataValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension MetadataValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension MetadataValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension MetadataValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension MetadataValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension MetadataValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: MetadataValue...) {
        self = .array(elements)
    }
}

extension MetadataValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, MetadataValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Accessor Properties

extension MetadataValue {
    /// Returns the string value if this is a `.string` case, `nil` otherwise.
    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the integer value if this is an `.int` case, `nil` otherwise.
    public var intValue: Int? {
        if case .int(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the double value if this is a `.double` case, `nil` otherwise.
    ///
    /// Note: This does not convert from `.int`. Use `numericValue` for that.
    public var doubleValue: Double? {
        if case .double(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the boolean value if this is a `.bool` case, `nil` otherwise.
    public var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the array value if this is an `.array` case, `nil` otherwise.
    public var arrayValue: [MetadataValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the dictionary value if this is a `.dictionary` case, `nil` otherwise.
    public var dictionaryValue: [String: MetadataValue]? {
        if case .dictionary(let value) = self {
            return value
        }
        return nil
    }

    /// Returns a numeric value as Double, converting from Int if necessary.
    ///
    /// Returns `nil` if the value is neither `.int` nor `.double`.
    public var numericValue: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    /// Returns `true` if this value is `.null`.
    public var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }
}

// MARK: - CustomStringConvertible

extension MetadataValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value.description
        case .int(let value):
            return value.description
        case .double(let value):
            return value.description
        case .string(let value):
            return "\"\(value)\""
        case .array(let values):
            let contents = values.map { $0.description }.joined(separator: ", ")
            return "[\(contents)]"
        case .dictionary(let dict):
            let contents = dict.sorted(by: { $0.key < $1.key })
                .map { "\"\($0.key)\": \($0.value.description)" }
                .joined(separator: ", ")
            return "{\(contents)}"
        }
    }
}

// MARK: - Hashable

extension MetadataValue: Hashable {
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

// MARK: - MetadataFilter

/// A filter for querying documents by their metadata.
///
/// `MetadataFilter` supports a wide range of comparison and logical operators
/// for building complex queries against document metadata.
///
/// Example usage:
/// ```swift
/// // Simple equality filter
/// let filter = MetadataFilter.equals("status", "published")
///
/// // Compound filter with AND logic
/// let complexFilter = MetadataFilter.and([
///     .greaterThan("rating", 4.0),
///     .equals("category", "technology"),
///     .contains("tags", "swift")
/// ])
/// ```
public struct MetadataFilter: Sendable, Equatable {
    /// The filter operator types supported for metadata queries.
    public enum Operator: Sendable, Equatable {
        /// Matches documents where the field equals the given value.
        case equals(String, MetadataValue)

        /// Matches documents where the field does not equal the given value.
        case notEquals(String, MetadataValue)

        /// Matches documents where the numeric field is greater than the given value.
        case greaterThan(String, Double)

        /// Matches documents where the numeric field is less than the given value.
        case lessThan(String, Double)

        /// Matches documents where the numeric field is greater than or equal to the given value.
        case greaterThanOrEqual(String, Double)

        /// Matches documents where the numeric field is less than or equal to the given value.
        case lessThanOrEqual(String, Double)

        /// Matches documents where the field value is in the given set.
        case `in`(String, [MetadataValue])

        /// Matches documents where the field value is not in the given set.
        case notIn(String, [MetadataValue])

        /// Matches documents where the string field contains the given substring.
        case contains(String, String)

        /// Matches documents where the string field starts with the given prefix.
        case startsWith(String, String)

        /// Matches documents where the string field ends with the given suffix.
        case endsWith(String, String)

        /// Matches documents where the field exists (is not null/missing).
        case exists(String)

        /// Matches documents where the field does not exist (is null/missing).
        case notExists(String)

        /// Matches documents that satisfy all of the given filters.
        case and([MetadataFilter])

        /// Matches documents that satisfy any of the given filters.
        case or([MetadataFilter])

        /// Matches documents that do not satisfy the given filter.
        case not(MetadataFilter)
    }

    /// The conditions that make up this filter.
    public let conditions: [Operator]

    /// Creates a new metadata filter with the given conditions.
    ///
    /// - Parameter conditions: The filter conditions to apply.
    public init(conditions: [Operator]) {
        self.conditions = conditions
    }

    /// Creates a new metadata filter with a single condition.
    ///
    /// - Parameter condition: The filter condition to apply.
    public init(_ condition: Operator) {
        self.conditions = [condition]
    }
}

// MARK: - MetadataFilter Convenience Constructors

extension MetadataFilter {
    /// Creates a filter that matches documents where the field equals the given value.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - value: The value to match.
    /// - Returns: A filter matching documents with the specified field value.
    public static func equals(_ field: String, _ value: MetadataValue) -> MetadataFilter {
        MetadataFilter(.equals(field, value))
    }

    /// Creates a filter that matches documents where the field does not equal the given value.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - value: The value to exclude.
    /// - Returns: A filter matching documents without the specified field value.
    public static func notEquals(_ field: String, _ value: MetadataValue) -> MetadataFilter {
        MetadataFilter(.notEquals(field, value))
    }

    /// Creates a filter that matches documents where the numeric field is greater than the given value.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - value: The threshold value.
    /// - Returns: A filter matching documents with field values above the threshold.
    public static func greaterThan(_ field: String, _ value: Double) -> MetadataFilter {
        MetadataFilter(.greaterThan(field, value))
    }

    /// Creates a filter that matches documents where the numeric field is less than the given value.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - value: The threshold value.
    /// - Returns: A filter matching documents with field values below the threshold.
    public static func lessThan(_ field: String, _ value: Double) -> MetadataFilter {
        MetadataFilter(.lessThan(field, value))
    }

    /// Creates a filter that matches documents where the numeric field is greater than or equal to the given value.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - value: The threshold value.
    /// - Returns: A filter matching documents with field values at or above the threshold.
    public static func greaterThanOrEqual(_ field: String, _ value: Double) -> MetadataFilter {
        MetadataFilter(.greaterThanOrEqual(field, value))
    }

    /// Creates a filter that matches documents where the numeric field is less than or equal to the given value.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - value: The threshold value.
    /// - Returns: A filter matching documents with field values at or below the threshold.
    public static func lessThanOrEqual(_ field: String, _ value: Double) -> MetadataFilter {
        MetadataFilter(.lessThanOrEqual(field, value))
    }

    /// Creates a filter that matches documents where the field value is in the given set.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - values: The set of allowed values.
    /// - Returns: A filter matching documents with field values in the set.
    public static func `in`(_ field: String, _ values: [MetadataValue]) -> MetadataFilter {
        MetadataFilter(.in(field, values))
    }

    /// Creates a filter that matches documents where the field value is not in the given set.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - values: The set of excluded values.
    /// - Returns: A filter matching documents with field values not in the set.
    public static func notIn(_ field: String, _ values: [MetadataValue]) -> MetadataFilter {
        MetadataFilter(.notIn(field, values))
    }

    /// Creates a filter that matches documents where the string field contains the given substring.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - substring: The substring to search for.
    /// - Returns: A filter matching documents containing the substring.
    public static func contains(_ field: String, _ substring: String) -> MetadataFilter {
        MetadataFilter(.contains(field, substring))
    }

    /// Creates a filter that matches documents where the string field starts with the given prefix.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - prefix: The prefix to match.
    /// - Returns: A filter matching documents starting with the prefix.
    public static func startsWith(_ field: String, _ prefix: String) -> MetadataFilter {
        MetadataFilter(.startsWith(field, prefix))
    }

    /// Creates a filter that matches documents where the string field ends with the given suffix.
    ///
    /// - Parameters:
    ///   - field: The metadata field name.
    ///   - suffix: The suffix to match.
    /// - Returns: A filter matching documents ending with the suffix.
    public static func endsWith(_ field: String, _ suffix: String) -> MetadataFilter {
        MetadataFilter(.endsWith(field, suffix))
    }

    /// Creates a filter that matches documents where the field exists.
    ///
    /// - Parameter field: The metadata field name.
    /// - Returns: A filter matching documents with the field present.
    public static func exists(_ field: String) -> MetadataFilter {
        MetadataFilter(.exists(field))
    }

    /// Creates a filter that matches documents where the field does not exist.
    ///
    /// - Parameter field: The metadata field name.
    /// - Returns: A filter matching documents without the field.
    public static func notExists(_ field: String) -> MetadataFilter {
        MetadataFilter(.notExists(field))
    }

    /// Creates a filter that matches documents satisfying all of the given filters.
    ///
    /// - Parameter filters: The filters to combine with AND logic.
    /// - Returns: A compound filter requiring all conditions to match.
    public static func and(_ filters: [MetadataFilter]) -> MetadataFilter {
        MetadataFilter(.and(filters))
    }

    /// Creates a filter that matches documents satisfying any of the given filters.
    ///
    /// - Parameter filters: The filters to combine with OR logic.
    /// - Returns: A compound filter requiring any condition to match.
    public static func or(_ filters: [MetadataFilter]) -> MetadataFilter {
        MetadataFilter(.or(filters))
    }

    /// Creates a filter that matches documents not satisfying the given filter.
    ///
    /// - Parameter filter: The filter to negate.
    /// - Returns: A filter matching the inverse of the input filter.
    public static func not(_ filter: MetadataFilter) -> MetadataFilter {
        MetadataFilter(.not(filter))
    }
}

// MARK: - MetadataFilter Hashable

extension MetadataFilter: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(conditions.count)
        for condition in conditions {
            hasher.combine(condition)
        }
    }
}

extension MetadataFilter.Operator: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .equals(let field, let value):
            hasher.combine(0)
            hasher.combine(field)
            hasher.combine(value)
        case .notEquals(let field, let value):
            hasher.combine(1)
            hasher.combine(field)
            hasher.combine(value)
        case .greaterThan(let field, let value):
            hasher.combine(2)
            hasher.combine(field)
            hasher.combine(value)
        case .lessThan(let field, let value):
            hasher.combine(3)
            hasher.combine(field)
            hasher.combine(value)
        case .greaterThanOrEqual(let field, let value):
            hasher.combine(4)
            hasher.combine(field)
            hasher.combine(value)
        case .lessThanOrEqual(let field, let value):
            hasher.combine(5)
            hasher.combine(field)
            hasher.combine(value)
        case .in(let field, let values):
            hasher.combine(6)
            hasher.combine(field)
            hasher.combine(values)
        case .notIn(let field, let values):
            hasher.combine(7)
            hasher.combine(field)
            hasher.combine(values)
        case .contains(let field, let substring):
            hasher.combine(8)
            hasher.combine(field)
            hasher.combine(substring)
        case .startsWith(let field, let prefix):
            hasher.combine(9)
            hasher.combine(field)
            hasher.combine(prefix)
        case .endsWith(let field, let suffix):
            hasher.combine(10)
            hasher.combine(field)
            hasher.combine(suffix)
        case .exists(let field):
            hasher.combine(11)
            hasher.combine(field)
        case .notExists(let field):
            hasher.combine(12)
            hasher.combine(field)
        case .and(let filters):
            hasher.combine(13)
            hasher.combine(filters)
        case .or(let filters):
            hasher.combine(14)
            hasher.combine(filters)
        case .not(let filter):
            hasher.combine(15)
            hasher.combine(filter)
        }
    }
}
