#if DEBUG
import Foundation

enum MarkdownPreviewSamples {
    static let turnTitle = "Login com a Apple"
    static let turnSubtitle = "login-social • opus-5-5 • feat/login-social"
    static let turnTools = [
        "xcrun simctl launch booted com.demo.app",
        "xcrun simctl io booted screenshot /tmp/login.png",
    ]
    static let turnFooter = "Brewed for 45s"
    static let turnRecap = "Você pediu login com a Apple no worktree login-social. Está pronto e testado; falta decidir se eu abro o PR."

    static let turn = """
    Revisei o fluxo inteiro no simulador e o login volta para a Home sem piscar.

    ## Login com a Apple pronto

    O coordinator usa `ASAuthorizationAppleIDProvider` e guarda o token em `KeychainSessionStore`.

    - `AppleSignInCoordinator` com **async/await**
    - entitlement `applesignin` no target
    - 6 testes novos, todos passando

    | Arquivo | Mudança |
    |---|---|
    | `AppleSignInCoordinator` | novo |
    | `AuthService` | signInWithApple() |
    | `DemoApp.entitlements` | Sign in with Apple |

    ```swift
    // AuthService.swift
    let credential = try await coordinator.signIn()
    try keychain.save(credential.identityToken, for: .appleSession)
    ```
    """

    static let elements = """
    # Título de nível 1

    ## Título de nível 2

    ### Título de nível 3

    Parágrafo com **negrito**, *itálico*, ***negrito e itálico***, ~~riscado~~, `código inline` e um [link para o swift-markdown](https://github.com/swiftlang/swift-markdown). Autolink: <https://github.com/JetBrains/JetBrainsMono>.
    Quebra suave vira espaço,\\
    e a barra no fim força a quebra de linha.

    - Item com `AppSession`
    - Item com lista aninhada:
      - segundo nível com **negrito**
        - terceiro nível
    - [x] tarefa concluída
    - [ ] tarefa pendente

    1. Primeiro passo
    2. Segundo passo com `swift test`
       1. subpasso a
       2. subpasso b

    9) Nono item
    10) Décimo item, com o número mais largo

    > Citação com **ênfase** e `código`.
    >
    > Segundo parágrafo da citação.
    """

    static let blocks = """
    ```bash
    # instala e confere o daemon
    swift build -c release --product mochad && ./.build/release/mochad doctor --verbose | tee /tmp/doctor.log
    ```

    ```swift
    let pitch = 20
    ```

    | # | Tamanho | À direita |
    |:-:|---|--:|
    | 1 | pequeno | 12 ms |
    | 2 | médio | 128 ms |

    | Arquivo | Linhas | Mudança | Dono | Observação |
    |---|--:|---|---|---|
    | `App/Sources/Markdown/MarkdownView.swift` | 120 | novo | WP-I4 | renderizador próprio sobre a AST do swift-markdown |
    | `App/Sources/Chat/ChatScreen.swift` | 300 | usa o MarkdownView | WP-I5 | lista do chat |

    ---

    Depois da régua: HTML inline<br>quebra a linha, e a imagem ![logo do Mocha](https://example.com/mocha.png) vira link.
    """

    static func largeMessage(minimumBytes: Int = 20 * 1024) -> String {
        var sections: [String] = []
        var bytes = 0
        var index = 1
        while bytes < minimumBytes {
            let section = largeSection(index)
            sections.append(section)
            bytes += section.utf8.count + 2
            index += 1
        }
        return sections.joined(separator: "\n\n")
    }

    private static func largeSection(_ index: Int) -> String {
        var parts = [
            "### Etapa \(index): `Modulo\(index)Store`",
            "Revisei o `Modulo\(index)Store` e o fluxo de **reconexão** continua estável: o *backoff* respeita o limite de 8 s, o `heartbeat` fecha a conexão morta em 15 s e a lista volta para o fim sem salto. Detalhes na [SPEC §2.3](https://example.com/spec).",
            "O próximo passo é ligar o `Modulo\(index)Coordinator` ao `AppSession`, conferir o `setForeground` ao trocar de chat e medir a paginação com 2.000 itens no simulador, sem nenhum build rodando na máquina.",
            """
            - `Modulo\(index)Coordinator` com **async/await**
            - entitlement `modulo\(index)` no target
              - teste `modulo\(index)Reconnects()` passando
            - 6 testes novos, todos passando
            """,
        ]
        if index.isMultiple(of: 4) {
            parts.append("""
            ```swift
            let store = Modulo\(index)Store(connection: connection)
            try await store.reconnect(timeout: .seconds(15), retries: 8)
            ```
            """)
        }
        if index.isMultiple(of: 8) {
            parts.append("""
            | Arquivo | Mudança |
            |---|---|
            | `Modulo\(index)Store.swift` | novo |
            | `Modulo\(index)View.swift` | layout |
            """)
        }
        return parts.joined(separator: "\n\n")
    }
}
#endif
