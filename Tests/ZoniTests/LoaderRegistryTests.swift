// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// LoaderRegistryTests.swift - Tests for LoaderRegistry

import Testing
import Foundation
@testable import Zoni

// MARK: - LoaderRegistry Tests

@Suite("LoaderRegistry Tests")
struct LoaderRegistryTests {

    // MARK: - Registration Tests

    @Suite("Registration")
    struct RegistrationTests {

        @Test("Register loader for specific extensions")
        func registerLoaderForExtensions() async {
            let registry = LoaderRegistry()
            let loader = TextLoader()

            await registry.register(loader, for: ["txt", "text"])

            let extensions = await registry.registeredExtensions()
            #expect(extensions.contains("txt"))
            #expect(extensions.contains("text"))
        }

        @Test("Register loader using its supportedExtensions")
        func registerLoaderUsingSupportedExtensions() async {
            let registry = LoaderRegistry()
            let loader = MarkdownLoader()

            // Register using the loader's declared supportedExtensions
            await registry.register(loader)

            let extensions = await registry.registeredExtensions()
            #expect(extensions.contains("md"))
            #expect(extensions.contains("markdown"))
        }

        @Test("Register multiple loaders")
        func registerMultipleLoaders() async {
            let registry = LoaderRegistry()

            await registry.register(TextLoader())
            await registry.register(MarkdownLoader())
            await registry.register(JSONLoader())

            let extensions = await registry.registeredExtensions()
            #expect(extensions.contains("txt"))
            #expect(extensions.contains("text"))
            #expect(extensions.contains("md"))
            #expect(extensions.contains("markdown"))
            #expect(extensions.contains("json"))
        }

        @Test("Override existing loader for extension")
        func overrideExistingLoader() async {
            let registry = LoaderRegistry()
            let textLoader = TextLoader()
            let markdownLoader = MarkdownLoader()

            // Register TextLoader for "md"
            await registry.register(textLoader, for: ["md"])

            // Override with MarkdownLoader
            await registry.register(markdownLoader, for: ["md"])

            // The markdown loader should now handle "md"
            let loader = await registry.loader(for: URL(fileURLWithPath: "/test/file.md"))
            #expect(loader is MarkdownLoader)
        }
    }

    // MARK: - Loader Retrieval Tests

    @Suite("Loader Retrieval")
    struct LoaderRetrievalTests {

        @Test("Get loader for URL by extension")
        func loaderForURL() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())
            await registry.register(MarkdownLoader())

            let textURL = URL(fileURLWithPath: "/path/to/file.txt")
            let mdURL = URL(fileURLWithPath: "/path/to/file.md")

            let textLoader = await registry.loader(for: textURL)
            let mdLoader = await registry.loader(for: mdURL)

