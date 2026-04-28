// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// VectorStoreFactory.swift - Factory for creating vector store instances.

import Foundation
import ZoniCore

// MARK: - VectorStoreConfig

/// Configuration for creating vector stores.
///
/// Use this enum to specify which vector store implementation to create
/// and its configuration parameters. Each case represents a different
/// backend with its specific connection requirements.
///
/// ## Supported Backends
///
/// - **In-Memory**: Fast, ephemeral storage for testing and prototyping
/// - **Qdrant**: Cloud-native vector database with advanced features
/// - **Pinecone**: Managed vector database service
///
/// ## Example Usage
///
/// ```swift
/// // For testing - no persistence
/// let testConfig: VectorStoreConfig = .inMemory
///
/// // For production - Qdrant Cloud
/// let prodConfig: VectorStoreConfig = .qdrant(
///     url: URL(string: "https://your-cluster.qdrant.io")!,
///     collection: "documents",
///     apiKey: "your-api-key"
/// )
///
/// // For production - Pinecone
/// let pineconeConfig: VectorStoreConfig = .pinecone(
///     apiKey: "your-api-key",
///     indexHost: "your-index-abc123.svc.us-east1-gcp.pinecone.io",
///     namespace: "production"
/// )
/// ```
public enum VectorStoreConfig: Sendable {
    /// In-memory vector store (no persistence).
    ///
    /// Best for:
    /// - Unit testing
    /// - Prototyping RAG pipelines
    /// - Small datasets that fit in memory
    /// - Offline development
    ///
    /// Data is lost when the application terminates unless explicitly saved
    /// using `InMemoryVectorStore.save(to:)`.
    case inMemory

    /// Qdrant cloud vector store.
    ///
    /// Best for:
    /// - Production workloads requiring high performance
    /// - Large-scale vector search (millions of vectors)
    /// - Advanced filtering and payload capabilities
    /// - Self-hosted or cloud deployment options
    ///
    /// - Parameters:
    ///   - url: Base URL of the Qdrant server. For Qdrant Cloud, this is typically
    ///     `https://your-cluster-id.qdrant.io`. For self-hosted, use the appropriate URL.
    ///   - collection: Name of the Qdrant collection to use. Will be created if it
    ///     doesn't exist when `ensureCollection(dimensions:)` is called.
    ///   - apiKey: Optional API key for authentication. Required for Qdrant Cloud,
    ///     optional for self-hosted instances.
    ///
    /// ## Security Best Practices
    ///
    /// **Never hardcode API keys in source code.** Instead:
    /// - Use environment variables: `ProcessInfo.processInfo.environment["QDRANT_API_KEY"]`
    /// - Use secure configuration management (e.g., AWS Secrets Manager, Azure Key Vault)
    /// - Use Xcode configuration files (.xcconfig) excluded from version control
    case qdrant(url: URL, collection: String, apiKey: String?)

    /// Pinecone cloud vector store.
    ///
    /// Best for:
    /// - Fully managed vector database experience
    /// - Production workloads at scale
    /// - Teams wanting minimal infrastructure management
    /// - Applications requiring namespace isolation
    ///
    /// - Parameters:
    ///   - apiKey: Pinecone API key. Find this in the Pinecone console under API Keys.
    ///   - indexHost: Host URL for your Pinecone index. This is shown in the Pinecone
    ///     console when you select an index (e.g., `"your-index-abc123.svc.us-east1-gcp.pinecone.io"`).
    ///   - namespace: Optional namespace to isolate vectors. Vectors in different
    ///     namespaces are completely separate and cannot be queried together.
    ///
    /// ## Security Best Practices
    ///
    /// **Never hardcode API keys in source code.** Instead:
    /// - Use environment variables: `ProcessInfo.processInfo.environment["PINECONE_API_KEY"]`
    /// - Use secure configuration management (e.g., AWS Secrets Manager, Azure Key Vault)
    /// - Use Xcode configuration files (.xcconfig) excluded from version control
    case pinecone(apiKey: String, indexHost: String, namespace: String?)
}

// MARK: - VectorStoreFactory

