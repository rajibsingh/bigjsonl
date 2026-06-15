import Foundation
import UniformTypeIdentifiers
import SwiftUI
import BigJSONLCore

/// A document type that represents a JSONL file.
///
/// Unlike a typical `ReferenceFileDocument`, this does NOT load the file
/// contents into memory. It stores only the file URL and lazily builds
/// the line-offset index as the user scrolls.
@preconcurrency
final class BigJSONLDocument: ReferenceFileDocument {
    /// The supported content types for this document.
    static var readableContentTypes: [UTType] {
        [.jsonl, .json]
    }

    /// The URL of the file on disk.
    let url: URL

    /// The lazy incremental line-offset index for this file.
    var index: LineOffsetIndex

    init(url: URL) {
        self.url = url
        self.index = LineOffsetIndex()
    }

    /// Required initializer for document restoration.
    /// In v0.1 this should never be called since we don't support autosave.
    required convenience init(configuration: ReadConfiguration) throws {
        throw BigJSONLDocumentError.loadNotSupported
    }

    /// Override the standard read path — don't load file data into memory.
    ///
    /// Instead of reading the file contents, we just validate that the file
    /// exists and store the URL for lazy access.
    func read(from data: Data, ofType typeName: String) throws {
        // We override this at the DocumentGroup level via type configuration.
        // This method should not be called.
        throw BigJSONLDocumentError.loadNotSupported
    }

    /// Snapshot for autosave — not used in v0.1.
    func snapshot(contentType: UTType) throws -> Data {
        Data()
    }

    /// File writing — not supported (viewer-only).
    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        throw BigJSONLDocumentError.writeNotSupported
    }
}

enum BigJSONLDocumentError: Error, LocalizedError {
    case loadNotSupported
    case writeNotSupported

    var errorDescription: String? {
        switch self {
        case .loadNotSupported:
            return "This document does not support loading data through the standard path."
        case .writeNotSupported:
            return "bigjsonl is a viewer-only tool. Editing is not supported."
        }
    }
}
