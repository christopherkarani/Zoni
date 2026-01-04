// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// LoadingUtils.swift - Utility functions for document loading

import Foundation

/// Utility functions for document loading operations.
///
/// `LoadingUtils` provides essential helper functions for processing documents
/// during the loading phase of the RAG pipeline, including:
/// - Text encoding detection from BOM markers
/// - Whitespace normalization
/// - Text cleaning for embedding generation
/// - Filename extraction from URLs
///
/// ## Example
/// ```swift
/// // Detect encoding from raw data
/// let data = try Data(contentsOf: url)
/// let encoding = LoadingUtils.detectEncoding(data)
///
/// // Normalize whitespace in loaded text
/// let normalized = LoadingUtils.normalizeWhitespace(rawText)
///
/// // Clean text for embedding
/// let cleaned = LoadingUtils.cleanForEmbedding(text)
///
/// // Extract filename without extension
/// let name = LoadingUtils.filename(from: url)
/// ```
public enum LoadingUtils {

    // MARK: - Encoding Detection

    /// Detect text encoding from BOM markers or heuristics.
    ///
    /// This function examines the raw data for Byte Order Mark (BOM) signatures
    /// to determine the text encoding. If no BOM is found, it attempts to validate
    /// the data as UTF-8, falling back to ISO Latin-1 for binary or non-UTF-8 data.
    ///
    /// Supported BOM markers:
    /// - UTF-8: `0xEF 0xBB 0xBF`
    /// - UTF-16 Little Endian: `0xFF 0xFE`
    /// - UTF-16 Big Endian: `0xFE 0xFF`
    ///
    /// - Parameter data: Raw data to analyze for encoding detection.
    /// - Returns: The detected string encoding. Defaults to UTF-8 if the data
    ///   is valid UTF-8, or ISO Latin-1 if the data cannot be decoded as UTF-8.
    ///
    /// ## Example
    /// ```swift
    /// let data = try Data(contentsOf: fileURL)
    /// let encoding = LoadingUtils.detectEncoding(data)
    /// let text = String(data: data, encoding: encoding)
    /// ```
    public static func detectEncoding(_ data: Data) -> String.Encoding {
        // Handle empty data - default to UTF-8
        guard data.count >= 2 else {
            // For single byte or empty, default to UTF-8
            return .utf8
        }

        let bytes = Array(data.prefix(4))

        // Check for UTF-8 BOM: 0xEF, 0xBB, 0xBF
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return .utf8
        }

        // Check for UTF-16 Little Endian BOM: 0xFF, 0xFE
        if bytes[0] == 0xFF && bytes[1] == 0xFE {
            return .utf16LittleEndian
        }

        // Check for UTF-16 Big Endian BOM: 0xFE, 0xFF
        if bytes[0] == 0xFE && bytes[1] == 0xFF {
            return .utf16BigEndian
        }

        // No BOM found - try to decode as UTF-8
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }

        // Fallback to ISO Latin-1 for non-UTF-8 data
        return .isoLatin1
    }

    // MARK: - Whitespace Normalization

    /// Normalize whitespace by collapsing multiple spaces, newlines, and tabs to a single space.
    ///
    /// This function processes input text to:
    /// - Collapse consecutive whitespace characters (spaces, tabs, newlines, carriage returns)
    ///   into a single space
    /// - Trim leading and trailing whitespace from the result
    ///
    /// This is useful for preparing text for display, comparison, or further processing
    /// where consistent whitespace handling is required.
    ///
    /// - Parameter text: The input text to normalize.
    /// - Returns: Text with normalized whitespace. Returns an empty string if the input
    ///   contains only whitespace characters.
    ///
    /// ## Example
    /// ```swift
    /// let input = "Hello\n\n  World\t\t!"
    /// let normalized = LoadingUtils.normalizeWhitespace(input)
    /// // Result: "Hello World !"
    /// ```
    public static func normalizeWhitespace(_ text: String) -> String {
        // Split on any whitespace (spaces, tabs, newlines, carriage returns)
        let components = text.components(separatedBy: .whitespacesAndNewlines)

        // Filter out empty components and join with single space
        let filtered = components.filter { !$0.isEmpty }

        return filtered.joined(separator: " ")
    }

    // MARK: - Text Cleaning for Embedding

    /// Clean text for embedding by removing control characters and normalizing whitespace.
    ///
    /// This function prepares text for embedding generation by:
    /// - Removing control characters (Unicode range 0x00-0x1F, except converting tabs and
    ///   newlines to spaces, and 0x7F DELETE character)
    /// - Converting tabs and newlines to spaces
    /// - Collapsing multiple consecutive spaces into a single space
    /// - Trimming leading and trailing whitespace
    ///
    /// The resulting text is suitable for processing by embedding models that may be
    /// sensitive to control characters and inconsistent whitespace.
    ///
    /// - Parameter text: The input text to clean.
    /// - Returns: Cleaned text suitable for embedding generation. Returns an empty string
    ///   if the input contains only control characters or whitespace.
    ///
    /// ## Example
    /// ```swift
    /// let input = "Hello\u{0000}World\t\tTest"
    /// let cleaned = LoadingUtils.cleanForEmbedding(input)
    /// // Result: "HelloWorld Test"
    /// ```
    public static func cleanForEmbedding(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        for scalar in text.unicodeScalars {
            let value = scalar.value

            // Handle control characters (0x00-0x1F) and DELETE (0x7F)
            if value <= 0x1F || value == 0x7F {
                // Convert tab (0x09), newline (0x0A), and carriage return (0x0D) to space
                if value == 0x09 || value == 0x0A || value == 0x0D {
                    result.append(" ")
                }
                // Other control characters are removed (not appended)
            } else {
                // Keep all other characters
                result.append(Character(scalar))
            }
        }

        // Collapse multiple spaces and trim
        return normalizeWhitespace(result)
    }

    // MARK: - Filename Extraction

    /// Extract filename without extension from a URL.
    ///
    /// This function extracts the last path component of a URL and removes its
    /// file extension (the last dot-separated component). For files with multiple
    /// extensions (e.g., `archive.tar.gz`), only the last extension is removed.
    ///
    /// - Parameter url: The file URL to extract the filename from.
    /// - Returns: The filename without its extension. For hidden files that start
    ///   with a dot but have no extension (e.g., `.gitignore`), returns the full
    ///   filename including the leading dot.
    ///
    /// ## Example
    /// ```swift
    /// let url = URL(fileURLWithPath: "/path/to/document.txt")
    /// let name = LoadingUtils.filename(from: url)
    /// // Result: "document"
    ///
    /// let archiveURL = URL(fileURLWithPath: "/path/to/archive.tar.gz")
    /// let archiveName = LoadingUtils.filename(from: archiveURL)
    /// // Result: "archive.tar"
    /// ```
    public static func filename(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
