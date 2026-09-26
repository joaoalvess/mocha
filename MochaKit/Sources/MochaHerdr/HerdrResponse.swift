import Foundation

enum HerdrResponse {
    struct Empty: Decodable, Sendable {}

    struct Snapshot: Decodable, Sendable {
        let snapshot: HerdrSessionSnapshot
    }

    struct AgentList: Decodable, Sendable {
        let agents: [HerdrPane]
    }

    struct Agent: Decodable, Sendable {
        let agent: HerdrPane
    }

    struct WorkspaceList: Decodable, Sendable {
        let workspaces: [HerdrWorkspace]
    }

    struct TabList: Decodable, Sendable {
        let tabs: [HerdrTab]
    }

    struct Pane: Decodable, Sendable {
        let pane: HerdrPane
    }

    private struct Head: Decodable {
        struct ResultHead: Decodable {
            let type: String
        }

        struct ErrorBody: Decodable {
            let code: String
            let message: String
        }

        let id: String?
        let result: ResultHead?
        let error: ErrorBody?
    }

    private struct Body<Result: Decodable>: Decodable {
        let result: Result
    }

    static func decode<Result: Decodable>(
        _ line: Data,
        method: String,
        expecting type: String,
        as resultType: Result.Type
    ) throws -> Result {
        let decoder = JSONDecoder()
        let head: Head
        do {
            head = try decoder.decode(Head.self, from: line)
        } catch {
            throw HerdrClientError.invalidResponse(method: method, detail: "malformed response line")
        }
        if let error = head.error {
            throw HerdrClientError.server(
                HerdrServerError(requestId: head.id ?? "", code: HerdrErrorCode(rawValue: error.code), message: error.message)
            )
        }
        guard let result = head.result else {
            throw HerdrClientError.invalidResponse(method: method, detail: "response without result")
        }
        guard result.type == type else {
            throw HerdrClientError.invalidResponse(method: method, detail: "unexpected result type \(result.type)")
        }
        do {
            return try decoder.decode(Body<Result>.self, from: line).result
        } catch {
            throw HerdrClientError.invalidResponse(method: method, detail: String(describing: error))
        }
    }
}
