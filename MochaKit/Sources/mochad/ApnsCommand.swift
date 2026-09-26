import Foundation
import MochaDaemonCore
import MochaProtocol
import Security

enum ApnsCommand {
    static let usage = """
        uso:
          mochad apns import <arquivo.p8> --key-id <KID> --team-id <TID> [--bundle-id <id>]
          mochad apns test --device <id> [envio] [--title <t>] [--body <b>] [--time-sensitive]
          mochad apns test --token <hex> --env sandbox|production [envio] [--title <t>] [--body <b>] [--time-sensitive]
          mochad apns liveactivity start|update|end --token <hex> --env sandbox|production [envio] [estado]

        envio:  --priority 5|10  --expiration <segundos a partir de agora, ou 0>  --collapse-id <id>
        estado: --working <n>  --waiting <n>  --title <destaque>  --workspace <nome>  --no-highlight
                --stale-in <segundos>  --dismiss-in <segundos> (end)
        """

    private static let flags: Set<String> = ["--time-sensitive", "--no-highlight"]

    static func run(_ arguments: [String]) async -> Int32 {
        guard let subcommand = arguments.first else { return fail(usage, code: 64) }
        let options: CommandOptions
        do {
            options = try CommandOptions(Array(arguments.dropFirst()), flags: flags)
        } catch {
            return fail("\(error)\n\n\(usage)", code: 64)
        }
        do {
            switch subcommand {
            case "import":
                return try runImport(options)
            case "test":
                return try await runTest(options)
            case "liveactivity":
                return try await runLiveActivity(options)
            default:
                return fail(usage, code: 64)
            }
        } catch let error as CommandOptions.UsageError {
            return fail("\(error)\n\n\(usage)", code: 64)
        } catch {
            return fail(describe(error), code: 1)
        }
    }

    private static func runImport(_ options: CommandOptions) throws -> Int32 {
        guard options.positional.count == 1 else { throw CommandOptions.UsageError("informe o caminho da .p8") }
        let fileURL = URL(filePath: (options.positional[0] as NSString).expandingTildeInPath)
        let config = try ApnsKeyImporter().importKey(
            fileURL: fileURL,
            keyId: try options.required("--key-id"),
            teamId: try options.required("--team-id"),
            bundleId: options.value("--bundle-id") ?? ApnsConfig.defaultBundleId
        )
        print("chave \(config.keyId) guardada no Keychain de login (serviço \(KeychainApnsKeyStore.service), conta \(config.keyId))")
        print("config: \(ApnsConfigStore.defaultURL.path(percentEncoded: false)) → apns {teamId, keyId \(config.keyId), bundleId \(config.bundleId)}")
        return 0
    }

    private static func runTest(_ options: CommandOptions) async throws -> Int32 {
        let target = try await Target(options, allowsDevice: true)
        let sentAt = Date()
        let push = ApnsAlertPush(
            title: options.value("--title") ?? "Mocha",
            body: options.value("--body") ?? "Push de teste enviado do Mac às \(clockTime(sentAt))",
            threadId: "mocha-test",
            interruptionLevel: options.has("--time-sensitive") ? .timeSensitive : nil,
            kind: "test",
            sentAt: sentAt
        )
        return try await send(
            label: "alerta",
            payload: try push.payload(),
            pushType: .alert,
            topic: ApnsTopic.alert(bundleId: target.config.bundleId),
            defaultPriority: .high,
            sentAt: sentAt,
            target: target,
            options: options
        )
    }

    private static func runLiveActivity(_ options: CommandOptions) async throws -> Int32 {
        guard let eventName = options.positional.first, ["start", "update", "end"].contains(eventName) else {
            throw CommandOptions.UsageError("informe start, update ou end")
        }
        let target = try await Target(options, allowsDevice: false)
        let sentAt = Date()
        let isEnd = eventName == "end"
        let working = try options.integer("--working") ?? (isEnd ? 0 : 1)
        let waiting = try options.integer("--waiting") ?? 0
        let highlight: LiveActivityContentState.Highlight? = options.has("--no-highlight") || (isEnd && options.value("--title") == nil)
            ? nil
            : .init(
                agentId: "w1:p1",
                title: String((options.value("--title") ?? "Rodando os testes do Mocha").prefix(60)),
                workspaceLabel: options.value("--workspace") ?? "demo-app",
                status: waiting > 0 ? "blocked" : "working",
                since: sentAt.addingTimeInterval(-125)
            )
        let state = LiveActivityContentState(working: working, waiting: waiting, highlight: highlight, updatedAt: sentAt)
        let event: LiveActivityEvent
        switch eventName {
        case "start":
            event = .start(alert: LiveActivityStartAlert(title: "Mocha", body: summary(working: working, waiting: waiting)))
        case "update":
            event = .update
        default:
            event = .end(dismissalDate: sentAt.addingTimeInterval(try options.integer("--dismiss-in").map(TimeInterval.init) ?? 15 * 60))
        }
        let push = LiveActivityPush(
            event: event,
            contentState: state,
            timestamp: sentAt,
            staleDate: try options.integer("--stale-in").map { sentAt.addingTimeInterval(TimeInterval($0)) }
        )
        return try await send(
            label: "liveactivity \(eventName)",
            payload: try push.payload(),
            pushType: .liveactivity,
            topic: ApnsTopic.liveActivity(bundleId: target.config.bundleId),
            defaultPriority: eventName == "update" ? .low : .high,
            sentAt: sentAt,
            target: target,
            options: options
        )
    }

