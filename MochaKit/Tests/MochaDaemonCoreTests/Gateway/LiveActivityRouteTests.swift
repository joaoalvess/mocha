import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityRouteTests {
    private struct Harness {
        let port: UInt16
        let token: String
        let device: DeviceRecord
        let registrar: FakeLiveActivityRegistrar
    }

    private static let registration = LiveActivityRegistration(activityId: "act-1", updateToken: "80f1c2", agentId: "w1:p1", env: .sandbox)

    private func withLiveActivityGateway(_ body: (Harness) async throws -> Void) async throws {
        try await withHub { hub in
            let token = SecureToken.generate()
            let device = try await hub.devices.register(name: "iPhone do João", token: token, at: Sample.start)
            let registrar = FakeLiveActivityRegistrar()
            let gateway = Gateway(version: "9.9.9", herdr: hub.herdr, hub: hub.hub, liveActivities: registrar)
            try await withRunningServer(gateway.makeRouter()) { port in
                try await body(Harness(port: port, token: token, device: device, registrar: registrar))
            }
        }
    }

    private func post(_ harness: Harness, authorization: String?, body: Data) async throws -> (status: Int, body: Data) {
        var headers = ["Content-Type": "application/json"]
        if let authorization {
            headers["Authorization"] = authorization
        }
        let response = try await sendRequest("POST", port: harness.port, target: Gateway.liveActivityPath, headers: headers, body: body)
        return (response.status, response.body)
    }

    @Test func forwardsTheRegistrationOfTheBearerDevice() async throws {
        try await withLiveActivityGateway { harness in
            let response = try await post(harness, authorization: "Bearer \(harness.token)", body: try JSONEncoder().encode(Self.registration))
            #expect(response.status == 200)
            #expect(String(decoding: response.body, as: UTF8.self) == "{}")
            #expect(harness.registrar.registered == [.init(registration: Self.registration, deviceId: harness.device.id)])
        }
    }

    @Test func pushToStartTokenAloneIsForwarded() async throws {
        try await withLiveActivityGateway { harness in
            let body = Data(#"{"pushToStartToken":"a1b2","env":"production"}"#.utf8)
            let response = try await post(harness, authorization: "Bearer \(harness.token)", body: body)
            #expect(response.status == 200)
            #expect(harness.registrar.registered.map(\.registration) == [LiveActivityRegistration(pushToStartToken: "a1b2", env: .production)])
        }
    }

    @Test(arguments: [nil, "Bearer token-errado", "Basic abc"])
    func rejectsRequestsWithoutAValidBearer(_ authorization: String?) async throws {
        try await withLiveActivityGateway { harness in
            let response = try await post(harness, authorization: authorization, body: try JSONEncoder().encode(Self.registration))
            #expect(response.status == 401)
            #expect(harness.registrar.registered.isEmpty)
        }
    }

    @Test func malformedBodyIsABadRequest() async throws {
        try await withLiveActivityGateway { harness in
            let response = try await post(harness, authorization: "Bearer \(harness.token)", body: Data(#"{"activityId":"x"}"#.utf8))
            #expect(response.status == 400)
            #expect(harness.registrar.registered.isEmpty)
        }
    }

    @Test func anInvalidTokenIsABadRequest() async throws {
        try await withLiveActivityGateway { harness in
            harness.registrar.fail(with: LiveActivityRegistrationError.invalidToken)
            let response = try await post(harness, authorization: "Bearer \(harness.token)", body: try JSONEncoder().encode(Self.registration))
            #expect(response.status == 400)
        }
    }

    @Test func theServiceRefusesAMalformedTokenAndSavesAValidOne() async throws {
        try await withHub { hub in
            let token = SecureToken.generate()
            let device = try await hub.devices.register(name: "iPhone do João", token: token, at: Sample.start)
            let service = LiveActivityService(devices: hub.devices, sender: FakeLiveActivitySender(), clock: hub.clock)
            let gateway = Gateway(version: "9.9.9", herdr: hub.herdr, hub: hub.hub, liveActivities: service)
            try await withRunningServer(gateway.makeRouter()) { port in
                let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
                let invalid = Data(#"{"activityId":"act-1","updateToken":"não-é-hex","env":"sandbox"}"#.utf8)
                let refused = try await sendRequest("POST", port: port, target: Gateway.liveActivityPath, headers: headers, body: invalid)
                #expect(refused.status == 400)
                #expect(try await hub.devices.devices().first?.agentActivities.isEmpty == true)

                let accepted = try await sendRequest("POST", port: port, target: Gateway.liveActivityPath, headers: headers, body: try JSONEncoder().encode(Self.registration))
                #expect(accepted.status == 200)
                #expect(try await hub.devices.devices().first { $0.id == device.id }?.agentActivities == [Self.registration])
            }
            await service.shutdown()
        }
    }

    @Test func registrarFailureIsAnInternalError() async throws {
        try await withLiveActivityGateway { harness in
            harness.registrar.fail(with: CocoaError(.fileWriteUnknown))
            let response = try await post(harness, authorization: "Bearer \(harness.token)", body: try JSONEncoder().encode(Self.registration))
            #expect(response.status == 500)
        }
    }

    @Test func routeOnlyExistsWithARegistrar() async throws {
        try await withHub { hub in
            let gateway = Gateway(version: "9.9.9", herdr: hub.herdr, hub: hub.hub)
            try await withRunningServer(gateway.makeRouter()) { port in
                let response = try await sendRequest("POST", port: port, target: Gateway.liveActivityPath, headers: [:], body: Data("{}".utf8))
                #expect(response.status == 404)
            }
        }
    }
}
