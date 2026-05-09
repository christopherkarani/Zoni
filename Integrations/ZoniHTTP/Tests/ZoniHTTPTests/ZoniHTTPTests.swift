import Foundation
import Testing
@testable import ZoniHTTP

@Suite("HTTP Embedding Model Tests")
struct HTTPEmbeddingModelTests {
    @Test("OpenAI models expose expected dimensions")
    func openAIModelDimensions() {
        #expect(OpenAIEmbedding.Model.textEmbedding3Small.dimensions == 1536)
        #expect(OpenAIEmbedding.Model.textEmbedding3Large.dimensions == 3072)
        #expect(OpenAIEmbedding.Model.textEmbeddingAda002.dimensions == 1536)
    }

    @Test("Cohere models expose expected dimensions")
    func cohereModelDimensions() {
        #expect(CohereEmbedding.Model.embedEnglishV3.dimensions == 1024)
        #expect(CohereEmbedding.Model.embedMultilingualV3.dimensions == 1024)
        #expect(CohereEmbedding.Model.embedEnglishLightV3.dimensions == 384)
        #expect(CohereEmbedding.Model.embedMultilingualLightV3.dimensions == 384)
    }

    @Test("Voyage domain metadata is preserved")
    func voyageDomainMetadata() {
        #expect(VoyageEmbedding.Model.voyageCode2.isDomainSpecific)
        #expect(VoyageEmbedding.Model.voyageCode2.domain == "code")
        #expect(VoyageEmbedding.Model.voyage3.domain == nil)
    }

    @Test("Ollama defaults are preserved")
    func ollamaDefaults() {
        let ollama = OllamaEmbedding()
        #expect(ollama.name == "ollama")
        #expect(ollama.maxTokensPerRequest == 1)
        #expect(OllamaEmbedding.KnownModel.nomicEmbedText == "nomic-embed-text")
    }
}

@Suite("HTTP Loader Tests")
struct HTTPLoaderTests {
    @Test("HTML loader extracts clean text")
    func htmlLoaderExtractsCleanText() async throws {
        let html = """
        <html>
        <head><title>Test Page</title></head>
        <body><nav>Hidden</nav><main>Hello <strong>World</strong></main></body>
        </html>
        """
        let loader = HTMLLoader()
        let document = try await loader.load(from: Data(html.utf8), metadata: nil)

        #expect(document.metadata.title == "Test Page")
        #expect(document.content.contains("Hello World"))
        #expect(!document.content.contains("Hidden"))
    }

    @Test("Web loader recognizes HTTP schemes")
    func webLoaderSchemeSupport() async {
        let loader = WebLoader()

        #expect(await loader.canLoad(URL(string: "https://example.com")!))
        #expect(await loader.canLoad(URL(string: "http://example.com")!))
        #expect(await loader.canLoad(URL(fileURLWithPath: "/tmp/index.html")) == false)
    }
}
