// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGPrompts.swift - Prompt templates for RAG query operations.

import Foundation

// MARK: - RAGPrompts

/// Pre-defined prompt templates for RAG query synthesis and generation.
///
/// `RAGPrompts` provides standardized prompt templates for various RAG synthesis
/// strategies, including compact single-prompt, iterative refinement, and
/// hierarchical tree summarization approaches.
///
/// All templates use placeholder syntax (e.g., `{context}`, `{query}`) that must
/// be replaced with actual values before use in LLM generation.
///
/// Example usage:
/// ```swift
/// let prompt = RAGPrompts.compactTemplate
///     .replacingOccurrences(of: "{context}", with: contextText)
///     .replacingOccurrences(of: "{query}", with: userQuery)
/// ```
///
/// ## Topics
///
/// ### System Prompts
/// - ``defaultSystemPrompt``
///
/// ### Synthesis Templates
/// - ``compactTemplate``
/// - ``refineInitialTemplate``
/// - ``refineIterativeTemplate``
/// - ``treeSummarizeTemplate``
public enum RAGPrompts: Sendable {

    // MARK: - System Prompts

    /// Default system prompt for RAG-based question answering.
    ///
    /// This system prompt instructs the language model to:
    /// - Answer questions based solely on the provided context
    /// - Cite sources using `[Source N]` notation for attribution
    /// - Acknowledge when the context lacks relevant information
    /// - Maintain factual accuracy without hallucination
    ///
    /// Example usage:
    /// ```swift
    /// let messages = [
    ///     ("system", RAGPrompts.defaultSystemPrompt),
    ///     ("user", "Context:\n\(context)\n\nQuestion: \(query)")
    /// ]
    /// ```
    public static let defaultSystemPrompt: String = """
        You are a helpful assistant that answers questions based on the provided context.

        Guidelines:
        1. Answer the question using ONLY the information from the provided context.
        2. If the context contains relevant information, provide a comprehensive answer.
        3. Cite your sources by referencing [Source N] where N is the source number.
        4. If the context does not contain enough information to answer the question, \
        clearly state: "I don't have enough information in the provided context to answer this question."
        5. Do not make up or hallucinate information that is not in the context.
        6. Be concise but thorough in your responses.
        7. If multiple sources support your answer, cite all relevant sources.
        """

    // MARK: - Synthesis Templates

    /// Template for compact single-prompt synthesis.
    ///
    /// The compact template combines all retrieved context into a single prompt
    /// for one-shot answer generation. This is the simplest and most efficient
    /// synthesis strategy, suitable for most use cases.
    ///
    /// **Placeholders:**
    /// - `{context}` - The concatenated retrieved context from all sources
    /// - `{query}` - The user's question or query
    ///
    /// Example usage:
    /// ```swift
    /// let prompt = RAGPrompts.compactTemplate
    ///     .replacingOccurrences(of: "{context}", with: formattedContext)
    ///     .replacingOccurrences(of: "{query}", with: userQuestion)
    /// let response = try await llm.generate(prompt: prompt)
    /// ```
    public static let compactTemplate: String = """
        Context information is provided below.

        ---------------------
        {context}
        ---------------------

        Given the context information above and no prior knowledge, answer the following question.

        Question: {query}

        Answer:
        """

    /// Template for the initial answer in iterative refinement synthesis.
    ///
    /// The refine strategy processes context chunks iteratively, starting with
    /// this template to generate an initial answer from the first chunk. This
    /// approach is useful when context is too large for a single prompt or when
    /// incremental answer building produces better results.
    ///
    /// **Placeholders:**
    /// - `{context}` - The first context chunk to process
    /// - `{query}` - The user's question or query
    ///
    /// Example usage:
    /// ```swift
    /// let initialPrompt = RAGPrompts.refineInitialTemplate
    ///     .replacingOccurrences(of: "{context}", with: firstChunk)
    ///     .replacingOccurrences(of: "{query}", with: userQuestion)
    /// var currentAnswer = try await llm.generate(prompt: initialPrompt)
    /// ```
    public static let refineInitialTemplate: String = """
        Context information is provided below.

        ---------------------
        {context}
        ---------------------

        Given the context information above and no prior knowledge, answer the following question.

        Question: {query}

        Answer:
        """

    /// Template for iterative answer refinement with additional context.
    ///
    /// This template is used after the initial answer to progressively refine
    /// and improve the response with each additional context chunk. The model
    /// is instructed to either improve the existing answer or keep it unchanged
    /// if the new context is not relevant.
    ///
    /// **Placeholders:**
    /// - `{existing_answer}` - The current answer to be refined
    /// - `{context}` - The new context chunk to incorporate
    /// - `{query}` - The original user question
    ///
    /// Example usage:
    /// ```swift
    /// for chunk in remainingChunks {
    ///     let refinePrompt = RAGPrompts.refineIterativeTemplate
    ///         .replacingOccurrences(of: "{existing_answer}", with: currentAnswer)
    ///         .replacingOccurrences(of: "{context}", with: chunk)
    ///         .replacingOccurrences(of: "{query}", with: userQuestion)
    ///     currentAnswer = try await llm.generate(prompt: refinePrompt)
    /// }
    /// ```
    public static let refineIterativeTemplate: String = """
        The original question is as follows:

        Question: {query}

        We have provided an existing answer:

        ---------------------
        {existing_answer}
        ---------------------

        We have the opportunity to refine the existing answer (only if needed) with \
        some more context below.

        ---------------------
        {context}
        ---------------------

        Given the new context, refine the original answer to better answer the question. \
        If the context is not useful or relevant, return the original answer unchanged. \
        Do not mention that you are refining or that new context was provided.

        Refined Answer:
        """

