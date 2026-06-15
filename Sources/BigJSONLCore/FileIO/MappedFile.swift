import Foundation
import Dispatch

/// A memory-mapped view of a file, providing zero-copy access to arbitrary byte ranges.
///
/// The file is mapped in its entirety on open, but the mapping is lazy —
/// the OS only loads pages that are actually accessed.
public final class MappedFile: @unchecked Sendable {
    /// The URL of the opened file.
    public let url: URL

    /// The total size of the file in bytes.
    public private(set) var size: UInt64 = 0

    /// The mapped memory region, or nil if the file is empty.
    private let baseAddress: UnsafeMutableRawPointer?
    private let mappedSize: Int

    /// Opens and memory-maps the file at the given URL.
    ///
    /// - Parameter url: The file URL to open.
    /// - Throws: `MappedFileError` if the file cannot be opened or mapped.
    public init(url: URL) throws {
        self.url = url

        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw MappedFileError.fileNotFound(url)
        }

        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else {
            throw MappedFileError.cannotOpen(url)
        }
        defer { close(fd) }

        // Get file size
        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0 else {
            throw MappedFileError.cannotStat(url)
        }
        let fileSize = Int(statInfo.st_size)
        self.size = UInt64(fileSize)
        self.mappedSize = fileSize

        // mmap the entire file (lazy: pages fault on access)
        if fileSize > 0 {
            guard let addr = mmap(nil, fileSize, PROT_READ, MAP_PRIVATE, fd, 0),
                  addr != MAP_FAILED else {
                throw MappedFileError.cannotMap(url)
            }
            self.baseAddress = addr
        } else {
            self.baseAddress = nil
        }
    }

    /// Returns a `DispatchData` referencing the bytes in the given range.
    ///
    /// The returned data is backed by the memory mapping — no copying occurs.
    /// - Parameter range: The byte range to read (0-based from file start).
    /// - Returns: A `DispatchData` referencing the region, or an empty `DispatchData` if
    ///   the range is invalid.
    public func read(offset: UInt64, length: UInt64) -> DispatchData {
        guard let base = baseAddress,
              offset + length <= size,
              length > 0 else {
            return DispatchData.empty
        }
        let ptr = base.advanced(by: Int(offset))
        let buffer = UnsafeRawBufferPointer(start: ptr, count: Int(length))
        // DispatchData must not deallocate — the MappedFile owns the mapping
        return DispatchData(bytesNoCopy: buffer, deallocator: .custom(nil, {}))
    }

    /// Reads a single byte at the given offset.
    public func readByte(at offset: UInt64) -> UInt8? {
        guard let base = baseAddress, offset < size else { return nil }
        let rawBase = UnsafeRawPointer(base)
        return rawBase.load(fromByteOffset: Int(offset), as: UInt8.self)
    }

    deinit {
        if let base = baseAddress, mappedSize > 0 {
            munmap(base, mappedSize)
        }
    }
}

// MARK: - Errors

public enum MappedFileError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case cannotOpen(URL)
    case cannotStat(URL)
    case cannotMap(URL)

    public var description: String {
        switch self {
        case .fileNotFound(let url): return "File not found: \(url.path)"
        case .cannotOpen(let url): return "Cannot open file: \(url.path)"
        case .cannotStat(let url): return "Cannot stat file: \(url.path)"
        case .cannotMap(let url): return "Cannot memory-map file: \(url.path)"
        }
    }
}
