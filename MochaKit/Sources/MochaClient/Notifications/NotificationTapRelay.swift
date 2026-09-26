@MainActor
public final class NotificationTapRelay {
    private var pending: DeepLink?
    private var handler: ((DeepLink) -> Void)?

    public init() {}

    public func deliver(_ link: DeepLink) {
        guard let handler else {
            pending = link
            return
        }
        handler(link)
    }

    public func attach(_ handler: @escaping (DeepLink) -> Void) {
        self.handler = handler
        guard let link = pending else { return }
        pending = nil
        handler(link)
    }
}
