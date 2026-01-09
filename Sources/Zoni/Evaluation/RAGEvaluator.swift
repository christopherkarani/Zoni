// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGEvaluator.swift - Evaluation framework for RAG pipeline quality.

import Foundation

// MARK: - Evaluation Types

/// An item to evaluate in the RAG pipeline.
///
/// `EvaluationItem` represents a single test case for evaluating
/// the RAG pipeline's retrieval and generation capabilities.
///
/// Example usage:
/// ```swift
/// let item = EvaluationItem(
///     query: "What is Swift concurrency?",
///     expectedChunkIds: ["chunk-1", "chunk-2"],
///     groundTruthAnswer: "Swift concurrency provides async/await..."
/// )
/// ```
public struct EvaluationItem: Sendable {
    /// The query to evaluate.
    public let query: String

    /// The expected chunk IDs that should be retrieved for this query.
    ///
    /// Used to calculate precision and recall metrics.
    public let expectedChunkIds: [String]?

    /// The ground truth answer for evaluating generation quality.
    ///
    /// Used to calculate faithfulness and relevance scores.
    public let groundTruthAnswer: String?

    /// The IDs of documents that are relevant to this query.
    ///
    /// Used for document-level relevance metrics.
    public let relevantDocumentIds: [String]?

    /// Creates a new evaluation item.
    ///
    /// - Parameters:
    ///   - query: The query to evaluate.
    ///   - expectedChunkIds: Expected chunk IDs for retrieval metrics.
    ///   - groundTruthAnswer: Ground truth answer for generation metrics.
    ///   - relevantDocumentIds: Relevant document IDs for document-level metrics.
    public init(
        query: String,
        expectedChunkIds: [String]? = nil,
        groundTruthAnswer: String? = nil,
        relevantDocumentIds: [String]? = nil
    ) {
        self.query = query
        self.expectedChunkIds = expectedChunkIds
        self.groundTruthAnswer = groundTruthAnswer
        self.relevantDocumentIds = relevantDocumentIds
    }
}

/// A dataset of evaluation items for benchmarking RAG pipelines.
///
/// `EvaluationDataset` groups multiple evaluation items together
/// for systematic evaluation of RAG pipeline quality.
///
/// Example usage:
/// ```swift
/// let dataset = EvaluationDataset(
///     items: [item1, item2, item3],
///     name: "Swift Documentation QA"
/// )
/// let results = try await evaluator.evaluate(dataset)
/// ```
public struct EvaluationDataset: Sendable {
    /// The evaluation items in this dataset.
    public let items: [EvaluationItem]

    /// A name for this dataset for identification in results.
    public let name: String

    /// Creates a new evaluation dataset.
    ///
    /// - Parameters:
    ///   - items: The evaluation items to include.
    ///   - name: A name for the dataset. Defaults to "default".
    public init(items: [EvaluationItem], name: String = "default") {
        self.items = items
        self.name = name
    }
}

// MARK: - Metrics Types

/// Metrics for evaluating retrieval quality.
///
/// `RetrievalMetrics` captures how well the RAG pipeline retrieves
/// relevant documents in response to queries.
public struct RetrievalMetrics: Sendable {
    /// Precision: The ratio of relevant retrieved chunks to total retrieved chunks.
    ///
    /// A precision of 1.0 means all retrieved chunks were relevant.
    public let precision: Float

    /// Recall: The ratio of relevant retrieved chunks to total relevant chunks.
    ///
    /// A recall of 1.0 means all relevant chunks were retrieved.
    public let recall: Float

    /// F1 Score: The harmonic mean of precision and recall.
    ///
    /// Provides a balanced measure of retrieval quality.
    public let f1Score: Float

    /// Mean Reciprocal Rank: Average of the reciprocal ranks of first relevant results.
    ///
    /// Placeholder: Currently returns 0.
    public let mrr: Float

    /// Normalized Discounted Cumulative Gain: Measures ranking quality.
    ///
    /// Placeholder: Currently returns 0.
    public let ndcg: Float

    /// The average retrieval latency in milliseconds.
    public let averageLatencyMs: Double

