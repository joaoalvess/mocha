import os
import SwiftUI

enum ChatSignposts {
    static let subsystem = "com.joaoalves.mocha"
    static let category = "chat"
    static let signposter = OSSignposter(subsystem: subsystem, category: category)
    static let logger = Logger(subsystem: subsystem, category: category)
}

struct SignpostedRowLayout: Layout {
    let kind: StaticString

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let signposter = ChatSignposts.signposter
        let state = signposter.beginInterval("rowLayout", id: signposter.makeSignpostID(), "\(String(describing: kind), privacy: .public)")
        defer { signposter.endInterval("rowLayout", state) }
        return subview.sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
