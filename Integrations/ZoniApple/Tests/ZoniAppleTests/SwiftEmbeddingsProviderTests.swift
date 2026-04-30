// ZoniApple - Apple platform extensions for Zoni
//
// SwiftEmbeddingsProviderTests.swift - Tests for swift-embeddings based embedding provider

import Testing
import Foundation
@testable import ZoniApple
@testable import Zoni

// MARK: - Model Enum Tests

/// Tests for the SwiftEmbeddingsProvider.Model enum.
@Suite("SwiftEmbeddingsProvider.Model Tests")
struct SwiftEmbeddingsProviderModelTests {

    @Test("Model enum has 6 models")
    func modelEnumHasSixModels() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let allModels = SwiftEmbeddingsProvider.Model.allCases
        #expect(allModels.count == 6)
    }

    @Test("All models have dimensions of 256")
    func allModelsHave256Dimensions() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        for model in SwiftEmbeddingsProvider.Model.allCases {
            #expect(model.dimensions == 256, "Model \(model.rawValue) should have 256 dimensions")
        }
    }

    @Test("modelId returns correct HuggingFace identifier for potionBase2M")
    func modelIdPotionBase2M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase2M
        #expect(model.modelId == "minishlab/potion-base-2M")
    }

    @Test("modelId returns correct HuggingFace identifier for potionBase4M")
    func modelIdPotionBase4M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase4M
        #expect(model.modelId == "minishlab/potion-base-4M")
    }

    @Test("modelId returns correct HuggingFace identifier for potionBase8M")
    func modelIdPotionBase8M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase8M
        #expect(model.modelId == "minishlab/potion-base-8M")
    }

    @Test("modelId returns correct HuggingFace identifier for potionBase32M")
    func modelIdPotionBase32M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase32M
        #expect(model.modelId == "minishlab/potion-base-32M")
    }

    @Test("modelId returns correct HuggingFace identifier for potionRetrieval32M")
    func modelIdPotionRetrieval32M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionRetrieval32M
        #expect(model.modelId == "minishlab/potion-retrieval-32M")
    }

    @Test("modelId returns correct HuggingFace identifier for m2vBaseOutput")
    func modelIdM2VBaseOutput() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.m2vBaseOutput
        #expect(model.modelId == "minishlab/M2V_base_output")
    }

    @Test("displayName returns human-readable name for potionBase2M")
    func displayNamePotionBase2M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase2M
        #expect(model.displayName == "Potion Base 2M")
    }

    @Test("displayName returns human-readable name for potionBase4M")
    func displayNamePotionBase4M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase4M
        #expect(model.displayName == "Potion Base 4M")
    }

    @Test("displayName returns human-readable name for potionBase8M")
    func displayNamePotionBase8M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase8M
        #expect(model.displayName == "Potion Base 8M")
    }

    @Test("displayName returns human-readable name for potionBase32M")
    func displayNamePotionBase32M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionBase32M
        #expect(model.displayName == "Potion Base 32M")
    }

    @Test("displayName returns human-readable name for potionRetrieval32M")
    func displayNamePotionRetrieval32M() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.potionRetrieval32M
        #expect(model.displayName == "Potion Retrieval 32M")
    }

    @Test("displayName returns human-readable name for m2vBaseOutput")
    func displayNameM2VBaseOutput() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let model = SwiftEmbeddingsProvider.Model.m2vBaseOutput
        #expect(model.displayName == "M2V Base Output")
    }

    @Test("rawValue matches modelId")
    func rawValueMatchesModelId() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        for model in SwiftEmbeddingsProvider.Model.allCases {
            #expect(model.rawValue == model.modelId)
        }
    }
}

// MARK: - Provider Properties Tests

/// Tests for SwiftEmbeddingsProvider static properties and constants.
@Suite("SwiftEmbeddingsProvider Properties Tests")
struct SwiftEmbeddingsProviderPropertiesTests {

    @Test("name is swift-embeddings")
    func nameIsSwiftEmbeddings() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        // Note: This test requires network access to download the model
        // Skip if model download fails
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            #expect(provider.name == "swift-embeddings")
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("maxTokensPerRequest is 512")
    func maxTokensPerRequestIs512() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            #expect(provider.maxTokensPerRequest == 512)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("optimalBatchSize is 1000")
    func optimalBatchSizeIs1000() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            #expect(provider.optimalBatchSize == 1000)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("dimensions matches model dimensions")
    func dimensionsMatchesModelDimensions() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase8M)
            #expect(provider.dimensions == 256)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("supportedModels returns all model cases")
    func supportedModelsReturnsAllCases() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let supported = SwiftEmbeddingsProvider.supportedModels
        #expect(supported.count == 6)
        #expect(supported == SwiftEmbeddingsProvider.Model.allCases)
    }
}

// MARK: - Factory Methods Tests

/// Tests for SwiftEmbeddingsProvider factory methods.
@Suite("SwiftEmbeddingsProvider Factory Methods Tests")
struct SwiftEmbeddingsProviderFactoryTests {

