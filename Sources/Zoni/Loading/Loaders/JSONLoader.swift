// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// JSONLoader.swift - Loader for JSON files

import Foundation

/// A document loader for JSON files with optional path-based extraction.
///
/// `JSONLoader` supports loading `.json` files and extracting content from
/// specific JSON paths. It can handle both single JSON objects and arrays,
/// converting them to one or more documents.
///
/// ## Example
/// ```swift
/// // Load entire JSON as content
/// let loader = JSONLoader()
/// let document = try await loader.load(from: fileURL)
///
/// // Extract specific field as content
/// let extractLoader = JSONLoader(contentKeyPath: "data.text")
/// let doc = try await extractLoader.load(from: data, metadata: nil)
///
/// // Load JSON array as multiple documents
/// let docs = try await loader.loadArray(from: fileURL, itemKeyPath: "items")
/// ```
public struct JSONLoader: DocumentLoader, Sendable {

    /// The file extensions supported by this loader.
    public static let supportedExtensions: Set<String> = ["json"]

    /// Key path to extract as content (e.g., "content" or "data.text").
    ///
    /// Use dot notation to navigate nested objects. If `nil`, the entire
    /// JSON object is serialized as pretty-printed content.
    public var contentKeyPath: String?

    /// Metadata key paths mapping metadata field names to JSON paths.
    ///
    /// Keys are the metadata field names, values are JSON key paths.
    /// Supports "title" and "author" as special fields that map to
    /// DocumentMetadata properties. Other fields are stored in `custom`.
    public var metadataKeyPaths: [String: String]?

    /// Creates a new JSON loader.
    ///
    /// - Parameters:
    ///   - contentKeyPath: Key path to extract as content. If `nil`, serializes entire JSON.
    ///   - metadataKeyPaths: Mapping of metadata field names to JSON paths.
    public init(contentKeyPath: String? = nil, metadataKeyPaths: [String: String]? = nil) {
        self.contentKeyPath = contentKeyPath
        self.metadataKeyPaths = metadataKeyPaths
    }

    /// Loads a document from a file URL.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: A document containing the JSON content with appropriate metadata.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read,
    ///           `ZoniError.invalidData` if the JSON is invalid.
    public func load(from url: URL) async throws -> Document {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ZoniError.loadingFailed(url: url, reason: error.localizedDescription)
        }

        var metadata = DocumentMetadata(
            source: LoadingUtils.filename(from: url),
            url: url,
            mimeType: "application/json"
        )

