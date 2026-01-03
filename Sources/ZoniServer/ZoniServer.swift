// ZoniServer - Server-side extensions for Zoni
//
// This module will contain:
// - Vapor integration
// - OpenAI client implementation
// - Anthropic client implementation
// - ChromaDB integration
// - Other server-side vector stores

import Zoni

/// Marker type for server-side RAG functionality
public struct ZoniServerMarker: Sendable {
    public init() {}
}
