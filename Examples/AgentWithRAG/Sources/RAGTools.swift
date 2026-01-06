// AgentWithRAG Example
//
// RAGTools.swift - Custom RAG tools that wrap RAGPipeline methods.

import Zoni
import ZoniAgents

// MARK: - SearchKnowledgeBaseTool

/// A tool that searches the knowledge base using semantic similarity.
///
/// This tool wraps `RAGPipeline.retrieve()` to provide agents with the ability
/// to search for relevant documents without generating an LLM response.
///
/// ## Tool Name
/// `search_knowledge_base`
///
/// ## Parameters
/// - `query` (String, required): The search query to find relevant documents.
/// - `limit` (Int, optional): Maximum number of results. Default: 5.
/// - `min_score` (Double, optional): Minimum relevance score (0.0-1.0). Default: 0.0.
///
/// ## Returns
/// A dictionary containing:
/// - `results`: Array of matching documents with content, score, and metadata.
/// - `total`: Number of results returned.
/// - `query`: The original search query.
public struct SearchKnowledgeBaseTool: Tool, Sendable {

    public let name = "search_knowledge_base"

    public let description = """
        Search the knowledge base for documents relevant to a query.
        Returns the most relevant text chunks with their sources and relevance scores.
        Use this tool to find information before answering questions.
        """

    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "query",
            description: "The search query to find relevant information",
            type: .string,
            isRequired: true
        ),
        ToolParameter(
            name: "limit",
            description: "Maximum number of results to return (default: 5)",
            type: .int,
            isRequired: false,
            defaultValue: .int(5)
        ),
        ToolParameter(
            name: "min_score",
            description: "Minimum relevance score threshold (0.0-1.0, default: 0.0)",
            type: .double,
            isRequired: false,
            defaultValue: .double(0.0)
        )
    ]

    private let pipeline: RAGPipeline

    /// Creates a search tool backed by the given RAG pipeline.
    ///
    /// - Parameter pipeline: The RAG pipeline to use for searches.
    public init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let query = try arguments.requireString("query")
        let limit = arguments.optionalInt("limit", default: 5)
        let minScore = Float(arguments.optionalDouble("min_score", default: 0.0))

        // Retrieve documents from the pipeline
        let results = try await pipeline.retrieve(query, limit: limit)

        // Filter by minimum score
        let filteredResults = results.filter { $0.score >= minScore }

        // Convert to SendableValue
        let resultsArray: [SendableValue] = filteredResults.map { result in
            result.toSendableValue()
        }

        return .dictionary([
            "results": .array(resultsArray),
            "total": .int(resultsArray.count),
            "query": .string(query)
        ])
    }
}

// MARK: - IngestDocumentTool

/// A tool that ingests documents into the knowledge base.
///
/// This tool wraps `RAGPipeline.ingest()` to allow agents to dynamically
/// add new information to the knowledge base.
///
/// ## Tool Name
/// `ingest_document`
///
/// ## Parameters
/// - `content` (String, required): The document content to ingest.
/// - `title` (String, optional): Title for the document.
/// - `source` (String, optional): Source identifier for the document.
///
/// ## Returns
/// A dictionary containing:
/// - `success`: Boolean indicating if ingestion succeeded.
/// - `document_id`: The ID assigned to the ingested document.
/// - `message`: Status message.
public struct IngestDocumentTool: Tool, Sendable {

    public let name = "ingest_document"

    public let description = """
        Add a new document to the knowledge base.
        The document will be chunked, embedded, and stored for future retrieval.
        Use this tool to add new information that can be searched later.
        """

    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "content",
            description: "The document content to ingest",
            type: .string,
            isRequired: true
        ),
        ToolParameter(
            name: "title",
            description: "Optional title for the document",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "source",
            description: "Optional source identifier (e.g., 'user_input', 'web_page')",
            type: .string,
            isRequired: false
        )
    ]

    private let pipeline: RAGPipeline

    /// Creates an ingest tool backed by the given RAG pipeline.
    ///
    /// - Parameter pipeline: The RAG pipeline to use for ingestion.
    public init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let content = try arguments.requireString("content")
        let title = arguments.optionalString("title")
        let source = arguments.optionalString("source")

        // Create document with metadata
        let documentId = UUID().uuidString
        let metadata = DocumentMetadata(
            source: source,
            title: title
        )
        let document = Document(
            id: documentId,
            content: content,
            metadata: metadata
        )

        // Ingest the document
        try await pipeline.ingest(document)

        return .dictionary([
            "success": .bool(true),
            "document_id": .string(documentId),
            "message": .string("Document '\(title ?? documentId)' successfully ingested")
        ])
    }
}

