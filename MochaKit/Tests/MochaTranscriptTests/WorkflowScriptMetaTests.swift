import Foundation
import Testing
import MochaTranscript

@Suite
struct WorkflowScriptMetaTests {
    @Test func readsNameAndPhasesInEveryQuoteStyle() {
        let script = """
        import { helper } from './lib.js'

        export const meta = {
          // comentário com { chave
          name: 'demo-wave',
          description: `Onda ${1}`,
          limits: { agents: [1, 2, { nested: "}" }] },
          "phases": [
            { title: 'Implementar', detail: "Um agente por tarefa" },
            { title: "Verificar", model: 'sonnet' },
            { title: `Corrigir`, detail: 'Refaz o que falhou' },
          ],
        }

        export default async function run(ctx) {
          return ctx.agent({ prompt: `Tarefa ${ctx.args.task}` })
        }
        """
        #expect(WorkflowScriptMeta.parse(script) == WorkflowScriptMeta(name: "demo-wave", phases: [
            WorkflowScriptPhase(title: "Implementar", detail: "Um agente por tarefa"),
            WorkflowScriptPhase(title: "Verificar"),
            WorkflowScriptPhase(title: "Corrigir", detail: "Refaz o que falhou"),
        ]))
    }

    @Test func missingNameOrPhasesAreNotFailures() {
        #expect(WorkflowScriptMeta.parse("export const meta = { phases: [{ title: 'A' }] }") == WorkflowScriptMeta(name: nil, phases: [WorkflowScriptPhase(title: "A")]))
        #expect(WorkflowScriptMeta.parse("export const meta = { name: \"só-nome\" }") == WorkflowScriptMeta(name: "só-nome", phases: []))
        #expect(WorkflowScriptMeta.parse("export const meta={name:'a\\'b',phases:[]}") == WorkflowScriptMeta(name: "a'b", phases: []))
    }

    @Test(arguments: [
        "export default async function run() {}",
        "const meta = { name: 'fora do export' }",
        "export const metadata = { name: 'outro nome' }",
        "export const meta = { name: 'x', phases: [{ title: `Fase ${n}` }] }",
        "export const meta = { name: `nome ${x}` }",
        "export const meta = { name: nome }",
        "export const meta = { phases: [{ detail: 'sem título' }] }",
        "export const meta = { phases: [{ title: 'A', detail: detalhe }] }",
        "export const meta = { phases: phasesList }",
        "export const meta = { name: 'aberto', phases: [{ title: 'A' }",
        "export const meta = { name: 'sem fim",
        "export const meta = buildMeta()",
    ])
    func malformedOrDynamicMetaFailsWithoutThrowing(_ script: String) {
        #expect(WorkflowScriptMeta.parse(script) == nil)
    }
}
