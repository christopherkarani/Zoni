// iOSDocumentQA - Example iOS app demonstrating Zoni RAG capabilities
//
// DocumentPickerView.swift - UIDocumentPickerViewController wrapper for SwiftUI

import SwiftUI
import UniformTypeIdentifiers
import PDFKit

#if os(iOS)
import UIKit

// MARK: - DocumentPickerView

/// A SwiftUI wrapper for UIDocumentPickerViewController.
///
/// `DocumentPickerView` allows users to select PDF and text files from
/// the device's file system for ingestion into the RAG knowledge base.
///
/// ## Supported File Types
/// - PDF documents (.pdf)
/// - Plain text files (.txt)
/// - Markdown files (.md)
///
/// ## Example Usage
/// ```swift
/// @State private var showPicker = false
///
/// Button("Add Document") {
///     showPicker = true
/// }
/// .sheet(isPresented: $showPicker) {
///     DocumentPickerView { result in
///         switch result {
///         case .success(let document):
///             // Process the document
///         case .failure(let error):
///             // Handle error
///         }
///     }
/// }
/// ```
struct DocumentPickerView: UIViewControllerRepresentable {

    // MARK: - Types

    /// Represents a selected document with its content and metadata.
    struct SelectedDocument {
        /// The text content of the document.
        let content: String

        /// The filename of the document.
        let filename: String

        /// The file URL (for reference).
        let url: URL
    }

    // MARK: - Properties

    /// Callback invoked when document selection completes.
    let onSelection: (Result<SelectedDocument, Error>) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .pdf,
            .plainText,
            UTType(filenameExtension: "md") ?? .plainText
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelection: (Result<SelectedDocument, Error>) -> Void

        init(onSelection: @escaping (Result<SelectedDocument, Error>) -> Void) {
            self.onSelection = onSelection
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onSelection(.failure(DocumentPickerError.noDocumentSelected))
                return
            }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                onSelection(.failure(DocumentPickerError.accessDenied))
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                let content = try loadDocumentContent(from: url)
                let document = SelectedDocument(
                    content: content,
                    filename: url.lastPathComponent,
                    url: url
                )
                onSelection(.success(document))
            } catch {
                onSelection(.failure(error))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onSelection(.failure(DocumentPickerError.cancelled))
        }

        // MARK: - Private Methods

        private func loadDocumentContent(from url: URL) throws -> String {
            let fileExtension = url.pathExtension.lowercased()

            switch fileExtension {
            case "pdf":
                return try loadPDFContent(from: url)
            case "txt", "md", "markdown":
                return try String(contentsOf: url, encoding: .utf8)
            default:
                // Try to load as plain text
                return try String(contentsOf: url, encoding: .utf8)
            }
        }

        private func loadPDFContent(from url: URL) throws -> String {
            guard let pdfDocument = PDFDocument(url: url) else {
                throw DocumentPickerError.pdfLoadFailed
            }

            var fullText = ""
            let pageCount = pdfDocument.pageCount

            for pageIndex in 0..<pageCount {
                guard let page = pdfDocument.page(at: pageIndex) else { continue }

                if let pageText = page.string {
                    fullText += pageText
                    if pageIndex < pageCount - 1 {
                        fullText += "\n\n"
                    }
                }
            }

            if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DocumentPickerError.emptyDocument
            }

            return fullText
        }
    }
}

// MARK: - DocumentPickerError

/// Errors that can occur during document selection.
enum DocumentPickerError: LocalizedError {
    case noDocumentSelected
    case accessDenied
    case pdfLoadFailed
    case emptyDocument
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDocumentSelected:
            return "No document was selected."
        case .accessDenied:
            return "Access to the selected file was denied."
        case .pdfLoadFailed:
            return "Failed to load the PDF document."
        case .emptyDocument:
            return "The selected document appears to be empty."
        case .cancelled:
            return "Document selection was cancelled."
        }
    }
}

#else

// MARK: - macOS Fallback

import AppKit

/// macOS implementation using NSOpenPanel.
struct DocumentPickerView: View {
    let onSelection: (Result<SelectedDocument, Error>) -> Void

    struct SelectedDocument {
        let content: String
        let filename: String
        let url: URL
    }

    var body: some View {
        Button("Select Document") {
            selectDocument()
        }
        .buttonStyle(.borderedProminent)
    }

    private func selectDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try loadContent(from: url)
                let document = SelectedDocument(
                    content: content,
                    filename: url.lastPathComponent,
                    url: url
                )
                onSelection(.success(document))
            } catch {
                onSelection(.failure(error))
            }
        }
    }

    private func loadContent(from url: URL) throws -> String {
        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "pdf":
            guard let pdfDocument = PDFDocument(url: url) else {
                throw DocumentPickerError.pdfLoadFailed
            }
            var text = ""
            for i in 0..<pdfDocument.pageCount {
                if let page = pdfDocument.page(at: i), let pageText = page.string {
                    text += pageText + "\n\n"
                }
            }
            return text
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }
}

enum DocumentPickerError: LocalizedError {
    case pdfLoadFailed

    var errorDescription: String? {
        switch self {
        case .pdfLoadFailed:
            return "Failed to load the PDF document."
        }
    }
}

#endif
