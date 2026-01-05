// ServerRAG - Vapor-based RAG Server Example
//
// main.swift - Application entry point.
//
// This example demonstrates how to build a RAG server using Zoni with Vapor.
// It uses mock providers so it can run without external API keys.

import Vapor

@main
struct ServerRAGApp {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        defer { Task { try? await app.asyncShutdown() } }

        try await configure(app)
        try await app.execute()
    }
}
