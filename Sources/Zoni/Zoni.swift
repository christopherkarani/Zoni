// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// A cross-platform RAG framework that works on Linux, macOS, and iOS.
// This module contains the core protocols, types, and pipeline skeleton.

// MARK: - Public API

/// Zoni is a Retrieval-Augmented Generation (RAG) framework for Swift.
///
/// ## Overview
/// Zoni provides a complete RAG pipeline for building AI-powered search and
/// question-answering systems. It supports:
/// - Document ingestion and chunking
/// - Vector embedding generation
/// - Similarity search in vector stores
/// - LLM-powered response generation
///
/// ## Quick Start
/// ```swift
/// import Zoni
///
/// // Create pipeline components (implementations in ZoniServer/ZoniApple)
/// let pipeline = RAGPipeline(
///     embedding: myEmbeddingProvider,
///     vectorStore: myVectorStore,
///     llm: myLLMProvider,
///     chunker: myChunker
/// )
///
/// // Ingest documents
/// try await pipeline.ingest(document)
///
/// // Query the knowledge base
/// let response = try await pipeline.query("What is Swift?")
/// print(response.answer)
/// ```
///
/// ## Core Components
///
/// ### Types
/// - ``Document`` - Source document with content and metadata
/// - ``Chunk`` - Piece of a document with position info
/// - ``Embedding`` - Vector representation with similarity methods
/// - ``RetrievalResult`` - Chunk with relevance score
/// - ``RAGResponse`` - Answer with sources
/// - ``MetadataValue`` - Flexible metadata value type
/// - ``MetadataFilter`` - Query filter conditions
///
/// ### Protocols
/// - ``DocumentLoader`` - Load documents from various sources
/// - ``ChunkingStrategy`` - Split documents into chunks
/// - ``EmbeddingProvider`` - Generate vector embeddings
/// - ``VectorStore`` - Store and search vectors
/// - ``Retriever`` - High-level document retrieval
/// - ``LLMProvider`` - Generate text responses
///
/// ### Configuration
/// - ``RAGConfiguration`` - Pipeline configuration options
/// - ``QueryOptions`` - Query-time options
/// - ``LLMOptions`` - LLM generation options
///
/// ### Errors
/// - ``ZoniError`` - All possible errors with recovery suggestions
public enum Zoni {
    /// The current version of Zoni
    public static let version = "0.1.0"
}
