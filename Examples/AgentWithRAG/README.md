# Agent with RAG Example

This example demonstrates how to integrate Zoni's RAG (Retrieval-Augmented Generation) capabilities with an AI agent pattern. The agent can search, learn, and answer questions using a knowledge base.

## Overview

The example shows:
- Creating a RAG pipeline with mock providers (no API keys required)
- Building custom tools that wrap RAGPipeline methods
- Implementing a KnowledgeAgent that uses these tools
- Running queries through the agent

## Running the Example

```bash
cd Examples/AgentWithRAG
swift run
```

No API keys or external services are required - the example uses mock providers.

## Project Structure

```
Sources/
  main.swift           - Entry point with demo workflow
  KnowledgeAgent.swift - Agent class that orchestrates RAG tools
  RAGTools.swift       - Custom tools wrapping RAGPipeline
  MockProviders.swift  - Mock embedding/LLM providers for demo
```

## Components

### MockProviders

Mock implementations of `EmbeddingProvider` and `LLMProvider` that work without external APIs:

```swift
// Mock embedding provider generates deterministic embeddings
let embedder = MockEmbeddingProvider(dimensions: 128)

// Mock LLM generates contextual responses
let llm = MockLLMProvider(responseDelay: .milliseconds(100))
```

### RAGTools

Three tools that wrap `RAGPipeline` methods for agent use:

1. **SearchKnowledgeBaseTool** - Searches for relevant documents
   - Parameters: `query` (required), `limit`, `min_score`
   - Returns: Array of matching documents with scores

2. **IngestDocumentTool** - Adds documents to the knowledge base
   - Parameters: `content` (required), `title`, `source`
   - Returns: Document ID and success status

3. **QueryKnowledgeTool** - Answers questions using RAG
   - Parameters: `question` (required), `max_sources`, `include_sources`
   - Returns: Answer with sources and confidence

### KnowledgeAgent

A high-level agent class that orchestrates the tools:

```swift
let agent = KnowledgeAgent(pipeline: ragPipeline)

// Ask questions
let response = try await agent.ask("What is Swift concurrency?")
print(response.answer)
print(response.confidence) // .high, .medium, .low

// Search without answering
let results = try await agent.search("actors")

// Add new knowledge
try await agent.learn(content: "...", title: "New Topic")

// Get tool definitions for prompts
let definitions = agent.toolDefinitions()
```

## Extending with Real Providers

To use real providers instead of mocks:

### OpenAI

```swift
import Zoni

let embedder = OpenAIEmbedding(apiKey: "sk-...")
let llm = OpenAIProvider(apiKey: "sk-...", model: "gpt-4")
```

### Other Providers

```swift
// Cohere
let embedder = CohereEmbedding(apiKey: "...")

// Ollama (local)
let embedder = OllamaEmbedding(model: "nomic-embed-text")
let llm = OllamaProvider(model: "llama3")
```

## Tool Pattern

The tools follow Zoni's `Tool` protocol which is compatible with SwiftAgents:

```swift
public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue
}
```

This means you can use these tools directly with SwiftAgents:

```swift
import SwiftAgents

let agent = ReActAgent.Builder()
    .addTool(SearchKnowledgeBaseTool(pipeline: pipeline))
    .addTool(QueryKnowledgeTool(pipeline: pipeline))
    .build()
```

## Creating Custom Tools

To create your own RAG-based tool:

```swift
struct MyCustomTool: Tool, Sendable {
    let name = "my_custom_tool"
    let description = "Does something custom with the knowledge base"
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "input",
            description: "The input to process",
            type: .string,
            isRequired: true
        )
    ]

    private let pipeline: RAGPipeline

    init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let input = try arguments.requireString("input")

        // Use pipeline methods
        let results = try await pipeline.retrieve(input, limit: 3)

        // Process and return
        return .dictionary([
            "processed": .string("Result for: \(input)"),
            "sources_found": .int(results.count)
        ])
    }
}
```

## Architecture

```
User Query
    |
    v
KnowledgeAgent
    |
    +-- SearchKnowledgeBaseTool --> RAGPipeline.retrieve()
    |
    +-- IngestDocumentTool ------> RAGPipeline.ingest()
    |
    +-- QueryKnowledgeTool ------> RAGPipeline.query()
                                        |
                                        +-- EmbeddingProvider
                                        +-- VectorStore
                                        +-- LLMProvider
                                        +-- ChunkingStrategy
```

## License

This example is part of the Zoni framework.
