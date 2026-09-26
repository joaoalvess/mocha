import Foundation
import MochaDaemonCore
import MochaHerdr

enum StatusCommand {
    static let statusTimeout: Duration = .seconds(5)

    static func status(_ arguments: [String]) async -> Int32 {
        let options: CommandOptions
        switch CommandOptions.parse(arguments, allowed: ["--herdr-socket"], usage: "uso: mochad status [--herdr-socket <caminho>]") {
        case .success(let parsed): options = parsed
        case .failure(let error): return Console.fail(error.description, code: 64)
        }
        let paths = DaemonPaths()
        let local = await Doctor.localStatus(LocalControlClient(socketPath: paths.controlSocket.path(percentEncoded: false)))
        var herdrPing: HerdrPing?
        if case .failure = local {
            herdrPing = await HerdrProbe(socketPath: HerdrSocketPath.resolve(override: options.value("--herdr-socket"))).ping()
        }
        let inspector = ServeInspector(gatewayPort: (try? DaemonConfigStore(url: paths.configFile).read().gatewayPort) ?? DaemonConfig.defaultGatewayPort)
        let serve = DoctorChecks.serve(
            await inspector.diagnose(healthTimeout: statusTimeout),
            setupCommand: inspector.setupCommand,
            expectedTarget: inspector.expectedTarget
        )
        let report = StatusReport.make(local: local, herdrPing: herdrPing, serve: serve, now: Date())
        Console.line(report.text)
        return report.exitCode
    }

    static func doctor(_ arguments: [String]) async -> Int32 {
        let options: CommandOptions
        switch CommandOptions.parse(arguments, allowed: ["--herdr-socket"], usage: "uso: mochad doctor [--herdr-socket <caminho>]") {
        case .success(let parsed): options = parsed
        case .failure(let error): return Console.fail(error.description, code: 64)
        }
        let paths = DaemonPaths()
        let gatewayPort = (try? DaemonConfigStore(url: paths.configFile).read().gatewayPort) ?? DaemonConfig.defaultGatewayPort
        let doctor = Doctor(
            paths: paths,
            herdr: HerdrProbe(socketPath: HerdrSocketPath.resolve(override: options.value("--herdr-socket"))),
            local: LocalControlClient(socketPath: paths.controlSocket.path(percentEncoded: false)),
            serve: ServeInspector(gatewayPort: gatewayPort),
            signer: CodeSigner(),
            keyPresence: KeychainApnsKeyPresence(),
            executable: CurrentExecutable.url
        )
        let items = await doctor.run()
        Console.line(DoctorReport.render(items))
        return DoctorReport.exitCode(items)
    }
}