    private static func send(
        label: String,
        payload: Data,
        pushType: ApnsPushType,
        topic: String,
        defaultPriority: ApnsPriority,
        sentAt: Date,
        target: Target,
        options: CommandOptions
    ) async throws -> Int32 {
        let priority = try options.integer("--priority").map { value in
            guard let priority = ApnsPriority(rawValue: value) else { throw CommandOptions.UsageError("--priority aceita 5 ou 10") }
            return priority
        } ?? defaultPriority
        let expiration: ApnsExpiration? = try options.integer("--expiration").map { seconds in
            seconds == 0 ? .deliverOnce : .at(sentAt.addingTimeInterval(TimeInterval(seconds)))
        }
        let request = ApnsRequest(
            deviceToken: target.token,
            environment: target.environment,
            pushType: pushType,
            topic: topic,
            priority: priority,
            expiration: expiration,
            collapseId: options.value("--collapse-id"),
            payload: payload
        )
        try request.validate()
        let client = ApnsClient(tokens: ApnsTokenProvider(key: target.key))
        let recipient = target.deviceName.map { "\($0), " } ?? ""
        print("enviando \(label) para \(recipient)\(target.token.prefix(8))… (\(target.environment.rawValue)) · \(payload.count) bytes")
        print("headers: " + request.headers.map { "\($0.name)=\($0.value)" }.joined(separator: " "))
        print("payload: " + (String(data: payload, encoding: .utf8) ?? ""))
        print("enviado em \(timestamp(sentAt)) (sentAt \(Int64((sentAt.timeIntervalSince1970 * 1000).rounded())))")
        let clock = ContinuousClock()
        let started = clock.now
        let response = try await client.send(request)
        let elapsed = clock.now - started
        let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        var line = "resposta \(response.status)"
        if let reason = response.reason { line += " \(reason)" }
        line += String(format: " em %.0f ms", milliseconds)
        if let networkProtocol = response.networkProtocol { line += " · \(networkProtocol)" }
        if let apnsId = response.apnsId { line += " · apns-id \(apnsId)" }
        if let uniqueId = response.uniqueId { line += " · apns-unique-id \(uniqueId)" }
        if let inactiveSince = response.inactiveSince { line += " · inativo desde \(timestamp(inactiveSince))" }
        print(line)
        if response.deviceTokenIsInvalid {
            print("o APNs recusou esse token: abra o app no iPhone para registrar um novo")
        }
        return response.isSuccess ? 0 : 1
    }

    private struct Target {
        let token: String
        let environment: ApnsEnvironment
        let deviceName: String?
        let config: ApnsConfig
        let key: ApnsSigningKey

        init(_ options: CommandOptions, allowsDevice: Bool) async throws {
            let registration: ApnsRegistration
            if allowsDevice, let deviceId = options.value("--device") {
                guard options.value("--token") == nil, options.value("--env") == nil else {
                    throw CommandOptions.UsageError("use --device ou --token com --env, não os dois")
                }
                let paths = DaemonPaths()
                guard let record = try await DeviceStore(fileURL: paths.devicesFile).devices().first(where: { $0.id == deviceId }) else {
                    throw CommandOptions.UsageError("aparelho \(deviceId) não está em \(paths.display(paths.devicesFile)) (mochad devices)")
                }
                guard let apns = record.apns else {
                    throw CommandOptions.UsageError("\(record.name) ainda não mandou o token de push: abra o app no iPhone conectado ao Mac")
                }
                registration = apns
                deviceName = record.name
            } else {
                let token = try options.required("--token")
                guard let environment = ApnsEnvironment(rawValue: try options.required("--env")) else {
                    throw CommandOptions.UsageError("--env aceita sandbox ou production")
                }
                registration = ApnsRegistration(token: token, env: environment)
                deviceName = nil
            }
            guard ApnsRequest.isValidDeviceToken(registration.token) else {
                throw CommandOptions.UsageError("o token precisa ser hexadecimal")
            }
            let loaded = try ApnsKeyImporter().loadSigningKey()
            self.token = registration.token.lowercased()
            self.environment = registration.env
            self.config = loaded.config
            self.key = loaded.key
        }
    }

    private static func summary(working: Int, waiting: Int) -> String {
        guard working + waiting > 0 else { return "Tudo pronto" }
        return [working > 0 ? "\(working) trabalhando" : nil, waiting > 0 ? "\(waiting) esperando você" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private static func describe(_ error: any Error) -> String {
        guard let error = error as? ApnsError else { return "erro: \(error)" }
        switch error {
        case .notConfigured:
            return "APNs não configurado: rode mochad apns import <arquivo.p8> --key-id <KID> --team-id <TID>"
        case .keyNotFound(let keyId):
            return "chave \(keyId) não encontrada no Keychain (serviço \(KeychainApnsKeyStore.service))"
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "sem descrição"
            return "o Keychain recusou a operação (OSStatus \(status): \(message))"
        case .invalidPrivateKey:
            return "a .p8 não é uma chave P-256 em PEM"
        case .invalidKeyId:
            return "--key-id precisa de 10 caracteres A-Z/0-9"
        case .invalidTeamId:
            return "--team-id precisa de 10 caracteres A-Z/0-9"
        default:
            return "erro: \(error)"
        }
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current))
    }

    private static func clockTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }

    private static func fail(_ message: String, code: Int32) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return code
    }
}
