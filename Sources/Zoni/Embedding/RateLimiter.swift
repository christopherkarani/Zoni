// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RateLimiter.swift - Token bucket rate limiting for API requests

import Foundation

// MARK: - RateLimiter

/// Token bucket rate limiter for controlling API request rates.
///
/// `RateLimiter` implements the token bucket algorithm to throttle requests
/// to embedding APIs, preventing rate limit errors and ensuring fair usage.
///
/// The algorithm works as follows:
/// - A bucket holds a maximum number of tokens (`bucketSize`)
/// - Tokens are added at a constant rate (`tokensPerSecond`)
/// - Each request consumes one or more tokens
/// - If insufficient tokens are available, the request waits
///
/// Example usage:
/// ```swift
/// let limiter = RateLimiter.forOpenAI()
///
/// // Acquire tokens before making API call
/// try await limiter.acquire(permits: 1)
/// let response = try await callAPI()
/// ```
///
/// ## Thread Safety
/// `RateLimiter` is implemented as an actor, making it safe to use
/// concurrently from multiple tasks.
public actor RateLimiter {

    // MARK: - Properties

    /// The rate at which tokens are added to the bucket per second.
    private let tokensPerSecond: Double

    /// The maximum number of tokens the bucket can hold.
    private let bucketSize: Int

    /// The current number of available tokens.
    private var tokens: Double

    /// The timestamp of the last token refill.
    private var lastRefill: Date

    // MARK: - Initialization

    /// Creates a new rate limiter with the specified parameters.
    ///
    /// - Parameters:
    ///   - tokensPerSecond: The rate at which tokens are replenished.
    ///   - bucketSize: The maximum token capacity. Defaults to twice the tokens per second.
    public init(tokensPerSecond: Double, bucketSize: Int? = nil) {
        self.tokensPerSecond = tokensPerSecond
        self.bucketSize = bucketSize ?? Int(tokensPerSecond * 2)
        self.tokens = Double(self.bucketSize)
        self.lastRefill = Date()
    }

    // MARK: - Public Methods

    /// Acquires the specified number of permits, waiting if necessary.
    ///
    /// This method blocks (via async/await) until the requested number of
    /// tokens becomes available. Use this before making API calls to ensure
    /// you don't exceed rate limits.
    ///
    /// - Parameter permits: The number of tokens to acquire. Defaults to 1.
    /// - Throws: `CancellationError` if the task is cancelled while waiting.
    public func acquire(permits: Int = 1) async throws {
        refill()

        while tokens < Double(permits) {
            let waitTime = (Double(permits) - tokens) / tokensPerSecond
            try await Task.sleep(for: .seconds(waitTime))
            refill()
        }

        tokens -= Double(permits)
    }

    /// Attempts to acquire permits without waiting.
    ///
    /// This method returns immediately, either with success if sufficient
    /// tokens are available, or failure if not.
    ///
    /// - Parameter permits: The number of tokens to acquire. Defaults to 1.
    /// - Returns: `true` if the permits were acquired, `false` otherwise.
    public func tryAcquire(permits: Int = 1) -> Bool {
        refill()

        if tokens >= Double(permits) {
            tokens -= Double(permits)
            return true
        }

        return false
    }

    /// Returns the current number of available tokens.
    ///
    /// Useful for monitoring and debugging rate limiter state.
    public func availableTokens() -> Double {
        refill()
        return tokens
    }

    /// Resets the rate limiter to its initial state.
    ///
    /// This fills the bucket to capacity and resets the refill timestamp.
    public func reset() {
        tokens = Double(bucketSize)
        lastRefill = Date()
    }

    // MARK: - Private Methods

    /// Refills tokens based on elapsed time since last refill.
    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        tokens = min(Double(bucketSize), tokens + elapsed * tokensPerSecond)
        lastRefill = now
    }
}

// MARK: - Factory Methods

extension RateLimiter {

    /// Creates a rate limiter configured for OpenAI API limits.
    ///
    /// OpenAI allows approximately 3000 requests per minute on standard tiers.
    /// This translates to ~50 requests per second with burst capacity.
    ///
    /// - Returns: A rate limiter configured for OpenAI.
    public static func forOpenAI() -> RateLimiter {
        RateLimiter(tokensPerSecond: 50, bucketSize: 100)
    }

    /// Creates a rate limiter configured for Cohere API limits.
    ///
    /// Cohere has more conservative rate limits, especially on free tiers.
    ///
    /// - Returns: A rate limiter configured for Cohere.
    public static func forCohere() -> RateLimiter {
        RateLimiter(tokensPerSecond: 10, bucketSize: 50)
    }

    /// Creates a rate limiter configured for Voyage AI API limits.
    ///
    /// - Returns: A rate limiter configured for Voyage AI.
    public static func forVoyage() -> RateLimiter {
        RateLimiter(tokensPerSecond: 20, bucketSize: 50)
    }

    /// Creates a rate limiter with no practical limits.
    ///
    /// Useful for local providers like Ollama that don't have rate limits.
    ///
    /// - Returns: A rate limiter with very high limits.
    public static func unlimited() -> RateLimiter {
        RateLimiter(tokensPerSecond: 10000, bucketSize: 10000)
    }
}
