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

    /// Creates a default registry with all built-in loaders pre-registered.
    ///
    /// This method returns a new registry populated with loaders for:
    /// - Text files (.txt, .text)
    /// - Markdown files (.md, .markdown)
    /// - HTML files (.html, .htm)
    /// - JSON files (.json)
    /// - CSV files (.csv, .tsv)
    /// - PDF files (.pdf)
    ///
    /// - Returns: A registry with all built-in document loaders registered.
    ///
    /// ## Example
    /// ```swift
    /// let registry = await LoaderRegistry.defaultRegistry()
    /// let document = try await registry.load(from: fileURL)
    /// ```
    public static func defaultRegistry() async -> LoaderRegistry {
        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        await registry.register(MarkdownLoader())
        await registry.register(HTMLLoader())
        await registry.register(JSONLoader())
        await registry.register(CSVLoader())
        await registry.register(PDFLoader())
        return registry
    }

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

    /// Registers a loader for specific file extensions.
    ///
    /// Use this method to register a loader for custom extensions that differ
    /// from its declared `supportedExtensions`. If a loader is already registered
    /// for an extension, it will be overridden.
    ///
    /// - Parameters:
    ///   - loader: The document loader to register.
    ///   - extensions: The file extensions to associate with this loader.
    ///
    /// ## Example
    /// ```swift
    /// let registry = LoaderRegistry()
    /// // Register TextLoader for custom extensions
    /// await registry.register(TextLoader(), for: ["log", "conf"])
    /// ```
    public func register(_ loader: any DocumentLoader, for extensions: [String]) {
        for ext in extensions {
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

    // MARK: - Capability Checking

    /// Checks if this registry can load the given URL.
    ///
    /// This method returns `true` if a loader is registered for the URL's
    /// file extension.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if a loader is registered for this URL's extension, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// let registry = LoaderRegistry()
    /// await registry.register(TextLoader())
    ///
    /// if await registry.canLoad(textFileURL) {
    ///     let document = try await registry.load(from: textFileURL)
    /// }
    /// ```
    public func canLoad(_ url: URL) -> Bool {
        loader(for: url) != nil
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

    /// All currently registered extensions (property).
    ///
    /// Returns the set of all file extensions that have loaders registered.
    /// Extensions are returned in lowercase form.
    ///
    /// ## Example
    /// ```swift
    /// let extensions = await registry.registeredExtensions
    /// // e.g., ["txt", "text", "md", "markdown"]
    /// ```
    public var registeredExtensionsSet: Set<String> {
        Set(loaders.keys)
    }

    /// Returns all currently registered extensions.
    ///
    /// This method returns the set of all file extensions that have loaders registered.
    /// Extensions are returned in lowercase form.
    ///
    /// - Returns: A set of all registered file extensions.
    ///
    /// ## Example
    /// ```swift
    /// let extensions = await registry.registeredExtensions()
    /// // e.g., ["txt", "text", "md", "markdown"]
    /// ```
    public func registeredExtensions() -> Set<String> {
        Set(loaders.keys)
    }
}