    /// Template for hierarchical tree summarization synthesis.
    ///
    /// The tree summarization strategy recursively summarizes groups of context
    /// chunks in a hierarchical manner, reducing multiple chunks to a single
    /// summary at each level until a final answer emerges. This is effective
    /// for very large context sets.
    ///
    /// **Placeholders:**
    /// - `{context}` - Multiple context chunks or intermediate summaries
    /// - `{query}` - The user's question or query
    ///
    /// Example usage:
    /// ```swift
    /// // First level: summarize groups of raw chunks
    /// let level1Summaries = try await chunks.chunked(into: 3).asyncMap { group in
    ///     let prompt = RAGPrompts.treeSummarizeTemplate
    ///         .replacingOccurrences(of: "{context}", with: group.joined(separator: "\n\n"))
    ///         .replacingOccurrences(of: "{query}", with: userQuestion)
    ///     return try await llm.generate(prompt: prompt)
    /// }
    /// // Continue until single summary remains
    /// ```
    public static let treeSummarizeTemplate: String = """
        Context information from multiple sources is provided below.

        ---------------------
        {context}
        ---------------------

        Given the context information from multiple sources above and no prior knowledge, \
        synthesize a comprehensive answer to the following question. Combine information \
        from all relevant sources into a cohesive response.

        Question: {query}

        Synthesized Answer:
        """
}

// MARK: - Placeholder Constants

extension RAGPrompts {

    /// Placeholder string for context insertion in templates.
    ///
    /// Use this constant when programmatically replacing placeholders to ensure
    /// consistency across the codebase.
    ///
    /// Example usage:
    /// ```swift
    /// let prompt = RAGPrompts.compactTemplate
    ///     .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: context)
    /// ```
    public static let contextPlaceholder: String = "{context}"

    /// Placeholder string for query insertion in templates.
    ///
    /// Use this constant when programmatically replacing placeholders to ensure
    /// consistency across the codebase.
    ///
    /// Example usage:
    /// ```swift
    /// let prompt = RAGPrompts.compactTemplate
    ///     .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: query)
    /// ```
    public static let queryPlaceholder: String = "{query}"

    /// Placeholder string for existing answer insertion in refinement templates.
    ///
    /// Use this constant when programmatically replacing placeholders to ensure
    /// consistency across the codebase.
    ///
    /// Example usage:
    /// ```swift
    /// let prompt = RAGPrompts.refineIterativeTemplate
    ///     .replacingOccurrences(of: RAGPrompts.existingAnswerPlaceholder, with: answer)
    /// ```
    public static let existingAnswerPlaceholder: String = "{existing_answer}"
}

// MARK: - Template Validation

extension RAGPrompts {

    /// Validates that a template string contains all required placeholders.
    ///
    /// Use this method to verify custom templates have all necessary placeholders
    /// before using them for synthesis.
    ///
    /// - Parameters:
    ///   - template: The template string to validate.
    ///   - requiredPlaceholders: Array of placeholder strings that must be present.
    /// - Throws: `ZoniError.invalidConfiguration` if any placeholder is missing.
    ///
    /// Example usage:
    /// ```swift
    /// let customTemplate = """
    ///     Context: {context}
    ///     Question: {query}
    ///     Answer:
    ///     """
    /// try RAGPrompts.validateTemplate(
    ///     customTemplate,
    ///     requiredPlaceholders: [RAGPrompts.contextPlaceholder, RAGPrompts.queryPlaceholder]
    /// )
    /// ```
    public static func validateTemplate(
        _ template: String,
        requiredPlaceholders: [String]
    ) throws {
        let missing = requiredPlaceholders.filter { !template.contains($0) }
        guard missing.isEmpty else {
            throw ZoniError.invalidConfiguration(
                reason: "Template missing required placeholders: \(missing.joined(separator: ", "))"
            )
        }
    }

    /// Validates the compact template has all required placeholders.
    ///
    /// - Throws: `ZoniError.invalidConfiguration` if placeholders are missing.
    public static func validateCompactTemplate() throws {
        try validateTemplate(compactTemplate, requiredPlaceholders: [contextPlaceholder, queryPlaceholder])
    }

    /// Validates the refine initial template has all required placeholders.
    ///
    /// - Throws: `ZoniError.invalidConfiguration` if placeholders are missing.
    public static func validateRefineInitialTemplate() throws {
        try validateTemplate(refineInitialTemplate, requiredPlaceholders: [contextPlaceholder, queryPlaceholder])
    }

    /// Validates the refine iterative template has all required placeholders.
    ///
    /// - Throws: `ZoniError.invalidConfiguration` if placeholders are missing.
    public static func validateRefineIterativeTemplate() throws {
        try validateTemplate(
            refineIterativeTemplate,
            requiredPlaceholders: [contextPlaceholder, queryPlaceholder, existingAnswerPlaceholder]
        )
    }

    /// Validates the tree summarize template has all required placeholders.
    ///
    /// - Throws: `ZoniError.invalidConfiguration` if placeholders are missing.
    public static func validateTreeSummarizeTemplate() throws {
        try validateTemplate(treeSummarizeTemplate, requiredPlaceholders: [contextPlaceholder, queryPlaceholder])
    }
}
