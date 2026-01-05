// iOSDocumentQA - Example iOS app demonstrating Zoni RAG capabilities
//
// ContentView.swift - Main UI for document Q&A

import SwiftUI
import Zoni

// MARK: - ContentView

/// The main content view for the iOSDocumentQA app.
///
/// This view provides:
/// - Document picker to add PDFs and text files
/// - Text field for entering questions
/// - Results display area showing answers
/// - Loading indicators during operations
/// - Document count and status display
struct ContentView: View {

    // MARK: - Environment

    @Environment(RAGService.self) private var ragService

    // MARK: - State

    @State private var queryText: String = ""
    @State private var answerText: String = ""
    @State private var showDocumentPicker: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var searchResults: [RetrievalResult] = []
    @State private var showSearchResults: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                statusBar

                Divider()

                // Main content
                ScrollView {
                    VStack(spacing: 20) {
                        // Query section
                        querySection

                        // Answer section
                        if !answerText.isEmpty {
                            answerSection
                        }

                        // Search results section
                        if showSearchResults && !searchResults.isEmpty {
                            searchResultsSection
                        }

                        // Documents section
                        documentsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Document Q&A")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Add Document", systemImage: "doc.badge.plus")
                    }
                    .disabled(!ragService.isReady)
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) {
                        Task {
                            await ragService.clearKnowledgeBase()
                            answerText = ""
                            searchResults = []
                        }
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(ragService.documentCount == 0)
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                documentPickerSheet
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack {
            if ragService.isReady {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Initializing...")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                Text("\(ragService.documentCount)")
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up")
                Text("\(ragService.chunkCount)")
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask a Question")
                .font(.headline)

            HStack {
                TextField("What would you like to know?", text: $queryText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(ragService.isQuerying || !ragService.isReady)

                Button {
                    submitQuery()
                } label: {
                    if ragService.isQuerying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(queryText.isEmpty || ragService.isQuerying || !ragService.isReady)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            if ragService.documentCount == 0 {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Add documents to start asking questions")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Answer")
                    .font(.headline)

                Spacer()

                Button {
                    showSearchResults.toggle()
                } label: {
                    Label(
                        showSearchResults ? "Hide Sources" : "Show Sources",
                        systemImage: showSearchResults ? "eye.slash" : "eye"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(answerText)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources (\(searchResults.count))")
                .font(.headline)

            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Source \(index + 1)")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Spacer()

                        Text(String(format: "%.1f%% match", result.score * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(result.chunk.content)
                        .font(.caption)
                        .lineLimit(4)
                        .foregroundStyle(.secondary)

                    if let source = result.chunk.metadata.source {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(source)
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Knowledge Base")
                .font(.headline)

            if ragService.documentTitles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("No documents yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Add PDF or text files to build your knowledge base")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Add Document", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ragService.isReady)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(ragService.documentTitles, id: \.self) { title in
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.blue)
                        Text(title)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var documentPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Select a Document")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Choose a PDF or text file to add to your knowledge base")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                DocumentPickerView { result in
                    showDocumentPicker = false
                    handleDocumentSelection(result)
                }
                #if os(iOS)
                .frame(height: 300)
                #endif
            }
            .padding()
            .navigationTitle("Add Document")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDocumentPicker = false
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    // MARK: - Actions

    private func submitQuery() {
        guard !queryText.isEmpty else { return }

        let query = queryText

        Task {
            do {
                // First, get search results for display
                searchResults = try await ragService.search(query, limit: 3)

                // Then get the full answer
                answerText = try await ragService.query(query)
                queryText = ""
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func handleDocumentSelection(_ result: Result<DocumentPickerView.SelectedDocument, Error>) {
        switch result {
        case .success(let document):
            Task {
                do {
                    try await ragService.ingestDocument(
                        content: document.content,
                        title: document.filename,
                        source: document.filename
                    )
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }

        case .failure(let error):
            // Ignore cancellation errors
            if case DocumentPickerError.cancelled = error {
                return
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(RAGService())
}
