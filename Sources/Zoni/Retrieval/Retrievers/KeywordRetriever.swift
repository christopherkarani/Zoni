// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// KeywordRetriever.swift - BM25 keyword retrieval strategy

import Foundation

// MARK: - KeywordRetriever

/// A retriever that uses BM25 keyword matching.
///
/// `KeywordRetriever` implements the Okapi BM25 ranking algorithm for
/// lexical search. It maintains an inverted index of terms to chunks
/// and scores matches based on term frequency and document frequency.
///
/// ## BM25 Algorithm
///
/// The BM25 score for a term in a document is calculated as:
/// ```
/// IDF(term) = log((N - df + 0.5) / (df + 0.5) + 1)
/// Score = IDF * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * docLen / avgDocLen))
/// ```
///
/// Where:
/// - N = total number of documents
/// - df = document frequency (documents containing the term)
/// - tf = term frequency in the document
/// - k1 = term frequency saturation parameter (default: 1.2)
/// - b = length normalization parameter (default: 0.75)
///
/// ## Example Usage
///
/// ```swift
/// let retriever = KeywordRetriever()
///
/// // Index chunks
/// await retriever.index([chunk1, chunk2, chunk3])
///
/// // Search
/// let results = try await retriever.retrieve(
///     query: "Swift programming",
///     limit: 10,
///     filter: nil
/// )
/// ```
public actor KeywordRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "keyword"

    /// BM25 term frequency saturation parameter.
    ///
    /// Higher values increase the influence of term frequency.
    /// Typical range: 1.2 to 2.0. Default: 1.2
    public var k1: Double = 1.2

    /// BM25 length normalization parameter.
    ///
    /// 0.0 = no length normalization, 1.0 = full normalization.
    /// Default: 0.75
    public var b: Double = 0.75

    /// Maximum number of chunks to store (memory safety).
    private let maxChunkCount: Int

    // MARK: - Index State

    /// Inverted index: term -> set of chunk IDs containing the term.
    private var invertedIndex: [String: Set<String>] = [:]

    /// Document frequency: term -> number of chunks containing the term.
    private var documentFrequencies: [String: Int] = [:]

    /// Chunk lengths: chunk ID -> number of terms in the chunk.
    private var chunkLengths: [String: Int] = [:]

    /// Stored chunks: chunk ID -> chunk.
    private var chunks: [String: Chunk] = [:]

    /// Cached term frequencies: chunk ID -> term -> count.
    private var termFrequencyCache: [String: [String: Int]] = [:]

    /// Total number of indexed chunks.
    private var totalChunks: Int = 0

    /// Average chunk length in terms.
    private var avgChunkLength: Double = 0

    // MARK: - Initialization

    /// Creates a new keyword retriever.
    ///
    /// - Parameters:
    ///   - k1: BM25 term frequency saturation. Must be > 0. Default: 1.2
    ///   - b: BM25 length normalization. Must be in [0, 1]. Default: 0.75
    ///   - maxChunkCount: Maximum chunks to store. Must be > 0. Default: 1,000,000
    /// - Precondition: k1 > 0, b in [0, 1], maxChunkCount > 0
    public init(
        k1: Double = 1.2,
        b: Double = 0.75,
        maxChunkCount: Int = 1_000_000
    ) {
        precondition(k1 > 0, "BM25 k1 must be positive, got \(k1)")
        precondition(b >= 0 && b <= 1, "BM25 b must be in [0, 1], got \(b)")
        precondition(maxChunkCount > 0, "maxChunkCount must be positive, got \(maxChunkCount)")

        self.k1 = k1
        self.b = b
        self.maxChunkCount = maxChunkCount
    }

    // MARK: - Indexing

    /// Indexes chunks for keyword search.
    ///
    /// Each chunk is tokenized and added to the inverted index.
    /// Duplicate chunk IDs will update the existing entry.
    ///
    /// - Parameter chunks: The chunks to index.
    public func index(_ newChunks: [Chunk]) {
        for chunk in newChunks {
            // Check memory limit
            if chunks.count >= maxChunkCount && chunks[chunk.id] == nil {
                continue
            }

            // Remove existing entry if updating
            if chunks[chunk.id] != nil {
                removeFromIndexInternal(id: chunk.id)
            }

            // Store chunk
            chunks[chunk.id] = chunk

            // Tokenize content
            let terms = RetrievalUtils.tokenize(chunk.content)
            chunkLengths[chunk.id] = terms.count

            // Calculate and cache term frequencies
            var tf: [String: Int] = [:]
            for term in terms {
                tf[term, default: 0] += 1
            }
            termFrequencyCache[chunk.id] = tf

            // Update inverted index and document frequencies
            let uniqueTerms = Set(terms)
            for term in uniqueTerms {
                invertedIndex[term, default: []].insert(chunk.id)
                documentFrequencies[term, default: 0] += 1
            }
        }

        // Update statistics
        totalChunks = chunks.count
        avgChunkLength = chunkLengths.values.isEmpty ? 0 :
            Double(chunkLengths.values.reduce(0, +)) / Double(totalChunks)
    }

    /// Removes chunks from the index by ID.
    ///
    /// - Parameter ids: The chunk IDs to remove.
    public func removeFromIndex(ids: [String]) {
        for id in ids {
            removeFromIndexInternal(id: id)
        }

        // Update statistics
        totalChunks = chunks.count
        avgChunkLength = chunkLengths.values.isEmpty ? 0 :
            Double(chunkLengths.values.reduce(0, +)) / Double(max(1, totalChunks))
    }

    /// Clears all indexed data.
    public func clearIndex() {
        invertedIndex.removeAll()
        documentFrequencies.removeAll()
        chunkLengths.removeAll()
        chunks.removeAll()
        termFrequencyCache.removeAll()
        totalChunks = 0
        avgChunkLength = 0
    }

    /// Returns the number of indexed chunks.
    public func indexedCount() -> Int {
        totalChunks
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant chunks using BM25 keyword matching.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to apply.
    /// - Returns: Matching chunks sorted by BM25 score (descending).
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        let queryTerms = RetrievalUtils.tokenize(query)

        guard !queryTerms.isEmpty else {
            return []
        }

        var scores: [String: Double] = [:]

        for term in queryTerms {
            guard let chunkIds = invertedIndex[term] else { continue }

            // Calculate IDF
            let df = Double(chunkIds.count)
            let idf = log((Double(totalChunks) - df + 0.5) / (df + 0.5) + 1)

            for chunkId in chunkIds {
                // Apply metadata filter if provided
                if let filter = filter, let chunk = chunks[chunkId] {
                    if !filter.matches(chunk) {
                        continue
                    }
                }

                // Calculate term frequency
                let tf = termFrequency(term, in: chunkId)
                let docLen = Double(chunkLengths[chunkId] ?? 0)

                // BM25 score for this term
                let score = idf * (tf * (k1 + 1)) /
                    (tf + k1 * (1 - b + b * docLen / max(1, avgChunkLength)))

                scores[chunkId, default: 0] += score
            }
        }

        // Sort by score and return top results
        return scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { id, score in
                guard let chunk = chunks[id] else { return nil }
                return RetrievalResult(chunk: chunk, score: Float(score))
            }
    }

    // MARK: - Private Methods

    /// Removes a single chunk from the index.
    private func removeFromIndexInternal(id: String) {
        guard let chunk = chunks.removeValue(forKey: id) else { return }
        chunkLengths.removeValue(forKey: id)
        termFrequencyCache.removeValue(forKey: id)

        let terms = Set(RetrievalUtils.tokenize(chunk.content))
        for term in terms {
            invertedIndex[term]?.remove(id)
            if invertedIndex[term]?.isEmpty == true {
                invertedIndex.removeValue(forKey: term)
            }
            // Safely decrement document frequency, preventing underflow
            if let currentDf = documentFrequencies[term], currentDf > 0 {
                let newDf = currentDf - 1
                if newDf == 0 {
                    documentFrequencies.removeValue(forKey: term)
                } else {
                    documentFrequencies[term] = newDf
                }
            } else {
                // Term not in documentFrequencies or already 0 - clean up
                documentFrequencies.removeValue(forKey: term)
            }
        }
    }

    /// Returns cached term frequency for a term in a chunk.
    /// Uses O(1) lookup instead of O(n) tokenization.
    private func termFrequency(_ term: String, in chunkId: String) -> Double {
        guard let chunkTf = termFrequencyCache[chunkId] else { return 0 }
        return Double(chunkTf[term] ?? 0)
    }
}
