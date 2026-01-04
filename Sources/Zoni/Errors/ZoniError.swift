// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ZoniError.swift - Comprehensive error types for the Zoni RAG framework

import Foundation

/// Comprehensive error type for all Zoni RAG framework operations.
///
/// `ZoniError` provides detailed, categorized errors covering the full RAG pipeline:
/// - Document loading and parsing
/// - Text chunking and processing
/// - Embedding generation
/// - Vector store operations
/// - Retrieval and search
/// - LLM generation
/// - Configuration and setup
///
/// All cases include contextual information to aid debugging and provide
/// actionable recovery suggestions where possible.
///
/// ## Example
/// ```swift
/// do {
///     let chunks = try await chunker.chunk(document)
/// } catch let error as ZoniError {
///     print(error.localizedDescription)
///     if let suggestion = error.recoverySuggestion {
///         print("Suggestion: \(suggestion)")
///     }
/// }
/// ```
public enum ZoniError: Error, Sendable, LocalizedError {

    // MARK: - Loading Errors

    /// The specified file type is not supported for loading.
    ///
    /// - Parameter fileExtension: The unsupported file extension (e.g., "xyz").
    case unsupportedFileType(String)

    /// Failed to load a document from the specified URL.
    ///
    /// - Parameters:
    ///   - url: The URL that could not be loaded.
    ///   - reason: A description of why loading failed.
    case loadingFailed(url: URL, reason: String)

    /// The loaded data is invalid or corrupted.
    ///
    /// - Parameter reason: A description of the validation failure.
    case invalidData(reason: String)

    // MARK: - Chunking Errors

    /// Failed to chunk the document into smaller pieces.
    ///
    /// - Parameter reason: A description of why chunking failed.
    case chunkingFailed(reason: String)

    /// The document is empty and cannot be processed.
    case emptyDocument

    // MARK: - Embedding Errors

    /// Failed to generate embeddings for the given content.
    ///
    /// - Parameter reason: A description of the embedding failure.
    case embeddingFailed(reason: String)

    /// The embedding dimensions do not match the expected size.
    ///
    /// - Parameters:
    ///   - expected: The expected embedding dimension.
    ///   - got: The actual embedding dimension received.
    case embeddingDimensionMismatch(expected: Int, got: Int)

    /// The specified embedding provider is not available.
    ///
    /// - Parameter name: The name of the unavailable provider.
    case embeddingProviderUnavailable(name: String)

    /// The embedding API rate limit has been exceeded.
    ///
    /// - Parameter retryAfter: The suggested duration to wait before retrying, if available.
    case rateLimited(retryAfter: Duration?)

    // MARK: - Vector Store Errors

    /// The specified vector store is not available.
    ///
    /// - Parameter name: The name of the unavailable vector store.
    case vectorStoreUnavailable(name: String)

    /// Failed to establish a connection to the vector store.
    ///
    /// - Parameter reason: A description of the connection failure.
    case vectorStoreConnectionFailed(reason: String)

    /// The specified index was not found in the vector store.
    ///
    /// - Parameter name: The name of the missing index.
    case indexNotFound(name: String)

    /// Failed to insert vectors into the store.
    ///
    /// - Parameter reason: A description of the insertion failure.
    case insertionFailed(reason: String)

    /// Failed to search the vector store.
    ///
    /// - Parameter reason: A description of the search failure.
    case searchFailed(reason: String)

    // MARK: - Retrieval Errors

    /// Failed to retrieve relevant documents.
    ///
    /// - Parameter reason: A description of the retrieval failure.
    case retrievalFailed(reason: String)

    /// No results were found for the given query.
    case noResultsFound

    // MARK: - Generation Errors

    /// Failed to generate a response from the LLM.
    ///
    /// - Parameter reason: A description of the generation failure.
    case generationFailed(reason: String)

    /// The specified LLM provider is not available.
    ///
    /// - Parameter name: The name of the unavailable provider.
    case llmProviderUnavailable(name: String)

    /// The input context exceeds the model's token limit.
    ///
    /// - Parameters:
    ///   - tokens: The number of tokens in the context.
    ///   - limit: The maximum allowed tokens.
    case contextTooLong(tokens: Int, limit: Int)

    // MARK: - Configuration Errors

    /// The configuration is invalid.
    ///
    /// - Parameter reason: A description of what is invalid.
    case invalidConfiguration(reason: String)

    /// A required component is missing from the configuration.
    ///
    /// - Parameter component: The name of the missing component.
    case missingRequiredComponent(String)

