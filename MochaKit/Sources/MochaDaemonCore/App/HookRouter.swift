import Foundation
import MochaProtocol

public actor HookRouter {
    private let hub: SessionHub
    private let herdr: any HerdrBridging
    private let push: PushService
    private var tasks: [Task<Void, Never>] = []

    public init(hub: SessionHub, herdr: any HerdrBridging, push: PushService) {
        self.hub = hub
        self.herdr = herdr
        self.push = push
    }

    public func start(hooks: AsyncStream<ReceivedHook>) {
        guard tasks.isEmpty else { return }
        let statuses = herdr.events()
        let hub = hub
        let herdr = herdr
        let push = push
        tasks = [
            Task {
                for await hook in hooks {
                    await Self.route(hook, hub: hub, herdr: herdr, push: push)
                }
            },
            Task {
                for await event in statuses {
                    guard case .agentStatus(let agentId, let status, _) = event else { continue }
                    await push.agentStatusChanged(agentId, to: status)
                }
            },
        ]
    }

    public func stop() async {
        let running = tasks
        tasks.removeAll()
        for task in running {
            task.cancel()
        }
        for task in running {
            await task.value
        }
    }

    static func route(_ hook: ReceivedHook, hub: SessionHub, herdr: any HerdrBridging, push: PushService) async {
        await hub.hookReceived(hook)
        switch hook.event {
        case .sessionStart(let start):
            await herdr.refreshAgent(hook.agentId, expectingSession: start.context.sessionId)
        case .stop:
            await herdr.refreshDirtyState(ofAgent: hook.agentId)
        case .userPromptSubmit, .notification, .permissionRequest:
            break
        }
        await push.handle(hook)
    }
}
