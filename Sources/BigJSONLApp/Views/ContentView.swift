import SwiftUI
import BigJSONLCore

struct ContentView: View {
    let document: BigJSONLDocument
    let viewModel: DocumentViewModel
    let searchQuery: String
    let onClearSearch: () -> Void
    @State private var scrollPosition: ScrollPosition = .init()
    @State private var selectedLine: UInt64?

    init(document: BigJSONLDocument, viewModel: DocumentViewModel, searchQuery: String, onClearSearch: @escaping () -> Void) {
        self.document = document
        self.viewModel = viewModel
        self.searchQuery = searchQuery
        self.onClearSearch = onClearSearch
    }

    var body: some View {
        NavigationSplitView {
            // Left pane: search results when active, otherwise scrollable line list
            Group {
                if !viewModel.searchResults.isEmpty {
                    searchResultsPane
                } else {
                    lineListPane
                }
            }
            .navigationTitle(document.url.lastPathComponent)
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
            prepareSelectionIfPossible(viewModel.visibleLines)
        }
        .onDisappear {
            viewModel.cancelSearch()
            viewModel.cancelInspectorPreparation()
        }
        .onChange(of: viewModel.visibleLines.map(\.lineNumber)) { _, _ in
            prepareSelectionIfPossible(viewModel.visibleLines)
        }
        .onChange(of: viewModel.requestedScrollLine) { _, line in
            if let line {
                scrollPosition.scrollTo(id: line, anchor: .center)
                viewModel.requestedScrollLine = nil
            }
        }
    }

    private func prepareSelectionIfPossible(_ lines: [LineInfo]) {
        if selectedLine == nil {
            selectedLine = lines.first?.lineNumber
        }

        guard let selectedLine,
              let lineInfo = lines.first(where: { $0.lineNumber == selectedLine }),
              viewModel.inspectorLineNumber != selectedLine else {
            return
        }

        viewModel.prepareInspector(for: lineInfo)
    }

    /// Called by BigJSONLApp when the user submits a search query.
    func performSearch() {
        viewModel.performSearch(query: searchQuery)
    }

    /// Called by BigJSONLApp when the user clears the search.
    func clearSearch() {
        viewModel.clearSearch()
        selectedLine = nil
    }

    // MARK: - Line list pane

    private var lineListPane: some View {
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
                        Button {
                            selectedLine = lineInfo.lineNumber
                            viewModel.prepareInspector(for: lineInfo)
                        } label: {
                            LineView(
                                lineInfo: lineInfo,
                                isSelected: selectedLine == lineInfo.lineNumber
                            )
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(lineInfo.lineNumber)
                        Divider()
                            .opacity(0.3)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.top)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        viewModel.updateViewportHeight(proxy.size.height)
                    }
                    .onChange(of: proxy.size.height) { _, height in
                        viewModel.updateViewportHeight(height)
                    }
            }
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            guard newPhase == .idle, oldPhase.isScrolling else { return }
            loadWindowIfNeeded(for: context.geometry)
        }
    }

    // MARK: - Search results pane

    private var searchResultsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.searchResults.count) result\(viewModel.searchResults.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.searchResults.count >= 500 {
                    Text("capped at 500")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.2))

            Divider()

            SearchResultsView(
                results: viewModel.searchResults,
                query: searchQuery,
                selectedLine: selectedLine
            ) { result in
                selectedLine = result.lineNumber
                viewModel.scrollTo(line: result.lineNumber)
                if let lineInfo = viewModel.visibleLines.first(where: { $0.lineNumber == result.lineNumber }) {
                    viewModel.prepareInspector(for: lineInfo)
                }
            }
        }
    }


    private func loadWindowIfNeeded(for geometry: ScrollGeometry) {
        let threshold: CGFloat = 24
        let distanceFromBottom = geometry.contentSize.height - geometry.visibleRect.maxY

        if distanceFromBottom <= threshold, viewModel.canLoadNextWindow {
            let anchor = viewModel.visibleLines.last?.lineNumber
            viewModel.loadNextWindow()
            if let anchor {
                scrollPosition.scrollTo(id: anchor, anchor: .bottom)
            }
        } else if geometry.visibleRect.minY <= threshold, viewModel.canLoadPreviousWindow {
            let anchor = viewModel.visibleLines.first?.lineNumber
            viewModel.loadPreviousWindow()
            if let anchor {
                scrollPosition.scrollTo(id: anchor, anchor: .top)
            }
        }
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

                    Text("Content")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Group {
                        if viewModel.isPreparingInspector,
                           viewModel.inspectorLineNumber == lineNumber {
                            ProgressView("Formatting content...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let content = viewModel.inspectorContent,
                                  viewModel.inspectorLineNumber == lineNumber {
                            SyntaxHighlightedTextView(
                                content: content,
                                contentID: lineNumber
                            )
                        } else {
                            Text("Content unavailable.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.2))
                    .clipShape(.rect(cornerRadius: 4))
                }
            } else {
                Text("Line not loaded in viewport.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding()
        .inspectorColumnWidth(min: 200, ideal: 250, max: 400)
    }
}
