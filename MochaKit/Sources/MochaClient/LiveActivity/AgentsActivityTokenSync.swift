import Foundation
import MochaProtocol

public actor AgentsActivityTokenSync {
    private var book: AgentsActivityTokenBook
    private let file: AgentsActivityTokenFile
    private let gateway: any AgentsActivityRegistering
    private var socket: (any AgentsActivityRegistering)?
    private var isFlushing = false
    private var isFlushRequested = false
    private var isResendRequested = false

    public init(
        environment: ApnsEnvironment,
        liveActivityIds: Set<String>,
        file: AgentsActivityTokenFile = AgentsActivityTokenFile(),
        gateway: any AgentsActivityRegistering
    ) {
        var book = file.load()
        let changedEnvironment = book.use(environment)
        let forgotActivities = book.forgetActivities(except: liveActivityIds)
        if changedEnvironment || forgotActivities {
            try? file.save(book)
        }
        self.book = book
        self.file = file
        self.gateway = gateway
    }

    public var tokens: AgentsActivityTokenBook {
        book
    }

    public func recordPushToStartToken(_ token: String) async {
        guard book.recordPushToStartToken(token) else { return }
        persist()
        await flush(resendingAll: false)
    }

    public func recordUpdateToken(_ token: String, activityId: String) async {
        guard book.recordUpdateToken(token, activityId: activityId) else { return }
        persist()
        await flush(resendingAll: false)
    }

    public func forgetActivity(_ activityId: String) {
        guard book.forgetActivity(activityId) else { return }
        persist()
    }

    public func deliverPending() async {
        guard book.hasUndelivered else { return }
        await flush(resendingAll: false)
    }

    public func socketOpened(_ socket: any AgentsActivityRegistering) async {
        self.socket = socket
        await flush(resendingAll: true)
    }

    public func socketClosed() {
        socket = nil
    }

    private func flush(resendingAll: Bool) async {
        isResendRequested = isResendRequested || resendingAll
        isFlushRequested = true
        guard !isFlushing else { return }
        isFlushing = true
        while isFlushRequested {
            isFlushRequested = false
            let includingDelivered = isResendRequested
            isResendRequested = false
            let channel = socket ?? gateway
            for registration in book.registrations(includingDelivered: includingDelivered) {
                guard await channel.register(registration) == .delivered else { break }
                if book.markDelivered(registration) {
                    persist()
                }
            }
        }
        isFlushing = false
    }

    private func persist() {
        try? file.save(book)
    }
}
