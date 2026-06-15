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

    var title: String {
        url?.lastPathComponent ?? "New Tab"
    }

    init(url: URL? = nil) {
        self.id = UUID()
        self.url = url
        self.document = url.map { BigJSONLDocument(url: $0) }
    }

    func open(url: URL) {
        self.url?.stopAccessingSecurityScopedResource()
        self.url = url
        self.document = BigJSONLDocument(url: url)
    }
}
