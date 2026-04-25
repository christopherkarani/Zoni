# Zoni Codebase Health Pass

Date: 2026-04-25

## Assumptions

- "Bloated" means the package may have too many dependencies, targets, examples, or partially implemented modules that make builds and onboarding harder than necessary.
- "Builds works" means the root Swift package should resolve, build, and run its test suite on the local machine without special hidden setup.
- "Good developer experience" means clear setup docs, predictable commands, scoped test targets, and no avoidable compile or test failures.

## Plan

- [x] Baseline project state and preserve unrelated changes.
  - Verify: record current git status and existing untracked files.
- [x] Audit package shape, dependencies, products, examples, and docs for bloat or confusing boundaries.
  - Verify: summarize concrete friction points with file references.
- [x] Run build and test baselines before edits.
  - Verify: capture failing commands, errors, and whether failures are dependency, compile, or test behavior issues.
- [x] Make the smallest production-grade fixes needed to restore a clean build/test/developer workflow.
  - Verify: add or adjust tests first where a behavior bug is found, then make tests pass.
- [x] Improve developer experience where low-risk and directly justified by findings.
  - Verify: document canonical commands and any known optional-platform limitations.
- [x] Final verification and review.
  - Verify: rerun relevant build/tests and document results below.

## Research Notes

- Root package build succeeded, but the dependency graph is heavy: core `Zoni` currently pulls HTML parsing, HTTP, SQLite, Postgres/NIO, crypto/logging, Vapor, Hummingbird, Conduit, MLX, and swift-embeddings through one package manifest. Product splitting exists, but dependency resolution still makes first builds expensive.
- The README advertised Swift 6.0 while `Package.swift` uses Swift tools 6.1, omitted `ZoniConduit`, and linked to missing `Documentation/AdvancedRetrieval.md` and `Documentation/API/`.
- ServerRAG referenced missing `ZoniVapor` APIs and docs, so the example could not build.
- AgentWithRAG and ServerRAG used `@main` inside files named `main.swift`, which Swift rejects in this setup.
- iOSDocumentQA had divergent `DocumentPickerError` definitions across platform branches.
- Cloud integration tests ran by default, making the core test suite fail without external Qdrant/Pinecone setup.
- Several warnings remain and should be addressed separately: unhandled `Tests/ZoniTests/README.md`, repeated unused `var metadata`, unused `await` expressions, and unnecessary `nonisolated(unsafe)` annotations.

## Review

- Fixed loader behavior covered by existing tests: directory exclude matching, binary text rejection, Markdown frontmatter variants, PDF annotation/page-range extraction, parent-child offsets, and WebLoader lifecycle.
- Gated Qdrant/Pinecone suites behind `ZONI_RUN_INTEGRATION_TESTS=1` so the default core suite is local and repeatable.
- Repaired example builds for `Examples/AgentWithRAG`, `Examples/ServerRAG`, and `Examples/iOSDocumentQA`.
- Updated README and ServerRAG docs with current products, commands, and integration-test guidance.
- Verification:
  - `swift build` passed.
  - `swift test --filter ZoniTests` passed with 945 tests in 112 suites.
  - `(cd Examples/AgentWithRAG && swift build)` passed.
  - `(cd Examples/ServerRAG && swift build)` passed.
  - `(cd Examples/iOSDocumentQA && swift build)` passed.

# Dependency Graph Reduction Pass

Date: 2026-04-25

## Assumptions

- Zoni should stay focused on RAG primitives: loading, chunking, embeddings, retrieval, vector stores, query orchestration, and narrow optional integrations.
- Web frameworks such as Vapor and Hummingbird should not be part of the root package unless there is a source target that actually imports and exposes framework-specific APIs.
- Standalone examples may depend on Vapor directly without forcing the root package to resolve Vapor.

## Plan

- [x] Map root package dependencies to actual imports and target usage.
  - Verify: compare `Package.swift` dependencies with `Sources/`, `Tests/`, and `Examples/` imports.
- [x] Remove unused framework dependencies and traits from the root package.
  - Verify: `swift package describe` and `swift build` still resolve.
- [x] Confirm standalone examples still carry their own needed dependencies.
  - Verify: rebuild ServerRAG after root dependency removal.
- [x] Update docs/task notes to reflect the narrower dependency graph and remaining optional dependencies.
  - Verify: README no longer implies unused framework adapters exist.
- [x] Final verification.
  - Verify: root build, core tests, and affected examples pass.

## Research Notes

- Import scan and package metadata showed root `vapor`, `jwt`, `hummingbird`, `hummingbird-websocket`, and `hummingbird-auth` were unused by source targets. Vapor is still used by `Examples/ServerRAG`, where it belongs as an example-local dependency.
- `ZoniServer` does still use `PostgresNIO`, `NIOSSL`, `Crypto`, and `Logging` for pgvector, JWT HMAC validation, and job logging.
- `Zoni` still directly uses `SwiftSoup`, `AsyncHTTPClient`, and `SQLite`. Reducing those requires a larger target split, not a manifest-only cleanup.
- `ZoniApple` still directly uses MLX and swift-embeddings. Reducing that requires splitting Apple providers into smaller products.

## Review

- Removed root package traits and framework packages for Vapor/JWT/Hummingbird.
- Removed dormant `#if HUMMINGBIRD` DTO response conformances that referenced framework types without a maintained adapter target.
- Updated server docs to describe framework-agnostic ZoniServer usage and moved Vapor guidance to the standalone ServerRAG example.
- Verification:
  - `swift package describe --type json` passed and no longer lists Vapor, JWT, Hummingbird, HummingbirdWebSocket, or HummingbirdAuth as dependencies.
  - `swift build` passed.
  - `swift test --filter ZoniTests` passed with 945 tests in 112 suites.
  - `swift test --filter ZoniServerTests` passed with 9 XCTest cases plus 184 Swift Testing tests.
  - `(cd Examples/ServerRAG && swift build)` passed.
