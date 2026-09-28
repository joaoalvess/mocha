import Foundation
import MochaClient
import MochaProtocol

enum WebServersLoad: Equatable {
    case loading
    case loaded([WebServerGroup])
    case failed(String)
}

extension WebServer {
    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let directory, let folder = URL(filePath: directory).pathComponents.last, folder != "/" {
            return folder
        }
        return "Porta \(port)"
    }

    var detailLine: String {
        "PID \(pid) · \(process) · PORT \(port)"
    }
}