            #expect(textLoader is TextLoader)
            #expect(mdLoader is MarkdownLoader)
        }

        @Test("Get loader for unknown extension returns nil")
        func loaderForUnknownExtension() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())

            let unknownURL = URL(fileURLWithPath: "/path/to/file.xyz")
            let loader = await registry.loader(for: unknownURL)

            #expect(loader == nil)
        }

        @Test("Get loader for URL without extension returns nil")
        func loaderForURLWithoutExtension() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())

            let noExtURL = URL(fileURLWithPath: "/path/to/file")
            let loader = await registry.loader(for: noExtURL)

            #expect(loader == nil)
        }
    }

    // MARK: - canLoad Tests

    @Suite("Can Load")
    struct CanLoadTests {

        @Test("Can load URL with registered extension")
        func canLoadRegisteredExtension() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())

            let url = URL(fileURLWithPath: "/path/to/file.txt")
            let result = await registry.canLoad(url)

            #expect(result == true)
        }

        @Test("Cannot load URL with unknown extension")
        func cannotLoadUnknownExtension() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())

            let url = URL(fileURLWithPath: "/path/to/file.unknown")
            let result = await registry.canLoad(url)

            #expect(result == false)
        }

        @Test("Cannot load URL without extension")
        func cannotLoadURLWithoutExtension() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())

            let url = URL(fileURLWithPath: "/path/to/file")
            let result = await registry.canLoad(url)

            #expect(result == false)
        }
    }

    // MARK: - Case Insensitivity Tests

    @Suite("Case Insensitivity")
    struct CaseInsensitivityTests {

        @Test("Extensions are case-insensitive when registering")
        func caseInsensitiveRegistration() async {
            let registry = LoaderRegistry()
            let loader = TextLoader()

            await registry.register(loader, for: ["TXT", "TEXT"])

            let extensions = await registry.registeredExtensions()
            #expect(extensions.contains("txt"))
            #expect(extensions.contains("text"))
            // Should be stored as lowercase
            #expect(!extensions.contains("TXT"))
            #expect(!extensions.contains("TEXT"))
        }

        @Test("URL lookup is case-insensitive")
        func caseInsensitiveLookup() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())

            // The URL has uppercase extension
            let upperURL = URL(fileURLWithPath: "/path/to/file.TXT")
            let mixedURL = URL(fileURLWithPath: "/path/to/file.TxT")

            let upperLoader = await registry.loader(for: upperURL)
            let mixedLoader = await registry.loader(for: mixedURL)

            #expect(upperLoader is TextLoader)
            #expect(mixedLoader is TextLoader)
        }

        @Test("canLoad is case-insensitive")
        func caseInsensitiveCanLoad() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())

            let upperURL = URL(fileURLWithPath: "/path/to/file.TXT")
            let mixedURL = URL(fileURLWithPath: "/path/to/file.TxT")
            let lowerURL = URL(fileURLWithPath: "/path/to/file.txt")

            #expect(await registry.canLoad(upperURL) == true)
            #expect(await registry.canLoad(mixedURL) == true)
            #expect(await registry.canLoad(lowerURL) == true)
        }
    }

    // MARK: - Default Registry Tests

    @Suite("Default Registry")
    struct DefaultRegistryTests {

        @Test("Default registry has TextLoader")
        func defaultHasTextLoader() async {
            let registry = await LoaderRegistry.defaultRegistry()

            let txtURL = URL(fileURLWithPath: "/path/to/file.txt")
            let textURL = URL(fileURLWithPath: "/path/to/file.text")

            #expect(await registry.canLoad(txtURL) == true)
            #expect(await registry.canLoad(textURL) == true)
        }

        @Test("Default registry has MarkdownLoader")
        func defaultHasMarkdownLoader() async {
            let registry = await LoaderRegistry.defaultRegistry()

            let mdURL = URL(fileURLWithPath: "/path/to/file.md")
            let markdownURL = URL(fileURLWithPath: "/path/to/file.markdown")

            #expect(await registry.canLoad(mdURL) == true)
            #expect(await registry.canLoad(markdownURL) == true)
        }

        @Test("Default registry has HTMLLoader")
        func defaultHasHTMLLoader() async {
            let registry = await LoaderRegistry.defaultRegistry()

            let htmlURL = URL(fileURLWithPath: "/path/to/file.html")
            let htmURL = URL(fileURLWithPath: "/path/to/file.htm")

            #expect(await registry.canLoad(htmlURL) == true)
            #expect(await registry.canLoad(htmURL) == true)
        }

        @Test("Default registry has JSONLoader")
        func defaultHasJSONLoader() async {
            let registry = await LoaderRegistry.defaultRegistry()

            let jsonURL = URL(fileURLWithPath: "/path/to/file.json")

            #expect(await registry.canLoad(jsonURL) == true)
        }

        @Test("Default registry has CSVLoader")
        func defaultHasCSVLoader() async {
            let registry = await LoaderRegistry.defaultRegistry()

            let csvURL = URL(fileURLWithPath: "/path/to/file.csv")
            let tsvURL = URL(fileURLWithPath: "/path/to/file.tsv")

            #expect(await registry.canLoad(csvURL) == true)
            #expect(await registry.canLoad(tsvURL) == true)
        }

        @Test("Default registry has PDFLoader")
        func defaultHasPDFLoader() async {
            let registry = await LoaderRegistry.defaultRegistry()

            let pdfURL = URL(fileURLWithPath: "/path/to/file.pdf")

            #expect(await registry.canLoad(pdfURL) == true)
        }

        @Test("Default registry has all built-in loaders")
        func defaultHasAllLoaders() async {
            let registry = await LoaderRegistry.defaultRegistry()
            let extensions = await registry.registeredExtensions()

            // TextLoader extensions
            #expect(extensions.contains("txt"))
            #expect(extensions.contains("text"))

            // MarkdownLoader extensions
            #expect(extensions.contains("md"))
            #expect(extensions.contains("markdown"))

            // HTMLLoader extensions
            #expect(extensions.contains("html"))
            #expect(extensions.contains("htm"))

            // JSONLoader extensions
            #expect(extensions.contains("json"))

            // CSVLoader extensions
            #expect(extensions.contains("csv"))
            #expect(extensions.contains("tsv"))

            // PDFLoader extensions
            #expect(extensions.contains("pdf"))
        }
    }

    // MARK: - Registered Extensions Tests

    @Suite("Registered Extensions")
    struct RegisteredExtensionsTests {

        @Test("Empty registry has no extensions")
        func emptyRegistryHasNoExtensions() async {
            let registry = LoaderRegistry()
            let extensions = await registry.registeredExtensions()

            #expect(extensions.isEmpty)
        }

        @Test("registeredExtensions returns all registered extensions")
        func registeredExtensionsReturnsAll() async {
            let registry = LoaderRegistry()
            await registry.register(TextLoader())
            await registry.register(JSONLoader())

            let extensions = await registry.registeredExtensions()

            #expect(extensions.count == 3) // txt, text, json
            #expect(extensions.contains("txt"))
            #expect(extensions.contains("text"))
            #expect(extensions.contains("json"))
        }
    }
}
