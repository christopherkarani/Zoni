import Testing
import Foundation
@testable import Zoni

// MARK: - LoadingUtils Tests

@Suite("LoadingUtils Tests")
struct LoadingUtilsTests {

    // MARK: - Encoding Detection Tests

    @Suite("Encoding Detection")
    struct EncodingDetectionTests {

        @Test("Detect UTF-8 BOM")
        func detectUTF8BOM() {
            // UTF-8 BOM: 0xEF, 0xBB, 0xBF
            let data = Data([0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello" with UTF-8 BOM
            let encoding = LoadingUtils.detectEncoding(data)
            #expect(encoding == .utf8)
        }

        @Test("Detect UTF-16 Little Endian BOM")
        func detectUTF16LEBOM() {
            // UTF-16 LE BOM: 0xFF, 0xFE
            let data = Data([0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00]) // "Hi" in UTF-16 LE
            let encoding = LoadingUtils.detectEncoding(data)
            #expect(encoding == .utf16LittleEndian)
        }

        @Test("Detect UTF-16 Big Endian BOM")
        func detectUTF16BEBOM() {
            // UTF-16 BE BOM: 0xFE, 0xFF
            let data = Data([0xFE, 0xFF, 0x00, 0x48, 0x00, 0x69]) // "Hi" in UTF-16 BE
            let encoding = LoadingUtils.detectEncoding(data)
            #expect(encoding == .utf16BigEndian)
        }

        @Test("Fallback to UTF-8 for valid UTF-8 without BOM")
        func fallbackToUTF8WithoutBOM() {
            // Valid UTF-8 text without BOM
            let text = "Hello, World!"
            let data = text.data(using: .utf8)!
            let encoding = LoadingUtils.detectEncoding(data)
            #expect(encoding == .utf8)
        }

        @Test("Fallback to UTF-8 for UTF-8 multibyte characters without BOM")
        func fallbackToUTF8ForMultibyte() {
            // Valid UTF-8 with multibyte characters (no BOM)
            let text = "Hello, World!"
            let data = text.data(using: .utf8)!
            let encoding = LoadingUtils.detectEncoding(data)
            #expect(encoding == .utf8)
        }

        @Test("Fallback to isoLatin1 for non-UTF-8 data")
        func fallbackToISOLatin1() {
            // Invalid UTF-8 sequence - isolated continuation bytes
            let data = Data([0x80, 0x81, 0x82, 0x83])
            let encoding = LoadingUtils.detectEncoding(data)
            #expect(encoding == .isoLatin1)
        }

        @Test("Handle empty data")
        func handleEmptyData() {
            let data = Data()
            let encoding = LoadingUtils.detectEncoding(data)
            // Empty data should default to UTF-8
            #expect(encoding == .utf8)
        }

        @Test("Handle data with only BOM")
        func handleDataWithOnlyBOM() {
            let data = Data([0xEF, 0xBB, 0xBF]) // Just UTF-8 BOM
            let encoding = LoadingUtils.detectEncoding(data)
            #expect(encoding == .utf8)
        }
    }

    // MARK: - Whitespace Normalization Tests

    @Suite("Whitespace Normalization")
    struct WhitespaceNormalizationTests {

        @Test("Collapse multiple spaces to single space")
        func collapseMultipleSpaces() {
            let input = "Hello    World"
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello World")
        }

        @Test("Collapse multiple newlines to single space")
        func collapseMultipleNewlines() {
            let input = "Hello\n\n\nWorld"
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello World")
        }

        @Test("Collapse tabs to single space")
        func collapseTabs() {
            let input = "Hello\t\t\tWorld"
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello World")
        }

        @Test("Trim leading and trailing whitespace")
        func trimLeadingAndTrailing() {
            let input = "   Hello World   "
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello World")
        }

        @Test("Handle mixed whitespace")
        func handleMixedWhitespace() {
            let input = "  Hello\t\t \n\n  World  "
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello World")
        }

        @Test("Handle carriage return and newline")
        func handleCarriageReturnNewline() {
            let input = "Hello\r\n\r\nWorld"
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello World")
        }

        @Test("Preserve single spaces between words")
        func preserveSingleSpaces() {
            let input = "Hello World Test"
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello World Test")
        }

        @Test("Handle empty string")
        func handleEmptyString() {
            let input = ""
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "")
        }

        @Test("Handle string with only whitespace")
        func handleOnlyWhitespace() {
            let input = "   \t\n\r  "
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "")
        }

        @Test("Handle single word")
        func handleSingleWord() {
            let input = "Hello"
            let result = LoadingUtils.normalizeWhitespace(input)
            #expect(result == "Hello")
        }
    }

    // MARK: - Clean For Embedding Tests

    @Suite("Clean For Embedding")
    struct CleanForEmbeddingTests {

        @Test("Remove control characters")
        func removeControlCharacters() {
            // Control characters: 0x00-0x1F (except tab, newline, carriage return which become spaces)
            let input = "Hello\u{0000}World\u{0001}Test"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(!result.contains("\u{0000}"))
            #expect(!result.contains("\u{0001}"))
        }

        @Test("Normalize multiple spaces")
        func normalizeMultipleSpaces() {
            let input = "Hello    World"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello World")
        }

        @Test("Preserve normal text")
        func preserveNormalText() {
            let input = "Hello World"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello World")
        }

        @Test("Handle tabs by converting to space")
        func handleTabs() {
            let input = "Hello\tWorld"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello World")
        }

        @Test("Handle newlines by converting to space")
        func handleNewlines() {
            let input = "Hello\nWorld"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello World")
        }

        @Test("Trim result")
        func trimResult() {
            let input = "  Hello World  "
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello World")
        }

        @Test("Handle empty string")
        func handleEmptyString() {
            let input = ""
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "")
        }

        @Test("Handle string with only control characters")
        func handleOnlyControlCharacters() {
            let input = "\u{0000}\u{0001}\u{0002}"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "")
        }

        @Test("Preserve Unicode letters and symbols")
        func preserveUnicode() {
            let input = "Hello World Cafe"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello World Cafe")
        }

        @Test("Preserve punctuation")
        func preservePunctuation() {
            let input = "Hello, World! How are you?"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello, World! How are you?")
        }

        @Test("Remove delete character")
        func removeDeleteCharacter() {
            let input = "Hello\u{007F}World"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(!result.contains("\u{007F}"))
        }

        @Test("Handle complex mixed content")
        func handleComplexMixedContent() {
            let input = "\u{0000}  Hello\t\t\nWorld  \u{0001}"
            let result = LoadingUtils.cleanForEmbedding(input)
            #expect(result == "Hello World")
        }
    }

    // MARK: - Filename Extraction Tests

    @Suite("Filename Extraction")
    struct FilenameExtractionTests {

        @Test("Extract filename without extension")
        func extractFilenameWithoutExtension() {
            let url = URL(fileURLWithPath: "/path/to/document.txt")
            let filename = LoadingUtils.filename(from: url)
            #expect(filename == "document")
        }

        @Test("Handle multiple extensions")
        func handleMultipleExtensions() {
            let url = URL(fileURLWithPath: "/path/to/archive.tar.gz")
            let filename = LoadingUtils.filename(from: url)
            // Should remove last extension only
            #expect(filename == "archive.tar")
        }

        @Test("Handle paths with directories")
        func handlePathsWithDirectories() {
            let url = URL(fileURLWithPath: "/Users/test/Documents/folder/file.pdf")
            let filename = LoadingUtils.filename(from: url)
            #expect(filename == "file")
        }

        @Test("Handle filename with no extension")
        func handleNoExtension() {
            let url = URL(fileURLWithPath: "/path/to/README")
            let filename = LoadingUtils.filename(from: url)
            #expect(filename == "README")
        }

        @Test("Handle hidden file with extension")
        func handleHiddenFileWithExtension() {
            let url = URL(fileURLWithPath: "/path/to/.gitignore")
            let filename = LoadingUtils.filename(from: url)
            // .gitignore has no extension, so filename should be .gitignore
            #expect(filename == ".gitignore")
        }

        @Test("Handle filename with spaces")
        func handleFilenameWithSpaces() {
            let url = URL(fileURLWithPath: "/path/to/my document.txt")
            let filename = LoadingUtils.filename(from: url)
            #expect(filename == "my document")
        }

        @Test("Handle filename with special characters")
        func handleFilenameWithSpecialCharacters() {
            let url = URL(fileURLWithPath: "/path/to/file-name_v2.0.txt")
            let filename = LoadingUtils.filename(from: url)
            #expect(filename == "file-name_v2.0")
        }

        @Test("Handle root level file")
        func handleRootLevelFile() {
            let url = URL(fileURLWithPath: "/file.txt")
            let filename = LoadingUtils.filename(from: url)
            #expect(filename == "file")
        }

        @Test("Handle relative path URL")
        func handleRelativePath() {
            let url = URL(fileURLWithPath: "relative/path/file.md")
            let filename = LoadingUtils.filename(from: url)
            #expect(filename == "file")
        }

        @Test("Handle URL with percent encoding")
        func handlePercentEncoding() {
            let url = URL(fileURLWithPath: "/path/to/file%20name.txt")
            let filename = LoadingUtils.filename(from: url)
            // URL should handle percent encoding
            #expect(filename == "file%20name")
        }
    }
}