    // MARK: - LocalizedError Implementation

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        // Loading errors
        case .unsupportedFileType(let fileExtension):
            return "Unsupported file type: '\(fileExtension)'"

        case .loadingFailed(let url, let reason):
            return "Failed to load document from '\(url.lastPathComponent)': \(reason)"

        case .invalidData(let reason):
            return "Invalid data: \(reason)"

        // Chunking errors
        case .chunkingFailed(let reason):
            return "Failed to chunk document: \(reason)"

        case .emptyDocument:
            return "Cannot process an empty document"

        // Embedding errors
        case .embeddingFailed(let reason):
            return "Failed to generate embeddings: \(reason)"

        case .embeddingDimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"

        case .embeddingProviderUnavailable(let name):
            return "Embedding provider '\(name)' is not available"

        case .rateLimited(let retryAfter):
            if let duration = retryAfter {
                return "Rate limited. Retry after \(formatDuration(duration))"
            }
            return "Rate limited. Please wait before retrying"

        // Vector store errors
        case .vectorStoreUnavailable(let name):
            return "Vector store '\(name)' is not available"

        case .vectorStoreConnectionFailed(let reason):
            return "Failed to connect to vector store: \(reason)"

        case .indexNotFound(let name):
            return "Index '\(name)' not found in vector store"

        case .insertionFailed(let reason):
            return "Failed to insert vectors: \(reason)"

        case .searchFailed(let reason):
            return "Failed to search vector store: \(reason)"

        // Retrieval errors
        case .retrievalFailed(let reason):
            return "Failed to retrieve documents: \(reason)"

        case .noResultsFound:
            return "No results found for the given query"

        // Generation errors
        case .generationFailed(let reason):
            return "Failed to generate response: \(reason)"

        case .llmProviderUnavailable(let name):
            return "LLM provider '\(name)' is not available"

        case .contextTooLong(let tokens, let limit):
            return "Context too long: \(tokens) tokens exceeds limit of \(limit)"

        // Configuration errors
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"

        case .missingRequiredComponent(let component):
            return "Missing required component: '\(component)'"
        }
    }

    /// A localized suggestion for recovering from the error.
    public var recoverySuggestion: String? {
        switch self {
        // Loading errors
        case .unsupportedFileType:
            return "Use a supported file type such as .txt, .pdf, .md, or .json"

        case .loadingFailed:
            return "Verify the file exists and you have read permissions"

        case .invalidData:
            return "Check that the file is not corrupted and is in the expected format"

        // Chunking errors
        case .chunkingFailed:
            return "Try adjusting the chunk size or overlap settings"

        case .emptyDocument:
            return "Provide a document with content to process"

        // Embedding errors
        case .embeddingFailed:
            return "Check your API credentials and network connection"

        case .embeddingDimensionMismatch:
            return "Ensure the embedding model matches the vector store configuration"

        case .embeddingProviderUnavailable:
            return "Configure a valid embedding provider or check API availability"

        case .rateLimited:
            return "Wait before retrying or consider implementing request throttling"

        // Vector store errors
        case .vectorStoreUnavailable:
            return "Check that the vector store is properly configured and running"

        case .vectorStoreConnectionFailed:
            return "Verify the connection string and network accessibility"

        case .indexNotFound:
            return "Create the index before performing operations on it"

        case .insertionFailed:
            return "Check the vector dimensions and data format"

        case .searchFailed:
            return "Verify the query format and index availability"

        // Retrieval errors
        case .retrievalFailed:
            return "Check the retrieval configuration and data availability"

        case .noResultsFound:
            return "Try broadening the search query or lowering the similarity threshold"

        // Generation errors
        case .generationFailed:
            return "Check the LLM provider status and your API credentials"

        case .llmProviderUnavailable:
            return "Configure a valid LLM provider or check API availability"

        case .contextTooLong:
            return "Reduce the number of retrieved documents or use a model with a larger context window"

        // Configuration errors
        case .invalidConfiguration:
            return "Review the configuration parameters and documentation"

        case .missingRequiredComponent:
            return "Add the required component to your configuration"
        }
    }

    // MARK: - Private Helpers

    /// Formats a Duration into a human-readable string.
    private func formatDuration(_ duration: Duration) -> String {
        let seconds = duration.components.seconds
        let attoseconds = duration.components.attoseconds

        if seconds >= 60 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds > 0 {
                return "\(minutes) minute\(minutes == 1 ? "" : "s") and \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")"
            }
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if seconds > 0 {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        } else {
            let milliseconds = attoseconds / 1_000_000_000_000_000
            return "\(milliseconds) millisecond\(milliseconds == 1 ? "" : "s")"
        }
    }
}
