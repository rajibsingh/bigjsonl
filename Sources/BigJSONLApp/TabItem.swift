import Foundation
import Observation
import BigJSONLCore

/// Represents a single open tab in the app.
///
/// A tab with a nil URL is an empty tab showing the welcome/file-picker screen.
@MainActor
@Observable
final class TabItem: Identifiable {
    let id: UUID
    var url: URL?
    var document: BigJSONLDocument?
    var viewModel: DocumentViewModel?

    var title: String {
        url?.lastPathComponent ?? "New Tab"
    }

    init(url: URL? = nil) {
        self.id = UUID()
        self.url = url
        if let url {
            let doc = BigJSONLDocument(url: url)
            self.document = doc
            self.viewModel = DocumentViewModel(document: doc)
        }
    }

    func open(url: URL) {
        dispose(stopAccessingResource: true)
        self.url = url
        let doc = BigJSONLDocument(url: url)
        self.document = doc
        self.viewModel = DocumentViewModel(document: doc)
    }

    /// Re-opens the current file from scratch, picking up any new content written since open.
    func reload() {
        guard let url else { return }
        viewModel?.dispose()
        let doc = BigJSONLDocument(url: url)
        self.document = doc
        self.viewModel = DocumentViewModel(document: doc)
    }

    func close() {
        dispose(stopAccessingResource: true)
    }

    private func dispose(stopAccessingResource: Bool) {
        viewModel?.dispose()
        if stopAccessingResource {
            url?.stopAccessingSecurityScopedResource()
            url = nil
        }
        document = nil
        viewModel = nil
    }
}
