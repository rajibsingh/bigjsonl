import UniformTypeIdentifiers

extension UTType {
    /// The JSONL (JSON Lines) file format, declared as a subtype of JSON.
    static var jsonl: UTType {
        UTType(tag: "jsonl", tagClass: .filenameExtension, conformingTo: .json)!
    }
}
