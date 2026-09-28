import Foundation
import MochaProtocol
import Synchronization
import Testing
@testable import MochaClient

final class FakeActivityRegistrar: AgentsActivityRegistering {
    private let state: Mutex<(results: [AgentsActivityRegistrationResult], calls: [LiveActivityRegistration])>

    init(_ results: AgentsActivityRegistrationResult...) {
        state = Mutex((results, []))
    }

    var calls: [LiveActivityRegistration] {
        state.withLock { $0.calls }
    }

    func register(_ registration: LiveActivityRegistration) async -> AgentsActivityRegistrationResult {
        state.withLock { state in
            state.calls.append(registration)
            return state.results.isEmpty ? .delivered : state.results.removeFirst()
        }
    }
}

struct AgentsActivityTokenBookTests {
    @Test func registrationsCarryThePushToStartTokenWithEachActivity() {
        var book = AgentsActivityTokenBook()
        book.use(.sandbox)
        #expect(book.registrations(includingDelivered: true).isEmpty)
        book.recordPushToStartToken("aa01")
        #expect(book.registrations(includingDelivered: false) == [LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox)])
        book.recordUpdateToken("bb02", activityId: "B")
        book.recordUpdateToken("cc03", activityId: "A")
        #expect(book.registrations(includingDelivered: false) == [
            LiveActivityRegistration(pushToStartToken: "aa01", activityId: "A", updateToken: "cc03", env: .sandbox),
            LiveActivityRegistration(pushToStartToken: "aa01", activityId: "B", updateToken: "bb02", env: .sandbox),
        ])
    }

    @Test func deliveredTokensAreOnlyResentWhenAsked() {
        var book = AgentsActivityTokenBook()
        book.use(.production)
        book.recordPushToStartToken("aa01")
        book.recordUpdateToken("bb02", activityId: "A")
        let registration = LiveActivityRegistration(pushToStartToken: "aa01", activityId: "A", updateToken: "bb02", env: .production)
        let marked = book.markDelivered(registration)
        #expect(marked)
        #expect(!book.hasUndelivered)
        #expect(book.registrations(includingDelivered: false).isEmpty)
        #expect(book.registrations(includingDelivered: true) == [registration])
    }

    @Test func aTokenThatChangedWhileSendingStaysUndelivered() {
        var book = AgentsActivityTokenBook()
        book.use(.sandbox)
        book.recordUpdateToken("bb02", activityId: "A")
        let sent = book.registrations(includingDelivered: false)
        book.recordUpdateToken("dd04", activityId: "A")
        let marked = book.markDelivered(sent[0])
        #expect(!marked)
        #expect(book.hasUndelivered)
        #expect(book.registrations(includingDelivered: false).first?.updateToken == "dd04")
    }

    @Test func theSameTokenAgainChangesNothing() {
        var book = AgentsActivityTokenBook()
        book.use(.sandbox)
        let first = book.recordPushToStartToken("aa01")
        book.markDelivered(LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox))
        let again = book.recordPushToStartToken("aa01")
        #expect(first)
        #expect(!again)
        #expect(!book.hasUndelivered)
    }

    @Test func aNewEnvironmentMakesEveryTokenUndelivered() {
        var book = AgentsActivityTokenBook()
        book.use(.sandbox)
        book.recordPushToStartToken("aa01")
        book.markDelivered(LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox))
        let sameEnvironment = book.use(.sandbox)
        let newEnvironment = book.use(.production)
        #expect(!sameEnvironment)
        #expect(newEnvironment)
        #expect(book.registrations(includingDelivered: false) == [LiveActivityRegistration(pushToStartToken: "aa01", env: .production)])
        let markedForOldEnvironment = book.markDelivered(LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox))
        #expect(!markedForOldEnvironment)
    }

    @Test func forgottenActivitiesAreNotSentAgain() {
        var book = AgentsActivityTokenBook()
        book.use(.sandbox)
        book.recordUpdateToken("bb02", activityId: "A")
        book.recordUpdateToken("cc03", activityId: "B")
        let forgotA = book.forgetActivities(except: ["B"])
        let forgotNothing = book.forgetActivities(except: ["B"])
        #expect(forgotA)
        #expect(!forgotNothing)
        #expect(book.registrations(includingDelivered: true).map(\.activityId) == ["B"])
        let forgotB = book.forgetActivity("B")
        let forgotBAgain = book.forgetActivity("B")
        #expect(forgotB)
        #expect(!forgotBAgain)
        #expect(book.registrations(includingDelivered: true).isEmpty)
    }

    @Test func fileRoundTripsAndStartsEmptyWhenMissingOrUnreadable() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-la-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentsActivityTokenFile(url: directory.appending(path: "nested/live-activity-tokens.json"))
        #expect(file.load() == AgentsActivityTokenBook())
        var book = AgentsActivityTokenBook()
        book.use(.sandbox)
        book.recordPushToStartToken("aa01")
        book.recordUpdateToken("bb02", activityId: "A")
        book.markDelivered(LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox))
        try file.save(book)
        #expect(file.load() == book)
        try Data(#"{"pushToStartToken":"aa01","activities":{}}"#.utf8).write(to: file.url)
        #expect(file.load() == AgentsActivityTokenBook())
    }

    @Test func anOldFileWithAgentIdsLoadsAndRegistersWithoutThem() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-la-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentsActivityTokenFile(url: directory.appending(path: "live-activity-tokens.json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = #"{"environment":"sandbox","pushToStart":{"value":"aa01","isDelivered":true},"activities":{"A":{"value":"bb02","agentId":"w1:p1","isDelivered":true}}}"#
        try Data(old.utf8).write(to: file.url)
        let book = file.load()
        #expect(book.registrations(includingDelivered: true) == [
            LiveActivityRegistration(pushToStartToken: "aa01", activityId: "A", updateToken: "bb02", env: .sandbox),
        ])
        #expect(book.registrations(includingDelivered: true).allSatisfy { $0.agentId == nil })
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any]
        let activity = try #require((encoded?["activities"] as? [String: Any])?["A"] as? [String: Any])
        #expect(activity["agentId"] == nil)
    }

    @Test func theDefaultFileLivesInApplicationSupport() {
        #expect(AgentsActivityTokenFile().url == URL.applicationSupportDirectory.appending(path: "live-activity-tokens.json"))
    }
}

struct AgentsActivityTokenSyncTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-la-\(UUID().uuidString)")

    private var file: AgentsActivityTokenFile {
        AgentsActivityTokenFile(url: directory.appending(path: "live-activity-tokens.json"))
    }

    @Test func withoutSocketATokenGoesThroughTheGatewayAndIsPersisted() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let gateway = FakeActivityRegistrar()
        let sync = AgentsActivityTokenSync(environment: .sandbox, liveActivityIds: [], file: file, gateway: gateway)
        await sync.recordPushToStartToken("aa01")
        #expect(gateway.calls == [LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox)])
        await sync.recordUpdateToken("bb02", activityId: "A")
        #expect(gateway.calls.last == LiveActivityRegistration(pushToStartToken: "aa01", activityId: "A", updateToken: "bb02", env: .sandbox))
        #expect(!file.load().hasUndelivered)
        #expect(file.load().activities["A"]?.value == "bb02")
    }

    @Test func aFailedDeliveryIsResentOnTheNextOpportunity() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let gateway = FakeActivityRegistrar(.unreachable)
        let sync = AgentsActivityTokenSync(environment: .sandbox, liveActivityIds: [], file: file, gateway: gateway)
        await sync.recordUpdateToken("bb02", activityId: "A")
        #expect(gateway.calls.count == 1)
        #expect(file.load().hasUndelivered)

        let relaunchGateway = FakeActivityRegistrar()
        let relaunched = AgentsActivityTokenSync(environment: .sandbox, liveActivityIds: ["A"], file: file, gateway: relaunchGateway)
        await relaunched.deliverPending()
        #expect(relaunchGateway.calls == [LiveActivityRegistration(activityId: "A", updateToken: "bb02", env: .sandbox)])
        #expect(!file.load().hasUndelivered)
        await relaunched.deliverPending()
        #expect(relaunchGateway.calls.count == 1)
    }

    @Test func aFailureStopsTheRoundAndKeepsTheRestUndelivered() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = FakeActivityRegistrar(.delivered, .unreachable)
        let sync = AgentsActivityTokenSync(environment: .sandbox, liveActivityIds: [], file: file, gateway: FakeActivityRegistrar(.unreachable, .unreachable, .unreachable))
        await sync.recordUpdateToken("aa01", activityId: "A")
        await sync.recordUpdateToken("bb02", activityId: "B")
        await sync.recordUpdateToken("cc03", activityId: "C")
        await sync.socketOpened(socket)
        #expect(socket.calls.map(\.activityId) == ["A", "B"])
        let tokens = await sync.tokens
        #expect(tokens.activities["A"]?.isDelivered == true)
        #expect(tokens.activities["B"]?.isDelivered == false)
        #expect(tokens.activities["C"]?.isDelivered == false)
    }

    @Test func anOpenSocketTakesPrecedenceAndReceivesEveryTokenOnConnect() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let gateway = FakeActivityRegistrar()
        let sync = AgentsActivityTokenSync(environment: .production, liveActivityIds: [], file: file, gateway: gateway)
        await sync.recordPushToStartToken("aa01")
        #expect(gateway.calls.count == 1)

        let socket = FakeActivityRegistrar()
        await sync.socketOpened(socket)
        #expect(socket.calls == [LiveActivityRegistration(pushToStartToken: "aa01", env: .production)])
        await sync.recordUpdateToken("bb02", activityId: "A")
        #expect(socket.calls.last == LiveActivityRegistration(pushToStartToken: "aa01", activityId: "A", updateToken: "bb02", env: .production))
        #expect(gateway.calls.count == 1)

        await sync.socketClosed()
        await sync.recordUpdateToken("cc03", activityId: "A")
        #expect(gateway.calls.last?.updateToken == "cc03")
        #expect(socket.calls.count == 2)
    }

    @Test func endedActivitiesAreNotResent() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let sync = AgentsActivityTokenSync(environment: .sandbox, liveActivityIds: [], file: file, gateway: FakeActivityRegistrar())
        await sync.recordPushToStartToken("aa01")
        await sync.recordUpdateToken("bb02", activityId: "A")
        await sync.recordUpdateToken("cc03", activityId: "B")
        await sync.forgetActivity("A")
        let socket = FakeActivityRegistrar()
        await sync.socketOpened(socket)
        #expect(socket.calls == [LiveActivityRegistration(pushToStartToken: "aa01", activityId: "B", updateToken: "cc03", env: .sandbox)])

        let relaunched = AgentsActivityTokenSync(environment: .sandbox, liveActivityIds: [], file: file, gateway: FakeActivityRegistrar())
        #expect(file.load().activities.isEmpty)
        let relaunchSocket = FakeActivityRegistrar()
        await relaunched.socketOpened(relaunchSocket)
        #expect(relaunchSocket.calls == [LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox)])
    }

    @Test func tokensSavedForAnotherEnvironmentAreSentAgain() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AgentsActivityTokenSync(environment: .sandbox, liveActivityIds: [], file: file, gateway: FakeActivityRegistrar())
        await first.recordPushToStartToken("aa01")
        #expect(!file.load().hasUndelivered)
        let gateway = FakeActivityRegistrar()
        let second = AgentsActivityTokenSync(environment: .production, liveActivityIds: [], file: file, gateway: gateway)
        await second.deliverPending()
        #expect(gateway.calls == [LiveActivityRegistration(pushToStartToken: "aa01", env: .production)])
    }
}