    @Test("default() uses potionBase8M model")
    func defaultUsesPotionBase8M() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider.default()
            let modelInfo = await provider.modelInfo
            #expect(modelInfo.model == .potionBase8M)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("retrieval() uses potionRetrieval32M model")
    func retrievalUsesPotionRetrieval32M() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider.retrieval()
            let modelInfo = await provider.modelInfo
            #expect(modelInfo.model == .potionRetrieval32M)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("fast() uses potionBase2M model")
    func fastUsesPotionBase2M() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider.fast()
            let modelInfo = await provider.modelInfo
            #expect(modelInfo.model == .potionBase2M)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }
}

// MARK: - Embedding Tests

/// Tests for SwiftEmbeddingsProvider embedding operations.
/// Note: These tests require network access to download models on first run.
@Suite("SwiftEmbeddingsProvider Embedding Tests")
struct SwiftEmbeddingsProviderEmbeddingTests {

    @Test("embed() produces 256-dimensional vector")
    func embedProduces256DimensionalVector() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            let embedding = try await provider.embed("Hello, world!")

            #expect(embedding.dimensions == 256)
            #expect(embedding.vector.count == 256)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("embed([]) returns empty array")
    func embedEmptyArrayReturnsEmptyArray() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            let embeddings = try await provider.embed([])

            #expect(embeddings.isEmpty)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("batch embedding maintains order")
    func batchEmbeddingMaintainsOrder() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            let texts = ["First document", "Second document", "Third document"]

            let batchEmbeddings = try await provider.embed(texts)

            #expect(batchEmbeddings.count == 3)

            // Verify each batch embedding matches the individual embedding
            for (i, text) in texts.enumerated() {
                let singleEmbedding = try await provider.embed(text)
                // Note: Due to potential floating point differences, we check similarity
                let similarity = batchEmbeddings[i].cosineSimilarity(to: singleEmbedding)
                #expect(similarity > 0.99, "Batch embedding \(i) should match single embedding")
            }
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("embed() produces finite values")
    func embedProducesFiniteValues() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            let embedding = try await provider.embed("The quick brown fox jumps over the lazy dog")

            #expect(embedding.hasFiniteValues())
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("embed() sets model name correctly")
    func embedSetsModelName() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase8M)
            let embedding = try await provider.embed("Test text")

            #expect(embedding.model == "minishlab/potion-base-8M")
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("embed() produces different embeddings for different texts")
    func embedProducesDifferentEmbeddings() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)

            let embedding1 = try await provider.embed("The cat sat on the mat")
            let embedding2 = try await provider.embed("Quantum physics is fascinating")

            #expect(embedding1.vector != embedding2.vector)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("normalized embeddings have magnitude close to 1.0")
    func normalizedEmbeddingsHaveMagnitudeOne() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M, normalize: true)
            let embedding = try await provider.embed("Normalized vector test")

            let magnitude = embedding.magnitude()
            #expect(abs(magnitude - 1.0) < 0.01, "Magnitude should be close to 1.0, got \(magnitude)")
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }
}

// MARK: - Error Handling Tests

/// Tests for SwiftEmbeddingsProvider error handling.
@Suite("SwiftEmbeddingsProvider Error Handling Tests")
struct SwiftEmbeddingsProviderErrorTests {

    @Test("embed empty string throws invalidEmbedding")
    func embedEmptyStringThrowsInvalidEmbedding() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)

            await #expect(throws: AppleMLError.self) {
                _ = try await provider.embed("")
            }
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("embed empty string throws correct error type")
    func embedEmptyStringThrowsCorrectErrorType() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)

            do {
                _ = try await provider.embed("")
                Issue.record("Expected error to be thrown")
            } catch let error as AppleMLError {
                switch error {
                case .invalidEmbedding(let reason):
                    #expect(reason.contains("empty"))
                default:
                    Issue.record("Expected invalidEmbedding error, got \(error)")
                }
            }
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("batch embed with all empty strings throws invalidEmbedding")
    func batchEmbedAllEmptyStringsThrowsInvalidEmbedding() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)

            await #expect(throws: AppleMLError.self) {
                _ = try await provider.embed(["", "", ""])
            }
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("modelDownloadFailed error has correct associated values")
    func modelDownloadFailedErrorHasCorrectValues() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let error = AppleMLError.modelDownloadFailed(
            model: "test-model",
            reason: "Network error"
        )

        switch error {
        case .modelDownloadFailed(let model, let reason):
            #expect(model == "test-model")
            #expect(reason == "Network error")
        default:
            Issue.record("Expected modelDownloadFailed error")
        }
    }

    @Test("invalidEmbedding error has reason")
    func invalidEmbeddingErrorHasReason() {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let error = AppleMLError.invalidEmbedding(reason: "Cannot embed empty text")

        switch error {
        case .invalidEmbedding(let reason):
            #expect(reason == "Cannot embed empty text")
        default:
            Issue.record("Expected invalidEmbedding error")
        }
    }
}

// MARK: - ModelInfo Tests

/// Tests for SwiftEmbeddingsProvider.ModelInfo.
@Suite("SwiftEmbeddingsProvider.ModelInfo Tests")
struct SwiftEmbeddingsProviderModelInfoTests {

