import Testing
@testable import MochaClient

struct ToolPresentationTests {
    @Test func bashIsShownAsShell() {
        #expect(ToolPresentation.displayName(for: "Bash") == "Shell")
    }

    @Test(arguments: ["Read", "Edit", "Write", "Grep", "Task", "WebFetch", "bash"])
    func otherToolsKeepTheirName(name: String) {
        #expect(ToolPresentation.displayName(for: name) == name)
    }

    @Test(arguments: [
        ("Bash", ToolIcon.shell),
        ("BashOutput", .shell),
        ("Shell", .shell),
        ("Read", .document),
        ("Edit", .pencil),
        ("MultiEdit", .pencil),
        ("Write", .pencil),
        ("Grep", .sparkles),
        ("Task", .sparkles),
    ])
    func picksIcon(name: String, icon: ToolIcon) {
        #expect(ToolPresentation.icon(for: name) == icon)
    }
}
