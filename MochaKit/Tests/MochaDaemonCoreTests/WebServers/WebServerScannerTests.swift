import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

struct WebServerScannerTests {
    private static let mochadPorts: Set<Int> = [47420, 47421]

    private func scanner(
        _ processes: [ListeningProcess],
        probe: FakeWebPageProbe,
        probeTimeout: Duration = .milliseconds(800),
        deadline: Duration = .seconds(2),
        listingDelay: Duration = .zero
    ) -> WebServerScanner {
        WebServerScanner(
            configuration: .init(excludedPorts: Self.mochadPorts, probeTimeout: probeTimeout, deadline: deadline),
            processes: FakeProcessListing(processes: processes, delay: listingDelay),
            probe: probe
        )
    }

    @Test func returnsHtmlServersWithTitleProcessAndDirectory() async {
        let probe = FakeWebPageProbe([5190: .respond(.page("<title>Portal &amp; Cliente</title>"))])
        let servers = await scanner(
            [ListeningProcess(pid: 53243, name: "node", executablePath: "/opt/homebrew/bin/node", directory: "/Users/joao/portal", ports: [5190])],
            probe: probe
        ).scan()
        #expect(servers == [WebServer(pid: 53243, process: "node", port: 5190, title: "Portal & Cliente", directory: "/Users/joao/portal")])
    }

    @Test func htmlWithoutTitleStaysWithoutTitle() async {
        let probe = FakeWebPageProbe([6173: .respond(.page("<html><body>app</body></html>"))])
        let servers = await scanner([ListeningProcess(pid: 5335, name: "node", ports: [6173])], probe: probe).scan()
        #expect(servers == [WebServer(pid: 5335, process: "node", port: 6173)])
    }

    @Test func largeHtmlOnlyReadsTitleFromTheFirst64KB() async {
        let filler = String(repeating: "x", count: 100 * 1024)
        let probe = FakeWebPageProbe([
            3000: .respond(.page("<title>Grande</title>" + filler)),
            3001: .respond(.page("<body>" + filler + "<title>Tarde</title>")),
        ])
        let servers = await scanner([ListeningProcess(pid: 10, name: "next-server", ports: [3000, 3001])], probe: probe).scan()
        #expect(servers.map(\.port) == [3000, 3001])
        #expect(servers.map(\.title) == ["Grande", nil])
    }

    @Test func dropsNonHtmlAndUnreachablePorts() async {
        let probe = FakeWebPageProbe([
            4000: .respond(.notHTML),
            4001: .respond(.unreachable),
            4002: .respond(.page("<title>Ok</title>")),
        ])
        let servers = await scanner([ListeningProcess(pid: 20, name: "ruby", ports: [4000, 4001, 4002])], probe: probe).scan()
        #expect(servers.map(\.port) == [4002])
    }

    @Test func slowProbeTimesOutWithoutHoldingTheOthers() async {
        let probe = FakeWebPageProbe([
            8000: .hang,
            8001: .respond(.page("<title>Rápido</title>")),
        ])
        let clock = ContinuousClock()
        let start = clock.now
        let servers = await scanner(
            [ListeningProcess(pid: 30, name: "python3", ports: [8000, 8001])],
            probe: probe,
            probeTimeout: .milliseconds(100)
        ).scan()
        #expect(clock.now - start < .seconds(5))
        #expect(servers.map(\.port) == [8001])
        #expect(probe.probed == [8000, 8001])
    }

    @Test func slowListingSpendsTheWholeDeadlineAndProbesNothing() async {
        let probe = FakeWebPageProbe([8080: .respond(.page("<title>X</title>"))])
        let servers = await scanner(
            [ListeningProcess(pid: 40, name: "node", ports: [8080])],
            probe: probe,
            deadline: .milliseconds(50),
            listingDelay: .milliseconds(100)
        ).scan()
        #expect(servers.isEmpty)
        #expect(probe.probed.isEmpty)
    }

    @Test func duplicatePortKeepsTheLowestPid() async {
        let probe = FakeWebPageProbe([5173: .respond(.page("<title>Vite</title>"))])
        let servers = await scanner(
            [
                ListeningProcess(pid: 900, name: "esbuild", directory: "/b", ports: [5173]),
                ListeningProcess(pid: 120, name: "node", directory: "/a", ports: [5173]),
                ListeningProcess(pid: 500, name: "bun", directory: "/c", ports: [5173]),
            ],
            probe: probe
        ).scan()
        #expect(servers == [WebServer(pid: 120, process: "node", port: 5173, title: "Vite", directory: "/a")])
        #expect(probe.probed == [5173])
    }

    @Test func mochadPortsAreNeverProbed() async {
        let probe = FakeWebPageProbe([
            47420: .respond(.page("<title>Hooks</title>")),
            47421: .respond(.page("<title>Gateway</title>")),
            5190: .respond(.page("<title>App</title>")),
        ])
        let servers = await scanner([ListeningProcess(pid: 1, name: "mochad", ports: [47420, 47421, 5190])], probe: probe).scan()
        #expect(servers.map(\.port) == [5190])
        #expect(probe.probed == [5190])
    }

    @Test func systemAndAppBundleExecutablesAreSkipped() async {
        let ports = [7001, 7002, 7003, 7004, 7005, 7006]
        let probe = FakeWebPageProbe(Dictionary(uniqueKeysWithValues: ports.map { ($0, .respond(.page("<title>\($0)</title>"))) }))
        let servers = await scanner(
            [
                ListeningProcess(pid: 1, name: "rapportd", executablePath: "/usr/libexec/rapportd", ports: [7001]),
                ListeningProcess(pid: 2, name: "ControlCenter", executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", ports: [7002]),
                ListeningProcess(pid: 3, name: "Figma", executablePath: "/Applications/Figma.app/Contents/MacOS/Figma", ports: [7003]),
                ListeningProcess(pid: 4, name: "node", executablePath: "/opt/homebrew/bin/node", ports: [7004]),
                ListeningProcess(pid: 5, name: "tool", executablePath: "/Applications/tools/tool", ports: [7005]),
                ListeningProcess(pid: 6, name: "unknown", ports: [7006]),
            ],
            probe: probe
        ).scan()
        #expect(servers.map(\.port) == [7004, 7005, 7006])
        #expect(probe.probed == [7004, 7005, 7006])
    }

    @Test func sortsByPortAscending() async {
        let probe = FakeWebPageProbe([
            9000: .respond(.page("")),
            3000: .respond(.page("")),
            5173: .respond(.page("")),
        ])
        let servers = await scanner(
            [
                ListeningProcess(pid: 1, name: "a", ports: [9000]),
                ListeningProcess(pid: 2, name: "b", ports: [5173, 3000]),
            ],
            probe: probe
        ).scan()
        #expect(servers.map(\.port) == [3000, 5173, 9000])
    }

    @Test func systemExecutableRule() {
        #expect(WebServerScanner.isSystemExecutable("/System/Library/x"))
        #expect(WebServerScanner.isSystemExecutable("/usr/libexec/sharingd"))
        #expect(WebServerScanner.isSystemExecutable("/Applications/Xcode.app/Contents/MacOS/Xcode"))
        #expect(!WebServerScanner.isSystemExecutable("/Applications/Utilities/x"))
        #expect(!WebServerScanner.isSystemExecutable("/Applications/Foo.app"))
        #expect(!WebServerScanner.isSystemExecutable("/usr/local/bin/node"))
        #expect(!WebServerScanner.isSystemExecutable("/Users/joao/Applications/Foo.app/Contents/MacOS/Foo"))
    }
}
