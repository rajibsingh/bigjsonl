import SwiftUI
import BigJSONLCore

struct ContentView: View {
    let document: BigJSONLDocument

    var body: some View {
        VStack {
            Text("bigjsonl")
                .font(.title)
            Text(document.url.lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Viewer coming soon.")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
