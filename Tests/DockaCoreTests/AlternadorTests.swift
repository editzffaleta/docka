import Testing
@testable import DockaCore

@Suite("Alternador de apps")
struct AlternadorTests {

    @Test("Ordena pelo uso; quem nunca foi ativado vai para o fim")
    func porUso() {
        #expect(Alternador.porUso([10, 20, 30, 40], historico: [30, 10]) == [30, 10, 20, 40])
        #expect(Alternador.porUso([1, 2], historico: []) == [1, 2])
    }

    @Test("Ativar leva para a frente, sem repetir e com limite")
    func registrar() {
        #expect(Alternador.registrar(5, em: [1, 5, 2]) == [5, 1, 2])
        #expect(Alternador.registrar(9, em: [1, 2, 3], limite: 3) == [9, 1, 2])
    }

    @Test("Abre no segundo, como o ⌘Tab")
    func inicial() {
        #expect(Alternador.selecaoInicial(total: 5) == 1)
        #expect(Alternador.selecaoInicial(total: 1) == 0)
        #expect(Alternador.selecaoInicial(total: 0) == 0)
    }

    @Test("Avançar e voltar dão a volta nas pontas")
    func mover() {
        #expect(Alternador.mover(3, passo: 1, total: 4) == 0)
        #expect(Alternador.mover(0, passo: -1, total: 4) == 3)
        #expect(Alternador.mover(0, passo: 1, total: 0) == 0)
    }

    @Test("Soltar qualquer modificador do gatilho confirma")
    func segurando() {
        #expect(Alternador.aindaSegurando(gatilho: [.option], agora: [.option]))
        #expect(Alternador.aindaSegurando(gatilho: [.option], agora: [.option, .shift]))
        #expect(!Alternador.aindaSegurando(gatilho: [.option], agora: []))
        #expect(!Alternador.aindaSegurando(gatilho: [.command, .option], agora: [.command]))
        // só shift não segura nada: sem ⌘/⌥/⌃ não há o que soltar
        #expect(!Alternador.aindaSegurando(gatilho: [.shift], agora: [.shift]))
    }

    @Test("O alternador é um atalho próprio")
    func atalho() {
        #expect(AcaoDeAtalho(id: AcaoDeAtalho.alternador.id) == .alternador)
    }
}
