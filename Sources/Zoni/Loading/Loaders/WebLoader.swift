// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// WebLoader.swift - Loader for web pages using AsyncHTTPClient

import Foundation
import AsyncHTTPClient
import NIOCore

/// Actor-based loader for fetching and parsing web pages.
///
/// `WebLoader` uses `AsyncHTTPClient` for HTTP requests and `HTMLLoader` for parsing
/// the fetched HTML content. It supports configurable user agents, timeouts, and
/// redirect handling.
///
/// ## Features
/// - Asynchronous HTTP/HTTPS requests using AsyncHTTPClient
/// - Automatic HTML parsing with HTMLLoader
/// - Concurrent loading of multiple URLs with configurable concurrency
/// - Configurable user agent, timeout, and redirect behavior
/// - Actor isolation for thread-safe state management
///
/// ## Example
/// ```swift
/// // Basic usage
/// let loader = WebLoader()
/// let document = try await loader.load(from: URL(string: "https://example.com")!)
///
/// // Custom configuration
/// let customLoader = WebLoader(
///     userAgent: "MyBot/1.0",
///     timeout: .seconds(60),
///     followRedirects: true
/// )
///
/// // Load multiple URLs concurrently
/// let documents = try await loader.loadMultiple(
///     urls: urls,
///     maxConcurrency: 5
/// )
/// ```
public actor WebLoader {

    /// Empty - this loader handles URLs based on scheme, not file extensions.
    public static let supportedExtensions: Set<String> = []

    /// The underlying HTTP client used for making requests.
    private let httpClient: HTTPClient

    /// The HTML loader used for parsing fetched content.
    private let htmlLoader: HTMLLoader

    /// Whether this actor owns the HTTP client and should shut it down.
    private let ownsClient: Bool

    /// User agent string for HTTP requests.
    public let userAgent: String

    /// Request timeout duration.
    public let timeout: Duration

    /// Whether to follow HTTP redirects.
    public let followRedirects: Bool

    /// Creates a new web loader with the specified configuration.
    ///
    /// - Parameters:
    ///   - httpClient: An existing HTTP client to use. If `nil`, creates a new one.
    ///   - userAgent: The user agent string for HTTP requests. Defaults to `"Zoni/1.0"`.
    ///   - timeout: The request timeout duration. Defaults to 30 seconds.
    ///   - followRedirects: Whether to follow HTTP redirects. Defaults to `true`.
    public init(
        httpClient: HTTPClient? = nil,
        userAgent: String = "Zoni/1.0",
        timeout: Duration = .seconds(30),
        followRedirects: Bool = true
    ) {
        if let client = httpClient {
            self.httpClient = client
            self.ownsClient = false
        } else {
            self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            self.ownsClient = true
        }
        self.userAgent = userAgent
        self.timeout = timeout
        self.followRedirects = followRedirects
        self.htmlLoader = HTMLLoader()
    }

    /// Loads a document from a web URL.
    ///
    /// Fetches the content from the URL and parses it as HTML to extract
    /// clean text content.
    ///
    /// - Parameter url: The HTTP or HTTPS URL to load from.
    /// - Returns: A document containing the extracted text content with metadata.
    /// - Throws: `ZoniError.invalidData` if the URL scheme is not http/https.
    /// - Throws: `ZoniError.loadingFailed` if the HTTP request fails.
    public func load(from url: URL) async throws -> Document {
        guard canLoad(url) else {
            throw ZoniError.invalidData(reason: "WebLoader only supports http/https URLs")
        }

        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .GET
        request.headers.add(name: "User-Agent", value: userAgent)
        request.headers.add(name: "Accept", value: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        request.headers.add(name: "Accept-Language", value: "en-US,en;q=0.5")

        let response: HTTPClientResponse
        do {
            // Convert Duration to TimeAmount
            let timeoutSeconds = Int64(timeout.components.seconds)
            response = try await httpClient.execute(
                request,
                timeout: .seconds(timeoutSeconds)
            )
        } catch {
            throw ZoniError.loadingFailed(
                url: url,
                reason: "HTTP request failed: \(error.localizedDescription)"
            )
        }

        // Check for successful response
        guard response.status == .ok else {
            throw ZoniError.loadingFailed(
                url: url,
                reason: "HTTP \(response.status.code): \(response.status.reasonPhrase)"
            )
        }

        // Collect the response body (limit to 10MB)
        let maxBytes = 10 * 1024 * 1024
        let body: ByteBuffer
        do {
            body = try await response.body.collect(upTo: maxBytes)
        } catch {
            throw ZoniError.loadingFailed(
                url: url,
                reason: "Failed to read response body: \(error.localizedDescription)"
            )
        }

        let data = Data(buffer: body)

        // Create metadata with URL and source information
        var metadata = DocumentMetadata(
            source: url.absoluteString,
            url: url,
            mimeType: "text/html"
        )

        // Extract content type from response headers if available
        if let contentType = response.headers.first(name: "Content-Type") {
            metadata.mimeType = contentType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
        }

        // Parse the HTML using HTMLLoader
        return try await htmlLoader.load(from: data, metadata: metadata)
    }

    /// Loads multiple URLs concurrently with bounded concurrency.
    ///
    /// - Parameters:
    ///   - urls: The URLs to load.
    ///   - maxConcurrency: Maximum number of concurrent requests. Defaults to 5.
    /// - Returns: An array of loaded documents in the same order as the input URLs.
    /// - Throws: Rethrows any errors from individual loads.
    public func loadMultiple(urls: [URL], maxConcurrency: Int = 5) async throws -> [Document] {
        try await withThrowingTaskGroup(of: (Int, Document).self) { group in
            var documents: [Document?] = Array(repeating: nil, count: urls.count)
            var pending = 0
            var currentIndex = 0

            // Start initial batch up to maxConcurrency
            while pending < maxConcurrency && currentIndex < urls.count {
                let index = currentIndex
                let url = urls[index]
                group.addTask {
                    let document = try await self.load(from: url)
                    return (index, document)
                }
                pending += 1
                currentIndex += 1
            }

            // Process results and add more tasks as capacity becomes available
            while let (index, document) = try await group.next() {
                documents[index] = document
                pending -= 1

                // Add another task if there are more URLs to process
                if currentIndex < urls.count {
                    let nextIndex = currentIndex
                    let nextUrl = urls[nextIndex]
                    group.addTask {
                        let doc = try await self.load(from: nextUrl)
                        return (nextIndex, doc)
                    }
                    pending += 1
                    currentIndex += 1
                }
            }

            // Return documents in original order (force unwrap is safe because all were filled)
            return documents.compactMap { $0 }
        }
    }

    /// Checks if this loader can handle the given URL.
    ///
    /// WebLoader handles HTTP and HTTPS URLs.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL scheme is `http` or `https`, `false` otherwise.
    public func canLoad(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// Shuts down the HTTP client.
    ///
    /// Call this method when you're done using the web loader to release resources.
    /// Only shuts down the client if it was created by this loader (not passed in).
    ///
    /// - Throws: Any errors from the HTTP client shutdown.
    public func shutdown() async throws {
        if ownsClient {
            try await httpClient.shutdown()
        }
    }
}
