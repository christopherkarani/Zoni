// AgentWithRAG Example
//
// main.swift - Entry point demonstrating agent + RAG integration.
//
// This example shows how to:
// 1. Create a RAGPipeline with mock providers (no API keys needed)
// 2. Ingest sample documents into the knowledge base
// 3. Create a KnowledgeAgent with RAG tools
// 4. Run queries through the agent

import Zoni
import ZoniAgents

// MARK: - Sample Documents

/// Sample documents about Swift programming for the demo.
let sampleDocuments = [
    Document(
        content: """
        Swift is a powerful and intuitive programming language developed by Apple. \
        It was introduced in 2014 and has since become the primary language for iOS, \
        macOS, watchOS, and tvOS development. Swift is designed to be safe, fast, and \
        expressive, making it ideal for both beginners and experienced developers.
        """,
        metadata: DocumentMetadata(
            source: "swift-overview",
            title: "Swift Programming Language Overview"
        )
    ),
    Document(
        content: """
        Swift Concurrency was introduced in Swift 5.5, bringing modern async/await \
        syntax to the language. It includes features like async functions, await \
        expressions, actors for safe concurrent state management, and structured \
        concurrency with task groups. These features help developers write safe \
        concurrent code without common pitfalls like data races.
        """,
        metadata: DocumentMetadata(
            source: "swift-concurrency",
            title: "Swift Concurrency Guide"
        )
    ),
    Document(
        content: """
        Actors in Swift provide a way to isolate mutable state and prevent data races. \
        An actor is a reference type that protects its internal state from concurrent \
        access. When you access an actor's properties or methods from outside the actor, \
        you must use await because the access might need to wait for exclusive access. \
        The @MainActor attribute marks code that must run on the main thread.
        """,
        metadata: DocumentMetadata(
            source: "swift-actors",
            title: "Understanding Swift Actors"
        )
    ),
    Document(
        content: """
        The Sendable protocol in Swift marks types as safe to share across concurrency \
        domains. Value types like structs and enums are often implicitly Sendable. \
        Reference types must explicitly conform to Sendable and ensure their mutable \
        state is protected. Closures can be marked @Sendable to indicate they are safe \
        to pass across actor boundaries.
        """,
        metadata: DocumentMetadata(
            source: "swift-sendable",
            title: "Swift Sendable Protocol"
        )
    ),
    Document(
        content: """
        SwiftUI is a declarative framework for building user interfaces across Apple \
        platforms. It uses a state-driven approach where the UI automatically updates \
        when the underlying data changes. Key concepts include Views, State, Binding, \
        and environment values. SwiftUI works seamlessly with Swift Concurrency for \
        handling async operations in the UI layer.
        """,
        metadata: DocumentMetadata(
            source: "swiftui-intro",
            title: "Introduction to SwiftUI"
        )
    )
]

// MARK: - Main Entry Point

@main
struct AgentWithRAGDemo {
    static func main() async {
        print("=== Agent with RAG Example ===\n")

        do {
            // Step 1: Create mock providers
            print("[1] Creating mock providers...")
            let embeddingProvider = MockEmbeddingProvider(dimensions: 128)
            let llmProvider = MockLLMProvider()
            let chunker = MockChunker(chunkSize: 200, overlap: 50)
            let vectorStore = InMemoryVectorStore()

            print("    - Embedding provider: \(embeddingProvider.name) (\(embeddingProvider.dimensions)d)")
            print("    - LLM provider: \(llmProvider.name)")
            print("    - Vector store: \(vectorStore.name)")
            print()

            // Step 2: Create the RAG pipeline
            print("[2] Creating RAG pipeline...")
            let pipeline = RAGPipeline(
                embedding: embeddingProvider,
                vectorStore: vectorStore,
                llm: llmProvider,
                chunker: chunker
            )
            print("    Pipeline created successfully")
            print()

            // Step 3: Ingest sample documents
            print("[3] Ingesting sample documents...")
            for doc in sampleDocuments {
                try await pipeline.ingest(doc)
                print("    - Ingested: \(doc.metadata.title ?? doc.id)")
            }

            let stats = try await pipeline.statistics()
            print("    Total: \(stats.documentCount) documents, \(stats.chunkCount) chunks")
            print()

            // Step 4: Create the knowledge agent
            print("[4] Creating knowledge agent...")
            let agent = await KnowledgeAgent(pipeline: pipeline)
            let tools = await agent.availableTools()
            print("    Agent created with \(tools.count) tools:")
            for tool in tools {
                print("      - \(tool.name): \(tool.description.prefix(60))...")
            }
            print()

            // Step 5: Run sample queries
            print("[5] Running sample queries...\n")

            // Query 1: Ask about Swift concurrency
            print("--- Query 1: What is Swift concurrency? ---")
            let response1 = try await agent.ask("What is Swift concurrency?")
            print("Answer: \(response1.answer)")
            print("Confidence: \(response1.confidence.rawValue)")
            print("Sources used: \(response1.sources.count)")
            for source in response1.sources.prefix(2) {
                print("  - \(source.source) (score: \(String(format: "%.2f", source.score)))")
            }
            print()

            // Query 2: Search for actor-related content
            print("--- Query 2: Search for 'actors and state isolation' ---")
            let searchResults = try await agent.search("actors and state isolation", limit: 3)
            print("Found \(searchResults.count) results:")
            for result in searchResults {
                print("  - \(result.source) (score: \(String(format: "%.2f", result.score)))")
                print("    \(result.excerpt.prefix(100))...")
            }
            print()

            // Query 3: Add new knowledge and query it
            print("--- Query 3: Learning and querying new information ---")
            let newDocId = try await agent.learn(
                content: """
                Swift 6 introduces strict concurrency checking by default, making data race \
                safety a compile-time guarantee. The compiler now validates that all code \
                respects actor isolation boundaries and properly handles Sendable requirements.
                """,
                title: "Swift 6 Concurrency",
                source: "swift6-notes"
            )
            print("Added new document: \(newDocId)")

            let response3 = try await agent.ask("What is new in Swift 6 concurrency?")
            print("Answer: \(response3.answer)")
            print("Confidence: \(response3.confidence.rawValue)")
            print()

            // Step 6: Demonstrate tool definitions
            print("[6] Tool definitions for agent prompts:\n")
            let definitions = await agent.toolDefinitions()
            for definition in definitions {
                print("Tool: \(definition.name)")
                print("Description: \(definition.description.prefix(80))...")
                print("Parameters:")
                for param in definition.parameters {
                    let required = param.isRequired ? "(required)" : "(optional)"
                    print("  - \(param.name): \(param.type) \(required)")
                }
                print()
            }

            print("=== Demo Complete ===")

        } catch {
            print("Error: \(error)")
        }
    }
}
