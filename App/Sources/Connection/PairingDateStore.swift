import Foundation

@MainActor
protocol PairingDateStore: AnyObject {
    var pairedAt: Date? { get set }
}

@MainActor
final class UserDefaultsPairingDateStore: PairingDateStore {
    static let key = "pairing.pairedAt"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pairedAt: Date? {
        get { defaults.object(forKey: Self.key) as? Date }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

@MainActor
final class InMemoryPairingDateStore: PairingDateStore {
    var pairedAt: Date?

    init(pairedAt: Date? = nil) {
        self.pairedAt = pairedAt
    }
}
