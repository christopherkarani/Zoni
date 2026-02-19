// ZoniServer - Server-side extensions for Zoni
//
// This module contains:
// - PostgreSQL/pgvector integration
// - Server-side job processing
// - Multi-tenancy support
// - Server DTOs and protocols

import Zoni

/// Marker type for server-side RAG functionality
public struct ZoniServerMarker: Sendable {
    public init() {}
}
