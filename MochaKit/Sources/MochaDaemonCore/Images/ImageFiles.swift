import Foundation

struct RegularFile: Sendable, Equatable {
    let url: URL
    let size: Int
}

enum ImageFiles {
    static func regularFile(atPath path: String) -> RegularFile? {
        let url = URL(filePath: path).resolvingSymlinksInPath()
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else {
            return nil
        }
        return RegularFile(url: url, size: values.fileSize ?? 0)
    }

    static func isRegularFile(atPath path: String) -> Bool {
        regularFile(atPath: path) != nil
    }

    static func existing(_ paths: [String]) -> [String] {
        paths.filter(isRegularFile(atPath:))
    }

    static func isReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }
}
