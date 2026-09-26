import SwiftUI

struct MarkdownView: View {
    let markdown: String

    var body: some View {
        Text(markdown)
            .chatBodyStyle()
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
