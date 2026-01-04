// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// DirectoryLoader.swift - Recursive directory loading

import Foundation

/// Actor-based loader for loading all documents from a directory.
///
/// `DirectoryLoader` provides a convenient way to load multiple documents from a directory
/// structure, with support for recursive traversal, file filtering, and streaming loading.
/// It uses a `LoaderRegistry` to automatically select the appropriate loader for each file
/// based on its extension.
///
/// ## Features
/// - Recursive or non-recursive directory traversal
/// - Hidden file filtering
/// - Extension-based file filtering
/// - Pattern-based exclusion
/// - Streaming loading for memory efficiency
///
/// ## Example
/// ```swift
/// let registry = LoaderRegistry()
/// await registry.register(TextLoader())
/// await registry.register(MarkdownLoader())
///
/// let loader = DirectoryLoader(
///     registry: registry,
///     recursive: true,
///     includeHidden: false,
///     fileExtensions: ["txt", "md"],
///     excludePatterns: ["node_modules", "*.min.js"]
/// )
///
/// // Load all documents at once
/// let documents = try await loader.load(from: directoryURL)
///
/// // Or stream documents for memory efficiency
/// for try await document in await loader.loadStream(from: directoryURL) {
///     process(document)
/// }
/// ```
public actor DirectoryLoader {

    // MARK: - Properties

    /// The registry used to select loaders for each file.
    private let registry: LoaderRegistry

    /// Whether to recursively traverse subdirectories.
    ///
    /// When `true`, files in all nested subdirectories will be loaded.
    /// When `false`, only files in the top-level directory are loaded.
    /// Defaults to `true`.
    public let recursive: Bool

    /// Whether to include hidden files (starting with `.`).
    ///
    /// When `false`, files and directories starting with `.` are skipped.
    /// Defaults to `false`.
    public let includeHidden: Bool

    /// File extensions to load.
    ///
    /// When `nil`, all files with registered loaders are loaded.
    /// When specified, only files with matching extensions are loaded.
    /// Extensions should be lowercase without the leading dot.
    public let fileExtensions: Set<String>?

    /// Filename patterns to exclude.
    ///
    /// Files matching any of these patterns will be skipped.
    /// Supports simple glob patterns with `*` wildcards.
    /// Can also match directory names to exclude entire directories.
    public let excludePatterns: [String]

    // MARK: - Initialization

    /// Creates a new directory loader.
    ///
    /// - Parameters:
    ///   - registry: The loader registry to use for selecting document loaders.
    ///               Defaults to a new `LoaderRegistry` instance.
    ///   - recursive: Whether to recursively traverse subdirectories. Defaults to `true`.
    ///   - includeHidden: Whether to include hidden files. Defaults to `false`.
    ///   - fileExtensions: File extensions to load. Defaults to `nil` (all registered extensions).
    ///   - excludePatterns: Filename patterns to exclude. Defaults to empty.
    public init(
        registry: LoaderRegistry? = nil,
        recursive: Bool = true,
        includeHidden: Bool = false,
        fileExtensions: Set<String>? = nil,
        excludePatterns: [String] = []
    ) {
        self.registry = registry ?? LoaderRegistry()
        self.recursive = recursive
        self.includeHidden = includeHidden
        self.fileExtensions = fileExtensions
        self.excludePatterns = excludePatterns
    }

    // MARK: - Loading Methods

    /// Loads all documents from a directory.
    ///
    /// This method loads all matching files in the directory into memory at once.
    /// For large directories, consider using `loadStream(from:)` instead.
    ///
    /// - Parameter directory: The directory URL to load documents from.
    /// - Returns: An array of loaded documents.
    /// - Throws: `ZoniError.loadingFailed` if the directory does not exist or cannot be enumerated,
    ///           or any error thrown by individual document loaders.
    ///
    /// ## Example
    /// ```swift
    /// let documents = try await loader.load(from: projectDirectory)
    /// print("Loaded \(documents.count) documents")
    /// ```
    public func load(from directory: URL) async throws -> [Document] {
        let files = try listFiles(in: directory)
        var documents: [Document] = []

        for file in files {
            if let loader = await registry.loader(for: file) {
                let document = try await loader.load(from: file)
                documents.append(document)
            }
        }

        return documents
    }

    /// Streams documents as they are loaded.
    ///
    /// This method returns an `AsyncThrowingStream` that yields documents one at a time
    /// as they are loaded, which is more memory efficient for large directories.
    ///
    /// - Parameter directory: The directory URL to load documents from.
    /// - Returns: An async stream of documents.
    ///
    /// ## Example
    /// ```swift
    /// let stream = await loader.loadStream(from: projectDirectory)
    /// for try await document in stream {
    ///     await indexer.index(document)
    /// }
    /// ```
    public func loadStream(from directory: URL) -> AsyncThrowingStream<Document, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let files = try self.listFiles(in: directory)

                    for file in files {
                        if let loader = await self.registry.loader(for: file) {
                            let document = try await loader.load(from: file)
                            continuation.yield(document)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - File Listing

    /// Lists all loadable files in a directory.
    ///
    /// This method returns the URLs of all files that match the configured filters
    /// without actually loading them. Useful for previewing what would be loaded
    /// or for implementing custom loading logic.
    ///
    /// - Parameter directory: The directory URL to list files from.
    /// - Returns: An array of file URLs.
    /// - Throws: `ZoniError.loadingFailed` if the directory does not exist or cannot be enumerated.
    ///
    /// ## Example
    /// ```swift
    /// let files = try await loader.listFiles(in: projectDirectory)
    /// print("Found \(files.count) files to load")
    /// for file in files {
    ///     print("  - \(file.lastPathComponent)")
    /// }
    /// ```
    public func listFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            throw ZoniError.loadingFailed(url: directory, reason: "Directory does not exist")
        }

        var files: [URL] = []

        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? []
            : [.skipsSubdirectoryDescendants]

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: options
        ) else {
            throw ZoniError.loadingFailed(url: directory, reason: "Cannot enumerate directory")
        }

        for case let fileURL as URL in enumerator {
            // Check if it's a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            // Check hidden files
            if !includeHidden {
                if resourceValues.isHidden == true || fileURL.lastPathComponent.hasPrefix(".") {
                    continue
                }
                // Check for hidden parent directories
                if fileURL.pathComponents.contains(where: { $0.hasPrefix(".") && $0 != "." }) {
                    continue
                }
            }

            // Check extension filter
            if let extensions = fileExtensions {
                if !extensions.contains(fileURL.pathExtension.lowercased()) {
                    continue
                }
            }

            // Check exclude patterns
            if matchesExcludePattern(fileURL) {
                continue
            }

            files.append(fileURL)
        }

        return files
    }

    // MARK: - Private Helpers

    /// Checks if a URL matches any of the exclude patterns.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL matches an exclude pattern, `false` otherwise.
    private func matchesExcludePattern(_ url: URL) -> Bool {
        let filename = url.lastPathComponent
        let pathComponents = url.pathComponents

        for pattern in excludePatterns {
            // Simple glob matching with wildcard support
            if pattern.contains("*") {
                let regex = pattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                if let _ = filename.range(of: "^\(regex)$", options: .regularExpression) {
                    return true
                }
            } else {
                // Exact match on filename or directory name
                if filename == pattern || pathComponents.contains(pattern) {
                    return true
                }
            }
        }

        return false
    }
}