/// Factory for creating vector store instances.
///
/// Use `VectorStoreFactory` to create vector store instances from configuration.
/// This provides a unified way to instantiate different vector store backends,
/// making it easy to switch between implementations for testing, development,
/// and production environments.
///
/// ## Factory Pattern Benefits
///
/// - **Configuration-driven**: Create stores from serializable configuration
/// - **Testability**: Easily swap implementations for testing
/// - **Environment support**: Use different backends per environment
/// - **Centralized creation**: Single point for store instantiation
///
/// ## Example Usage
///
/// ```swift
/// // Create an in-memory store for testing
/// let testStore = try await VectorStoreFactory.create(from: .inMemory)
///
/// // Create a Qdrant store for production
/// let qdrantStore = try await VectorStoreFactory.create(from: .qdrant(
///     url: URL(string: "https://your-cluster.qdrant.io")!,
///     collection: "documents",
///     apiKey: "your-api-key"
/// ))
///
/// // Create a Pinecone store for production
/// let pineconeStore = try await VectorStoreFactory.create(from: .pinecone(
///     apiKey: "your-api-key",
///     indexHost: "your-index-abc123.svc.us-east1-gcp.pinecone.io",
///     namespace: "production"
/// ))
/// ```
///
/// ## Environment-Based Configuration
///
/// A common pattern is to use different stores based on the environment:
///
/// ```swift
/// func createVectorStore(for environment: Environment) async throws -> any VectorStore {
///     let config: VectorStoreConfig
///
///     switch environment {
///     case .testing:
///         config = .inMemory
///     case .development, .production:
///         config = .qdrant(
///             url: URL(string: ProcessInfo.processInfo.environment["QDRANT_URL"]!)!,
///             collection: "documents",
///             apiKey: ProcessInfo.processInfo.environment["QDRANT_API_KEY"]
///         )
///     }
///
///     return try await VectorStoreFactory.create(from: config)
/// }
/// ```
public enum VectorStoreFactory {

    // MARK: - Factory Methods

    /// Creates a vector store from the given configuration.
    ///
    /// This is the primary factory method that creates the appropriate vector store
    /// implementation based on the configuration. The returned store is ready for use.
    ///
    /// - Parameter config: The configuration specifying which store to create and its parameters.
    ///
    /// - Returns: A vector store instance conforming to `VectorStore`.
    ///
    /// - Throws: `ZoniError.vectorStoreUnavailable` if the store cannot be created
    ///   due to configuration issues, connection failures, or missing dependencies.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create from configuration
    /// let store = try await VectorStoreFactory.create(from: .inMemory)
    ///
    /// // Use the store
    /// try await store.add(chunks, embeddings: embeddings)
    /// let results = try await store.search(query: queryEmbedding, limit: 10, filter: nil)
    /// ```
    ///
    /// ## Error Handling
    ///
    /// ```swift
    /// do {
    ///     let store = try await VectorStoreFactory.create(from: config)
    /// } catch let error as ZoniError {
    ///     switch error {
    ///     case .vectorStoreUnavailable(let name):
    ///         print("Failed to create vector store: \(name)")
    ///     default:
    ///         print("Unexpected error: \(error)")
    ///     }
    /// }
    /// ```
    public static func create(from config: VectorStoreConfig) async throws -> any VectorStore {
        switch config {
        case .inMemory:
            return InMemoryVectorStore()

        case .qdrant(let url, let collection, let apiKey):
            // Validate inputs
            guard !collection.isEmpty else {
                throw ZoniError.vectorStoreUnavailable(name: "qdrant: collection name cannot be empty")
            }
            guard url.scheme == "http" || url.scheme == "https" else {
                throw ZoniError.vectorStoreUnavailable(name: "qdrant: URL must use http or https scheme")
            }

            return QdrantStore(baseURL: url, collectionName: collection, apiKey: apiKey)

        case .pinecone(let apiKey, let indexHost, let namespace):
            // Validate inputs
            guard !apiKey.isEmpty else {
                throw ZoniError.vectorStoreUnavailable(name: "pinecone: API key cannot be empty")
            }
            guard !indexHost.isEmpty else {
                throw ZoniError.vectorStoreUnavailable(name: "pinecone: index host cannot be empty")
            }

            return PineconeStore(apiKey: apiKey, indexHost: indexHost, namespace: namespace)
        }
    }

    // MARK: - Convenience Methods

    /// Creates an in-memory vector store for testing.
    ///
    /// This is a convenience method equivalent to `create(from: .inMemory)`.
    /// Use this when you specifically need an `InMemoryVectorStore` instance
    /// with access to its additional methods like `save(to:)` and `load(from:)`.
    ///
    /// - Returns: An `InMemoryVectorStore` instance.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create for testing
    /// let store = VectorStoreFactory.createInMemory()
    ///
    /// // Use InMemoryVectorStore-specific methods
    /// try await store.save(to: URL(fileURLWithPath: "/tmp/test_store.json"))
    /// ```
    public static func createInMemory() -> InMemoryVectorStore {
        InMemoryVectorStore()
    }

    /// Creates a Qdrant vector store.
    ///
    /// Use this method when you need direct access to the `QdrantStore` instance
    /// for Qdrant-specific operations like `ensureCollection(dimensions:)`.
    ///
    /// - Parameters:
    ///   - url: Base URL of the Qdrant server.
    ///   - collection: Name of the collection to use.
    ///   - apiKey: Optional API key for authentication.
    ///
    /// - Returns: A `QdrantStore` instance.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create Qdrant store
    /// let store = VectorStoreFactory.createQdrant(
    ///     url: URL(string: "https://your-cluster.qdrant.io")!,
    ///     collection: "documents",
    ///     apiKey: "your-api-key"
    /// )
    ///
    /// // Ensure collection exists with correct dimensions
    /// try await store.ensureCollection(dimensions: 1536)
    /// ```
    public static func createQdrant(
        url: URL,
        collection: String,
        apiKey: String? = nil
    ) -> QdrantStore {
        QdrantStore(baseURL: url, collectionName: collection, apiKey: apiKey)
    }

