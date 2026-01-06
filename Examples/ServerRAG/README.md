# ServerRAG Example

A complete Vapor-based RAG server example using Zoni.

## Overview

This example demonstrates how to build a production-ready RAG (Retrieval-Augmented Generation) server using:

- **Zoni** - Core RAG framework
- **ZoniServer** - Server-side extensions with multi-tenancy support
- **ZoniVapor** - Vapor framework integration
- **Vapor** - Swift web framework

The example uses mock providers (no API keys required) for easy local testing. In production, replace them with real providers.

## Running the Example

```bash
# Navigate to the example directory
cd Examples/ServerRAG

# Build and run
swift run

# The server starts at http://localhost:8080
```

## API Endpoints

### Health Check

Check if the server is running.

```bash
curl http://localhost:8080/health
```

Response:
```json
{
    "status": "healthy",
    "service": "ServerRAG"
}
```

### Ingest Documents

Add documents to the knowledge base.

```bash
curl -X POST http://localhost:8080/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "documents": [
      {
        "content": "Swift is a powerful and intuitive programming language developed by Apple. It is designed to work with Apple frameworks like Cocoa and Cocoa Touch.",
        "title": "Swift Overview",
        "source": "swift-guide.md"
      },
      {
        "content": "Swift concurrency uses async/await syntax for asynchronous programming. Actors provide data isolation and prevent data races.",
        "title": "Swift Concurrency",
        "source": "concurrency.md"
      },
      {
        "content": "SwiftUI is a declarative framework for building user interfaces. It uses a reactive data binding model and integrates with Combine.",
        "title": "SwiftUI Introduction",
        "source": "swiftui.md"
      }
    ]
  }'
```

Response:
```json
{
    "success": true,
    "documentsProcessed": 3,
    "chunksCreated": 3,
    "message": "Successfully ingested 3 documents"
}
```

### Query the Knowledge Base

Ask questions about your documents.

```bash
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is Swift concurrency?",
    "retrievalLimit": 5
  }'
```

Response:
```json
{
    "answer": "Based on the provided context...",
    "sources": [
        {
            "content": "Swift concurrency uses async/await syntax...",
            "score": 0.85,
            "documentId": "doc-123",
            "source": "concurrency.md"
        }
    ],
    "metadata": {
        "chunksRetrieved": 3,
        "model": "mock-llm-v1",
        "totalTimeMs": 125.5
    }
}
```

### Get Statistics

View pipeline statistics.

```bash
curl http://localhost:8080/stats
```

Response:
```json
{
    "totalChunks": 3,
    "vectorStore": "in_memory",
    "embeddingProvider": "mock",
    "embeddingDimensions": 384,
    "status": "ready"
}
```

## Complete Demo Flow

Run this sequence to see the full RAG pipeline in action:

```bash
# 1. Check server health
curl http://localhost:8080/health

# 2. Ingest sample documents
curl -X POST http://localhost:8080/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "documents": [
      {
        "content": "Swift is a type-safe language that helps you catch errors at compile time. It uses optionals to handle the absence of values safely.",
        "title": "Type Safety in Swift",
        "source": "types.md"
      },
      {
        "content": "Protocols in Swift define a blueprint of methods and properties. Conforming types must implement all required members.",
        "title": "Swift Protocols",
        "source": "protocols.md"
      },
      {
        "content": "Generics allow you to write flexible, reusable functions and types. They enable type-safe code that works with any type.",
        "title": "Swift Generics",
        "source": "generics.md"
      }
    ]
  }'

# 3. Check statistics
curl http://localhost:8080/stats

# 4. Query the knowledge base
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"query": "How does Swift handle type safety?"}'

# 5. Try another query
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"query": "What are protocols used for?"}'
```

## Extending with Real Providers

### Using OpenAI

Replace the mock providers in `configure.swift`:

```swift
import OpenAI  // Add OpenAI Swift SDK

// Replace MockEmbedding with OpenAI embeddings
let embeddingProvider = OpenAIEmbedding(
    apiKey: Environment.get("OPENAI_API_KEY")!,
    model: "text-embedding-3-small"
)

// Replace MockLLMProvider with OpenAI
let llmProvider = OpenAILLMProvider(
    apiKey: Environment.get("OPENAI_API_KEY")!,
    model: "gpt-4"
)
```

### Using a Persistent Vector Store

Replace InMemoryVectorStore for production:

```swift
// Option 1: SQLite for single-server deployments
let vectorStore = try SQLiteVectorStore(
    path: "./data/vectors.db"
)

// Option 2: PostgreSQL with pgvector for distributed deployments
let vectorStore = try await PgVectorStore(
    connectionString: Environment.get("DATABASE_URL")!
)

// Option 3: Pinecone for managed vector search
let vectorStore = PineconeStore(
    apiKey: Environment.get("PINECONE_API_KEY")!,
    indexName: "my-index"
)
```

### Adding Authentication

The ZoniVapor configuration already includes tenant management. For production:

```swift
// Use a real tenant storage backend
let tenantManager = TenantManager(
    storage: PostgresTenantStorage(database: db),
    jwtSecret: Environment.get("JWT_SECRET")
)

// Apply middleware to protected routes
app.grouped(TenantMiddleware()) { protected in
    protected.post("query", use: executeQuery)
    protected.post("ingest", use: ingestDocuments)
}
```

## Project Structure

```
Examples/ServerRAG/
├── Package.swift          # Dependencies and build configuration
├── README.md              # This file
└── Sources/
    └── App/
        ├── main.swift     # Application entry point
        ├── configure.swift # Zoni and Vapor configuration
        └── routes.swift    # HTTP endpoint definitions
```

## Configuration Options

Environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP server port | 8080 |
| `LOG_LEVEL` | Logging verbosity | info |

## Notes

- **Data Persistence**: The in-memory vector store loses data on restart. Use SQLite or a database-backed store for persistence.
- **Mock Responses**: The mock LLM provider returns placeholder text. Configure a real provider for actual generation.
- **Rate Limiting**: The example includes rate limiting infrastructure. Configure per-tenant limits via `TenantConfiguration`.
- **Chunking**: Documents are split using `ParagraphChunker`. Adjust chunking strategy based on your content type.

## License

This example is part of the Zoni framework and is available under the same license.