        return try await load(from: data, metadata: metadata)
    }

    /// Loads a document from raw JSON data.
    ///
    /// - Parameters:
    ///   - data: The raw JSON data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Returns: A document containing the extracted or serialized JSON content.
    /// - Throws: `ZoniError.invalidData` if the JSON is invalid or key path not found.
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ZoniError.invalidData(reason: "Invalid JSON: \(error.localizedDescription)")
        }

        // Extract content
        let content: String
        if let keyPath = contentKeyPath {
            guard let value = extractValue(from: json, keyPath: keyPath) else {
                throw ZoniError.invalidData(reason: "Key path '\(keyPath)' not found in JSON")
            }

            // Handle null values
            if value is NSNull {
                content = ""
            } else {
                content = stringify(value)
            }
        } else {
            // Serialize entire JSON as pretty-printed string
            content = stringify(json)
        }

        // Build metadata
        var finalMetadata = metadata ?? DocumentMetadata()
        if finalMetadata.mimeType == nil {
            finalMetadata.mimeType = "application/json"
        }

        // Extract metadata from key paths
        if let metadataPaths = metadataKeyPaths {
            for (fieldName, keyPath) in metadataPaths {
                if let value = extractValue(from: json, keyPath: keyPath) {
                    let stringValue = stringify(value)

                    // Handle special metadata fields
                    switch fieldName {
                    case "title":
                        finalMetadata.title = stringValue
                    case "author":
                        finalMetadata.author = stringValue
                    case "source":
                        finalMetadata.source = stringValue
                    default:
                        finalMetadata.custom[fieldName] = .string(stringValue)
                    }
                }
            }
        }

        return Document(content: content, metadata: finalMetadata)
    }

    /// Loads a JSON array as multiple documents from a file URL.
    ///
    /// - Parameters:
    ///   - url: The file URL to load from.
    ///   - itemKeyPath: Optional key path to the array within the JSON.
    ///                  If `nil`, the root must be an array.
    /// - Returns: An array of documents, one per JSON array item.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read,
    ///           `ZoniError.invalidData` if the JSON is invalid or not an array.
    public func loadArray(from url: URL, itemKeyPath: String?) async throws -> [Document] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ZoniError.loadingFailed(url: url, reason: error.localizedDescription)
        }

        let baseMetadata = DocumentMetadata(
            source: LoadingUtils.filename(from: url),
            url: url,
            mimeType: "application/json"
        )

        return try await loadArray(from: data, itemKeyPath: itemKeyPath, metadata: baseMetadata)
    }

    /// Loads a JSON array as multiple documents from raw data.
    ///
    /// - Parameters:
    ///   - data: The raw JSON data to load.
    ///   - itemKeyPath: Optional key path to the array within the JSON.
    ///                  If `nil`, the root must be an array.
    ///   - metadata: Optional base metadata to attach to all documents.
    /// - Returns: An array of documents, one per JSON array item.
    /// - Throws: `ZoniError.invalidData` if the JSON is invalid or not an array.
    public func loadArray(from data: Data, itemKeyPath: String?, metadata: DocumentMetadata?) async throws -> [Document] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ZoniError.invalidData(reason: "Invalid JSON: \(error.localizedDescription)")
        }

        // Get the array
        let array: [Any]
        if let keyPath = itemKeyPath {
            guard let value = extractValue(from: json, keyPath: keyPath),
                  let extractedArray = value as? [Any] else {
                throw ZoniError.invalidData(reason: "Key path '\(keyPath)' does not contain an array")
            }
            array = extractedArray
        } else {
            guard let rootArray = json as? [Any] else {
                throw ZoniError.invalidData(reason: "JSON root is not an array")
            }
            array = rootArray
        }

        // Convert each item to a document
        var documents: [Document] = []
        for (index, item) in array.enumerated() {
            // Serialize item back to data for loading
            let itemData: Data
            do {
                itemData = try JSONSerialization.data(withJSONObject: item, options: [])
            } catch {
                throw ZoniError.invalidData(reason: "Failed to serialize array item \(index)")
            }

            // Create metadata with index
            var itemMetadata = metadata ?? DocumentMetadata()
            if itemMetadata.mimeType == nil {
                itemMetadata.mimeType = "application/json"
            }
            itemMetadata.custom["arrayIndex"] = .int(index)

            let document = try await load(from: itemData, metadata: itemMetadata)
            documents.append(document)
        }

        return documents
    }

    // MARK: - Private Helpers

    /// Extracts a value from a JSON object using dot-notation key path.
    ///
    /// - Parameters:
    ///   - json: The JSON object to extract from.
    ///   - keyPath: The dot-separated key path (e.g., "data.content").
    /// - Returns: The extracted value, or `nil` if the path doesn't exist.
    private func extractValue(from json: Any, keyPath: String) -> Any? {
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any = json

        for component in components {
            if let dict = current as? [String: Any], let value = dict[component] {
                current = value
            } else if let array = current as? [Any], let index = Int(component), index < array.count {
                current = array[index]
            } else {
                return nil
            }
        }

        return current
    }

    /// Converts any JSON value to a string representation.
    ///
    /// - Parameter value: The value to stringify.
    /// - Returns: A string representation of the value.
    private func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            // Check if it's a boolean
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case is NSNull:
            return ""
        default:
            // For objects and arrays, serialize to pretty-printed JSON
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return String(describing: value)
        }
    }
}