struct GatewayAgentsActivityRegistrarTests {
    private static let pairingURL = "wss://mac-mini.tail1234.ts.net/v1"

    private static func registrar(_ transport: FakeUploadTransport, paired: Bool = true) throws -> GatewayAgentsActivityRegistrar {
        let credential = paired ? DeviceCredential(url: try #require(URL(string: pairingURL)), token: "device-token-1") : nil
        return GatewayAgentsActivityRegistrar(tokenStore: FakeTokenStore(credential: credential), transport: transport)
    }

    @Test func postsTheRegistrationWithBearer() async throws {
        let transport = FakeUploadTransport(.status(200, Data("{}".utf8)))
        let registration = LiveActivityRegistration(
            pushToStartToken: "80a1f2c3d4e5f60718293a4b5c6d7e8f",
            activityId: "B4F1C2D3-9E8A-4B7C-A6D5-E4F3A2B1C0D9",
            updateToken: "91b2c3d4e5f60718293a4b5c6d7e8f90",
            env: .sandbox
        )
        #expect(await (try Self.registrar(transport)).register(registration) == .delivered)
        let call = try #require(transport.calls.first)
        #expect(transport.calls.count == 1)
        #expect(call.request.url == URL(string: "https://mac-mini.tail1234.ts.net/v1/live-activity"))
        #expect(call.request.httpMethod == "POST")
        #expect(call.request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token-1")
        #expect(call.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: call.body) as? NSDictionary
        let fixture = try #require(try JSONSerialization.jsonObject(with: Fixtures.data("protocol/client.registerLiveActivity.json")) as? [String: Any])
        #expect(body == fixture["payload"] as? NSDictionary)
    }

    @Test(arguments: [
        (200, AgentsActivityRegistrationResult.delivered),
        (400, .refused),
        (401, .unauthorized),
        (500, .unexpectedStatus(500)),
    ])
    func statusMapsToTheResult(status: Int, result: AgentsActivityRegistrationResult) async throws {
        let registration = LiveActivityRegistration(pushToStartToken: "aa01", env: .production)
        #expect(await (try Self.registrar(FakeUploadTransport(.status(status, Data())))).register(registration) == result)
    }

    @Test func transportFailureIsUnreachableAndUnpairedSendsNothing() async throws {
        let registration = LiveActivityRegistration(pushToStartToken: "aa01", env: .production)
        #expect(await (try Self.registrar(FakeUploadTransport(.failure))).register(registration) == .unreachable)
        let transport = FakeUploadTransport(.status(200, Data()))
        #expect(await (try Self.registrar(transport, paired: false)).register(registration) == .notPaired)
        #expect(transport.calls.isEmpty)
    }

    @Test(arguments: [
        ("wss://mac-mini.tail1234.ts.net/v1", "https://mac-mini.tail1234.ts.net/v1/live-activity"),
        ("ws://127.0.0.1:8787/v1", "http://127.0.0.1:8787/v1/live-activity"),
    ])
    func registrationURLFollowsThePairingHost(pairing: String, expected: String) throws {
        #expect(GatewayAgentsActivityRegistrar.registrationURL(forPairingURL: try #require(URL(string: pairing)))?.absoluteString == expected)
    }

    @Test func socketRegistrarReportsWhetherTheMacAcknowledged() async {
        let registration = LiveActivityRegistration(pushToStartToken: "aa01", env: .sandbox)
        #expect(await SocketAgentsActivityRegistrar { _ in true }.register(registration) == .delivered)
        #expect(await SocketAgentsActivityRegistrar { _ in false }.register(registration) == .unreachable)
    }
}