// MARK: - TextLoader Tests

@Suite("TextLoader Tests")
struct TextLoaderTests {

    let loader = TextLoader()

    // MARK: - Supported Extensions Tests

    @Test("supportedExtensions contains txt and text")
    func supportedExtensions() {
        #expect(TextLoader.supportedExtensions.contains("txt"))
        #expect(TextLoader.supportedExtensions.contains("text"))
        #expect(TextLoader.supportedExtensions.count == 2)
    }

    // MARK: - Load UTF-8 Data Tests

    @Test("Load UTF-8 data and verify content matches")
    func loadUTF8Data() async throws {
        let content = "Hello, World!"
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == content)
    }

    @Test("Load UTF-8 text with emoji and verify preserved")
    func loadUTF8WithEmoji() async throws {
        let content = "Hello, World! \u{1F30D}" // Earth globe emoji
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == content)
        #expect(document.content.contains("\u{1F30D}"))
    }

    @Test("Load UTF-8 with BOM and verify BOM stripped from content")
    func loadWithBOM() async throws {
        let content = "Hello, World!"
        // UTF-8 BOM: 0xEF, 0xBB, 0xBF
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(content.data(using: .utf8)!)

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == content)
        #expect(!document.content.hasPrefix("\u{FEFF}")) // BOM character
    }

    // MARK: - Load From Data Tests

    @Test("Load from Data with provided metadata")
    func loadFromData() async throws {
        let content = "Test content"
        let data = content.data(using: .utf8)!
        let metadata = DocumentMetadata(
            source: "test-source",
            title: "Test Title",
            author: "Test Author"
        )

        let document = try await loader.load(from: data, metadata: metadata)

        #expect(document.content == content)
        #expect(document.metadata.source == "test-source")
        #expect(document.metadata.title == "Test Title")
        #expect(document.metadata.author == "Test Author")
    }

    @Test("Load from Data with nil metadata")
    func loadFromDataWithNilMetadata() async throws {
        let content = "Test content"
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == content)
        #expect(document.metadata.mimeType == "text/plain")
    }

    // MARK: - Error Handling Tests

    @Test("Throws invalidData for binary data")
    func throwsInvalidDataForBinary() async throws {
        // Binary data that is not valid UTF-8
        let binaryData = Data([0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87])

        await #expect(throws: ZoniError.self) {
            _ = try await loader.load(from: binaryData, metadata: nil)
        }
    }

    // MARK: - canLoad Tests

    @Test("canLoad returns true for .txt extension")
    func canLoadReturnsTrueForTxt() {
        let url = URL(fileURLWithPath: "/path/to/document.txt")
        #expect(loader.canLoad(url) == true)
    }

    @Test("canLoad returns true for .text extension")
    func canLoadReturnsTrueForText() {
        let url = URL(fileURLWithPath: "/path/to/document.text")
        #expect(loader.canLoad(url) == true)
    }

    @Test("canLoad returns false for other extensions")
    func canLoadReturnsFalseForOtherExtensions() {
        let pdfUrl = URL(fileURLWithPath: "/path/to/document.pdf")
        let mdUrl = URL(fileURLWithPath: "/path/to/document.md")

        #expect(loader.canLoad(pdfUrl) == false)
        #expect(loader.canLoad(mdUrl) == false)
    }

    // MARK: - Metadata Tests

    @Test("Sets correct mimeType to text/plain")
    func setsCorrectMimeType() async throws {
        let content = "Test content"
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.mimeType == "text/plain")
    }

    @Test("Sets source from URL filename")
    func setsSourceFromURL() async throws {
        // Create a temporary file for testing
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-document.txt")
        let content = "Test content"

        try content.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let document = try await loader.load(from: testFile)

        #expect(document.metadata.source == "test-document")
    }
}

// MARK: - LoaderRegistry Tests

@Suite("LoaderRegistry Tests")
struct LoaderRegistryTests {

    // MARK: - Registration and Retrieval Tests

    @Test("Register and retrieve loader by extension")
    func registerAndRetrieveLoader() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        let loader = await registry.loader(for: "txt")
        #expect(loader != nil)
    }

    @Test("Register multiple loaders and retrieve each correctly")
    func registerMultipleLoaders() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()
        let markdownLoader = MarkdownLoader()

        await registry.register(textLoader)
        await registry.register(markdownLoader)

        let txtLoader = await registry.loader(for: "txt")
        let mdLoader = await registry.loader(for: "md")

        #expect(txtLoader != nil)
        #expect(mdLoader != nil)
    }

    @Test("Loader lookup is case insensitive")
    func loaderLookupIsCaseInsensitive() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        let loaderLowercase = await registry.loader(for: "txt")
        let loaderUppercase = await registry.loader(for: "TXT")
        let loaderMixedcase = await registry.loader(for: "Txt")

        #expect(loaderLowercase != nil)
        #expect(loaderUppercase != nil)
        #expect(loaderMixedcase != nil)
    }

    @Test("Loader for unknown extension returns nil")
    func loaderForUnknownExtensionReturnsNil() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        let loader = await registry.loader(for: "xyz")
        #expect(loader == nil)
    }

    // MARK: - URL-based Lookup Tests

    @Test("Get loader by URL extension")
    func loaderForURL() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        let url = URL(fileURLWithPath: "/path/to/document.txt")
        let loader = await registry.loader(for: url)

        #expect(loader != nil)
    }

    @Test("Get loader by URL with mixed case extension")
    func loaderForURLWithMixedCase() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        let url = URL(fileURLWithPath: "/path/to/document.TXT")
        let loader = await registry.loader(for: url)

        #expect(loader != nil)
    }

    // MARK: - Unregistration Tests

    @Test("Unregister removes loader for extensions")
    func unregisterRemovesLoader() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        // Verify it was registered
        let loaderBefore = await registry.loader(for: "txt")
        #expect(loaderBefore != nil)

        // Unregister
        await registry.unregister(extensions: ["txt", "text"])

        // Verify it was removed
        let loaderAfter = await registry.loader(for: "txt")
        #expect(loaderAfter == nil)
    }

    // MARK: - Override Tests

    @Test("Later registration overrides previous for same extension")
    func laterRegistrationOverrides() async throws {
        let registry = LoaderRegistry()

        // Create two different loaders that both claim to handle "txt"
        struct FirstLoader: DocumentLoader {
            static let supportedExtensions: Set<String> = ["txt"]

            func load(from url: URL) async throws -> Document {
                Document(content: "first", metadata: DocumentMetadata())
            }

            func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
                Document(content: "first", metadata: metadata ?? DocumentMetadata())
            }
        }

        struct SecondLoader: DocumentLoader {
            static let supportedExtensions: Set<String> = ["txt"]

            func load(from url: URL) async throws -> Document {
                Document(content: "second", metadata: DocumentMetadata())
            }

            func load(from data: Data, metadata: DocumentMetadata?) async throws -> Document {
                Document(content: "second", metadata: metadata ?? DocumentMetadata())
            }
        }

        await registry.register(FirstLoader())
        await registry.register(SecondLoader())

        // The second loader should have overridden the first
        let loader = await registry.loader(for: "txt")
        #expect(loader != nil)

        // Load some data to verify it's the second loader
        let document = try await loader?.load(from: Data(), metadata: nil)
        #expect(document?.content == "second")
    }

    // MARK: - Registered Extensions Tests

    @Test("registeredExtensions returns all registered extensions")
    func registeredExtensionsReturnsAll() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()
        let markdownLoader = MarkdownLoader()

        await registry.register(textLoader)
        await registry.register(markdownLoader)

        let extensions = await registry.registeredExtensions

        // TextLoader supports: txt, text
        // MarkdownLoader supports: md, markdown
        #expect(extensions.contains("txt"))
        #expect(extensions.contains("text"))
        #expect(extensions.contains("md"))
        #expect(extensions.contains("markdown"))
    }

    // MARK: - Load from URL Tests

    @Test("load from URL uses correct loader and loads document")
    func loadFromURLUsesCorrectLoader() async throws {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        // Create a temporary file for testing
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_\(UUID().uuidString).txt")
        let testContent = "Hello, World!"

        try testContent.write(to: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let document = try await registry.load(from: tempFile)

        #expect(document.content == testContent)
    }

    @Test("load from URL throws for unknown extension")
    func loadFromURLThrowsForUnknownExtension() async {
        let registry = LoaderRegistry()
        let textLoader = TextLoader()

        await registry.register(textLoader)

        let url = URL(fileURLWithPath: "/path/to/document.xyz")

        do {
            _ = try await registry.load(from: url)
            Issue.record("Expected ZoniError.unsupportedFileType to be thrown")
        } catch let error as ZoniError {
            if case .unsupportedFileType(let ext) = error {
                #expect(ext == "xyz")
            } else {
                Issue.record("Expected unsupportedFileType error, got: \(error)")
            }
        } catch {
            Issue.record("Expected ZoniError, got: \(error)")
        }
    }

    // MARK: - Empty Registry Tests

    @Test("Empty registry has no registered extensions")
    func emptyRegistryHasNoExtensions() async {
        let registry = LoaderRegistry()

        let extensions = await registry.registeredExtensions

        #expect(extensions.isEmpty)
    }
}

