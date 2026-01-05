// ZoniApple - Apple platform extensions for Zoni
//
// This module provides on-device machine learning capabilities using Apple frameworks:
// - NaturalLanguage framework for free, private embeddings
// - Foundation Models for on-device LLM (iOS 26+)
// - MLX Swift for GPU-accelerated embeddings on Apple Silicon
// - swift-embeddings for ultra-fast Model2Vec embeddings
// - Memory-optimized vector store strategies for large on-device datasets

@_exported import Zoni

// MARK: - Errors

// AppleMLError is automatically exported as a public type from Errors/AppleMLError.swift

// MARK: - Embedding Providers

// NLEmbeddingProvider - Uses Apple NaturalLanguage framework for free, private embeddings
// Available on all Apple platforms (macOS, iOS, tvOS, watchOS, visionOS)
// 512-dimensional embeddings with support for 13 languages

// SwiftEmbeddingsProvider - Uses swift-embeddings for ultra-fast Model2Vec embeddings
// Available on macOS 15.0+, iOS 18.0+, tvOS 18.0+, visionOS 2.0+, watchOS 11.0+
// 256-dimensional embeddings, 10x faster than BERT

// MLXEmbeddingProvider - GPU-accelerated embeddings on Apple Silicon
// Available on macOS 14.0+, iOS 17.0+ (Apple Silicon only)
// 384-dimensional embeddings with GPU parallelism

// FoundationModelsProvider - Apple's on-device LLM for semantic embeddings
// Available on iOS 26.0+ and macOS 26.0+ when Apple Intelligence is enabled
// 1024-dimensional embeddings using SystemLanguageModel

// MARK: - Memory Strategies

// MemoryStrategy protocol and implementations for SQLiteVectorStore
// - EagerMemoryStrategy: Best for < 10k vectors (loads all into memory)
// - StreamingMemoryStrategy: Best for > 100k vectors (batched streaming)
// - CachedMemoryStrategy: LRU cache for frequent access patterns
// - HybridMemoryStrategy: Best for 10k-100k vectors (cache + streaming)
// - MemoryStrategyRecommendation: Auto-select based on store size
