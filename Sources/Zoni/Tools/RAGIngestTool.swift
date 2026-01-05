// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGIngestTool.swift - Document ingestion tool for adding to the knowledge base.

import Foundation

// MARK: - RAGIngestTool

/// A tool for adding documents to the knowledge base.
///
/// `RAGIngestTool` ingests text content into the RAG pipeline, where it
/// is chunked, embedded, and stored for future retrieval. This enables
/// agents to store new information for later use.
///
/// ## Example Usage
///
/// ```swift
/// let ingestTool = RAGIngestTool(pipeline: myPipeline)
///
/// let result = try await ingestTool.execute(arguments: [
///     "content": .string("Swift is a powerful programming language..."),
///     "source": .string("swift-docs.md"),
///     "title": .string("Swift Overview")
/// ])
///
/// if let documentId = result.dictionaryValue?["document_id"]?.stringValue {
///     print("Ingested document: \(documentId)")
/// }
/// ```
///
/// ## SwiftAgents Integration
///
/// This tool conforms to the `Tool` protocol and can be used directly
/// with SwiftAgents:
///
/// ```swift
/// let agent = ReActAgent.Builder()
///     .addTool(RAGIngestTool(pipeline: myPipeline))
///     .build()
/// ```
public struct RAGIngestTool: Tool, Sendable {

    // MARK: - Tool Protocol Properties

    /// The unique name identifying this tool.
    public let name = "ingest_document"

    /// A description of what this tool does.
    public let description = """
        Add a new document to the knowledge base for future searches.
        The document will be chunked, embedded, and indexed automatically.
        Use this to store new information the agent should remember.
        """

    /// The parameters this tool accepts.
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "content",
            description: "The text content to add to the knowledge base",
            type: .string,
            isRequired: true,
            defaultValue: nil
        ),
        ToolParameter(
            name: "source",
            description: "Source identifier for the document (e.g., filename, URL)",
            type: .string,
            isRequired: false,
            defaultValue: nil
        ),
        ToolParameter(
            name: "title",
            description: "Document title",
            type: .string,
            isRequired: false,
            defaultValue: nil
        ),
        ToolParameter(
            name: "author",
            description: "Document author",
            type: .string,
            isRequired: false,
            defaultValue: nil
        ),
        ToolParameter(
            name: "metadata",
            description: "Additional metadata as key-value pairs",
            type: .object(properties: []),
            isRequired: false,
            defaultValue: nil
        )
    ]

    // MARK: - Private Properties

    /// The RAG pipeline used to ingest documents.
    private let pipeline: RAGPipeline

    // MARK: - Initialization

    /// Creates a new ingest tool with the specified pipeline.
    ///
    /// - Parameter pipeline: The RAG pipeline to use for ingestion.
    public init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Tool Execution

    /// Executes the ingestion operation.
    ///
    /// - Parameter arguments: The arguments dictionary containing:
    ///   - `content` (String, required): The text content to ingest.
    ///   - `source` (String, optional): Source identifier.
    ///   - `title` (String, optional): Document title.
    ///   - `author` (String, optional): Document author.
    ///   - `metadata` (Object, optional): Additional key-value metadata.
    /// - Returns: A dictionary containing:
    ///   - `success`: Boolean indicating success.
    ///   - `document_id`: The unique ID of the ingested document.
    ///   - `source`: The source identifier if provided.
    ///   - `message`: A success message.
    /// - Throws: `ZoniError.invalidConfiguration` if required arguments are missing.
    ///           Other `ZoniError` variants if ingestion fails.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        // Extract required content argument
        let content = try arguments.requireString("content")

        // Validate content is not empty
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ZoniError.invalidConfiguration(reason: "Content cannot be empty")
        }

        // Extract optional arguments
        let source = arguments.optionalString("source")
        let title = arguments.optionalString("title")
        let author = arguments.optionalString("author")

        // Build custom metadata from the metadata argument
        var customMetadata: [String: MetadataValue] = [:]
        if let metadataDict = arguments["metadata"]?.dictionaryValue {
            for (key, value) in metadataDict {
                customMetadata[key] = value.toMetadataValue()
            }
        }

        // Create the document with metadata
        let documentMetadata = DocumentMetadata(
            source: source,
            title: title,
            author: author,
            custom: customMetadata
        )

        let document = Document(
            content: content,
            metadata: documentMetadata
        )

        // Ingest the document
        try await pipeline.ingest(document)

        // Build success response
        var result: [String: SendableValue] = [
            "success": .bool(true),
            "document_id": .string(document.id),
            "message": .string("Document ingested successfully")
        ]

        if let source = source {
            result["source"] = .string(source)
        }

        if let title = title {
            result["title"] = .string(title)
        }

        // Include content preview (first 100 chars)
        let preview = String(content.prefix(100))
        let needsEllipsis = content.count > 100
        result["content_preview"] = .string(preview + (needsEllipsis ? "..." : ""))

        return .dictionary(result)
    }
}