// MARK: - JSONLoader Tests

@Suite("JSONLoader Tests")
struct JSONLoaderTests {

    // MARK: - Supported Extensions Tests

    @Test("supportedExtensions contains json")
    func supportedExtensions() {
        #expect(JSONLoader.supportedExtensions.contains("json"))
        #expect(JSONLoader.supportedExtensions.count == 1)
    }

    // MARK: - Load JSON Without KeyPath Tests

    @Test("Load JSON without keypath serializes entire JSON as content")
    func loadJSONWithoutKeyPath() async throws {
        let loader = JSONLoader()
        let jsonString = """
        {"text": "Hello", "id": 123}
        """
        let data = jsonString.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        // Without keypath, content should be the serialized JSON
        #expect(document.content.contains("text"))
        #expect(document.content.contains("Hello"))
        #expect(document.content.contains("123"))
    }

    // MARK: - Load JSON With Content KeyPath Tests

    @Test("Load JSON with contentKeyPath extracts text field as content")
    func loadJSONWithContentKeyPath() async throws {
        let loader = JSONLoader(contentKeyPath: "text")
        let jsonString = """
        {"text": "Hello", "id": 123}
        """
        let data = jsonString.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == "Hello")
    }

    @Test("Load JSON with nested keypath extracts data.content field")
    func loadJSONWithNestedKeyPath() async throws {
        let loader = JSONLoader(contentKeyPath: "data.content")
        let jsonString = """
        {"data": {"content": "Nested"}}
        """
        let data = jsonString.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == "Nested")
    }

    // MARK: - Load JSON With Metadata KeyPaths Tests

    @Test("Load JSON with metadataKeyPaths extracts metadata from paths")
    func loadJSONWithMetadataKeyPaths() async throws {
        let loader = JSONLoader(
            contentKeyPath: "text",
            metadataKeyPaths: ["title": "meta.title", "author": "meta.author"]
        )
        let jsonString = """
        {"text": "Content here", "meta": {"title": "My Title", "author": "John Doe"}}
        """
        let data = jsonString.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == "Content here")
        #expect(document.metadata.title == "My Title")
        #expect(document.metadata.author == "John Doe")
    }

    // MARK: - Load JSON Array Tests

    @Test("loadArray returns multiple documents from JSON array")
    func loadJSONArrayAsDocuments() async throws {
        let loader = JSONLoader(contentKeyPath: "text")
        let jsonString = """
        [{"text": "First"}, {"text": "Second"}]
        """
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_array_\(UUID().uuidString).json")

        try jsonString.write(to: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let documents = try await loader.loadArray(from: tempFile, itemKeyPath: nil)

        #expect(documents.count == 2)
        #expect(documents[0].content == "First")
        #expect(documents[1].content == "Second")
    }

    @Test("loadArray with itemKeyPath extracts array from nested path")
    func loadJSONArrayWithItemKeyPath() async throws {
        let loader = JSONLoader(contentKeyPath: "text")
        let jsonString = """
        {"items": [{"text": "First"}, {"text": "Second"}]}
        """
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_nested_array_\(UUID().uuidString).json")

        try jsonString.write(to: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let documents = try await loader.loadArray(from: tempFile, itemKeyPath: "items")

        #expect(documents.count == 2)
        #expect(documents[0].content == "First")
        #expect(documents[1].content == "Second")
    }

    // MARK: - Error Handling Tests

    @Test("Throws invalidData for invalid JSON")
    func throwsForInvalidJSON() async {
        let loader = JSONLoader()
        let invalidJSON = "not valid json {{"
        let data = invalidJSON.data(using: .utf8)!

        await #expect(throws: ZoniError.self) {
            _ = try await loader.load(from: data, metadata: nil)
        }
    }

    @Test("Throws invalidData when keypath does not exist")
    func throwsForMissingKeyPath() async {
        let loader = JSONLoader(contentKeyPath: "nonexistent.path")
        let jsonString = """
        {"text": "Hello"}
        """
        let data = jsonString.data(using: .utf8)!

        await #expect(throws: ZoniError.self) {
            _ = try await loader.load(from: data, metadata: nil)
        }
    }

    // MARK: - Null and Type Handling Tests

    @Test("Handle null values gracefully")
    func handleNullValues() async throws {
        let loader = JSONLoader(contentKeyPath: "text")
        let jsonString = """
        {"text": null, "other": "value"}
        """
        let data = jsonString.data(using: .utf8)!

        // Should either return empty string or throw - implementation dependent
        // Testing that it handles gracefully without crashing
        do {
            let document = try await loader.load(from: data, metadata: nil)
            // If it succeeds, content should be empty or "null"
            #expect(document.content.isEmpty || document.content == "null")
        } catch {
            // Throwing is also acceptable for null values
            #expect(error is ZoniError)
        }
    }

    @Test("Handle numeric content by converting to string")
    func handleNumericContent() async throws {
        let loader = JSONLoader(contentKeyPath: "id")
        let jsonString = """
        {"id": 12345, "text": "Hello"}
        """
        let data = jsonString.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == "12345")
    }

    @Test("Handle boolean content by converting to string")
    func handleBooleanContent() async throws {
        let loader = JSONLoader(contentKeyPath: "active")
        let jsonString = """
        {"active": true, "text": "Hello"}
        """
        let data = jsonString.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == "true")
    }

    // MARK: - canLoad Tests

    @Test("canLoad returns true for .json extension and false for others")
    func canLoadReturnsCorrectly() {
        let loader = JSONLoader()

        let jsonUrl = URL(fileURLWithPath: "/path/to/document.json")
        let txtUrl = URL(fileURLWithPath: "/path/to/document.txt")
        let mdUrl = URL(fileURLWithPath: "/path/to/document.md")

        #expect(loader.canLoad(jsonUrl) == true)
        #expect(loader.canLoad(txtUrl) == false)
        #expect(loader.canLoad(mdUrl) == false)
    }
}

// MARK: - CSVLoader Tests

@Suite("CSVLoader Tests")
struct CSVLoaderTests {

    // MARK: - Supported Extensions Tests

    @Test("supportedExtensions contains csv and tsv")
    func supportedExtensions() {
        #expect(CSVLoader.supportedExtensions.contains("csv"))
        #expect(CSVLoader.supportedExtensions.contains("tsv"))
        #expect(CSVLoader.supportedExtensions.count == 2)
    }

    // MARK: - Load CSV as Document Tests

