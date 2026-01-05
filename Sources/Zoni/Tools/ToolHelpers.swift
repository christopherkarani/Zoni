// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ToolHelpers.swift - Helper extensions for tool development.

import Foundation

// MARK: - SendableValue Accessor Extensions

extension SendableValue {
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

    /// Returns the double value if this is a `.double` case.
    ///
    /// Also returns a double if the value is `.int`, converting the integer to double.
    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }

    /// Returns the boolean value if this is a `.bool` case, `nil` otherwise.
    public var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the array value if this is an `.array` case, `nil` otherwise.
    public var arrayValue: [SendableValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// Returns the dictionary value if this is a `.dictionary` case, `nil` otherwise.
    public var dictionaryValue: [String: SendableValue]? {
        if case .dictionary(let value) = self {
            return value
        }
        return nil
    }

    /// Returns `true` if this is a `.null` case.
    public var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }
}

// MARK: - SendableValue <-> MetadataValue Bridging

extension SendableValue {
    /// Converts this `SendableValue` to a `MetadataValue`.
    ///
    /// Both types have the same structure, so this is a straightforward conversion.
    ///
    /// - Returns: The equivalent `MetadataValue`.
    public func toMetadataValue() -> MetadataValue {
        switch self {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .int(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        case .string(let value):
            return .string(value)
        case .array(let values):
            return .array(values.map { $0.toMetadataValue() })
        case .dictionary(let dict):
            return .dictionary(dict.mapValues { $0.toMetadataValue() })
        }
    }
}

extension MetadataValue {
    /// Converts this `MetadataValue` to a `SendableValue`.
    ///
    /// Both types have the same structure, so this is a straightforward conversion.
    ///
    /// - Returns: The equivalent `SendableValue`.
    public func toSendableValue() -> SendableValue {
        switch self {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .int(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        case .string(let value):
            return .string(value)
        case .array(let values):
            return .array(values.map { $0.toSendableValue() })
        case .dictionary(let dict):
            return .dictionary(dict.mapValues { $0.toSendableValue() })
        }
    }
}

// MARK: - Chunk Metadata Conversion

extension ChunkMetadata {
    /// Converts this chunk metadata to a `SendableValue` dictionary.
    ///
    /// Useful for including chunk metadata in tool results.
    ///
    /// - Returns: A dictionary representation of this metadata.
    public func toSendableValue() -> SendableValue {
        var dict: [String: SendableValue] = [
            "document_id": .string(documentId),
            "index": .int(index),
            "start_offset": .int(startOffset),
            "end_offset": .int(endOffset)
        ]

        if let source = source {
            dict["source"] = .string(source)
        }

        if !custom.isEmpty {
            dict["custom"] = .dictionary(custom.mapValues { $0.toSendableValue() })
        }

        return .dictionary(dict)
    }
}

// MARK: - RetrievalResult Conversion

extension RetrievalResult {
    /// Converts this retrieval result to a `SendableValue` dictionary.
    ///
    /// Useful for returning retrieval results from tool executions.
    ///
    /// - Parameter includeFullMetadata: Whether to include full chunk metadata.
    /// - Returns: A dictionary representation of this result.
    public func toSendableValue(includeFullMetadata: Bool = false) -> SendableValue {
        var dict: [String: SendableValue] = [
            "content": .string(chunk.content),
            "score": .double(Double(score)),
            "chunk_id": .string(chunk.id)
        ]

        // Include source if available
        if let source = chunk.metadata.source {
            dict["source"] = .string(source)
        }

        // Include document ID
        dict["document_id"] = .string(chunk.metadata.documentId)

        // Optionally include full metadata
        if includeFullMetadata {
            dict["metadata"] = chunk.metadata.toSendableValue()
        }

        return .dictionary(dict)
    }
}

// MARK: - RAGResponse Conversion

extension RAGResponse {
    /// Converts this RAG response to a `SendableValue` dictionary.
    ///
    /// Useful for returning RAG query results from tool executions.
    ///
    /// - Parameter includeSources: Whether to include source chunks.
    /// - Returns: A dictionary representation of this response.
    public func toSendableValue(includeSources: Bool = true) -> SendableValue {
        var dict: [String: SendableValue] = [
            "answer": .string(answer),
            "sources_used": .int(sources.count)
        ]

        if includeSources {
            dict["sources"] = .array(sources.map { $0.toSendableValue() })
        }

        // Include timing metadata if available
        if let totalTime = metadata.totalTime {
            let milliseconds = Double(totalTime.components.seconds) * 1000 +
                Double(totalTime.components.attoseconds) / 1_000_000_000_000_000
            dict["total_time_ms"] = .double(milliseconds)
        }

        if let model = metadata.model {
            dict["model"] = .string(model)
        }

        return .dictionary(dict)
    }
}

// MARK: - Argument Extraction Helpers

extension Dictionary where Key == String, Value == SendableValue {
    /// Extracts a required string argument.
    ///
    /// - Parameter name: The argument name.
    /// - Returns: The string value.
    /// - Throws: `ZoniError.invalidConfiguration` if the argument is missing or wrong type.
    public func requireString(_ name: String) throws -> String {
        guard let value = self[name]?.stringValue else {
            throw ZoniError.invalidConfiguration(reason: "Missing required '\(name)' argument")
        }
        return value
    }

    /// Extracts an optional string argument.
    ///
    /// - Parameters:
    ///   - name: The argument name.
    ///   - defaultValue: The default value if not provided.
    /// - Returns: The string value or the default.
    public func optionalString(_ name: String, default defaultValue: String? = nil) -> String? {
        self[name]?.stringValue ?? defaultValue
    }

    /// Extracts an optional integer argument.
    ///
    /// - Parameters:
    ///   - name: The argument name.
    ///   - defaultValue: The default value if not provided.
    /// - Returns: The integer value or the default.
    public func optionalInt(_ name: String, default defaultValue: Int) -> Int {
        self[name]?.intValue ?? defaultValue
    }

    /// Extracts an optional double argument.
    ///
    /// - Parameters:
    ///   - name: The argument name.
    ///   - defaultValue: The default value if not provided.
    /// - Returns: The double value or the default.
    public func optionalDouble(_ name: String, default defaultValue: Double) -> Double {
        self[name]?.doubleValue ?? defaultValue
    }

    /// Extracts an optional boolean argument.
    ///
    /// - Parameters:
    ///   - name: The argument name.
    ///   - defaultValue: The default value if not provided.
    /// - Returns: The boolean value or the default.
    public func optionalBool(_ name: String, default defaultValue: Bool) -> Bool {
        self[name]?.boolValue ?? defaultValue
    }

    /// Extracts an optional array of strings argument.
    ///
    /// - Parameter name: The argument name.
    /// - Returns: The array of strings, or `nil` if not provided or not an array.
    public func optionalStringArray(_ name: String) -> [String]? {
        self[name]?.arrayValue?.compactMap { $0.stringValue }
    }
}
