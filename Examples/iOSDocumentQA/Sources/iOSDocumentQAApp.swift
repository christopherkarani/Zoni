// iOSDocumentQA - Example iOS app demonstrating Zoni RAG capabilities
//
// iOSDocumentQAApp.swift - Main app entry point

import SwiftUI

/// Main entry point for the iOSDocumentQA example app.
///
/// This app demonstrates how to use Zoni's RAG capabilities on iOS with:
/// - On-device embeddings using Apple's NaturalLanguage framework
/// - In-memory vector storage for document retrieval
/// - Document ingestion from PDFs and text files
/// - Semantic search and question answering
@main
struct iOSDocumentQAApp: App {

    /// The shared RAG service instance for the app.
    @State private var ragService = RAGService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(ragService)
        }
    }
}
