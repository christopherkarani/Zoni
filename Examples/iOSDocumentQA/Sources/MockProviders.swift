// iOSDocumentQA - Example iOS app demonstrating Zoni RAG capabilities
//
// MockProviders.swift - Mock LLM provider for demo purposes

import Foundation
import Zoni

// MARK: - MockLLMProvider

/// A mock LLM provider that generates placeholder responses for demo purposes.
///
/// This provider demonstrates the RAG pipeline without requiring an API key.
/// It synthesizes answers from the retrieved context, making it useful for
/// testing and development.
///
/// ## Usage
/// ```swift
/// let provider = MockLLMProvider()
/// let response = try await provider.generate(
///     prompt: "Based on the context, answer: What is Swift?",
///     systemPrompt: nil
/// )
/// ```
///
/// ## Production Use
/// For production apps, replace this with a real LLM provider:
/// - OpenAI GPT-4
/// - Anthropic Claude
/// - Local LLM via Ollama
/// - Apple Foundation Models (iOS 26+)
public struct MockLLMProvider: LLMProvider, Sendable {

    // MARK: - LLMProvider Properties

    /// The provider name for identification.
    public let name = "mock"

    /// The model identifier.
    public let model = "mock-demo-v1"

    /// Maximum context tokens supported.
    ///
    /// This mock provider accepts up to 8192 tokens, matching common LLM limits.
    public let maxContextTokens = 8192

    // MARK: - Initialization

    /// Creates a new mock LLM provider.
    public init() {}

    // MARK: - LLMProvider Methods

    /// Generates a mock response based on the provided prompt.
    ///
    /// The mock provider extracts context from the prompt and creates a
    /// summarized response that demonstrates the RAG pipeline flow.
    ///
    /// - Parameters:
    ///   - prompt: The prompt containing context and question.
    ///   - systemPrompt: Optional system prompt (ignored in mock).
    ///   - options: LLM generation options (ignored in mock).
    /// - Returns: A mock response synthesized from the context.
    public func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String {
        // Simulate some processing time
        try await Task.sleep(for: .milliseconds(500))

        // Extract the question from the prompt
        let question = extractQuestion(from: prompt)

        // Extract context snippets
        let contextSnippets = extractContextSnippets(from: prompt)

        // Generate a mock response
        return generateMockResponse(question: question, context: contextSnippets)
    }

    /// Streams a mock response chunk by chunk.
    ///
    /// - Parameters:
    ///   - prompt: The prompt containing context and question.
    ///   - systemPrompt: Optional system prompt (ignored in mock).
    ///   - options: LLM generation options (ignored in mock).
    /// - Returns: An async stream of response chunks.
    public func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generate(
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        options: options
                    )

                    // Stream word by word for a realistic effect
                    let words = response.split(separator: " ")
                    for (index, word) in words.enumerated() {
                        try await Task.sleep(for: .milliseconds(50))
                        let chunk = index == 0 ? String(word) : " " + String(word)
                        continuation.yield(chunk)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Extracts the question from a RAG prompt.
    private func extractQuestion(from prompt: String) -> String {
        // Look for common question patterns in the prompt
        let patterns = [
            "Question: ",
            "User question: ",
            "Query: ",
            "Answer the following: "
        ]

        for pattern in patterns {
            if let range = prompt.range(of: pattern, options: .caseInsensitive) {
                let afterPattern = prompt[range.upperBound...]
                // Take until newline or end
                if let newlineRange = afterPattern.range(of: "\n") {
                    return String(afterPattern[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return String(afterPattern).trimmingCharacters(in: .whitespaces)
            }
        }

        // If no pattern found, return a default
        return "your question"
    }

    /// Extracts context snippets from a RAG prompt.
    private func extractContextSnippets(from prompt: String) -> [String] {
        var snippets: [String] = []

        // Look for context sections
        let contextPatterns = [
            "Context:",
            "Relevant information:",
            "Source documents:",
            "Retrieved content:"
        ]

        for pattern in contextPatterns {
            if let range = prompt.range(of: pattern, options: .caseInsensitive) {
                let afterPattern = prompt[range.upperBound...]

                // Extract up to the question or end
                let endPatterns = ["Question:", "Query:", "---"]
                var endIndex = afterPattern.endIndex

                for endPattern in endPatterns {
                    if let endRange = afterPattern.range(of: endPattern, options: .caseInsensitive) {
                        if endRange.lowerBound < endIndex {
                            endIndex = endRange.lowerBound
                        }
                    }
                }

                let contextText = String(afterPattern[..<endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !contextText.isEmpty {
                    // Split into paragraphs and take first few
                    let paragraphs = contextText.components(separatedBy: "\n\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .prefix(3)

                    snippets.append(contentsOf: paragraphs)
                }
                break
            }
        }

        return snippets
    }

    /// Generates a mock response from the question and context.
    private func generateMockResponse(question: String, context: [String]) -> String {
        if context.isEmpty {
            return """
                I don't have enough context to answer "\(question)" accurately. \
                Please add some documents to the knowledge base first.
                """
        }

        // Create a synthesized response
        let contextSummary = context.prefix(2).joined(separator: " ")
        let truncatedSummary = String(contextSummary.prefix(300))

        return """
            Based on the documents in your knowledge base, here's what I found:

            \(truncatedSummary)...

            [Note: This is a demo response from MockLLMProvider. For production use, \
            integrate a real LLM provider like OpenAI, Anthropic, or Apple Foundation Models.]
            """
    }
}
