// ZoniConduit - Optional Conduit inference integration for Zoni.
//
// ConduitLLMProvider.swift - LLMProvider adapter for Conduit TextGenerator implementations.

#if canImport(Conduit)
import Foundation
import ConduitAdvanced
import Zoni

/// Adapts any Conduit `TextGenerator` into Zoni's `LLMProvider` protocol.
///
/// This adapter allows Zoni query/synthesizer components to use Conduit inference
/// providers without coupling to provider-specific APIs.
public struct ConduitLLMProvider<Provider: TextGenerator>: LLMProvider {
    /// Logical provider name used by Zoni telemetry and metadata.
    public let name: String

    /// Model identifier string used by Zoni metadata.
    public let model: String

    /// Maximum context token budget used by Zoni prompt budgeting.
    public let maxContextTokens: Int

    private let provider: Provider
    private let modelID: Provider.ModelID
    private let baseConfig: GenerateConfig

    /// Creates a Conduit-backed Zoni LLM provider.
    ///
    /// - Parameters:
    ///   - provider: Conduit text generator instance.
    ///   - model: Conduit model identifier for requests.
    ///   - name: Optional explicit provider name. Defaults to `conduit-<provider>`.
    ///   - maxContextTokens: Context budget used by Zoni. Defaults to 131072.
    ///   - baseConfig: Baseline Conduit generation config merged with per-call `LLMOptions`.
    public init(
        provider: Provider,
        model: Provider.ModelID,
        name: String? = nil,
        maxContextTokens: Int = 131_072,
        baseConfig: GenerateConfig = .default
    ) {
        self.provider = provider
        self.modelID = model
        self.model = model.rawValue
        self.name = name ?? "conduit-\(model.provider.rawValue)"
        self.maxContextTokens = maxContextTokens
        self.baseConfig = baseConfig
    }

    /// Generates a complete response using Conduit.
    public func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String {
        let messages = buildMessages(prompt: prompt, systemPrompt: systemPrompt)
        let config = mergedConfig(with: options)

        do {
            let result = try await provider.generate(
                messages: messages,
                model: modelID,
                config: config
            )
            return result.text
        } catch {
            throw ZoniError.generationFailed(reason: "Conduit generation failed: \(error.localizedDescription)")
        }
    }

    /// Streams response chunks using Conduit's streaming API.
    ///
    /// Metadata-only chunks (empty text) are filtered out.
    public func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error> {
        let messages = buildMessages(prompt: prompt, systemPrompt: systemPrompt)
        let config = mergedConfig(with: options)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = provider.streamWithMetadata(
                        messages: messages,
                        model: modelID,
                        config: config
                    )

                    for try await chunk in stream {
                        try Task.checkCancellation()
                        if !chunk.text.isEmpty {
                            continuation.yield(chunk.text)
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(
                        throwing: ZoniError.generationFailed(
                            reason: "Conduit streaming failed: \(error.localizedDescription)"
                        )
                    )
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func buildMessages(prompt: String, systemPrompt: String?) -> [Message] {
        var messages: [Message] = []

        if let systemPrompt,
           !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.system(systemPrompt))
        }

        messages.append(.user(prompt))
        return messages
    }

    private func mergedConfig(with options: LLMOptions) -> GenerateConfig {
        var config = baseConfig

        if let temperature = options.temperature {
            config.temperature = Float(temperature)
        }

        if let maxTokens = options.maxTokens {
            config.maxTokens = maxTokens
        }

        if let stopSequences = options.stopSequences {
            config.stopSequences = stopSequences
        }

        return config
    }
}
#endif
