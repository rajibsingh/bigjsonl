import SwiftUI
import BigJSONLCore

struct ContentView: View {
    let document: BigJSONLDocument
    @State private var viewModel: DocumentViewModel
    @State private var scrollPosition: ScrollPosition = .init()
    @State private var selectedLine: UInt64?

    init(document: BigJSONLDocument) {
        self.document = document
        self._viewModel = State(initialValue: DocumentViewModel(document: document))
    }

    var body: some View {
        NavigationSplitView {
            // Main content: scrollable line list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                    } else if viewModel.isLoading {
                        ProgressView("Opening file...")
                            .padding()
                    } else if viewModel.visibleLines.isEmpty {
                        Text("No lines to display")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(viewModel.visibleLines, id: \.lineNumber) { lineInfo in
                            LineView(
                                lineInfo: lineInfo,
                                isSelected: selectedLine == lineInfo.lineNumber
                            )
                            .onTapGesture {
                                selectedLine = lineInfo.lineNumber
                            }
                            Divider()
                                .opacity(0.3)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.top)
            .navigationTitle(document.url.lastPathComponent)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    searchToolbarItem
                }
            }
        } detail: {
            // Inspector sidebar
            if let line = selectedLine {
                LineInspectorView(
                    viewModel: viewModel,
                    lineNumber: line
                )
                .frame(minWidth: 200, idealWidth: 250)
            } else {
                Text("Select a line to inspect")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .onAppear {
            viewModel.openFile()
        }
    }

    // MARK: - Search toolbar

    private var searchToolbarItem: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search pattern...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .frame(width: 150)
                .onSubmit {
                    viewModel.performSearch()
                }
            if viewModel.isSearching {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3))
        .clipShape(.rect(cornerRadius: 6))
    }
}

// MARK: - Line Inspector

struct LineInspectorView: View {
    let viewModel: DocumentViewModel
    let lineNumber: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Line \(lineNumber)")
                .font(.headline)

            if let lineInfo = viewModel.visibleLines.first(where: { $0.lineNumber == lineNumber }) {
                Group {
                    LabeledContent("Offset") {
                        Text("\(lineInfo.byteOffset) bytes")
                            .font(.caption.monospaced())
                    }
                    LabeledContent("Length") {
                        Text("\(lineInfo.byteLength) bytes")
                            .font(.caption.monospaced())
                    }
                    LabeledContent("Status") {
                        if lineInfo.isValidJSON {
                            Label("Valid JSON", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Invalid JSON", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    Divider()

                    Text("Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(lineInfo.text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(6)
                    .background(.quaternary.opacity(0.2))
                    .clipShape(.rect(cornerRadius: 4))
                }
            } else {
                Text("Line not loaded in viewport.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
        .inspectorColumnWidth(min: 200, ideal: 250, max: 400)
    }
}
