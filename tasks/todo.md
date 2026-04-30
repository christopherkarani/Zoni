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
  - `swift build --target ZoniApple` passed.
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

# Postgres Integration Package Split

Date: 2026-04-28

## Assumptions

- PostgreSQL/pgvector support is useful, but it is not part of the smallest default Zoni experience.
- The root package should not declare Postgres dependencies unless a root product needs them.
- A local integration package is a safer first split than redesigning the whole core target graph in one pass.

## Plan

- [x] Move Postgres-backed vector store code out of the root `ZoniServer` target.
  - Verify: root `ZoniServer` no longer imports `PostgresNIO` or `NIOSSL`.
- [x] Add a separate `Integrations/ZoniServerPostgres` package for pgvector users.
  - Verify: the integration package builds independently.
- [x] Update README and server documentation so users can find the optional package.
  - Verify: product tables and setup snippets no longer advertise `ZoniServerPostgres` as a root product.
- [x] Re-run package resolution, root builds/tests, and integration build.
  - Verify: default package stays green and the optional Postgres package compiles.

## Research Notes

- A root target split alone does not reduce SwiftPM resolution when the root manifest still declares the Postgres packages.
- Moving Postgres into a separate local package removes `postgres-nio` and the direct `swift-nio-ssl` dependency from the default root manifest.
- Root dependency output still contains TLS transitively through `AsyncHTTPClient`; that is a separate web-loading/provider concern, not Postgres.
- Building the Postgres integration still builds heavy root `Zoni` dependencies because it depends on the root `Zoni` product. The next larger cleanup should split core protocols/models from optional loaders, HTTP, SQLite, MLX, and embedding providers.

## Review

- Added `Integrations/ZoniServerPostgres` as the optional pgvector package.
- Removed the root `ZoniServerPostgres` product/target and the root Postgres package declarations.
- Moved `PgVectorStore` and `RAGPipeline+Postgres` into the integration package.
- Updated README, server guide, and stale test import references.
- Verification:
  - `swift package resolve && swift package describe --type json` passed.
  - `swift build` passed.
  - `(cd Integrations/ZoniServerPostgres && swift build)` passed.
  - `swift package show-dependencies --format text` no longer lists `postgres-nio` in the root dependency tree.
  - `swift test --filter ZoniTests` passed with 945 tests in 112 suites.
  - `swift test --filter ZoniServerTests` passed with 9 XCTest cases plus 184 Swift Testing tests.

# ZoniCore Target Split

Date: 2026-04-28

## Assumptions

- The first useful split is an API boundary, not a full adapter extraction: move stable RAG contracts and data types into `ZoniCore`, then keep the existing `Zoni` product as the batteries-included module.
- `Zoni` should re-export `ZoniCore` so existing consumers can continue importing `Zoni`.
- This pass should avoid moving concrete loaders/providers/stores unless needed for the core boundary.

## Plan

- [x] Audit current imports and classify pure core files versus dependency-backed implementation files.
  - Verify: identify files that can compile with Foundation-only dependencies.
- [x] Add a `ZoniCore` product/target and move stable core contracts/types into it.
  - Verify: `swift package describe --type json` lists `ZoniCore`; `Zoni` depends on and re-exports it.
- [x] Update root implementation files and downstream targets to import the new core module where needed.
  - Verify: `swift build` compiles without ambiguous or missing symbols.
- [x] Run focused tests and package graph checks.
  - Verify: `swift test --filter ZoniTests`, `swift test --filter ZoniServerTests`, and `swift package describe --type json` pass.
- [x] Document the split and remaining dependency graph work.
  - Verify: README/task notes explain `ZoniCore` versus `Zoni`.

## Research Notes

- `ZoniCore` can stay dependency-free for this pass by owning values, protocols, configuration, error types, and metadata filter matching.
- `Zoni` remains the batteries-included module and re-exports `ZoniCore`, preserving existing `import Zoni` consumers.
- `HTMLLoader` needed explicit `ZoniCore.Document` return/construction because SwiftSoup also exposes a `Document` type.
- This is primarily an API boundary split. The root package manifest still declares HTTP, HTML, SQLite, Conduit, MLX, and swift-embeddings packages for existing products. Further dependency graph reduction requires moving adapters into separate packages or removing those dependencies from the root manifest.

## Review

- Added a new `ZoniCore` library product and dependency-free target.
- Moved stable core contracts and types into `Sources/ZoniCore`: document/chunk/embedding/metadata/result types, provider/store/retriever/loading/chunking protocols, configuration, errors, similarity protocol, and metadata filter matching.
- Updated `Zoni` to depend on and re-export `ZoniCore`, keeping existing `import Zoni` consumers working.
- Added `import ZoniCore` to root implementation files and resolved the SwiftSoup `Document` ambiguity in `HTMLLoader`.
- Updated README product docs to list `ZoniCore`.
- Verification:
  - `swift package describe --type json` passed and lists `ZoniCore`.
  - `swift build` passed.
  - `swift build --target ZoniCore` passed.
  - `swift test --filter ZoniTests` passed with 945 tests in 112 suites.
  - `swift test --filter ZoniServerTests` passed with 9 XCTest cases plus 184 Swift Testing tests.
  - `(cd Integrations/ZoniServerPostgres && swift build)` passed.

