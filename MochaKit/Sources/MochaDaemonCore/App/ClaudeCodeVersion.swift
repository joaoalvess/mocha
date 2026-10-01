public enum ClaudeCodeVersion {
    public static let lastValidated = "2.1.286"

    public static func isNewer(_ version: String, than reference: String = lastValidated) -> Bool {
        let lhs = components(version)
        let rhs = components(reference)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .split(separator: "-", maxSplits: 1)
            .first
            .map { $0.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } } ?? []
    }
}
