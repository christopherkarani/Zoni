// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// LoaderRegistry.swift - Registry for document loaders

import Foundation

/// Actor-based registry for managing document loaders.
///
/// `LoaderRegistry` provides thread-safe management of document loaders with automatic
/// loader selection based on file extensions. It maintains a mapping of file extensions
/// to their corresponding loaders, enabling the RAG pipeline to load documents from
/// various file formats transparently.
///
/// ## Features
/// - Thread-safe registration and retrieval (actor-isolated)
/// - Case-insensitive extension matching
/// - Automatic loader selection based on URL extension
/// - Support for overriding loaders for specific extensions
///
/// ## Example
/// ```swift
/// let registry = LoaderRegistry()
///
/// // Register loaders
/// await registry.register(TextLoader())
/// await registry.register(MarkdownLoader())
///
/// // Load documents automatically using the appropriate loader
/// let document = try await registry.load(from: fileURL)
///
/// // Get a specific loader by extension
/// if let loader = await registry.loader(for: "md") {
///     let doc = try await loader.load(from: url)
/// }
/// ```
public actor LoaderRegistry {

    // MARK: - Properties

    /// Registered loaders indexed by lowercase extension.
    private var loaders: [String: any DocumentLoader] = [:]

    // MARK: - Default Registry

    /// Default registry with pre-registered loaders.
    ///
    /// Note: Loaders are registered lazily or via a setup method to avoid
    /// issues with actor initialization.
    public static let `default`: LoaderRegistry = {
        let registry = LoaderRegistry()
        // Note: Loaders registered lazily or via setup method
        return registry
    }()

    // MARK: - Initialization

    /// Creates an empty registry.
    public init() {}

    // MARK: - Registration

    /// Registers a loader for all its supported extensions.
    ///
    /// The loader will be associated with each extension in its `supportedExtensions`
    /// set. If a loader is already registered for an extension, it will be overridden.
    ///
    /// - Parameter loader: The document loader to register.
    ///
    /// ## Example
    /// ```swift
    /// let registry = LoaderRegistry()
    /// await registry.register(TextLoader())  // Registers for "txt" and "text"
    /// ```
    public func register(_ loader: any DocumentLoader) {
        for ext in type(of: loader).supportedExtensions {
            loaders[ext.lowercased()] = loader
        }
    }

    /// Unregisters loaders for the given extensions.
    ///
    /// After calling this method, the specified extensions will no longer have
    /// associated loaders and attempts to load files with these extensions will
    /// fail with `ZoniError.unsupportedFileType`.
    ///
    /// - Parameter extensions: The list of extensions to unregister.
    ///
    /// ## Example
    /// ```swift
    /// // Remove support for text files
    /// await registry.unregister(extensions: ["txt", "text"])
    /// ```
    public func unregister(extensions: [String]) {
        for ext in extensions {
            loaders.removeValue(forKey: ext.lowercased())
        }
    }

    // MARK: - Loader Retrieval

    /// Gets a loader for the given file extension.
    ///
    /// Extension matching is case-insensitive. If no loader is registered for
    /// the extension, `nil` is returned.
    ///
    /// - Parameter extension: The file extension (without the leading dot).
    /// - Returns: The registered loader, or `nil` if no loader handles this extension.
    ///
    /// ## Example
    /// ```swift
    /// if let loader = await registry.loader(for: "txt") {
    ///     // Use the loader
    /// }
    /// ```
    public func loader(for extension: String) -> (any DocumentLoader)? {
        loaders[`extension`.lowercased()]
    }

    /// Gets a loader for the given URL's extension.
    ///
    /// This is a convenience method that extracts the path extension from the URL
    /// and looks up the appropriate loader.
    ///
    /// - Parameter url: The URL whose extension determines the loader to use.
    /// - Returns: The registered loader, or `nil` if no loader handles this extension.
    ///
    /// ## Example
    /// ```swift
    /// let url = URL(fileURLWithPath: "/path/to/document.txt")
    /// if let loader = await registry.loader(for: url) {
    ///     let document = try await loader.load(from: url)
    /// }
    /// ```
    public func loader(for url: URL) -> (any DocumentLoader)? {
        loader(for: url.pathExtension)
    }

    // MARK: - Document Loading

    /// Loads a document from URL using the appropriate loader.
    ///
    /// The loader is automatically selected based on the URL's file extension.
    /// If no loader is registered for the extension, an error is thrown.
    ///
    /// - Parameter url: The URL to load the document from.
    /// - Returns: The loaded document.
    /// - Throws: `ZoniError.unsupportedFileType` if no loader is registered for the extension,
    ///           or any error thrown by the underlying loader.
    ///
    /// ## Example
    /// ```swift
    /// let registry = LoaderRegistry()
    /// await registry.register(TextLoader())
    ///
    /// let document = try await registry.load(from: textFileURL)
    /// ```
    public func load(from url: URL) async throws -> Document {
        guard let loader = loader(for: url) else {
            throw ZoniError.unsupportedFileType(url.pathExtension)
        }
        return try await loader.load(from: url)
    }

    // MARK: - Introspection

    /// All currently registered extensions.
    ///
    /// Returns the set of all file extensions that have loaders registered.
    /// Extensions are returned in lowercase form.
    ///
    /// ## Example
    /// ```swift
    /// let extensions = await registry.registeredExtensions
    /// // e.g., ["txt", "text", "md", "markdown"]
    /// ```
    public var registeredExtensions: Set<String> {
        Set(loaders.keys)
    }
}
