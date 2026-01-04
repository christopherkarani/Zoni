// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MetadataFilter matching extension for evaluating filters against chunks.

// MARK: - MetadataFilter Matching

extension MetadataFilter {
    /// Evaluates this filter against a chunk's metadata.
    ///
    /// Returns `true` if the chunk matches all conditions in this filter.
    /// All conditions in the `conditions` array must pass (implicit AND semantics).
    ///
    /// This method handles both reserved field names (documentId, index, startOffset,
    /// endOffset, source) and custom metadata fields.
    ///
    /// Example usage:
    /// ```swift
    /// let filter = MetadataFilter.and([
    ///     .equals("documentId", "doc-123"),
    ///     .greaterThan("index", 5.0)
    /// ])
    ///
    /// let chunk = Chunk(
    ///     content: "Some text...",
    ///     metadata: ChunkMetadata(documentId: "doc-123", index: 10)
    /// )
    ///
    /// if filter.matches(chunk) {
    ///     print("Chunk matches filter criteria")
    /// }
    /// ```
    ///
    /// - Parameter chunk: The chunk to evaluate against this filter.
    /// - Returns: `true` if the chunk matches all conditions, `false` otherwise.
    public func matches(_ chunk: Chunk) -> Bool {
        // All conditions must pass (implicit AND)
        for condition in conditions {
            if !evaluateOperator(condition, chunk: chunk) {
                return false
            }
        }
        return true
    }

    /// Evaluates this filter against a metadata dictionary.
    ///
    /// This is useful for evaluating filters against arbitrary metadata
    /// without requiring a full `Chunk` instance.
    ///
    /// Example usage:
    /// ```swift
    /// let filter = MetadataFilter.equals("status", "published")
    /// let metadata: [String: MetadataValue] = ["status": "published", "rating": 4.5]
    ///
    /// if filter.matches(metadata) {
    ///     print("Metadata matches filter")
    /// }
    /// ```
    ///
    /// - Parameter metadata: The metadata dictionary to evaluate against this filter.
    /// - Returns: `true` if the metadata matches all conditions, `false` otherwise.
    public func matches(_ metadata: [String: MetadataValue]) -> Bool {
        // All conditions must pass (implicit AND)
        for condition in conditions {
            if !evaluateOperator(condition, metadata: metadata) {
                return false
            }
        }
        return true
    }
}

// MARK: - Private Helpers

extension MetadataFilter {
    /// Retrieves a metadata value from a chunk by field name.
    ///
    /// Handles reserved field names that map to `ChunkMetadata` properties:
    /// - `documentId`: Returns the chunk's document ID as a string value
    /// - `index`: Returns the chunk's index as an integer value
    /// - `startOffset`: Returns the chunk's start offset as an integer value
    /// - `endOffset`: Returns the chunk's end offset as an integer value
    /// - `source`: Returns the chunk's source as a string value (or nil if not set)
    ///
    /// All other field names are looked up in the chunk's custom metadata dictionary.
    ///
    /// - Parameters:
    ///   - field: The field name to look up.
    ///   - chunk: The chunk to retrieve the value from.
    /// - Returns: The metadata value for the field, or `nil` if not found.
    private func getValue(_ field: String, from chunk: Chunk) -> MetadataValue? {
        switch field {
        case "documentId":
            return .string(chunk.metadata.documentId)
        case "index":
            return .int(chunk.metadata.index)
        case "startOffset":
            return .int(chunk.metadata.startOffset)
        case "endOffset":
            return .int(chunk.metadata.endOffset)
        case "source":
            return chunk.metadata.source.map { .string($0) }
        default:
            return chunk.metadata.custom[field]
        }
    }