    /// Creates a Pinecone vector store.
    ///
    /// Use this method when you need direct access to the `PineconeStore` instance
    /// for Pinecone-specific operations.
    ///
    /// - Parameters:
    ///   - apiKey: Pinecone API key.
    ///   - indexHost: Host URL for your Pinecone index.
    ///   - namespace: Optional namespace to isolate vectors.
    ///
    /// - Returns: A `PineconeStore` instance.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create Pinecone store
    /// let store = VectorStoreFactory.createPinecone(
    ///     apiKey: "your-api-key",
    ///     indexHost: "your-index-abc123.svc.us-east1-gcp.pinecone.io",
    ///     namespace: "production"
    /// )
    ///
    /// // Add vectors
    /// try await store.add(chunks, embeddings: embeddings)
    /// ```
    public static func createPinecone(
        apiKey: String,
        indexHost: String,
        namespace: String? = nil
    ) -> PineconeStore {
        PineconeStore(apiKey: apiKey, indexHost: indexHost, namespace: namespace)
    }
}

// MARK: - VectorStoreConfig + CustomStringConvertible

extension VectorStoreConfig: CustomStringConvertible {
    /// A textual representation of the configuration for debugging.
    ///
    /// Sensitive information like API keys are not included in the description.
    public var description: String {
        switch self {
        case .inMemory:
            return "InMemory"
        case .qdrant(let url, let collection, let apiKey):
            let authStatus = apiKey != nil ? "authenticated" : "no auth"
            return "Qdrant(url: \"\(url.host ?? url.absoluteString)\", collection: \"\(collection)\", \(authStatus))"
        case .pinecone(_, let host, let namespace):
            let ns = namespace.map { ", namespace: \"\($0)\"" } ?? ""
            return "Pinecone(host: \"\(host)\"\(ns))"
        }
    }
}

// MARK: - VectorStoreConfig + Equatable

// MARK: - GPU Acceleration Note

extension VectorStoreFactory {
    /// Note about GPU acceleration for Apple platforms.
    ///
    /// On Apple platforms (iOS/macOS), you can use `GPUAcceleratedInMemoryVectorStore`
    /// from the `ZoniApple` module for significant performance improvements on large
    /// datasets (>10,000 vectors).
    ///
    /// ## Usage with ZoniApple
    ///
    /// ```swift
    /// import ZoniApple
    ///
    /// // Option 1: Wrap existing store
    /// let store = VectorStoreFactory.createInMemory()
    /// let gpuStore = store.gpuAccelerated()
    ///
    /// // Option 2: Create directly
    /// let gpuStore = GPUAcceleratedInMemoryVectorStore(maxChunkCount: 100_000)
    ///
    /// // Search with automatic backend selection
    /// let results = try await gpuStore.search(query: embedding, limit: 10, filter: nil)
    ///
    /// // Force GPU backend
    /// let gpuResults = try await gpuStore.search(
    ///     query: embedding,
    ///     limit: 10,
    ///     filter: nil,
    ///     backend: .gpu
    /// )
    /// ```
    ///
    /// ## Performance Characteristics
    ///
    /// - **< 5,000 vectors**: CPU is faster (GPU dispatch overhead)
    /// - **5,000-10,000 vectors**: Breakeven zone
    /// - **> 10,000 vectors**: GPU provides 3-50x speedup
    ///
    /// See `ComputeBackend` and `BackendSelector` in ZoniApple for details.
    public static var gpuAccelerationAvailable: Bool {
        #if canImport(Metal)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - VectorStoreConfig + Equatable

extension VectorStoreConfig: Equatable {
    /// Compares two configurations for equality.
    ///
    /// Two configurations are equal if they have the same type and parameters.
    /// API keys are compared for equality when present.
    public static func == (lhs: VectorStoreConfig, rhs: VectorStoreConfig) -> Bool {
        switch (lhs, rhs) {
        case (.inMemory, .inMemory):
            return true
        case (.qdrant(let lURL, let lColl, let lKey), .qdrant(let rURL, let rColl, let rKey)):
            return lURL == rURL && lColl == rColl && lKey == rKey
        case (.pinecone(let lKey, let lHost, let lNS), .pinecone(let rKey, let rHost, let rNS)):
            return lKey == rKey && lHost == rHost && lNS == rNS
        default:
            return false
        }
    }
}
