actor ImageDecodeLimiter {
    static let defaultLimit = 2

    let limit: Int
    private(set) var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int = ImageDecodeLimiter.defaultLimit) {
        self.limit = max(1, limit)
    }

    var waitingCount: Int {
        waiters.count
    }

    func acquire() async {
        guard activeCount >= limit else {
            activeCount += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard !waiters.isEmpty else {
            activeCount = max(0, activeCount - 1)
            return
        }
        waiters.removeFirst().resume()
    }
}
