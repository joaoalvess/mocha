import Foundation

public enum ContextWindow {
    public static let standard = 200_000
    public static let extended = 1_000_000

    private static let extendedFamilies = ["claude-opus-5", "claude-fable", "claude-sonnet-5"]
    private static let opusFourPrefix = "claude-opus-4-"
    private static let firstExtendedOpusFourMinor = 7

    public static func size(forModel model: String) -> Int {
        let name = model.lowercased()
        if extendedFamilies.contains(where: name.hasPrefix) {
            return extended
        }
        if name.hasPrefix(opusFourPrefix), let minor = opusFourMinor(in: name), minor >= firstExtendedOpusFourMinor {
            return extended
        }
        return standard
    }

    private static func opusFourMinor(in name: String) -> Int? {
        let component = name.dropFirst(opusFourPrefix.count).prefix(while: { $0 != "-" })
        let digits = component.prefix(while: { $0.isASCII && $0.isNumber })
        guard (1...2).contains(digits.count) else { return nil }
        return Int(digits)
    }
}
