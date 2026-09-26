import Foundation
import Testing
@testable import MochaDaemonCore

struct RawHttpResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

enum UploadRequests {
    static func post(
        port: UInt16,
        target: String = Gateway.uploadPath,
        headers: [(String, String)],
        body: [UInt8],
        sendsContentLength: Bool = true
    ) async throws -> RawHttpResponse {
        let client = try await RawClient.connect(to: loopbackEndpoint(port))
        defer { client.cancel() }
        var head = "POST \(target) HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        if sendsContentLength {
            head += "Content-Length: \(body.count)\r\n"
        }
        head += "\r\n"
        try await client.send(Array(head.utf8) + body)
        return try parse(try await client.readToEnd())
    }

    static func image(port: UInt16, token: String?, contentType: String? = "image/jpeg", body: [UInt8]) async throws -> RawHttpResponse {
        var headers: [(String, String)] = []
        if let token {
            headers.append(("Authorization", "Bearer \(token)"))
        }
        if let contentType {
            headers.append(("Content-Type", contentType))
        }
        return try await post(port: port, headers: headers, body: body)
    }

    private static func headEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        return (0...(bytes.count - 4)).first {
            bytes[$0] == 13 && bytes[$0 + 1] == 10 && bytes[$0 + 2] == 13 && bytes[$0 + 3] == 10
        }
    }

    private static func parse(_ bytes: [UInt8]) throws -> RawHttpResponse {
        let end = try #require(headEnd(bytes))
        let lines = String(decoding: bytes[..<end], as: UTF8.self).components(separatedBy: "\r\n")
        let statusParts = try #require(lines.first?.split(separator: " "))
        let status = try #require(statusParts.count >= 2 ? Int(statusParts[1]) : nil)
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return RawHttpResponse(status: status, headers: headers, body: Data(bytes[(end + 4)...]))
    }
}

enum UploadSamples {
    static let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0xFF, 0xD9]
    static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]
    static let heic: [UInt8] = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]

    static func bytes(for type: UploadImageType) -> [UInt8] {
        switch type {
        case .jpeg: jpeg
        case .png: png
        case .heic: heic
        }
    }
}

func directoryEntries(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.fileSystemPath)) ?? []).sorted()
}

func setModificationDate(_ date: Date, of url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.fileSystemPath)
}

func isUUIDFileName(_ name: String, extension fileExtension: String) -> Bool {
    guard name.hasSuffix(".\(fileExtension)") else { return false }
    let stem = String(name.dropLast(fileExtension.count + 1))
    return UUID(uuidString: stem)?.uuidString == stem
}
