import SwiftUI
import BigJSONLCore

@main
struct BigJSONLApp: App {
    var body: some Scene {
        DocumentGroup(viewing: BigJSONLDocument.self) { config in
            ContentView(document: config.document)
        }
    }
}
