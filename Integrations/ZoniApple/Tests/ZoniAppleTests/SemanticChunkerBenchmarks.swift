import Testing
import Foundation
@testable import Zoni

@testable import Zoni
#if canImport(Metal)
import Metal
@testable import ZoniApple
#endif

struct SemanticChunkerBenchmarks {
    
    // ... [Previous Mock Class] ...
    struct FastMockEmbedding: EmbeddingProvider {
        var name: String = "fast-mock"
        var maxTokensPerRequest: Int = 8192
        let dimensions: Int = 1536
        
        func embed(_ texts: [String]) async throws -> [Embedding] {
            return texts.map { _ in
                var vector = [Float](repeating: 0, count: dimensions)
                vector[0] = 1.0
                return Embedding(vector: vector)
            }
        }
        
        func embed(_ text: String) async throws -> Embedding {
            return try await embed([text])[0]
        }
    }
    
    @Test func benchmarkSemanticChunkingPerformance() async throws {
        // ... [Previous Test Code] ...
        let embedder = FastMockEmbedding()
        let chunker = SemanticChunker(
            embeddingProvider: embedder,
            targetChunkSize: 500,
            similarityThreshold: 0.5,
            windowSize: 3
        )
        
        // Generate large text (approx 2000 sentences)
        let sentence = "This is a test sentence for benchmarking purposes to see how fast we can chunk."
        let text = Array(repeating: sentence, count: 2000).joined(separator: " ")
        
        let clock = ContinuousClock()
        
        print("\n-------- BENCHMARK START --------")
        
        // 1. CPU Benchmark
        let cpuResult = try await clock.measure {
            _ = try await chunker.chunk(text, metadata: nil)
        }
        print("⚡️ CPU Semantic Chunker (2000 sentences): \(cpuResult)")
        
        // 2. Metal Benchmark
        #if canImport(Metal)
        do {
            // New Way: Inject the Calculator!
            let calculator = try MetalSimilarityCalculator()
            
            let metalChunker = SemanticChunker(
                embeddingProvider: embedder,
                targetChunkSize: 500,
                similarityThreshold: 0.5,
                windowSize: 3,
                similarityCalculator: calculator
            )
            
            let metalResult = try await clock.measure {
                _ = try await metalChunker.chunk(text, metadata: nil)
            }
            print("⚡️ Metal-Accelerated Semantic Chunker (2000 sentences): \(metalResult)")
            
        } catch {
            print("⚠️ Metal initialization failed: \(error)")
        }
        #else
        print("⚠️ Metal not supported on this platform")
        #endif
        print("---------------------------------\n")
    }
}
