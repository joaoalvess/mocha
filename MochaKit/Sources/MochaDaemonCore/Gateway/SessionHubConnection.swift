import Foundation
import MochaProtocol

extension SessionHub {
    enum AgentCommand: Sendable {
        case prompt(String)
        case interrupt
    }

    public func serve(_ socket: any GatewaySocket, messages: AsyncStream<WebSocketMessage>) async {
        guard !isShuttingDown else {
            await socket.close(code: .goingAway, reason: "")
            return
        }
        let clientId = UUID()
        let (frames, outbox) = AsyncStream.makeStream(of: OutboundFrame.self)
        clients[clientId] = Client(outbox: outbox, writer: Self.writer(for: socket, frames: frames))
        for await message in messages {
            guard let client = clients[clientId], !client.isClosing else { break }
            await receive(message, from: clientId)
        }
        disconnect(clientId)
    }

    func send(_ message: ServerMessage, id: String? = nil, to clientId: UUID) {
        guard let client = clients[clientId], !client.isClosing, let text = encode(message, id: id) else { return }
        client.outbox.yield(.text(text))
    }

    func send(_ error: HubError, id: String?, to clientId: UUID) {
        send(.error(code: error.code, message: error.message), id: id, to: clientId)
    }

    func broadcast(_ message: ServerMessage) {
        guard let text = encode(message, id: nil) else { return }
        for client in clients.values where client.isAuthenticated && !client.isClosing {
            client.outbox.yield(.text(text))
        }
    }

    @discardableResult
    func close(_ clientId: UUID, error: HubError?, id: String?, code: WebSocketCloseCode) -> Task<Void, Never>? {
        guard var client = clients[clientId], !client.isClosing else { return nil }
        if let error, let text = encode(.error(code: error.code, message: error.message), id: id) {
            client.outbox.yield(.text(text))
        }
        client.isClosing = true
        client.outbox.yield(.close(code, ""))
        client.outbox.finish()
        clients[clientId] = client
        return client.writer
    }

    private static func writer(for socket: any GatewaySocket, frames: AsyncStream<OutboundFrame>) -> Task<Void, Never> {
        Task {
            for await frame in frames {
                switch frame {
                case .text(let text):
                    do {
                        try await socket.send(text: text)
                    } catch {
                        gatewayLogger.debug("dropped a message for a closed socket")
                    }
                case .close(let code, let reason):
                    await socket.close(code: code, reason: reason)
                    return
                }
            }
        }
    }