# SQLite Integration Package Split

Date: 2026-04-28

## Assumptions

- SQLite is valuable, but it is a persistence adapter rather than required core RAG behavior.
- Moving SQLite out of the root package should remove `SQLite.swift` from default root dependency resolution.
- Apple SQLite memory strategies and Apple SQLite pipeline factories should travel with the SQLite integration instead of keeping root `ZoniApple` coupled to `SQLiteVectorStore`.

## Plan

- [x] Move `SQLiteVectorStore` into an optional `Integrations/ZoniSQLite` package.
  - Verify: root `Zoni` no longer imports `SQLite`.
- [x] Move Apple-specific SQLite helpers/factories into the same integration package.
  - Verify: root `ZoniApple` builds without `SQLiteVectorStore`.
- [x] Remove SQLite cases/convenience APIs from root `VectorStoreFactory` and document the optional package.
  - Verify: root manifest no longer declares `SQLite.swift`; docs point SQLite users to `ZoniSQLite`.
- [x] Gate or relocate root tests that require SQLite.
  - Verify: root `ZoniTests` and `ZoniAppleTests` build without SQLite.
- [x] Run root and integration verification.
  - Verify: `swift build`, filtered tests, dependency tree check, and integration build pass.

## Research Notes

- `SQLiteVectorStore` only depends on root RAG protocols/types, `Foundation`, and `SQLite.swift`, so it can move into a local integration package without pulling server or Apple code into root.
- Apple memory strategies and Apple SQLite pipeline factory helpers are coupled to `SQLiteVectorStore`, so keeping them in root `ZoniApple` would preserve a hidden SQLite dependency. They now live in `ZoniSQLiteApple`.
- Removing SQLite from root also means root `VectorStoreFactory` cannot keep a `.sqlite` config case or `createSQLite` convenience APIs without reintroducing the dependency.
- Root `ZoniTests` passed after gating SQLite-specific performance tests behind `canImport(ZoniSQLite)`.
- Root `ZoniAppleTests` builds, but the full Apple suite is environment-sensitive: several provider tests require local Apple/ML model availability and first-run model downloads. This was pre-existing noise and not caused by the SQLite package boundary.

## Review

- Added `Integrations/ZoniSQLite` with `ZoniSQLite` and `ZoniSQLiteApple` library products.
- Removed the root `SQLite.swift` dependency and moved the SQLite vector store plus Apple SQLite helpers into the optional integration package.
- Removed SQLite-specific creation APIs from root `VectorStoreFactory` so the default package no longer exposes APIs that require an absent adapter.
- Updated README, getting started docs, Apple docs, and ServerRAG notes to present SQLite as an optional integration.
- Added integration-local `ZoniSQLiteTests` so the adapter keeps its own behavior checks after leaving the root package.
- Verification so far:
  - `swift build` passed.
  - `(cd Integrations/ZoniSQLite && swift build)` passed.
  - `(cd Integrations/ZoniSQLite && swift test --filter ZoniSQLiteTests)` passed with 2 tests in 1 suite.
  - `swift package show-dependencies --format text | rg 'SQLite|sqlite'` found no SQLite dependency in the root package graph.
  - `swift package describe --type json | rg 'SQLite|sqlite'` found no SQLite package/target declarations in the root manifest.
  - `swift test --filter ZoniTests` passed with 942 tests in 111 suites.
  - `swift test --filter ZoniAppleTests` builds but exits with existing provider/model environment failures, including Apple provider availability expectations and SwiftEmbeddings model download/cache errors.

# Conduit Integration Package Split

Date: 2026-04-28

## Assumptions

- Conduit is useful as an inference adapter, but it is not part of Zoni's default RAG core.
- Keeping `ZoniConduit` in the root manifest forces default users to resolve Conduit and its transitive dependencies, including `swift-syntax`.
- A local integration package preserves the adapter for users who need it while reducing the default dependency graph.

## Plan

- [x] Move `ConduitLLMProvider` into `Integrations/ZoniConduit`.
  - Verify: integration package builds independently.
- [x] Remove the root `ZoniConduit` product/target and root Conduit package declaration.
  - Verify: root package dependency tree no longer lists Conduit or SwiftSyntax.
- [x] Update docs to list Conduit as an optional integration package.
  - Verify: README no longer lists `ZoniConduit` as a root product.
