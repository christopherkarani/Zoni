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
///
/// Network-backed stores such as Qdrant and Pinecone live in the optional
/// `ZoniHTTP` integration package.
///
/// ## Example Usage
///
/// ```swift
/// // For testing - no persistence
/// let testConfig: VectorStoreConfig = .inMemory
///
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
///         config = .inMemory
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
        }
    }
}
