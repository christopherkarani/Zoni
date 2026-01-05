// AgentWithRAG Example
//
// MockProviders.swift - Mock embedding and LLM providers for demo purposes.

import Zoni
import ZoniAgents

// MARK: - MockEmbeddingProvider

/// A mock embedding provider that generates deterministic embeddings based on text content.
///
/// This provider creates embeddings by hashing text content, making it suitable for
/// demonstrations and testing without requiring external API calls.
///
/// The embeddings are deterministic: the same text always produces the same embedding,
/// which allows for meaningful similarity comparisons in demos.
public struct MockEmbeddingProvider: EmbeddingProvider, Sendable {

    // MARK: - Properties

    public let name = "mock"
    public let dimensions: Int
    public let maxTokensPerRequest = 8192
    public let optimalBatchSize = 100

    // MARK: - Initialization

    /// Creates a mock embedding provider.
    ///
    /// - Parameter dimensions: The number of dimensions for generated embeddings. Default: 128.
    public init(dimensions: Int = 128) {
        self.dimensions = dimensions
    }

    // MARK: - EmbeddingProvider Protocol

    public func embed(_ text: String) async throws -> Embedding {
        // Generate a deterministic embedding based on text hash
        let vector = generateVector(for: text)
        return Embedding(vector: vector, model: "mock-\(dimensions)d")
    }

    public func embed(_ texts: [String]) async throws -> [Embedding] {
        texts.map { text in
            let vector = generateVector(for: text)
            return Embedding(vector: vector, model: "mock-\(dimensions)d")
        }
    }

    // MARK: - Private Methods

    /// Generates a deterministic vector from text content.
    ///
    /// Uses multiple hash functions to create a distributed vector that captures
    /// some semantic similarity (texts with shared words will have closer embeddings).
    private func generateVector(for text: String) -> [Float] {
        var vector = [Float](repeating: 0.0, count: dimensions)
        let words = text.lowercased().split(separator: " ")

        // Generate base vector from text hash
        let textHash = text.hashValue
        for i in 0..<dimensions {
            // Create varied values based on hash and position
            let seed = textHash &+ i &* 31
            vector[i] = Float(sin(Double(seed) * 0.001)) * 0.5
        }

        // Add word-based features for semantic similarity
        for (wordIndex, word) in words.enumerated() {
            let wordHash = word.hashValue
            let position = abs(wordHash) % dimensions
            vector[position] += 0.1 * Float(1.0 / Double(wordIndex + 1))
        }

        // Normalize the vector
        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            vector = vector.map { $0 / magnitude }
        }

        return vector
    }
}

// MARK: - MockLLMProvider

/// A mock LLM provider that generates contextual responses for demo purposes.
///
/// This provider creates realistic-looking responses based on the context provided,
/// without requiring external API calls. It detects the question type and generates
/// appropriate answers using the provided context.
public struct MockLLMProvider: LLMProvider, Sendable {

    // MARK: - Properties

    public let name = "mock"
    public let model = "mock-llm-v1"
    public let maxContextTokens = 4096

    /// Response delay in seconds (simulates API latency).
    private let responseDelay: Duration

    // MARK: - Initialization

    /// Creates a mock LLM provider.
    ///
    /// - Parameter responseDelay: Artificial delay before responses. Default: 0.1 seconds.
    public init(responseDelay: Duration = .milliseconds(100)) {
        self.responseDelay = responseDelay
    }

    // MARK: - LLMProvider Protocol

    public func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String {
        // Simulate API latency
        try await Task.sleep(for: responseDelay)

        // Extract context and question from prompt
        let (context, question) = parsePrompt(prompt)

        // Generate a contextual response
        return generateResponse(context: context, question: question)
    }

    public func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Generate full response
                    let response = try await generate(
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        options: options
                    )

