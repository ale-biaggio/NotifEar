
import Foundation

enum ModelPackaging {
    enum PackagingError: Error { case notADirectory, malformedArchive }

    static func pack(directory: URL, to fileURL: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw PackagingError.notADirectory
        }

        var entries: [String: Data] = [:]
        let base = directory.standardizedFileURL
        let basePrefix = base.path.hasSuffix("/") ? base.path : base.path + "/"

        if let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let url = enumerator.nextObject() as? URL {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let relative = url.standardizedFileURL.path.replacingOccurrences(of: basePrefix, with: "")
                entries[relative] = try Data(contentsOf: url)
            }
        }

        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    static func unpack(file: URL, to directory: URL) throws -> URL {
        let fm = FileManager.default
        let raw = try Data(contentsOf: file)
        guard let entries = try PropertyListSerialization
            .propertyList(from: raw, options: [], format: nil) as? [String: Data] else {
            throw PackagingError.malformedArchive
        }

        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        for (relative, data) in entries {
            let dest = directory.appendingPathComponent(relative)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
        }
        return directory
    }
}