    /// Creates new retrieval metrics.
    ///
    /// - Parameters:
    ///   - precision: Precision score (0.0 to 1.0).
    ///   - recall: Recall score (0.0 to 1.0).
    ///   - f1Score: F1 score (0.0 to 1.0).
    ///   - mrr: Mean Reciprocal Rank (placeholder).
    ///   - ndcg: NDCG score (placeholder).
    ///   - averageLatencyMs: Average latency in milliseconds.
    public init(
        precision: Float,
        recall: Float,
        f1Score: Float,
        mrr: Float,
        ndcg: Float,
        averageLatencyMs: Double
    ) {
        self.precision = precision
        self.recall = recall
        self.f1Score = f1Score
        self.mrr = mrr
        self.ndcg = ndcg
        self.averageLatencyMs = averageLatencyMs
    }
}

/// Metrics for evaluating generation quality.
///
/// `GenerationMetrics` captures how well the RAG pipeline generates
/// accurate and relevant answers based on retrieved context.
public struct GenerationMetrics: Sendable {
    /// Faithfulness: How well the answer is grounded in the retrieved context.
    ///
    /// A score of 1.0 means the answer is fully supported by the context.
    public let faithfulness: Float

    /// Relevance: How relevant the answer is to the query.
    ///
    /// Placeholder: Currently returns 0.
    public let relevance: Float

    /// Coherence: How coherent and well-structured the answer is.
    ///
    /// Placeholder: Currently returns 0.
    public let coherence: Float

    /// The average generation latency in milliseconds.
    public let averageLatencyMs: Double

    /// Creates new generation metrics.
    ///
    /// - Parameters:
    ///   - faithfulness: Faithfulness score (0.0 to 1.0).
    ///   - relevance: Relevance score (placeholder).
    ///   - coherence: Coherence score (placeholder).
    ///   - averageLatencyMs: Average latency in milliseconds.
    public init(
        faithfulness: Float,
        relevance: Float,
        coherence: Float,
        averageLatencyMs: Double
    ) {
        self.faithfulness = faithfulness
        self.relevance = relevance
        self.coherence = coherence
        self.averageLatencyMs = averageLatencyMs
    }
}

/// Complete evaluation results for a RAG pipeline.
///
/// `EvaluationResults` provides comprehensive metrics from evaluating
/// a RAG pipeline against a dataset, including both aggregate metrics
/// and per-item breakdowns.
///
/// Example usage:
/// ```swift
/// let results = try await evaluator.evaluate(dataset)
/// print("Precision: \(results.retrievalMetrics.precision)")
/// print("Faithfulness: \(results.generationMetrics.faithfulness)")
/// ```
public struct EvaluationResults: Sendable {
    /// Aggregated metrics for retrieval quality across all items.
    public let retrievalMetrics: RetrievalMetrics

    /// Aggregated metrics for generation quality across all items.
    public let generationMetrics: GenerationMetrics

    /// Individual results for each evaluation item.
    public let itemResults: [ItemResult]

    /// The timestamp when the evaluation was completed.
    public let timestamp: Date

    /// Creates new evaluation results.
    ///
    /// - Parameters:
    ///   - retrievalMetrics: Aggregated retrieval metrics.
    ///   - generationMetrics: Aggregated generation metrics.
    ///   - itemResults: Per-item result breakdowns.
    ///   - timestamp: When the evaluation completed.
    public init(
        retrievalMetrics: RetrievalMetrics,
        generationMetrics: GenerationMetrics,
        itemResults: [ItemResult],
        timestamp: Date
    ) {
        self.retrievalMetrics = retrievalMetrics
        self.generationMetrics = generationMetrics
        self.itemResults = itemResults
        self.timestamp = timestamp
    }

    /// Result for a single evaluation item.
    public struct ItemResult: Sendable {
        /// The query that was evaluated.
        public let query: String

        /// The chunk IDs that were retrieved.
        public let retrievedChunkIds: [String]

        /// The answer generated by the pipeline.
        public let generatedAnswer: String

        /// Precision score for this item.
        public let precision: Float

        /// Recall score for this item.
        public let recall: Float

        /// Faithfulness score for this item, if computed.
        public let faithfulness: Float?

        /// Time taken for retrieval in milliseconds.
        public let retrievalLatencyMs: Double

        /// Time taken for generation in milliseconds.
        public let generationLatencyMs: Double

