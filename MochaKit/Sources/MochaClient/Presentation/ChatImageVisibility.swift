import Foundation
import MochaProtocol

public enum ChatImageVisibility {
    public static func visiblePaths(in items: [ChatItem]) -> [String: [String]] {
        var shownInTurn: Set<String> = []
        var visible: [String: [String]] = [:]
        for item in items {
            if case .userPrompt = item.kind {
                shownInTurn.removeAll()
            }
            guard !item.imagePaths.isEmpty else { continue }
            let paths = item.imagePaths.filter { shownInTurn.insert($0).inserted }
            if !paths.isEmpty {
                visible[item.id] = paths
            }
        }
        return visible
    }

    public static func applied(to items: [ChatItem]) -> [ChatItem] {
        guard items.contains(where: { !$0.imagePaths.isEmpty }) else { return items }
        let visible = visiblePaths(in: items)
        return items.map { item in
            guard !item.imagePaths.isEmpty else { return item }
            var item = item
            item.imagePaths = visible[item.id] ?? []
            return item
        }
    }
}