    /// Evaluates a single operator condition against a chunk.
    ///
    /// - Parameters:
    ///   - op: The operator to evaluate.
    ///   - chunk: The chunk to evaluate against.
    /// - Returns: `true` if the condition is satisfied, `false` otherwise.
    private func evaluateOperator(_ op: Operator, chunk: Chunk) -> Bool {
        switch op {
        case .equals(let field, let expected):
            guard let value = getValue(field, from: chunk) else { return false }
            return value == expected

        case .notEquals(let field, let expected):
            guard let value = getValue(field, from: chunk) else { return true }
            return value != expected

        case .greaterThan(let field, let threshold):
            guard let value = getValue(field, from: chunk),
                  let numericValue = value.numericValue else { return false }
            return numericValue > threshold

        case .lessThan(let field, let threshold):
            guard let value = getValue(field, from: chunk),
                  let numericValue = value.numericValue else { return false }
            return numericValue < threshold

        case .greaterThanOrEqual(let field, let threshold):
            guard let value = getValue(field, from: chunk),
                  let numericValue = value.numericValue else { return false }
            return numericValue >= threshold

        case .lessThanOrEqual(let field, let threshold):
            guard let value = getValue(field, from: chunk),
                  let numericValue = value.numericValue else { return false }
            return numericValue <= threshold

        case .in(let field, let allowedValues):
            guard let value = getValue(field, from: chunk) else { return false }
            return allowedValues.contains(value)

        case .notIn(let field, let excludedValues):
            guard let value = getValue(field, from: chunk) else { return true }
            return !excludedValues.contains(value)

        case .contains(let field, let substring):
            guard let value = getValue(field, from: chunk),
                  let stringValue = value.stringValue else { return false }
            return stringValue.contains(substring)

        case .startsWith(let field, let prefix):
            guard let value = getValue(field, from: chunk),
                  let stringValue = value.stringValue else { return false }
            return stringValue.hasPrefix(prefix)

        case .endsWith(let field, let suffix):
            guard let value = getValue(field, from: chunk),
                  let stringValue = value.stringValue else { return false }
            return stringValue.hasSuffix(suffix)

        case .exists(let field):
            guard let value = getValue(field, from: chunk) else { return false }
            return !value.isNull

        case .notExists(let field):
            guard let value = getValue(field, from: chunk) else { return true }
            return value.isNull

        case .and(let filters):
            return filters.allSatisfy { $0.matches(chunk) }

        case .or(let filters):
            return filters.contains { $0.matches(chunk) }

        case .not(let filter):
            return !filter.matches(chunk)
        }
    }

    /// Evaluates a single operator condition against a metadata dictionary.
    ///
    /// - Parameters:
    ///   - op: The operator to evaluate.
    ///   - metadata: The metadata dictionary to evaluate against.
    /// - Returns: `true` if the condition is satisfied, `false` otherwise.
    private func evaluateOperator(_ op: Operator, metadata: [String: MetadataValue]) -> Bool {
        switch op {
        case .equals(let field, let expected):
            guard let value = metadata[field] else { return false }
            return value == expected

        case .notEquals(let field, let expected):
            guard let value = metadata[field] else { return true }
            return value != expected

        case .greaterThan(let field, let threshold):
            guard let value = metadata[field],
                  let numericValue = value.numericValue else { return false }
            return numericValue > threshold

        case .lessThan(let field, let threshold):
            guard let value = metadata[field],
                  let numericValue = value.numericValue else { return false }
            return numericValue < threshold

        case .greaterThanOrEqual(let field, let threshold):
            guard let value = metadata[field],
                  let numericValue = value.numericValue else { return false }
            return numericValue >= threshold

        case .lessThanOrEqual(let field, let threshold):
            guard let value = metadata[field],
                  let numericValue = value.numericValue else { return false }
            return numericValue <= threshold

        case .in(let field, let allowedValues):
            guard let value = metadata[field] else { return false }
            return allowedValues.contains(value)

        case .notIn(let field, let excludedValues):
            guard let value = metadata[field] else { return true }
            return !excludedValues.contains(value)

        case .contains(let field, let substring):
            guard let value = metadata[field],
                  let stringValue = value.stringValue else { return false }
            return stringValue.contains(substring)

        case .startsWith(let field, let prefix):
            guard let value = metadata[field],
                  let stringValue = value.stringValue else { return false }
            return stringValue.hasPrefix(prefix)

        case .endsWith(let field, let suffix):
            guard let value = metadata[field],
                  let stringValue = value.stringValue else { return false }
            return stringValue.hasSuffix(suffix)

        case .exists(let field):
            guard let value = metadata[field] else { return false }
            return !value.isNull

        case .notExists(let field):
            guard let value = metadata[field] else { return true }
            return value.isNull

        case .and(let filters):
            return filters.allSatisfy { $0.matches(metadata) }

        case .or(let filters):
            return filters.contains { $0.matches(metadata) }

        case .not(let filter):
            return !filter.matches(metadata)
        }
    }
}