        /// Creates a new item result.
        ///
        /// - Parameters:
        ///   - query: The evaluated query.
        ///   - retrievedChunkIds: IDs of retrieved chunks.
        ///   - generatedAnswer: The generated answer.
        ///   - precision: Precision score.
        ///   - recall: Recall score.
        ///   - faithfulness: Faithfulness score (optional).
        ///   - retrievalLatencyMs: Retrieval latency in ms.
        ///   - generationLatencyMs: Generation latency in ms.
        public init(
            query: String,
            retrievedChunkIds: [String],
            generatedAnswer: String,
            precision: Float,
            recall: Float,
            faithfulness: Float?,
            retrievalLatencyMs: Double,
            generationLatencyMs: Double
        ) {
            self.query = query
            self.retrievedChunkIds = retrievedChunkIds
            self.generatedAnswer = generatedAnswer
            self.precision = precision
            self.recall = recall
            self.faithfulness = faithfulness
            self.retrievalLatencyMs = retrievalLatencyMs
            self.generationLatencyMs = generationLatencyMs
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Converts the duration to milliseconds.
    var milliseconds: Int64 {
        let (seconds, attoseconds) = self.components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}

// MARK: - RAGEvaluator

/// An actor that evaluates RAG pipeline quality.
///
/// `RAGEvaluator` provides comprehensive evaluation of RAG pipelines,
/// measuring both retrieval quality (precision, recall, F1) and
/// generation quality (faithfulness, relevance, coherence).
///
/// ## Overview
///
/// The evaluator runs evaluation items through the pipeline and compares
/// results against ground truth data to calculate quality metrics.
///
/// ## Example Usage
///
/// ```swift
/// let evaluator = RAGEvaluator(pipeline: pipeline, llmJudge: judge)
///
/// let dataset = EvaluationDataset(
///     items: [
///         EvaluationItem(
///             query: "What is Swift?",
///             expectedChunkIds: ["swift-intro"],
///             groundTruthAnswer: "Swift is a programming language..."
///         )
///     ],
///     name: "Swift QA"
/// )
///
/// let results = try await evaluator.evaluate(dataset)
/// print("Precision: \(results.retrievalMetrics.precision)")
/// print("Recall: \(results.retrievalMetrics.recall)")
/// print("Faithfulness: \(results.generationMetrics.faithfulness)")
/// ```
///
/// ## Thread Safety
///
/// `RAGEvaluator` is implemented as an actor to ensure thread-safe
/// evaluation operations.
public actor RAGEvaluator {

    // MARK: - Properties

    /// The RAG pipeline to evaluate.
    private let pipeline: RAGPipeline

    /// An optional LLM provider used as a judge for generation quality metrics.
    ///
    /// When provided, the evaluator uses this LLM to assess faithfulness
    /// and other generation quality metrics.
    private let llmJudge: (any LLMProvider)?

    // MARK: - Initialization

    /// Creates a new RAG evaluator.
    ///
    /// - Parameters:
    ///   - pipeline: The RAG pipeline to evaluate.
    ///   - llmJudge: An optional LLM provider for judging generation quality.
    ///               When provided, enables faithfulness scoring.
    public init(pipeline: RAGPipeline, llmJudge: (any LLMProvider)? = nil) {
        self.pipeline = pipeline
        self.llmJudge = llmJudge
    }

    // MARK: - Public Methods

    /// Evaluates the RAG pipeline against a dataset.
    ///
    /// Runs each item in the dataset through the pipeline, measures
    /// retrieval and generation quality, and returns aggregated metrics.
    ///
    /// - Parameter dataset: The evaluation dataset to run.
    /// - Returns: Comprehensive evaluation results with metrics and per-item breakdowns.
    /// - Throws: `ZoniError` if pipeline operations fail.
    public func evaluate(_ dataset: EvaluationDataset) async throws -> EvaluationResults {
        var itemResults: [EvaluationResults.ItemResult] = []

        for item in dataset.items {
            let result = try await evaluateItem(item)
            itemResults.append(result)
        }

        let retrievalMetrics = aggregateRetrievalMetrics(itemResults)
        let generationMetrics = aggregateGenerationMetrics(itemResults)

        return EvaluationResults(
            retrievalMetrics: retrievalMetrics,
            generationMetrics: generationMetrics,
            itemResults: itemResults,
            timestamp: Date()
        )
    }

    // MARK: - Private Methods

    /// Evaluates a single evaluation item.
    ///
    /// - Parameter item: The item to evaluate.
    /// - Returns: The evaluation result for this item.
    private func evaluateItem(_ item: EvaluationItem) async throws -> EvaluationResults.ItemResult {
        // Measure retrieval latency
        let retrievalStart = ContinuousClock.now
        let retrievalResults = try await pipeline.retrieve(item.query)
        let retrievalDuration = ContinuousClock.now - retrievalStart
        let retrievalLatencyMs = Double(retrievalDuration.milliseconds)

        let retrievedChunkIds = retrievalResults.map(\.chunk.id)

        // Measure generation latency
        let generationStart = ContinuousClock.now
        let response = try await pipeline.query(item.query)
        let generationDuration = ContinuousClock.now - generationStart
        let generationLatencyMs = Double(generationDuration.milliseconds)

        // Calculate precision and recall
        let (precision, recall) = calculatePrecisionRecall(
            retrieved: Set(retrievedChunkIds),
            relevant: Set(item.expectedChunkIds ?? [])
        )

        // Calculate faithfulness if we have a judge and ground truth
        var faithfulness: Float?
        if let judge = llmJudge,
           let groundTruth = item.groundTruthAnswer {
            let context = retrievalResults.map(\.chunk.content).joined(separator: "\n\n")
            faithfulness = try await calculateFaithfulness(
                answer: response.answer,
                context: context,
                groundTruth: groundTruth,
                judge: judge
            )
        }

        return EvaluationResults.ItemResult(
            query: item.query,
            retrievedChunkIds: retrievedChunkIds,
            generatedAnswer: response.answer,
            precision: precision,
            recall: recall,
            faithfulness: faithfulness,
            retrievalLatencyMs: retrievalLatencyMs,
            generationLatencyMs: generationLatencyMs
        )
    }

    /// Calculates precision and recall for a retrieval result.
    ///
    /// - Parameters:
    ///   - retrieved: The set of retrieved chunk IDs.
    ///   - relevant: The set of relevant (expected) chunk IDs.
    /// - Returns: A tuple of (precision, recall) values.
    private func calculatePrecisionRecall(
        retrieved: Set<String>,
        relevant: Set<String>
    ) -> (precision: Float, recall: Float) {
        guard !retrieved.isEmpty || !relevant.isEmpty else {
            return (precision: 1.0, recall: 1.0)
        }

        let intersection = retrieved.intersection(relevant)

        let precision: Float
        if retrieved.isEmpty {
            precision = 0.0
        } else {
            precision = Float(intersection.count) / Float(retrieved.count)
        }

        let recall: Float
        if relevant.isEmpty {
            recall = 1.0
        } else {
            recall = Float(intersection.count) / Float(relevant.count)
        }

        return (precision: precision, recall: recall)
    }

    /// Calculates faithfulness score using an LLM judge.
    ///
    /// The judge evaluates whether the answer is grounded in the context
    /// and matches the ground truth.
    ///
    /// - Parameters:
    ///   - answer: The generated answer to evaluate.
    ///   - context: The retrieved context used for generation.
    ///   - groundTruth: The expected correct answer.
    ///   - judge: The LLM provider to use as a judge.
    /// - Returns: A faithfulness score from 0.0 to 1.0.
    private func calculateFaithfulness(
        answer: String,
        context: String,
        groundTruth: String,
        judge: any LLMProvider
    ) async throws -> Float {
        let prompt = """
        You are evaluating the faithfulness of an AI-generated answer.

        CONTEXT (retrieved documents):
        \(context)

        GROUND TRUTH ANSWER:
        \(groundTruth)

        GENERATED ANSWER:
        \(answer)

        Evaluate the generated answer on a scale of 0.0 to 1.0 based on:
        1. Is the answer grounded in the context? (Does it only use information from the context?)
        2. Does it match the ground truth answer in meaning and accuracy?

        Respond with ONLY a single decimal number between 0.0 and 1.0.
        - 1.0 = Perfect: Fully grounded and matches ground truth
        - 0.7-0.9 = Good: Mostly grounded, minor deviations from ground truth
        - 0.4-0.6 = Moderate: Partially grounded, some unsupported claims
        - 0.1-0.3 = Poor: Significant unsupported claims
        - 0.0 = Completely unfaithful or contradicts the context

        Score:
        """

        let systemPrompt = "You are a precise evaluation assistant. Respond only with a decimal number."

        let response = try await judge.generate(prompt: prompt, systemPrompt: systemPrompt)

        // Parse the score from the response
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let score = Float(trimmed) {
            return min(max(score, 0.0), 1.0)
        }

        // Try to extract a number from the response using regex
        do {
            let pattern = #"(\d+\.?\d*)"#
            let regex = try NSRegularExpression(pattern: pattern)
            if let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed),
               let score = Float(String(trimmed[range])) {
                return min(max(score, 0.0), 1.0)
            }
        } catch {
            // Log regex compilation errors in debug builds
            #if DEBUG
            assertionFailure("[RAGEvaluator] Regex pattern compilation failed: \(error). This should not happen with a valid pattern.")
            #endif
        }

        // Default to moderate score if parsing fails
        #if DEBUG
        print("[RAGEvaluator] Failed to parse faithfulness score from response: '\(trimmed.prefix(100))'. Defaulting to 0.5")
        #endif
        return 0.5
    }

    /// Aggregates retrieval metrics from individual item results.
    ///
    /// - Parameter results: The individual item results.
    /// - Returns: Aggregated retrieval metrics.
    private func aggregateRetrievalMetrics(
        _ results: [EvaluationResults.ItemResult]
    ) -> RetrievalMetrics {
        guard !results.isEmpty else {
            return RetrievalMetrics(
                precision: 0,
                recall: 0,
                f1Score: 0,
                mrr: 0,
                ndcg: 0,
                averageLatencyMs: 0
            )
        }

        let avgPrecision = results.map(\.precision).reduce(0, +) / Float(results.count)
        let avgRecall = results.map(\.recall).reduce(0, +) / Float(results.count)

        let f1Score: Float
        if avgPrecision + avgRecall > 0 {
            f1Score = 2 * (avgPrecision * avgRecall) / (avgPrecision + avgRecall)
        } else {
            f1Score = 0
        }

        let avgLatency = results.map(\.retrievalLatencyMs).reduce(0, +) / Double(results.count)

        return RetrievalMetrics(
            precision: avgPrecision,
            recall: avgRecall,
            f1Score: f1Score,
            mrr: 0,  // Placeholder
            ndcg: 0, // Placeholder
            averageLatencyMs: avgLatency
        )
    }

    /// Aggregates generation metrics from individual item results.
    ///
    /// - Parameter results: The individual item results.
    /// - Returns: Aggregated generation metrics.
    private func aggregateGenerationMetrics(
        _ results: [EvaluationResults.ItemResult]
    ) -> GenerationMetrics {
        guard !results.isEmpty else {
            return GenerationMetrics(
                faithfulness: 0,
                relevance: 0,
                coherence: 0,
                averageLatencyMs: 0
            )
        }

        // Calculate average faithfulness from items that have it
        let faithfulnessScores = results.compactMap(\.faithfulness)
        let avgFaithfulness: Float
        if faithfulnessScores.isEmpty {
            avgFaithfulness = 0
        } else {
            avgFaithfulness = faithfulnessScores.reduce(0, +) / Float(faithfulnessScores.count)
        }

        let avgLatency = results.map(\.generationLatencyMs).reduce(0, +) / Double(results.count)

        return GenerationMetrics(
            faithfulness: avgFaithfulness,
            relevance: 0,  // Placeholder
            coherence: 0,  // Placeholder
            averageLatencyMs: avgLatency
        )
    }
}

// MARK: - CustomStringConvertible

extension RetrievalMetrics: CustomStringConvertible {
    public var description: String {
        "RetrievalMetrics(precision: \(String(format: "%.3f", precision)), " +
        "recall: \(String(format: "%.3f", recall)), " +
        "f1: \(String(format: "%.3f", f1Score)), " +
        "latency: \(String(format: "%.1f", averageLatencyMs))ms)"
    }
}

extension GenerationMetrics: CustomStringConvertible {
    public var description: String {
        "GenerationMetrics(faithfulness: \(String(format: "%.3f", faithfulness)), " +
        "latency: \(String(format: "%.1f", averageLatencyMs))ms)"
    }
}

extension EvaluationResults: CustomStringConvertible {
    public var description: String {
        "EvaluationResults(items: \(itemResults.count), " +
        "retrieval: \(retrievalMetrics), " +
        "generation: \(generationMetrics))"
    }
}
