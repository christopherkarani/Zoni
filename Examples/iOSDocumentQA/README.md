# iOSDocumentQA

An iOS/macOS example app demonstrating Zoni's RAG (Retrieval-Augmented Generation) capabilities with on-device processing.

## Features

- **On-Device Embeddings**: Uses Apple's NaturalLanguage framework for private, free embeddings
- **Document Ingestion**: Add PDFs and text files to build a knowledge base
- **Semantic Search**: Find relevant content using vector similarity
- **Question Answering**: Ask questions about your documents
- **No API Keys Required**: Runs entirely on-device with mock LLM

## Requirements

- iOS 17.0+ or macOS 14.0+
- Xcode 16.0+
- Swift 6.0+

## Running the Example

### In Xcode

1. Open the Zoni package in Xcode:
   ```bash
   cd /path/to/zoni
   open Package.swift
   ```

2. In Xcode, select the `iOSDocumentQA` scheme from the scheme selector

3. Choose a simulator or device target

4. Press Cmd+R to build and run

### As Standalone Package

1. Navigate to the example directory:
   ```bash
   cd Examples/iOSDocumentQA
   ```

2. Open in Xcode:
   ```bash
   open Package.swift
   ```

3. Build and run the `iOSDocumentQA` target

## Usage

### Adding Documents

1. Tap the "+" button in the toolbar
2. Select a PDF or text file from your device
3. The document will be chunked and indexed

### Asking Questions

1. Type your question in the text field
2. Tap the send button
3. View the answer and source documents

### Viewing Sources

- Tap "Show Sources" to see which document chunks were used
- Each source shows the relevance score and content preview

## Architecture

```
iOSDocumentQA/
├── iOSDocumentQAApp.swift    # App entry point
├── ContentView.swift          # Main UI
├── DocumentPickerView.swift   # File picker wrapper
├── RAGService.swift           # RAG pipeline service
└── MockProviders.swift        # Mock LLM for demo
```

### RAGService

The `RAGService` class manages the RAG pipeline:

```swift
@Observable
@MainActor
public final class RAGService {
    // Ingest a document
    func ingestDocument(content: String, title: String) async throws

    // Query the knowledge base
    func query(_ question: String) async throws -> String

    // Search for relevant chunks
    func search(_ query: String, limit: Int) async throws -> [RetrievalResult]
}
```

### Components Used

- **NLEmbeddingProvider**: Apple NaturalLanguage embeddings (512 dimensions)
- **InMemoryVectorStore**: In-memory vector storage
- **ParagraphChunker**: Paragraph-based document chunking
- **VectorRetriever**: Semantic similarity retrieval
- **QueryEngine**: RAG query orchestration
- **MockLLMProvider**: Demo response generation

## Adding a Real LLM Provider

To use a real LLM instead of the mock provider:

### Option 1: OpenAI

```swift
import Zoni

struct OpenAIProvider: LLMProvider {
    let name = "openai"
    let model = "gpt-4"
    let maxContextTokens = 8192
    let apiKey: String

    func generate(prompt: String, systemPrompt: String?, options: LLMOptions) async throws -> String {
        // Implement OpenAI API call
    }

    func stream(prompt: String, systemPrompt: String?, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        // Implement streaming
    }
}
```

### Option 2: Apple Foundation Models (iOS 26+)

```swift
#if canImport(FoundationModels)
import FoundationModels

// Use Apple's on-device LLM when available
@available(iOS 26.0, macOS 26.0, *)
struct AppleLLMProvider: LLMProvider {
    // Implementation using SystemLanguageModel
}
#endif
```

### Option 3: Ollama (Local)

```swift
struct OllamaProvider: LLMProvider {
    let baseURL = "http://localhost:11434"
    let model = "llama3"

    // Implement Ollama API calls
}
```

## Customization

### Chunking Strategy

Adjust chunking parameters in `RAGService.swift`:

```swift
let chunker = ParagraphChunker(
    maxParagraphsPerChunk: 3,    // Paragraphs per chunk
    maxChunkSize: 1500,          // Max characters
    overlapParagraphs: 1         // Overlap for context
)
```

### Retrieval Settings

Configure retrieval in the query options:

```swift
let options = QueryOptions(
    retrievalLimit: 5,           // Number of chunks to retrieve
    includeMetadata: true        // Include source metadata
)
```

### Similarity Threshold

Set minimum similarity score in `VectorRetriever`:

```swift
let retriever = VectorRetriever(
    vectorStore: vectorStore,
    embeddingProvider: provider,
    similarityThreshold: 0.3     // Minimum score (0-1)
)
```

## Troubleshooting

### "RAG service is not initialized"

Wait for the embedding model to load. The status bar shows "Ready" when initialization completes.

### Empty or poor results

- Add more relevant documents
- Try rephrasing your question
- Lower the similarity threshold

### PDF text extraction issues

Complex PDFs may not extract text properly. For better PDF support, consider integrating a dedicated PDF library.

## License

This example is part of the Zoni framework and shares its license.