                    // Stream word by word
                    let words = response.split(separator: " ")
                    for (index, word) in words.enumerated() {
                        let separator = index > 0 ? " " : ""
                        continuation.yield(separator + String(word))
                        try await Task.sleep(for: .milliseconds(20))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Parses the prompt to extract context and question.
    private func parsePrompt(_ prompt: String) -> (context: String, question: String) {
        // Look for common patterns in RAG prompts
        var context = ""
        var question = prompt

        // Pattern: "Context: ... Question: ..."
        if let contextRange = prompt.range(of: "Context:", options: .caseInsensitive),
           let questionRange = prompt.range(of: "Question:", options: .caseInsensitive) {
            context = String(prompt[contextRange.upperBound..<questionRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            question = String(prompt[questionRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Pattern: Look for quoted context or document sections
        if context.isEmpty, let docStart = prompt.range(of: "Documents:"),
           let questionStart = prompt.range(of: "Query:", options: .caseInsensitive) {
            context = String(prompt[docStart.upperBound..<questionStart.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            question = String(prompt[questionStart.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (context, question)
    }

    /// Generates a response based on context and question.
    private func generateResponse(context: String, question: String) -> String {
        // If we have context, use it to form a response
        if !context.isEmpty {
            // Extract key phrases from context
            let sentences = context.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !sentences.isEmpty {
                // Use context to form an answer
                let relevantSentence = sentences.first ?? ""
                return "Based on the provided information: \(relevantSentence). " +
                       "This information was retrieved from the knowledge base to answer your query about '\(question)'."
            }
        }

        // Generic response when no context is available
        return "I don't have specific information about '\(question)' in my knowledge base. " +
               "Please try rephrasing your question or ingesting relevant documents first."
    }
}

// MARK: - MockChunker

/// A simple mock chunking strategy for demo purposes.
///
/// Splits text into fixed-size chunks with overlap for context preservation.
public struct MockChunker: ChunkingStrategy, Sendable {

    public let name = "mock"
    public let chunkSize: Int
    public let overlap: Int

    /// Creates a mock chunker.
    ///
    /// - Parameters:
    ///   - chunkSize: Target size for each chunk in characters. Default: 200.
    ///   - overlap: Number of characters to overlap between chunks. Default: 50.
    public init(chunkSize: Int = 200, overlap: Int = 50) {
        self.chunkSize = chunkSize
        self.overlap = overlap
    }

    public func chunk(_ document: Document) async throws -> [Chunk] {
        let baseMetadata = ChunkMetadata(
            documentId: document.id,
            index: 0,
            source: document.metadata.source
        )
        return try await chunk(document.content, metadata: baseMetadata)
    }

    public func chunk(_ text: String, metadata: ChunkMetadata?) async throws -> [Chunk] {
        guard !text.isEmpty else {
            throw ZoniError.emptyDocument
        }

        var chunks: [Chunk] = []
        var startIndex = text.startIndex
        var chunkIndex = 0
        let documentId = metadata?.documentId ?? UUID().uuidString
        let source = metadata?.source

        while startIndex < text.endIndex {
            let remainingDistance = text.distance(from: startIndex, to: text.endIndex)
            let chunkLength = min(chunkSize, remainingDistance)
            let endIndex = text.index(startIndex, offsetBy: chunkLength)

            let chunkContent = String(text[startIndex..<endIndex])
            let startOffset = text.distance(from: text.startIndex, to: startIndex)
            let endOffset = text.distance(from: text.startIndex, to: endIndex)

            let chunkMetadata = ChunkMetadata(
                documentId: documentId,
                index: chunkIndex,
                startOffset: startOffset,
                endOffset: endOffset,
                source: source
            )

            chunks.append(Chunk(content: chunkContent, metadata: chunkMetadata))

            let stride = chunkSize - overlap
            let nextStartOffset = startOffset + stride

            if endIndex >= text.endIndex || nextStartOffset >= text.count {
                break
            }

            startIndex = text.index(text.startIndex, offsetBy: nextStartOffset)
            chunkIndex += 1
        }

        return chunks
    }
}
