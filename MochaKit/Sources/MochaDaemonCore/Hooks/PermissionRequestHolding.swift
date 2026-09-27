import MochaProtocol

public protocol PermissionRequestHolding: Sendable {
    func observe(_ hook: ReceivedHook) async
    func open(_ hook: ReceivedHook, request: PermissionRequestHook) async -> RequestID
    func reply(to requestId: RequestID) async -> OrderedJSON
}