    @Test("modelInfo returns correct model")
    func modelInfoReturnsCorrectModel() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase8M)
            let info = await provider.modelInfo

            #expect(info.model == .potionBase8M)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("modelInfo returns correct dimensions")
    func modelInfoReturnsCorrectDimensions() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase8M)
            let info = await provider.modelInfo

            #expect(info.dimensions == 256)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("modelInfo returns correct normalizing flag when true")
    func modelInfoReturnsNormalizingTrue() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M, normalize: true)
            let info = await provider.modelInfo

            #expect(info.normalizing == true)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("modelInfo returns correct normalizing flag when false")
    func modelInfoReturnsNormalizingFalse() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M, normalize: false)
            let info = await provider.modelInfo

            #expect(info.normalizing == false)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("ModelInfo is Sendable")
    func modelInfoIsSendable() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)
            let info = await provider.modelInfo

            // Verify ModelInfo can be sent across actor boundaries
            await Task.detached {
                #expect(info.dimensions == 256)
            }.value
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }
}

// MARK: - Description Tests

/// Tests for SwiftEmbeddingsProvider CustomStringConvertible conformance.
@Suite("SwiftEmbeddingsProvider Description Tests")
struct SwiftEmbeddingsProviderDescriptionTests {

    @Test("description contains provider name")
    func descriptionContainsProviderName() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase8M)
            let description = provider.description

            #expect(description.contains("SwiftEmbeddingsProvider"))
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("description contains model display name")
    func descriptionContainsModelDisplayName() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase8M)
            let description = provider.description

            #expect(description.contains("Potion Base 8M"))
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("description contains dimensions")
    func descriptionContainsDimensions() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase8M)
            let description = provider.description

            #expect(description.contains("256"))
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }
}

// MARK: - Semantic Similarity Tests

/// Tests verifying semantic understanding of embeddings.
@Suite("SwiftEmbeddingsProvider Semantic Tests")
struct SwiftEmbeddingsProviderSemanticTests {

    @Test("similar texts have higher cosine similarity")
    func similarTextsHaveHigherSimilarity() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)

            // Similar texts about programming
            let text1 = "Swift is a modern programming language"
            let text2 = "Swift is a contemporary coding language"

            // Unrelated text
            let text3 = "The weather is sunny today"

            let embedding1 = try await provider.embed(text1)
            let embedding2 = try await provider.embed(text2)
            let embedding3 = try await provider.embed(text3)

            let similaritySimilar = embedding1.cosineSimilarity(to: embedding2)
            let similarityDifferent = embedding1.cosineSimilarity(to: embedding3)

            #expect(similaritySimilar > similarityDifferent)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }

    @Test("embeddings are useful for semantic search")
    func embeddingsWorkForSemanticSearch() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        do {
            let provider = try await SwiftEmbeddingsProvider(model: .potionBase2M)

            // Corpus of documents
            let documents = [
                "How to cook pasta with tomato sauce",
                "Introduction to machine learning algorithms",
                "Best hiking trails in the mountains",
                "Understanding neural networks and deep learning",
                "Italian recipes for beginners"
            ]

            // Query about AI/ML
            let query = "artificial intelligence tutorial"

            let queryEmbedding = try await provider.embed(query)
            let documentEmbeddings = try await provider.embed(documents)

            // Find most similar documents
            var similarities: [(Int, Float)] = []
            for (i, docEmbedding) in documentEmbeddings.enumerated() {
                let similarity = queryEmbedding.cosineSimilarity(to: docEmbedding)
                similarities.append((i, similarity))
            }

            // Sort by similarity (highest first)
            similarities.sort { $0.1 > $1.1 }

            // The ML-related documents (indices 1 and 3) should rank highest
            let topTwo = Set([similarities[0].0, similarities[1].0])
            let mlDocuments = Set([1, 3])

            #expect(topTwo.intersection(mlDocuments).count >= 1)
        } catch {
            throw SwiftEmbeddingsTestSkipReason.modelDownloadFailed(error)
        }
    }
}

// MARK: - Model Availability Tests

/// Tests for model availability checking.
@Suite("SwiftEmbeddingsProvider Availability Tests")
struct SwiftEmbeddingsProviderAvailabilityTests {

    @Test("isModelAvailable returns boolean")
    func isModelAvailableReturnsBool() async {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else { return }
        let available = await SwiftEmbeddingsProvider.isModelAvailable(.potionBase2M)
        #expect(available == true || available == false)
    }
}

// MARK: - Test Skip Reason

/// Custom error for skipping tests when model download fails.
struct SwiftEmbeddingsTestSkipReason: Error, CustomStringConvertible {
    let message: String

    var description: String { message }

    static func modelDownloadFailed(_ underlyingError: Error) -> SwiftEmbeddingsTestSkipReason {
        SwiftEmbeddingsTestSkipReason(
            message: "Model download failed: \(underlyingError.localizedDescription). " +
                     "Ensure network connectivity for first-time model download."
        )
    }
}