    private func encode(_ message: ServerMessage, id: String?) -> String? {
        do {
            return String(decoding: try encoder.encode(ServerEnvelope(id: id, message: message)), as: UTF8.self)
        } catch {
            gatewayLogger.error("failed to encode \(message.type, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func disconnect(_ clientId: UUID) {
        guard let client = clients.removeValue(forKey: clientId) else { return }
        client.outbox.finish()
        for chat in client.chats.values {
            chat.cancel()
        }
        publishOpenChats()
    }

    private func receive(_ message: WebSocketMessage, from clientId: UUID) async {
        let isAuthenticated = clients[clientId]?.isAuthenticated == true
        guard case .text(let text) = message else {
            if isAuthenticated {
                send(.invalidMessage, id: nil, to: clientId)
            } else {
                close(clientId, error: .notHelloFirst, id: nil, code: .policyViolation)
            }
            return
        }
        let data = Data(text.utf8)
        let header = try? decoder.decode(EnvelopeHeader.self, from: data)
        if let version = header?.version, version != ProtocolVersion.current {
            close(clientId, error: .protocolMismatch, id: header?.id, code: .protocolError)
            return
        }
        guard isAuthenticated else {
            await authenticate(data, header: header, clientId: clientId)
            return
        }
        let envelope: ClientEnvelope
        do {
            envelope = try decoder.decode(ClientEnvelope.self, from: data)
        } catch {
            send(.invalidMessage, id: header?.id, to: clientId)
            return
        }
        await handle(envelope.message, id: envelope.id, from: clientId)
    }

    private func authenticate(_ data: Data, header: EnvelopeHeader?, clientId: UUID) async {
        guard header?.type == ClientMessage.helloType else {
            close(clientId, error: .notHelloFirst, id: header?.id, code: .policyViolation)
            return
        }
        guard let envelope = try? decoder.decode(ClientEnvelope.self, from: data), case .hello(let hello) = envelope.message else {
            refuse(clientId, .invalidMessage, id: header?.id)
            return
        }
        switch (hello.deviceToken, hello.pairingCode) {
        case (let token?, nil):
            let record: DeviceRecord?
            do {
                record = try await devices.device(matchingToken: token)
            } catch {
                gatewayLogger.error("failed to read devices: \(String(describing: error), privacy: .public)")
                record = nil
            }
            guard let record else {
                refuse(clientId, .invalidToken, id: envelope.id)
                return
            }
            do {
                try await devices.markSeen(record.id, at: clock.now())
            } catch {
                gatewayLogger.error("failed to update lastSeenAt: \(String(describing: error), privacy: .public)")
            }
            accept(clientId, device: record, deviceToken: nil, id: envelope.id)
        case (nil, let code?):
            guard await pairing.redeem(code) else {
                refuse(clientId, .pairingExpired, id: envelope.id)
                return
            }
            let token = SecureToken.generate()
            do {
                let record = try await devices.register(name: hello.deviceName, token: token, at: clock.now())
                accept(clientId, device: record, deviceToken: token, id: envelope.id)
            } catch {
                gatewayLogger.error("failed to register a device: \(String(describing: error), privacy: .public)")
                send(.deviceStoreFailed, id: envelope.id, to: clientId)
            }
        default:
            refuse(clientId, .helloCredentials, id: envelope.id)
        }
    }

    private func refuse(_ clientId: UUID, _ error: HubError, id: String?) {
        guard var client = clients[clientId] else { return }
        client.failures += 1
        clients[clientId] = client
        if client.failures >= Self.maxAuthenticationFailures {
            close(clientId, error: error, id: id, code: .policyViolation)
        } else {
            send(error, id: id, to: clientId)
        }
    }

    private func accept(_ clientId: UUID, device: DeviceRecord, deviceToken: String?, id: String) {
        guard var client = clients[clientId], !client.isClosing else { return }
        client.deviceId = device.id
        client.name = device.name
        client.connectedAt = clock.now()
        client.failures = 0
        clients[clientId] = client
        let host = HostInfo(
            hostName: configuration.hostName,
            daemonVersion: configuration.daemonVersion,
            herdrConnected: herdrAvailable
        )
        send(
            .helloOk(HelloOkPayload(host: host, deviceId: device.id, deviceToken: deviceToken, preferences: device.preferences)),
            id: id,
            to: clientId
        )
        send(.tree(workspaces: composedTree()), id: id, to: clientId)
        send(.archived(sessions: archivedSessions), to: clientId)
        if let usageSnapshot {
            send(.usage(usageSnapshot), to: clientId)
        }
    }

    private func handle(_ message: ClientMessage, id: String, from clientId: UUID) async {
        switch message {
        case .hello:
            send(.repeatedHello, id: id, to: clientId)
        case .openChat(let target, let before, let limit):
            await openChat(target, before: before, limit: limit, id: id, clientId: clientId)
        case .closeChat(let target):
            await closeChat(target, id: id, clientId: clientId)
        case .sendPrompt(let agentId, let text):
            await run(.prompt(text), agentId: agentId, id: id, clientId: clientId)
        case .interrupt(let agentId):
            await run(.interrupt, agentId: agentId, id: id, clientId: clientId)
        case .setForeground(let agentId, let isActive):
            var resolved: AgentID?
            if let agentId {
                resolved = await herdr.resolve(agentId)
            }
            clients[clientId]?.foreground = Foreground(agentId: resolved, isActive: isActive)
            send(.ack(), id: id, to: clientId)
        case .unpair:
            await unpair(clientId, id: id)
        case .ping:
            send(.pong, id: id, to: clientId)
        case .archive(let sessionId):
            await archiveSession(sessionId, id: id, clientId: clientId)
        case .slash, .setPreferences, .respond, .newAgentTab, .registerLiveActivity, .unknown:
            send(.unknownType(message.type), id: id, to: clientId)
        }
    }

    private func run(_ command: AgentCommand, agentId: AgentID, id: String, clientId: UUID) async {
        guard await herdr.isAvailable else {
            send(.herdrUnavailable, id: id, to: clientId)
            return
        }
        let resolved = await herdr.resolve(agentId)
        guard let agent = await herdr.agent(resolved) else {
            send(.agentNotFound, id: id, to: clientId)
            return
        }
        guard agent.kind == TreeComposer.claudeKind else {
            send(.notClaude, id: id, to: clientId)
            return
        }
        do {
            switch command {
            case .prompt(let text):
                try await herdr.prompt(resolved, text: text)
            case .interrupt:
                try await herdr.interrupt(resolved)
            }
            send(.ack(), id: id, to: clientId)
        } catch let error as HerdrBridgeError {
            send(.herdr(error), id: id, to: clientId)
        } catch {
            send(.herdrFailed, id: id, to: clientId)
        }
    }

    private func unpair(_ clientId: UUID, id: String) async {
        guard let deviceId = clients[clientId]?.deviceId else { return }
        send(.ack(), id: id, to: clientId)
        do {
            _ = try await devices.remove(deviceId)
        } catch {
            gatewayLogger.error("failed to remove an unpaired device: \(String(describing: error), privacy: .public)")
        }
        close(clientId, error: nil, id: nil, code: .normalClosure)
        for (otherId, other) in clients where other.deviceId == deviceId {
            close(otherId, error: .deviceRemoved, id: nil, code: .policyViolation)
        }
    }
}

extension ClientMessage {
    static let helloType = "hello"
}