- [x] Run root and integration verification.
  - Verify: `swift build`, root dependency scans, and integration build pass.

## Research Notes

- `ZoniConduit` was a root product solely for the `ConduitLLMProvider` adapter; no root source or test target imports it.
- The root Conduit dependency pulled `swift-syntax` through Conduit macros, so keeping it in `Package.swift` increased default package resolution even for users who never use Conduit.
- Building the integration package against the current resolved Conduit release required importing `ConduitAdvanced` explicitly; the facade `Conduit` module does not re-export lower-level protocol/types such as `TextGenerator`, `Message`, and `GenerateConfig`.

## Review

- Added `Integrations/ZoniConduit` as the optional Conduit adapter package.
- Removed the root `ZoniConduit` product/target and root Conduit package declaration.
- Moved `ConduitLLMProvider` into the integration package and updated it to import `ConduitAdvanced` for the current Conduit API.
- Updated README to list Conduit under optional integration packages instead of root products.
- Verification:
  - `swift build` passed.
  - `(cd Integrations/ZoniConduit && swift build)` passed.
  - `swift package show-dependencies --format text | rg 'Conduit|swift-syntax|SwiftSyntax|conduit'` found no Conduit/SwiftSyntax dependency in the root package graph.
  - `swift package describe --type json | rg 'Conduit|conduit|swift-syntax|SwiftSyntax'` found no Conduit root manifest declarations.
  - `swift test --filter ZoniTests` passed with 942 tests in 111 suites.

# HTTP Integration Package Split

Date: 2026-04-30

## Assumptions

- HTTP embedding providers, HTML/web loaders, managed vector stores, and network reranking are useful integrations, but they are not required for the core local RAG package.
- Keeping `SwiftSoup` and `AsyncHTTPClient` in the root manifest forces default users to resolve NIO/TLS-era networking packages even when they only use in-memory/local RAG.
- A local `ZoniHTTP` package preserves the old functionality while making the root package graph easier to build and reason about.

## Plan

- [x] Move HTTP/cloud/web-backed implementation files into `Integrations/ZoniHTTP`.
  - Verify: the integration package builds and runs package-local tests.
- [x] Remove `SwiftSoup` and `AsyncHTTPClient` from the root manifest.
  - Verify: root dependency scans no longer list `SwiftSoup`, `async-http-client`, or NIO/TLS packages.
- [x] Tighten root default APIs so they do not expose moved adapters.
  - Verify: `LoaderRegistry.defaultRegistry()` no longer registers `HTMLLoader`; root `VectorStoreFactory` only creates in-memory stores.
- [x] Relocate/gate tests and add focused `ZoniHTTPTests`.
  - Verify: root `ZoniTests` and integration-local tests pass.
- [x] Update docs to make `ZoniHTTP` the explicit import/package for web, HTML, cloud embeddings, Qdrant/Pinecone, and Cohere reranking.
  - Verify: README and guide examples no longer imply these types are root-only.

## Research Notes

- The moved HTTP package owns `OpenAIEmbedding`, `CohereEmbedding`, `MistralEmbedding`, `VoyageEmbedding`, `OllamaEmbedding`, `CohereReranker`, `HTMLLoader`, `WebLoader`, `QdrantStore`, and `PineconeStore`.
- `LoaderRegistry.defaultRegistry()` and `VectorStoreFactory` are the main public boundaries that would otherwise keep moved functionality visible from root.
- After this split, root `swift build` still builds Apple/server products when invoked at package level because they are still root products. That is now the next large source of graph weight, separate from HTTP/NIO.
- The first post-move test run hit `_AtomicsShims` due stale SwiftPM build artifacts. `swift package clean` followed by a clean build/test removed the stale module reference.

## Review

- Added `Integrations/ZoniHTTP` with its own package manifest and focused tests.
- Removed root `SwiftSoup` and `AsyncHTTPClient` declarations and moved the HTTP/web/cloud adapter sources out of `Sources/Zoni`.
- Simplified root `LoaderRegistry.defaultRegistry()` and `VectorStoreFactory` so the root package does not advertise adapters it no longer owns.
- Updated root tests to compile without `ZoniHTTP`, with package-local tests covering the moved embedding metadata and loader behavior.
- Updated README, getting started docs, server guide, and examples to call out `ZoniHTTP` as optional.
- Verification:
  - `swift package clean` completed to remove stale build metadata from the old HTTP graph.
  - `swift build` passed.
  - `swift package show-dependencies --format text | rg 'SwiftSoup|swiftsoup|async-http-client|AsyncHTTPClient|swift-nio|swift-nio-ssl|swift-nio-http2'` found no root dependency matches.
  - `(cd Integrations/ZoniHTTP && swift test --filter ZoniHTTPTests)` passed with 6 tests in 2 suites.
  - `swift test --filter ZoniTests` passed with 891 tests in 103 suites.