// MARK: - QueryKnowledgeTool

/// A tool that answers questions using the full RAG pipeline.
///
/// This tool wraps `RAGPipeline.query()` to provide complete question-answering
/// capabilities with context retrieval and LLM generation.
///
/// ## Tool Name
/// `query_knowledge`
///
/// ## Parameters
/// - `question` (String, required): The question to answer.
/// - `max_sources` (Int, optional): Maximum number of sources to consider. Default: 5.
/// - `include_sources` (Bool, optional): Whether to include source excerpts. Default: true.
///
/// ## Returns
/// A dictionary containing:
/// - `answer`: The generated answer text.
/// - `confidence`: Confidence level based on source relevance.
/// - `sources`: Array of source documents used (if include_sources is true).
public struct QueryKnowledgeTool: Tool, Sendable {

    public let name = "query_knowledge"

    public let description = """
        Ask a question and get an answer based on the knowledge base.
        Returns an answer synthesized from relevant documents with source citations.
        Use this tool when you need a comprehensive answer to a question.
        """

    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "question",
            description: "The question to answer",
            type: .string,
            isRequired: true
        ),
        ToolParameter(
            name: "max_sources",
            description: "Maximum number of sources to consider (default: 5)",
            type: .int,
            isRequired: false,
            defaultValue: .int(5)
        ),
        ToolParameter(
            name: "include_sources",
            description: "Whether to include source excerpts in response (default: true)",
            type: .bool,
            isRequired: false,
            defaultValue: .bool(true)
        )
    ]

    private let pipeline: RAGPipeline

    /// Creates a query tool backed by the given RAG pipeline.
    ///
    /// - Parameter pipeline: The RAG pipeline to use for queries.
    public init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let question = try arguments.requireString("question")
        let maxSources = arguments.optionalInt("max_sources", default: 5)
        let includeSources = arguments.optionalBool("include_sources", default: true)

        // Build query options
        let options = QueryOptions(retrievalLimit: maxSources)

        // Execute the RAG query
        let response = try await pipeline.query(question, options: options)

        // Calculate confidence based on source scores
        let confidence: String
        if response.sources.isEmpty {
            confidence = "low"
        } else {
            let avgScore = response.sources.map(\.score).reduce(0, +) / Float(response.sources.count)
            confidence = avgScore > 0.8 ? "high" : (avgScore > 0.5 ? "medium" : "low")
        }

        // Build result
        var result: [String: SendableValue] = [
            "answer": .string(response.answer),
            "confidence": .string(confidence),
            "sources_count": .int(response.sources.count)
        ]

        if includeSources {
            let sources: [SendableValue] = response.sources.map { source in
                var dict: [String: SendableValue] = [
                    "content": .string(String(source.chunk.content.prefix(300))),
                    "score": .double(Double(source.score))
                ]
                if let sourceId = source.chunk.metadata.source {
                    dict["source"] = .string(sourceId)
                }
                return .dictionary(dict)
            }
            result["sources"] = .array(sources)
        }

        return .dictionary(result)
    }
}

// MARK: - RAGToolBundle Extension

extension RAGToolBundle {

    /// Creates a complete RAG tool bundle with search, ingest, and query capabilities.
    ///
    /// This bundle provides comprehensive knowledge base interaction:
    /// - `SearchKnowledgeBaseTool`: Search for relevant documents
    /// - `IngestDocumentTool`: Add new documents to the knowledge base
    /// - `QueryKnowledgeTool`: Ask questions and get answers
    ///
    /// - Parameter pipeline: The RAG pipeline to use for all tools.
    /// - Returns: An array of tools for full RAG functionality.
    public static func complete(pipeline: RAGPipeline) -> [any Tool] {
        [
            SearchKnowledgeBaseTool(pipeline: pipeline),
            IngestDocumentTool(pipeline: pipeline),
            QueryKnowledgeTool(pipeline: pipeline)
        ]
    }
}
