// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MultiIndexTool.swift - Multi-index search tool for cross-knowledge-base queries.

import Foundation

// MARK: - MultiIndexTool

/// A tool for searching across multiple knowledge base indexes.
///
/// `MultiIndexTool` manages multiple named indexes (each backed by a `Retriever`)
/// and can search across them simultaneously. This is useful when information
/// is spread across different knowledge bases.
///
/// ## Example Usage
///
/// ```swift
/// let multiIndex = MultiIndexTool()
///
/// // Register indexes
/// await multiIndex.registerIndex(IndexConfig(
///     name: "transactions",
///     description: "User financial transactions",
///     retriever: transactionRetriever
/// ))
///
/// await multiIndex.registerIndex(IndexConfig(
///     name: "faq",
///     description: "Frequently asked questions",
///     retriever: faqRetriever
/// ))
///
/// // Execute search across indexes
/// let result = try await multiIndex.execute(arguments: [
///     "query": .string("payment history"),
///     "indexes": .array([.string("transactions")]),
///     "limit_per_index": .int(3)
/// ])
/// ```
///
/// ## SwiftAgents Integration
///
/// This tool conforms to the `Tool` protocol and can be used directly
/// with SwiftAgents:
///
/// ```swift
/// let agent = ReActAgent.Builder()
///     .addTool(multiIndex)
///     .build()
/// ```
public actor MultiIndexTool: Tool {

    // MARK: - Tool Protocol Properties (nonisolated)

    /// The unique name identifying this tool.
    public nonisolated let name = "multi_index_search"

    /// A description of what this tool does.
    public nonisolated let description = """
        Search across multiple knowledge base indexes simultaneously.
        Can target specific indexes or search all available indexes.
        Use this when you need to search multiple knowledge domains.
        """

    /// The parameters this tool accepts.
    public nonisolated var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "query",
                description: "The search query",
                type: .string,
                isRequired: true,
                defaultValue: nil
            ),
            ToolParameter(
                name: "indexes",
                description: "List of index names to search (empty = all indexes)",
                type: .array(elementType: .string),
                isRequired: false,
                defaultValue: .array([])
            ),
            ToolParameter(
                name: "limit_per_index",
                description: "Maximum results per index (default: 3)",
                type: .int,
                isRequired: false,
                defaultValue: .int(3)
            )
        ]
    }

    // MARK: - IndexConfig

    /// Configuration for a named index.
    public struct IndexConfig: Sendable {
        /// The unique name of this index.
        public let name: String

        /// A description of what this index contains.
        public let description: String

        /// The retriever used to search this index.
        public let retriever: any Retriever

        /// Creates a new index configuration.
        ///
        /// - Parameters:
        ///   - name: The unique name for this index.
        ///   - description: A description of the index contents.
        ///   - retriever: The retriever to use for searching.
        public init(name: String, description: String, retriever: any Retriever) {
            self.name = name
            self.description = description
            self.retriever = retriever
        }
    }

    // MARK: - Private Properties

    /// Registered indexes by name.
    private var indexes: [String: IndexConfig] = [:]

    // MARK: - Initialization

    /// Creates a new multi-index tool with no registered indexes.
    public init() {}

    // MARK: - Index Management

    /// Registers a new index with this tool.
    ///
    /// - Parameter config: The index configuration to register.
    public func registerIndex(_ config: IndexConfig) {
        indexes[config.name] = config
    }

    /// Removes an index from this tool.
    ///
    /// - Parameter name: The name of the index to remove.
    public func removeIndex(name: String) {
        indexes.removeValue(forKey: name)
    }

    /// Returns a dictionary of available index names and their descriptions.
    ///
    /// - Returns: A dictionary mapping index names to descriptions.
    public func availableIndexes() -> [String: String] {
        indexes.mapValues { $0.description }
    }

    /// Returns the names of all registered indexes.
    ///
    /// - Returns: An array of index names.
    public func indexNames() -> [String] {
        Array(indexes.keys)
    }

    // MARK: - Tool Execution

    /// Executes the multi-index search operation.
    ///
    /// - Parameter arguments: The arguments dictionary containing:
    ///   - `query` (String, required): The search query.
    ///   - `indexes` (Array of Strings, optional): Specific indexes to search.
    ///   - `limit_per_index` (Int, optional): Max results per index. Default: 3.
    /// - Returns: A dictionary containing:
    ///   - `query`: The original search query.
    ///   - `indexes_searched`: Array of index names that were searched.
    ///   - `results_by_index`: Array of results grouped by index.
    ///   - `total_indexes`: Number of indexes searched.
    /// - Throws: `ZoniError.invalidConfiguration` if required arguments are missing
    ///           or if arguments have invalid values.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        // Extract required query argument
        let query = try arguments.requireString("query")

        // Extract and validate optional arguments
        let limitPerIndex = arguments.optionalInt("limit_per_index", default: 3)
        guard limitPerIndex >= 1 else {
            throw ZoniError.invalidConfiguration(
                reason: "limit_per_index must be at least 1, got \(limitPerIndex)"
            )
        }

        // Snapshot configs atomically BEFORE any async operations
        // This prevents race conditions if indexes are modified during search
        let targetConfigs: [(name: String, config: IndexConfig)]
        if let indexArray = arguments.optionalStringArray("indexes"),
           !indexArray.isEmpty {
            // Filter to only include registered indexes and capture their configs
            targetConfigs = indexArray.compactMap { name in
                guard let config = indexes[name] else { return nil }
                return (name: name, config: config)
            }
        } else {
            // Capture all registered indexes
            targetConfigs = indexes.map { (name: $0.key, config: $0.value) }
        }

        // Handle no indexes case
        guard !targetConfigs.isEmpty else {
            return .dictionary([
                "query": .string(query),
                "indexes_searched": .array([]),
                "results_by_index": .array([]),
                "total_indexes": .int(0),
                "message": .string(indexes.isEmpty ? "No indexes registered" : "No matching indexes found")
            ])
        }

        // Search each index using the captured configs (safe from concurrent modifications)
        var allResults: [SendableValue] = []

        for (indexName, config) in targetConfigs {
            do {
                let results = try await config.retriever.retrieve(
                    query: query,
                    limit: limitPerIndex,
                    filter: nil
                )

                let indexResults: SendableValue = .dictionary([
                    "index": .string(indexName),
                    "index_description": .string(config.description),
                    "result_count": .int(results.count),
                    "results": .array(results.map { $0.toSendableValue() })
                ])

                allResults.append(indexResults)
            } catch {
                // Include error information for failed indexes
                let errorResult: SendableValue = .dictionary([
                    "index": .string(indexName),
                    "index_description": .string(config.description),
                    "error": .string(error.localizedDescription),
                    "result_count": .int(0),
                    "results": .array([])
                ])

                allResults.append(errorResult)
            }
        }

        return .dictionary([
            "query": .string(query),
            "indexes_searched": .array(targetConfigs.map { .string($0.name) }),
            "results_by_index": .array(allResults),
            "total_indexes": .int(allResults.count)
        ])
    }
}