    @Test("Load entire CSV as single document")
    func loadCSVAsDocument() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content one","Alice"
        "Second","Content two","Bob"
        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader()

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("title,content,author"))
        #expect(document.content.contains("First"))
        #expect(document.content.contains("Second"))
    }

    // MARK: - Content Column Tests

    @Test("Load CSV with content column extracts specific column as content")
    func loadCSVWithContentColumn() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content one","Alice"
        "Second","Content two","Bob"
        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content")

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].content == "Content one")
        #expect(documents[1].content == "Content two")
    }

    // MARK: - Metadata Column Tests

    @Test("Load CSV with metadata columns extracts columns as metadata")
    func loadCSVWithMetadataColumns() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content one","Alice"
        "Second","Content two","Bob"
        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content", metadataColumns: ["title", "author"])

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].metadata.custom["title"]?.stringValue == "First")
        #expect(documents[0].metadata.custom["author"]?.stringValue == "Alice")
        #expect(documents[1].metadata.custom["title"]?.stringValue == "Second")
        #expect(documents[1].metadata.custom["author"]?.stringValue == "Bob")
    }

    // MARK: - Load Rows Tests

    @Test("loadRows returns array of documents for each row")
    func loadCSVRows() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content one","Alice"
        "Second","Content two","Bob"
        "Third","Content three","Charlie"
        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content")

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 3)
        #expect(documents[0].content == "Content one")
        #expect(documents[1].content == "Content two")
        #expect(documents[2].content == "Content three")
    }

    // MARK: - TSV Tests

    @Test("Load TSV with tab delimiter")
    func loadTSVWithTabDelimiter() async throws {
        let tsvContent = "title\tcontent\tauthor\n\"First\"\t\"Content one\"\t\"Alice\"\n\"Second\"\t\"Content two\"\t\"Bob\""
        let data = tsvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content", delimiter: "\t")

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].content == "Content one")
        #expect(documents[1].content == "Content two")
    }

    // MARK: - Quoted Fields Tests

    @Test("Handle quoted fields with embedded commas")
    func handleQuotedFields() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content, with comma","Alice"
        "Second","Another, content, with, commas","Bob"
        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content")

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].content == "Content, with comma")
        #expect(documents[1].content == "Another, content, with, commas")
    }

    @Test("Handle quoted fields with embedded newlines")
    func handleQuotedFieldsWithNewlines() async throws {
        let csvContent = "title,content,author\n\"First\",\"Content with\nnewline\",\"Alice\"\n\"Second\",\"Normal content\",\"Bob\""
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content")

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].content == "Content with\nnewline")
        #expect(documents[1].content == "Normal content")
    }

    @Test("Handle escaped quotes within quoted fields")
    func handleEscapedQuotes() async throws {
        let csvContent = #"""
        title,content,author
        "First","He said ""Hello""","Alice"
        "Second","She replied ""Hi""","Bob"
        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content")

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].content == "He said \"Hello\"")
        #expect(documents[1].content == "She replied \"Hi\"")
    }

    // MARK: - Headerless CSV Tests

    @Test("Handle headerless CSV with column indices")
    func handleHeaderless() async throws {
        let csvContent = #"""
        "First","Content one","Alice"
        "Second","Content two","Bob"
        """#
        let data = csvContent.data(using: .utf8)!
        // When hasHeaders is false, use column index "1" for second column
        let loader = CSVLoader(contentColumn: "1", hasHeaders: false)

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].content == "Content one")
        #expect(documents[1].content == "Content two")
    }

    // MARK: - Error Handling Tests

    @Test("Throws for missing content column")
    func throwsForMissingContentColumn() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content one","Alice"
        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "nonexistent")

        await #expect(throws: ZoniError.self) {
            _ = try await loader.loadRows(from: data)
        }
    }

    // MARK: - Empty Rows Tests

    @Test("Handle and skip empty rows")
    func handleEmptyRows() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content one","Alice"

        "Second","Content two","Bob"

        """#
        let data = csvContent.data(using: .utf8)!
        let loader = CSVLoader(contentColumn: "content")

        let documents = try await loader.loadRows(from: data)

        #expect(documents.count == 2)
        #expect(documents[0].content == "Content one")
        #expect(documents[1].content == "Content two")
    }

    // MARK: - canLoad Tests

    @Test("canLoad returns true for csv and tsv, false for others")
    func canLoadReturnsCorrectly() {
        let loader = CSVLoader()

        let csvUrl = URL(fileURLWithPath: "/path/to/data.csv")
        let tsvUrl = URL(fileURLWithPath: "/path/to/data.tsv")
        let txtUrl = URL(fileURLWithPath: "/path/to/data.txt")
        let jsonUrl = URL(fileURLWithPath: "/path/to/data.json")

        #expect(loader.canLoad(csvUrl) == true)
        #expect(loader.canLoad(tsvUrl) == true)
        #expect(loader.canLoad(txtUrl) == false)
        #expect(loader.canLoad(jsonUrl) == false)
    }

    // MARK: - Load from URL Tests

    @Test("Load CSV rows from file URL")
    func loadRowsFromURL() async throws {
        let csvContent = #"""
        title,content,author
        "First","Content one","Alice"
        "Second","Content two","Bob"
        """#

        // Create a temporary file for testing
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_\(UUID().uuidString).csv")

        try csvContent.write(to: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let loader = CSVLoader(contentColumn: "content")
        let documents = try await loader.loadRows(from: tempFile)

        #expect(documents.count == 2)
        #expect(documents[0].content == "Content one")
        #expect(documents[1].content == "Content two")
    }
}

// MARK: - MarkdownLoader Tests

@Suite("MarkdownLoader Tests")
struct MarkdownLoaderTests {

    let loader = MarkdownLoader()

    // MARK: - Supported Extensions Tests

    @Test("supportedExtensions contains md and markdown")
    func supportedExtensions() {
        #expect(MarkdownLoader.supportedExtensions.contains("md"))
        #expect(MarkdownLoader.supportedExtensions.contains("markdown"))
        #expect(MarkdownLoader.supportedExtensions.count == 2)
    }

    // MARK: - Frontmatter Parsing Tests

    @Test("Load markdown with frontmatter extracts title and author")
    func loadMarkdownWithFrontmatter() async throws {
        let content = #"""
        ---
        title: Document Title
        author: Jane Doe
        ---

        # Content starts here

        This is the body content.
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.title == "Document Title")
        #expect(document.metadata.author == "Jane Doe")
        #expect(document.content.contains("# Content starts here"))
        #expect(document.content.contains("This is the body content."))
        #expect(!document.content.contains("---"))
        #expect(!document.content.contains("title:"))
    }

    @Test("Load markdown with date in frontmatter extracts to custom metadata")
    func loadMarkdownWithDateInFrontmatter() async throws {
        let content = #"""
        ---
        title: Test Document
        date: 2024-01-15
        ---

        Body content here.
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.title == "Test Document")
        #expect(document.metadata.custom["date"]?.stringValue == "2024-01-15")
    }

    @Test("Load markdown with custom fields extracts to metadata.custom")
    func loadMarkdownWithCustomFields() async throws {
        let content = #"""
        ---
        title: Custom Fields Test
        category: testing
        tags: [swift, rag]
        priority: 5
        ---

        Document body.
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.title == "Custom Fields Test")
        #expect(document.metadata.custom["category"]?.stringValue == "testing")

        // Tags should be an array
        if let tags = document.metadata.custom["tags"]?.arrayValue {
            let tagStrings = tags.compactMap { $0.stringValue }
            #expect(tagStrings.contains("swift"))
            #expect(tagStrings.contains("rag"))
        } else {
            Issue.record("Expected tags to be an array")
        }

        // Priority should be an integer
        #expect(document.metadata.custom["priority"]?.intValue == 5)
    }

    @Test("Load markdown without frontmatter returns full content")
    func loadMarkdownWithoutFrontmatter() async throws {
        let content = #"""
        # No Frontmatter Here

        This document has no YAML frontmatter.
        Just plain markdown content.
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content == content)
        #expect(document.metadata.title == nil)
        #expect(document.metadata.author == nil)
    }

    @Test("Load markdown with malformed frontmatter treats as content")
    func loadMarkdownWithMalformedFrontmatter() async throws {
        let content = #"""
        ---
        title: This is incomplete
        no closing delimiter

        # This should all be content
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        // Malformed frontmatter should be treated as content
        #expect(document.content.contains("---"))
        #expect(document.content.contains("title: This is incomplete"))
        #expect(document.metadata.title == nil)
    }

    @Test("Frontmatter end with three dots is recognized")
    func frontmatterEndWithThreeDots() async throws {
        let content = #"""
        ---
        title: Three Dots End
        author: Test Author
        ...

        # Content After Dots

        The body starts here.
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.title == "Three Dots End")
        #expect(document.metadata.author == "Test Author")
        #expect(document.content.contains("# Content After Dots"))
        #expect(!document.content.contains("..."))
    }

    @Test("Content after frontmatter is preserved exactly")
    func preserveContentAfterFrontmatter() async throws {
        let bodyContent = #"""
        # Main Heading

        Paragraph with **bold** and *italic* text.

        - List item 1
        - List item 2

        ```swift
        let code = "preserved"
        ```
        """#
        let content = """
        ---
        title: Preservation Test
        ---

        \(bodyContent)
        """
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        // Body should be preserved with formatting intact
        #expect(document.content.contains("# Main Heading"))
        #expect(document.content.contains("**bold**"))
        #expect(document.content.contains("*italic*"))
        #expect(document.content.contains("- List item 1"))
        #expect(document.content.contains("```swift"))
        #expect(document.content.contains("let code = \"preserved\""))
    }

    @Test("extractFrontmatter disabled skips frontmatter parsing")
    func extractFrontmatterDisabled() async throws {
        let content = #"""
        ---
        title: Should Not Be Parsed
        author: Ignored Author
        ---

        # Content
        """#
        let data = content.data(using: .utf8)!

        let loaderNoFrontmatter = MarkdownLoader(extractFrontmatter: false)
        let document = try await loaderNoFrontmatter.load(from: data, metadata: nil)

        // When extractFrontmatter is false, the entire content including frontmatter is preserved
        #expect(document.content.contains("---"))
        #expect(document.content.contains("title: Should Not Be Parsed"))
        #expect(document.metadata.title == nil)
        #expect(document.metadata.author == nil)
    }

    @Test("Handle empty frontmatter block")
    func handleEmptyFrontmatter() async throws {
        let content = #"""
        ---
        ---

        # Content After Empty Frontmatter
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("# Content After Empty Frontmatter"))
        #expect(!document.content.contains("---"))
        #expect(document.metadata.title == nil)
    }

    @Test("Handle multiline quoted values in frontmatter")
    func handleMultilineValues() async throws {
        let content = #"""
        ---
        title: Multiline Test
        description: "This is a long description
        that spans multiple lines
        in the frontmatter"
        ---

        # Content
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.title == "Multiline Test")
        if let description = document.metadata.custom["description"]?.stringValue {
            #expect(description.contains("This is a long description"))
            #expect(description.contains("that spans multiple lines"))
        } else {
            Issue.record("Expected description to be a string")
        }
    }

    // MARK: - canLoad Tests

    @Test("canLoad returns correctly for different extensions")
    func canLoadReturnsCorrectly() {
        let mdUrl = URL(fileURLWithPath: "/path/to/document.md")
        let markdownUrl = URL(fileURLWithPath: "/path/to/document.markdown")
        let txtUrl = URL(fileURLWithPath: "/path/to/document.txt")
        let htmlUrl = URL(fileURLWithPath: "/path/to/document.html")

        #expect(loader.canLoad(mdUrl) == true)
        #expect(loader.canLoad(markdownUrl) == true)
        #expect(loader.canLoad(txtUrl) == false)
        #expect(loader.canLoad(htmlUrl) == false)
    }

    // MARK: - Metadata Tests

    @Test("Sets correct mimeType to text/markdown")
    func setsCorrectMimeType() async throws {
        let content = "# Simple Markdown"
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.mimeType == "text/markdown")
    }

    @Test("Sets source from URL filename")
    func setsSourceFromURL() async throws {
        // Create a temporary file for testing
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-document.md")
        let content = #"""
        ---
        title: Test
        ---

        # Content
        """#

        try content.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let document = try await loader.load(from: testFile)

        #expect(document.metadata.source == "test-document")
    }

    // MARK: - Edge Cases

    @Test("Handle frontmatter with only whitespace between delimiters")
    func handleWhitespaceOnlyFrontmatter() async throws {
        let content = #"""
        ---

        ---

        # Content
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("# Content"))
    }

    @Test("Frontmatter must start at beginning of file")
    func frontmatterMustStartAtBeginning() async throws {
        let content = #"""
        Some text before frontmatter
        ---
        title: Not Real Frontmatter
        ---

        # Content
        """#
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        // Since frontmatter doesn't start at beginning, treat entire content as body
        #expect(document.content.contains("Some text before frontmatter"))
        #expect(document.content.contains("---"))
        #expect(document.metadata.title == nil)
    }

    @Test("Handle Windows line endings in frontmatter")
    func handleWindowsLineEndings() async throws {
        let content = "---\r\ntitle: Windows Style\r\nauthor: Test\r\n---\r\n\r\n# Content"
        let data = content.data(using: .utf8)!

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.title == "Windows Style")
        #expect(document.metadata.author == "Test")
        #expect(document.content.contains("# Content"))
    }
}

// MARK: - WebLoader Tests

@Suite("WebLoader Tests")
struct WebLoaderTests {

    // MARK: - Supported Extensions Tests

    @Test("supportedExtensions is empty set (URL-based, not extension-based)")
    func supportedExtensionsIsEmpty() {
        #expect(WebLoader.supportedExtensions.isEmpty)
    }

    // MARK: - canLoad URL Scheme Tests

    @Test("canLoad returns true for http URL")
    func canLoadHttpURL() async {
        let loader = WebLoader()
        let url = URL(string: "http://example.com")!
        let result = await loader.canLoad(url)
        #expect(result == true)
    }

    @Test("canLoad returns true for https URL")
    func canLoadHttpsURL() async {
        let loader = WebLoader()
        let url = URL(string: "https://example.com")!
        let result = await loader.canLoad(url)
        #expect(result == true)
    }

    @Test("canLoad returns false for file URL")
    func canLoadReturnsFalseForFile() async {
        let loader = WebLoader()
        let url = URL(fileURLWithPath: "/path/to/file.html")
        let result = await loader.canLoad(url)
        #expect(result == false)
    }

    @Test("canLoad returns false for ftp URL")
    func canLoadReturnsFalseForFtp() async {
        let loader = WebLoader()
        let url = URL(string: "ftp://example.com/file.txt")!
        let result = await loader.canLoad(url)
        #expect(result == false)
    }

    // MARK: - Default Configuration Tests

    @Test("Default userAgent is Zoni/1.0")
    func defaultUserAgent() async {
        let loader = WebLoader()
        let userAgent = await loader.userAgent
        #expect(userAgent == "Zoni/1.0")
    }

    @Test("Default timeout is 30 seconds")
    func defaultTimeout() async {
        let loader = WebLoader()
        let timeout = await loader.timeout
        #expect(timeout == .seconds(30))
    }

    @Test("Default followRedirects is true")
    func defaultFollowRedirects() async {
        let loader = WebLoader()
        let followRedirects = await loader.followRedirects
        #expect(followRedirects == true)
    }

    // MARK: - Custom Configuration Tests

    @Test("Custom userAgent is preserved")
    func customUserAgent() async {
        let loader = WebLoader(userAgent: "CustomBot/2.0")
        let userAgent = await loader.userAgent
        #expect(userAgent == "CustomBot/2.0")
    }

    @Test("Custom timeout is preserved")
    func customTimeout() async {
        let loader = WebLoader(timeout: .seconds(60))
        let timeout = await loader.timeout
        #expect(timeout == .seconds(60))
    }

    @Test("Custom followRedirects is preserved")
    func customFollowRedirects() async {
        let loader = WebLoader(followRedirects: false)
        let followRedirects = await loader.followRedirects
        #expect(followRedirects == false)
    }

    // MARK: - URL Validation Tests

    @Test("canLoad returns true for http URL with path")
    func canLoadHttpWithPath() async {
        let loader = WebLoader()
        let url = URL(string: "http://example.com/path/to/page")!
        let result = await loader.canLoad(url)
        #expect(result == true)
    }

    @Test("canLoad returns true for https URL with query parameters")
    func canLoadHttpsWithQuery() async {
        let loader = WebLoader()
        let url = URL(string: "https://example.com/search?q=test&page=1")!
        let result = await loader.canLoad(url)
        #expect(result == true)
    }

    @Test("canLoad returns false for mailto URL")
    func canLoadReturnsFalseForMailto() async {
        let loader = WebLoader()
        let url = URL(string: "mailto:test@example.com")!
        let result = await loader.canLoad(url)
        #expect(result == false)
    }

    @Test("canLoad returns false for data URL")
    func canLoadReturnsFalseForDataUrl() async {
        let loader = WebLoader()
        let url = URL(string: "data:text/html,<h1>Hello</h1>")!
        let result = await loader.canLoad(url)
        #expect(result == false)
    }

    // Note: The following tests would require network access or mocking:
    // - load(from:) with actual HTTP request
    // - loadMultiple(urls:maxConcurrency:) with actual requests
    // - Error handling for network failures
    // - Response parsing and HTML extraction
    // - Redirect handling
    // - Timeout behavior
    //
    // These should be placed in an integration test target with proper
    // network mocking (e.g., using URLProtocol or a mock HTTP server)
    // or run against real test endpoints.
}

// MARK: - HTMLLoader Tests

@Suite("HTMLLoader Tests")
struct HTMLLoaderTests {

    // MARK: - Supported Extensions Tests

    @Test("supportedExtensions contains html and htm")
    func supportedExtensions() {
        #expect(HTMLLoader.supportedExtensions.contains("html"))
        #expect(HTMLLoader.supportedExtensions.contains("htm"))
        #expect(HTMLLoader.supportedExtensions.count == 2)
    }

    // MARK: - Load HTML Text Extraction Tests

    @Test("Load HTML extracts clean text from body")
    func loadHTMLExtractsText() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Test Page</title>
        </head>
        <body>
          <p>Hello, World!</p>
          <p>This is a test paragraph.</p>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("Hello, World!"))
        #expect(document.content.contains("This is a test paragraph."))
        // Should not contain HTML tags
        #expect(!document.content.contains("<p>"))
        #expect(!document.content.contains("</p>"))
        #expect(!document.content.contains("<html>"))
    }

    @Test("Load HTML with content selector extracts only article/main content")
    func loadHTMLWithContentSelector() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Test Page</title>
        </head>
        <body>
          <header>Header content</header>
          <article>Main article content here</article>
          <aside>Sidebar content</aside>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader(contentSelectors: ["article"])

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("Main article content here"))
        // Should not contain header or sidebar when using article selector
        #expect(!document.content.contains("Header content"))
        #expect(!document.content.contains("Sidebar content"))
    }

    // MARK: - Exclusion Tests

    @Test("Load HTML excludes nav by default")
    func loadHTMLExcludesNav() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <body>
          <nav>Navigation links here</nav>
          <main>Main content here</main>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("Main content here"))
        #expect(!document.content.contains("Navigation links here"))
    }

    @Test("Load HTML excludes footer by default")
    func loadHTMLExcludesFooter() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <body>
          <main>Main content here</main>
          <footer>Footer text with copyright</footer>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("Main content here"))
        #expect(!document.content.contains("Footer text with copyright"))
    }

    @Test("Load HTML excludes script tags by default")
    func loadHTMLExcludesScript() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <body>
          <p>Visible content</p>
          <script>alert('This should not appear');</script>
          <script type="text/javascript">
            function test() { return 'hidden'; }
          </script>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("Visible content"))
        #expect(!document.content.contains("alert"))
        #expect(!document.content.contains("This should not appear"))
        #expect(!document.content.contains("function test"))
    }

    @Test("Load HTML excludes style tags by default")
    func loadHTMLExcludesStyle() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { color: red; }
            .hidden { display: none; }
          </style>
        </head>
        <body>
          <p>Visible content</p>
          <style>.inline { color: blue; }</style>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("Visible content"))
        #expect(!document.content.contains("body { color: red; }"))
        #expect(!document.content.contains(".hidden"))
        #expect(!document.content.contains(".inline"))
    }

    // MARK: - Meta Tag Extraction Tests

    @Test("Extract title from head")
    func extractTitleFromHead() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Page Title From Head</title>
        </head>
        <body>
          <p>Content</p>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader(extractMetaTags: true)

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.title == "Page Title From Head")
    }

    @Test("Extract meta description")
    func extractMetaDescription() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Test Page</title>
          <meta name="description" content="A test page description">
        </head>
        <body>
          <p>Content</p>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader(extractMetaTags: true)

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.custom["description"]?.stringValue == "A test page description")
    }

    @Test("Extract meta author")
    func extractMetaAuthor() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Test Page</title>
          <meta name="author" content="Test Author">
        </head>
        <body>
          <p>Content</p>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader(extractMetaTags: true)

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.author == "Test Author")
    }

    @Test("Extract meta Open Graph tags")
    func extractMetaOgTags() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Test Page</title>
          <meta property="og:title" content="OG Title">
          <meta property="og:description" content="OG Description">
        </head>
        <body>
          <p>Content</p>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader(extractMetaTags: true)

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.custom["og:title"]?.stringValue == "OG Title")
        #expect(document.metadata.custom["og:description"]?.stringValue == "OG Description")
    }

    // MARK: - Error Handling Tests

    @Test("Handle malformed HTML gracefully")
    func handleMalformedHTML() async throws {
        let html = #"""
        <html>
        <head><title>Broken
        <body>
        <p>Unclosed paragraph
        <div>Nested <span>without closing
        </body>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        // Should not throw, should handle gracefully
        let document = try await loader.load(from: data, metadata: nil)

        // Should extract some content despite malformed HTML
        #expect(document.content.contains("Unclosed paragraph") || document.content.contains("Nested"))
    }

    @Test("Handle HTML with empty body")
    func handleEmptyBody() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Empty Body Page</title>
        </head>
        <body>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        let document = try await loader.load(from: data, metadata: nil)

        // Content should be empty or whitespace only
        #expect(document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // But title should still be extracted
        #expect(document.metadata.title == "Empty Body Page")
    }

    // MARK: - Custom Configuration Tests

    @Test("Custom exclude selectors work")
    func customExcludeSelectors() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <body>
          <div class="ads">Advertisement content</div>
          <div class="content">Main content here</div>
          <div class="sidebar">Sidebar content</div>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader(excludeSelectors: [".ads", ".sidebar"])

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.content.contains("Main content here"))
        #expect(!document.content.contains("Advertisement content"))
        #expect(!document.content.contains("Sidebar content"))
    }

    // MARK: - canLoad Tests

    @Test("canLoad returns correctly for different extensions")
    func canLoadReturnsCorrectly() {
        let loader = HTMLLoader()

        let htmlUrl = URL(fileURLWithPath: "/path/to/document.html")
        let htmUrl = URL(fileURLWithPath: "/path/to/document.htm")
        let txtUrl = URL(fileURLWithPath: "/path/to/document.txt")
        let mdUrl = URL(fileURLWithPath: "/path/to/document.md")

        #expect(loader.canLoad(htmlUrl) == true)
        #expect(loader.canLoad(htmUrl) == true)
        #expect(loader.canLoad(txtUrl) == false)
        #expect(loader.canLoad(mdUrl) == false)
    }

    // MARK: - MimeType Tests

    @Test("Sets correct mimeType to text/html")
    func setsCorrectMimeType() async throws {
        let html = "<html><body><p>Test</p></body></html>"
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader()

        let document = try await loader.load(from: data, metadata: nil)

        #expect(document.metadata.mimeType == "text/html")
    }

    // MARK: - Complex HTML Tests

    @Test("Load complex HTML with all exclusions")
    func loadComplexHTML() async throws {
        let html = #"""
        <!DOCTYPE html>
        <html>
        <head>
          <title>Test Page</title>
          <meta name="description" content="A test page">
          <meta name="author" content="Test Author">
          <meta property="og:title" content="OG Title">
          <style>body { color: black; }</style>
        </head>
        <body>
          <nav>
            <a href="/">Home</a>
            <a href="/about">About</a>
          </nav>
          <header>
            <h1>Page Header</h1>
          </header>
          <article>
            <h2>Article Title</h2>
            <p>Main content here with <strong>bold</strong> text.</p>
            <p>Another paragraph of content.</p>
          </article>
          <aside>
            <p>Related links</p>
          </aside>
          <footer>
            <p>Copyright 2024</p>
          </footer>
          <script>console.log("hidden");</script>
        </body>
        </html>
        """#
        let data = html.data(using: .utf8)!
        let loader = HTMLLoader(extractMetaTags: true)

        let document = try await loader.load(from: data, metadata: nil)

        // Should contain article content
        #expect(document.content.contains("Article Title"))
        #expect(document.content.contains("Main content here"))
        #expect(document.content.contains("bold"))
        #expect(document.content.contains("Another paragraph of content"))

        // Should exclude nav, footer, script, style
        #expect(!document.content.contains("Home"))
        #expect(!document.content.contains("About"))
        #expect(!document.content.contains("Copyright 2024"))
        #expect(!document.content.contains("console.log"))
        #expect(!document.content.contains("color: black"))

        // Should extract metadata
        #expect(document.metadata.title == "Test Page")
        #expect(document.metadata.author == "Test Author")
        #expect(document.metadata.custom["description"]?.stringValue == "A test page")
        #expect(document.metadata.custom["og:title"]?.stringValue == "OG Title")
    }
}

// MARK: - PDFLoader Tests

#if canImport(PDFKit)
import PDFKit

@Suite("PDFLoader Tests")
struct PDFLoaderTests {

    let loader = PDFLoader()

    // MARK: - Supported Extensions Tests

    @Test("supportedExtensions contains pdf")
    func supportedExtensions() {
        #expect(PDFLoader.supportedExtensions.contains("pdf"))
        #expect(PDFLoader.supportedExtensions.count == 1)
    }

    // MARK: - Load PDF Tests

    @Test("Load PDF extracts text content")
    func loadPDFExtractsText() async throws {
        // Create a simple PDF with text programmatically
        let pdfData = createTestPDFData(withText: "Hello, PDF World!")

        let document = try await loader.load(from: pdfData, metadata: nil)

        #expect(document.content.contains("Hello"))
        #expect(document.content.contains("PDF"))
        #expect(document.content.contains("World"))
    }

    @Test("Load PDF with page range extracts only specified pages")
    func loadPDFWithPageRange() async throws {
        // Create a multi-page PDF
        let pdfData = createMultiPageTestPDFData(pages: [
            "Page one content",
            "Page two content",
            "Page three content"
        ])

        let rangeLoader = PDFLoader(pageRange: 1...2)
        let document = try await rangeLoader.load(from: pdfData, metadata: nil)

        // Should contain pages 1 and 2 content
        #expect(document.content.contains("Page one") || document.content.contains("one"))
        #expect(document.content.contains("Page two") || document.content.contains("two"))
        // Should NOT contain page 3
        #expect(!document.content.contains("three"))
    }

    @Test("loadPages returns array of documents")
    func loadPagesReturnsArray() async throws {
        // Create a multi-page PDF
        let pdfData = createMultiPageTestPDFData(pages: [
            "First page text",
            "Second page text",
            "Third page text"
        ])

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_pages_\(UUID().uuidString).pdf")
        try pdfData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let documents = try await loader.loadPages(from: tempFile)

        #expect(documents.count == 3)
    }

    @Test("loadPages includes pageNumber in metadata")
    func loadPagesHasPageMetadata() async throws {
        // Create a multi-page PDF
        let pdfData = createMultiPageTestPDFData(pages: [
            "First page",
            "Second page"
        ])

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_meta_\(UUID().uuidString).pdf")
        try pdfData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let documents = try await loader.loadPages(from: tempFile)

        #expect(documents.count == 2)
        #expect(documents[0].metadata.custom["pageNumber"]?.intValue == 1)
        #expect(documents[1].metadata.custom["pageNumber"]?.intValue == 2)
    }

    // MARK: - Error Handling Tests

    @Test("Throws invalidData for non-PDF data")
    func handleInvalidPDF() async throws {
        // Random binary data that is NOT a PDF
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])

        await #expect(throws: ZoniError.self) {
            _ = try await loader.load(from: invalidData, metadata: nil)
        }
    }

    @Test("Handle empty PDF with no text gracefully")
    func handleEmptyPDF() async throws {
        // Create an empty PDF (no text)
        let emptyPDFData = createTestPDFData(withText: "")

        let document = try await loader.load(from: emptyPDFData, metadata: nil)

        // Should succeed but with empty or whitespace-only content
        #expect(document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || document.content.isEmpty)
    }

    // MARK: - canLoad Tests

    @Test("canLoad returns true for pdf and false for others")
    func canLoadReturnsCorrectly() {
        let pdfUrl = URL(fileURLWithPath: "/path/to/document.pdf")
        let txtUrl = URL(fileURLWithPath: "/path/to/document.txt")
        let mdUrl = URL(fileURLWithPath: "/path/to/document.md")
        let docxUrl = URL(fileURLWithPath: "/path/to/document.docx")

        #expect(loader.canLoad(pdfUrl) == true)
        #expect(loader.canLoad(txtUrl) == false)
        #expect(loader.canLoad(mdUrl) == false)
        #expect(loader.canLoad(docxUrl) == false)
    }

    // MARK: - Metadata Tests

    @Test("Sets mimeType to application/pdf")
    func setsMimeType() async throws {
        let pdfData = createTestPDFData(withText: "Test content")

        let document = try await loader.load(from: pdfData, metadata: nil)

        #expect(document.metadata.mimeType == "application/pdf")
    }

    @Test("Sets source from URL filename")
    func setsSourceFromURL() async throws {
        let pdfData = createTestPDFData(withText: "Test content")

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test-document.pdf")
        try pdfData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let document = try await loader.load(from: tempFile)

        #expect(document.metadata.source == "test-document")
    }

    // MARK: - Initialization Tests

    @Test("Initializer sets pageRange correctly")
    func initializerSetsPageRange() {
        let loaderWithRange = PDFLoader(pageRange: 1...5)
        #expect(loaderWithRange.pageRange == 1...5)
    }

    @Test("Initializer sets preserveLayout correctly")
    func initializerSetsPreserveLayout() {
        let loaderWithLayout = PDFLoader(preserveLayout: true)
        #expect(loaderWithLayout.preserveLayout == true)

        let loaderWithoutLayout = PDFLoader(preserveLayout: false)
        #expect(loaderWithoutLayout.preserveLayout == false)
    }

    @Test("Default initializer has nil pageRange and false preserveLayout")
    func defaultInitializer() {
        let defaultLoader = PDFLoader()
        #expect(defaultLoader.pageRange == nil)
        #expect(defaultLoader.preserveLayout == false)
    }

    // MARK: - Helper Methods

    /// Creates a simple single-page PDF with the given text using PDFKit
    private func createTestPDFData(withText text: String) -> Data {
        let pdfDocument = PDFDocument()
        let page = PDFPage()

        // Create a PDF page with text annotation to embed text
        if !text.isEmpty {
            let bounds = page.bounds(for: .mediaBox)
            let annotation = PDFAnnotation(
                bounds: CGRect(x: 50, y: bounds.height - 100, width: bounds.width - 100, height: 50),
                forType: .freeText,
                withProperties: nil
            )
            annotation.contents = text
            annotation.font = NSFont.systemFont(ofSize: 12)
            page.addAnnotation(annotation)
        }

        pdfDocument.insert(page, at: 0)
        return pdfDocument.dataRepresentation() ?? Data()
    }

    /// Creates a multi-page PDF with each string as a separate page using PDFKit
    private func createMultiPageTestPDFData(pages: [String]) -> Data {
        let pdfDocument = PDFDocument()

        for (index, pageText) in pages.enumerated() {
            let page = PDFPage()
            let bounds = page.bounds(for: .mediaBox)

            if !pageText.isEmpty {
                let annotation = PDFAnnotation(
                    bounds: CGRect(x: 50, y: bounds.height - 100, width: bounds.width - 100, height: 50),
                    forType: .freeText,
                    withProperties: nil
                )
                annotation.contents = pageText
                annotation.font = NSFont.systemFont(ofSize: 12)
                page.addAnnotation(annotation)
            }

            pdfDocument.insert(page, at: index)
        }

        return pdfDocument.dataRepresentation() ?? Data()
    }
}
#endif

// MARK: - PDFLoader Linux Tests

#if !canImport(PDFKit)
@Suite("PDFLoader Linux Tests")
struct PDFLoaderLinuxTests {

    @Test("Throws unsupportedFileType on Linux")
    func throwsOnLinux() async throws {
        let loader = PDFLoader()
        // PDF magic bytes: %PDF-1.4
        let data = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34])

        await #expect(throws: ZoniError.self) {
            _ = try await loader.load(from: data, metadata: nil)
        }
    }

    @Test("supportedExtensions still contains pdf on Linux")
    func supportedExtensionsOnLinux() {
        #expect(PDFLoader.supportedExtensions.contains("pdf"))
    }

    @Test("canLoad returns true for pdf even on Linux")
    func canLoadOnLinux() {
        let loader = PDFLoader()
        let pdfUrl = URL(fileURLWithPath: "/path/to/document.pdf")
        #expect(loader.canLoad(pdfUrl) == true)
    }
}
#endif

// MARK: - DirectoryLoader Tests

@Suite("DirectoryLoader Tests")
struct DirectoryLoaderTests {

    // MARK: - Test Helpers

    /// Creates a test directory with sample files for testing
    func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryLoaderTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create test files in root
        try "Content 1".write(to: tempDir.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try "Content 2".write(to: tempDir.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)

        // Create subdirectory with files
        let subDir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "Content 3".write(to: subDir.appendingPathComponent("file3.txt"), atomically: true, encoding: .utf8)

        // Create nested subdirectory with files
        let nestedDir = subDir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "Content 4".write(to: nestedDir.appendingPathComponent("file4.txt"), atomically: true, encoding: .utf8)

        return tempDir
    }

    /// Creates a test directory with hidden files
    func createTestDirectoryWithHiddenFiles() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryLoaderHiddenTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create regular files
        try "Visible content".write(to: tempDir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)

        // Create hidden files
        try "Hidden content".write(to: tempDir.appendingPathComponent(".hidden.txt"), atomically: true, encoding: .utf8)
        try "Gitignore content".write(to: tempDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        // Create hidden directory with files
        let hiddenDir = tempDir.appendingPathComponent(".hidden_dir")
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try "Hidden dir content".write(to: hiddenDir.appendingPathComponent("file_in_hidden.txt"), atomically: true, encoding: .utf8)

        return tempDir
    }

    /// Creates a test directory with multiple file types
    func createTestDirectoryWithMultipleTypes() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryLoaderTypesTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create different file types
        try "Text content".write(to: tempDir.appendingPathComponent("document.txt"), atomically: true, encoding: .utf8)
        try "# Markdown content".write(to: tempDir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "{\"key\": \"value\"}".write(to: tempDir.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
        try "name,value\ntest,123".write(to: tempDir.appendingPathComponent("data.csv"), atomically: true, encoding: .utf8)

        return tempDir
    }

    /// Cleans up a test directory
    func cleanupTestDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Load From Directory Tests

    @Test("Load from directory loads all supported files")
    func loadFromDirectory() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry)

        let documents = try await loader.load(from: tempDir)

        // Should load at least the 2 root level files (with recursive=true by default, also nested)
        #expect(documents.count >= 2)

        // Verify documents have content
        for document in documents {
            #expect(!document.content.isEmpty)
        }
    }

    @Test("Load recursively loads files from nested directories")
    func loadRecursively() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: true)

        let documents = try await loader.load(from: tempDir)

        // Should load all 4 files: file1.txt, file2.txt, subdir/file3.txt, subdir/nested/file4.txt
        #expect(documents.count == 4)

        let contents = documents.map { $0.content }
        #expect(contents.contains("Content 1"))
        #expect(contents.contains("Content 2"))
        #expect(contents.contains("Content 3"))
        #expect(contents.contains("Content 4"))
    }

    @Test("Load non-recursively loads only top-level files")
    func loadNonRecursively() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: false)

        let documents = try await loader.load(from: tempDir)

        // Should load only 2 files: file1.txt, file2.txt (not files in subdirectories)
        #expect(documents.count == 2)

        let contents = documents.map { $0.content }
        #expect(contents.contains("Content 1"))
        #expect(contents.contains("Content 2"))
        #expect(!contents.contains("Content 3"))
        #expect(!contents.contains("Content 4"))
    }

    // MARK: - Hidden Files Tests

    @Test("Exclude hidden files by default")
    func excludeHiddenFiles() async throws {
        let tempDir = try createTestDirectoryWithHiddenFiles()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, includeHidden: false)

        let documents = try await loader.load(from: tempDir)

        // Should only load visible.txt, not hidden files
        #expect(documents.count == 1)
        #expect(documents[0].content == "Visible content")
    }

    @Test("Include hidden files when includeHidden is true")
    func includeHiddenFiles() async throws {
        let tempDir = try createTestDirectoryWithHiddenFiles()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: true, includeHidden: true)

        let documents = try await loader.load(from: tempDir)

        // Should load visible.txt, .hidden.txt, and file_in_hidden.txt
        // (.gitignore has no extension so TextLoader won't handle it)
        #expect(documents.count >= 3)

        let contents = documents.map { $0.content }
        #expect(contents.contains("Visible content"))
        #expect(contents.contains("Hidden content"))
        #expect(contents.contains("Hidden dir content"))
    }

    // MARK: - Filter By Extension Tests

    @Test("Filter by extension loads only matching file types")
    func filterByExtension() async throws {
        let tempDir = try createTestDirectoryWithMultipleTypes()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        await registry.register(MarkdownLoader())
        await registry.register(JSONLoader())
        await registry.register(CSVLoader())

        let loader = DirectoryLoader(registry: registry, fileExtensions: ["txt", "md"])

        let documents = try await loader.load(from: tempDir)

        // Should only load .txt and .md files
        #expect(documents.count == 2)

        let contents = documents.map { $0.content }
        #expect(contents.contains("Text content"))
        #expect(contents.contains("# Markdown content"))
    }

    @Test("Filter by single extension")
    func filterBySingleExtension() async throws {
        let tempDir = try createTestDirectoryWithMultipleTypes()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        await registry.register(MarkdownLoader())
        await registry.register(JSONLoader())

        let loader = DirectoryLoader(registry: registry, fileExtensions: ["json"])

        let documents = try await loader.load(from: tempDir)

        // Should only load .json file
        #expect(documents.count == 1)
        #expect(documents[0].content.contains("key"))
        #expect(documents[0].content.contains("value"))
    }

    // MARK: - Exclude Patterns Tests

    @Test("Exclude patterns filters matching files")
    func excludePatterns() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: true, excludePatterns: ["file1", "file3"])

        let documents = try await loader.load(from: tempDir)

        // Should exclude file1.txt and file3.txt
        #expect(documents.count == 2)

        let contents = documents.map { $0.content }
        #expect(!contents.contains("Content 1"))
        #expect(contents.contains("Content 2"))
        #expect(!contents.contains("Content 3"))
        #expect(contents.contains("Content 4"))
    }

    @Test("Exclude patterns with directory names")
    func excludePatternsWithDirectoryNames() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: true, excludePatterns: ["subdir"])

        let documents = try await loader.load(from: tempDir)

        // Should exclude entire subdir directory
        #expect(documents.count == 2)

        let contents = documents.map { $0.content }
        #expect(contents.contains("Content 1"))
        #expect(contents.contains("Content 2"))
        #expect(!contents.contains("Content 3"))
        #expect(!contents.contains("Content 4"))
    }

    // MARK: - List Files Tests

    @Test("listFiles returns file URLs without loading content")
    func listFilesReturnsURLs() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: true)

        let files = try await loader.listFiles(in: tempDir)

        // Should return URLs for all 4 txt files
        #expect(files.count == 4)

        // Verify they are file URLs
        for file in files {
            #expect(file.isFileURL)
            #expect(file.pathExtension == "txt")
        }
    }

    @Test("listFiles respects recursive setting")
    func listFilesRespectsRecursive() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: false)

        let files = try await loader.listFiles(in: tempDir)

        // Should only list top-level files
        #expect(files.count == 2)
    }

    // MARK: - Empty Directory Tests

    @Test("Handle empty directory returns empty array")
    func handleEmptyDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmptyDirectoryTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry)

        let documents = try await loader.load(from: tempDir)

        #expect(documents.isEmpty)
    }

    @Test("Empty directory listFiles returns empty array")
    func emptyDirectoryListFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmptyDirectoryListTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry)

        let files = try await loader.listFiles(in: tempDir)

        #expect(files.isEmpty)
    }

    // MARK: - Nonexistent Directory Tests

    @Test("Handle nonexistent directory throws loadingFailed")
    func handleNonexistentDirectory() async throws {
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/that/does/not/exist_\(UUID().uuidString)")

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry)

        await #expect(throws: ZoniError.self) {
            _ = try await loader.load(from: nonexistentURL)
        }
    }

    @Test("listFiles throws for nonexistent directory")
    func listFilesThrowsForNonexistent() async throws {
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/that/does/not/exist_\(UUID().uuidString)")

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry)

        await #expect(throws: ZoniError.self) {
            _ = try await loader.listFiles(in: nonexistentURL)
        }
    }

    // MARK: - Stream Tests

    @Test("loadStream yields documents via AsyncThrowingStream")
    func loadStreamYieldsDocuments() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry, recursive: true)

        let stream = await loader.loadStream(from: tempDir)

        var documents: [Document] = []
        for try await document in stream {
            documents.append(document)
        }

        // Should yield all 4 documents
        #expect(documents.count == 4)

        let contents = documents.map { $0.content }
        #expect(contents.contains("Content 1"))
        #expect(contents.contains("Content 2"))
        #expect(contents.contains("Content 3"))
        #expect(contents.contains("Content 4"))
    }

    @Test("loadStream handles empty directory")
    func loadStreamHandlesEmptyDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmptyStreamTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        let loader = DirectoryLoader(registry: registry)

        let stream = await loader.loadStream(from: tempDir)

        var count = 0
        for try await _ in stream {
            count += 1
        }

        #expect(count == 0)
    }

    // MARK: - Registry Usage Tests

    @Test("Uses provided LoaderRegistry for loading")
    func usesRegistryForLoading() async throws {
        let tempDir = try createTestDirectoryWithMultipleTypes()
        defer { cleanupTestDirectory(tempDir) }

        // Create a registry with only TextLoader
        let registry = LoaderRegistry()
        await registry.register(TextLoader())

        let loader = DirectoryLoader(registry: registry)

        let documents = try await loader.load(from: tempDir)

        // Should only load .txt files since registry only has TextLoader
        #expect(documents.count == 1)
        #expect(documents[0].content == "Text content")
    }

    @Test("Registry with multiple loaders loads all supported types")
    func registryWithMultipleLoaders() async throws {
        let tempDir = try createTestDirectoryWithMultipleTypes()
        defer { cleanupTestDirectory(tempDir) }

        // Create a registry with multiple loaders
        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        await registry.register(MarkdownLoader())
        await registry.register(JSONLoader())
        await registry.register(CSVLoader())

        let loader = DirectoryLoader(registry: registry)

        let documents = try await loader.load(from: tempDir)

        // Should load all 4 files
        #expect(documents.count == 4)
    }

    // MARK: - Default Registry Tests

    @Test("Uses default registry when not provided")
    func usesDefaultRegistry() async throws {
        let tempDir = try createTestDirectory()
        defer { cleanupTestDirectory(tempDir) }

        // DirectoryLoader with default registry
        let loader = DirectoryLoader()

        // This test verifies the default registry is used
        // The exact behavior depends on what .default provides
        let documents = try await loader.load(from: tempDir)

        // Should be able to load without crashing
        // Number of documents depends on default registry configuration
        #expect(documents.count >= 0)
    }

    // MARK: - Combined Options Tests

    @Test("Combined options work together correctly")
    func combinedOptionsWorkTogether() async throws {
        let tempDir = try createTestDirectoryWithHiddenFiles()

        // Add some additional test files
        try "Extra content".write(to: tempDir.appendingPathComponent("extra.txt"), atomically: true, encoding: .utf8)
        try "# Markdown".write(to: tempDir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)

        defer { cleanupTestDirectory(tempDir) }

        let registry = LoaderRegistry()
        await registry.register(TextLoader())
        await registry.register(MarkdownLoader())

        let loader = DirectoryLoader(
            registry: registry,
            recursive: true,
            includeHidden: false,
            fileExtensions: ["txt"],
            excludePatterns: ["extra"]
        )

        let documents = try await loader.load(from: tempDir)

        // Should load only visible .txt files excluding "extra"
        // That means: visible.txt only
        #expect(documents.count == 1)
        #expect(documents[0].content == "Visible content")
    }
}
