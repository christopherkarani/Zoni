// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// CSVLoader.swift - Loader for CSV/TSV files

import Foundation

/// A document loader for CSV and TSV files with configurable parsing.
///
/// `CSVLoader` supports loading `.csv` and `.tsv` files with RFC 4180 compliant parsing.
/// It handles quoted fields, embedded commas, newlines within quotes, and escaped quotes.
///
/// ## Example
/// ```swift
/// // Load entire CSV as single document
/// let loader = CSVLoader()
/// let document = try await loader.load(from: fileURL)
///
/// // Load each row as a separate document with specific column as content
/// let rowLoader = CSVLoader(contentColumn: "text", metadataColumns: ["title", "author"])
/// let documents = try await rowLoader.loadRows(from: fileURL)
/// ```
public struct CSVLoader: DocumentLoader, Sendable {

    /// The file extensions supported by this loader.
    public static let supportedExtensions: Set<String> = ["csv", "tsv"]

    /// Column name to use as document content.
    ///
    /// When set, this column's value will be extracted as the document content.
    /// If `nil`, the entire row is used as content.
    public var contentColumn: String?

    /// Column names to extract as metadata.
    ///
    /// These columns will be added to the document's `metadata.custom` dictionary.
    public var metadataColumns: [String]?

    /// Whether the first row contains headers.
    ///
    /// When `true`, the first row is treated as column names.
    /// When `false`, columns are referenced by index ("0", "1", etc.).
    public var hasHeaders: Bool

    /// Field delimiter character.
    ///
    /// Use "," for CSV files and "\t" for TSV files.
    public var delimiter: Character

    /// Creates a new CSV loader with the specified configuration.
    ///
    /// - Parameters:
    ///   - contentColumn: Column name to use as document content. If `nil`, the entire row is used.
    ///   - metadataColumns: Column names to extract as metadata.
    ///   - hasHeaders: Whether the first row contains headers. Defaults to `true`.
    ///   - delimiter: Field delimiter character. Defaults to ",".
    public init(
        contentColumn: String? = nil,
        metadataColumns: [String]? = nil,
        hasHeaders: Bool = true,
        delimiter: Character = ","
    ) {
        self.contentColumn = contentColumn
        self.metadataColumns = metadataColumns
        self.hasHeaders = hasHeaders
        self.delimiter = delimiter
    }

    // MARK: - DocumentLoader Protocol

    /// Loads a document from a file URL.
    ///
    /// The entire CSV content is loaded as a single document.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: A document containing the CSV content with appropriate metadata.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read.
    public func load(from url: URL) async throws -> Document {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ZoniError.loadingFailed(url: url, reason: error.localizedDescription)
        }

        let mimeType = determineMimeType(for: url)
        var metadata = DocumentMetadata(
            source: LoadingUtils.filename(from: url),
            url: url,
            mimeType: mimeType
        )

        return try await load(from: data, metadata: metadata)
    }

    /// Loads a document from raw data.
    ///
    /// The entire CSV content is loaded as a single document.
    ///
    /// - Parameters:
    ///   - data: The raw data to load.
    ///   - metadata: Optional metadata to attach to the document.
    /// - Returns: A document containing the CSV content.
    /// - Throws: `ZoniError.invalidData` if the data cannot be decoded as text.
    public func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ZoniError.invalidData(reason: "Unable to decode CSV data as UTF-8")
        }

        var finalMetadata = metadata ?? DocumentMetadata()
        if finalMetadata.mimeType == nil {
            finalMetadata.mimeType = delimiter == "\t" ? "text/tab-separated-values" : "text/csv"
        }

        return Document(content: content, metadata: finalMetadata)
    }

    // MARK: - Row Loading

    /// Loads each row from a CSV file as a separate document.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: An array of documents, one per data row.
    /// - Throws: `ZoniError.loadingFailed` if the file cannot be read,
    ///           `ZoniError.invalidData` if the content column is not found.
    public func loadRows(from url: URL) async throws -> [Document] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ZoniError.loadingFailed(url: url, reason: error.localizedDescription)
        }

        let mimeType = determineMimeType(for: url)
        var metadata = DocumentMetadata(
            source: LoadingUtils.filename(from: url),
            url: url,
            mimeType: mimeType
        )

        return try await loadRows(from: data, metadata: metadata)
    }

    /// Loads each row from CSV data as a separate document.
    ///
    /// - Parameters:
    ///   - data: The raw CSV data.
    ///   - metadata: Optional base metadata for documents.
    /// - Returns: An array of documents, one per data row.
    /// - Throws: `ZoniError.invalidData` if the data cannot be decoded or content column is not found.
    public func loadRows(from data: Data, metadata: DocumentMetadata? = nil) async throws -> [Document] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ZoniError.invalidData(reason: "Unable to decode CSV data as UTF-8")
        }

        let rows = parseCSV(text)

        guard !rows.isEmpty else {
            return []
        }

        // Determine headers
        let headers: [String]
        let dataRows: [[String]]

        if hasHeaders {
            headers = rows[0]
            dataRows = Array(rows.dropFirst())
        } else {
            // Use column indices as headers
            let maxColumns = rows.map { $0.count }.max() ?? 0
            headers = (0..<maxColumns).map { String($0) }
            dataRows = rows
        }

        // Validate content column if specified
        var contentColumnIndex: Int? = nil
        if let contentCol = contentColumn {
            guard let index = headers.firstIndex(of: contentCol) else {
                throw ZoniError.invalidData(reason: "Content column '\(contentCol)' not found in CSV headers")
            }
            contentColumnIndex = index
        }

        // Find indices for metadata columns
        var metadataColumnIndices: [(String, Int)] = []
        if let metaCols = metadataColumns {
            for col in metaCols {
                if let index = headers.firstIndex(of: col) {
                    metadataColumnIndices.append((col, index))
                }
            }
        }

        let baseMimeType = delimiter == "\t" ? "text/tab-separated-values" : "text/csv"

        var documents: [Document] = []

        for row in dataRows {
            // Determine content
            let content: String
            if let colIndex = contentColumnIndex {
                if colIndex < row.count {
                    content = row[colIndex]
                } else {
                    content = ""
                }
            } else {
                // Use entire row as content
                content = row.joined(separator: String(delimiter))
            }

            // Build metadata
            var docMetadata = metadata ?? DocumentMetadata()
            if docMetadata.mimeType == nil {
                docMetadata.mimeType = baseMimeType
            }

            // Add metadata columns to custom
            if !metadataColumnIndices.isEmpty {
                var customMeta: [String: MetadataValue] = docMetadata.custom
                for (colName, colIndex) in metadataColumnIndices {
                    if colIndex < row.count {
                        customMeta[colName] = .string(row[colIndex])
                    }
                }
                docMetadata.custom = customMeta
            }

            let document = Document(content: content, metadata: docMetadata)
            documents.append(document)
        }

        return documents
    }

    // MARK: - Private Helpers

    /// Determines the MIME type based on the file extension.
    private func determineMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext == "tsv" ? "text/tab-separated-values" : "text/csv"
    }

    /// Parses CSV text into a 2D array of strings.
    ///
    /// This parser is RFC 4180 compliant:
    /// - Handles quoted fields with commas inside
    /// - Handles quoted fields with newlines inside
    /// - Handles escaped quotes ("" becomes ")
    /// - Skips empty rows
    ///
    /// - Parameter text: The CSV text to parse.
    /// - Returns: A 2D array where each inner array represents a row of fields.
    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let char = text[i]

            if inQuotes {
                if char == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        // Escaped quote
                        currentField.append("\"")
                        i = next
                    } else {
                        // End of quoted field
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == delimiter {
                    currentRow.append(currentField)
                    currentField = ""
                } else if char == "\n" || char == "\r" {
                    // Handle line endings
                    if char == "\r" {
                        let next = text.index(after: i)
                        if next < text.endIndex && text[next] == "\n" {
                            i = next
                        }
                    }
                    currentRow.append(currentField)
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }
            i = text.index(after: i)
        }

        // Handle last field/row
        currentRow.append(currentField)
        if !currentRow.allSatisfy({ $0.isEmpty }) {
            rows.append(currentRow)
        }

        return rows
    }
}
