import Testing
@testable import DockaCore

@Suite("Mouse")
struct RolagemTests {
    private let dente = Rolada(linhasY: 3, linhasX: 0, pontosY: 36, pontosX: 0)

    @Test("Sem ajuste, nada muda")
    func identidade() {
        #expect(Rolagem.transformar(dente, com: .init(), modificadores: []) == dente)
    }

    @Test("Inverter só o eixo pedido")
    func inverter() {
        let r = Rolagem.transformar(Rolada(linhasY: 2, linhasX: -1, pontosY: 20, pontosX: -10),
                                    com: .init(inverterVertical: true), modificadores: [])
        #expect(r == Rolada(linhasY: -2, linhasX: -1, pontosY: -20, pontosX: -10))
    }

    @Test("Linear: um dente vale sempre o mesmo, rápido ou devagar")
    func linear() {
        let a = AjustesDeRolagem(linhasPorDente: 3)
        let rapido = Rolada(linhasY: -9, linhasX: 0, pontosY: -140, pontosX: 0)
        #expect(Rolagem.transformar(rapido, com: a, modificadores: []) == Rolada(linhasY: -3, linhasX: 0, pontosY: -30, pontosX: 0))
        #expect(Rolagem.transformar(dente, com: a, modificadores: []).pontosY == 30)
    }

    @Test("Linear e invertido juntos")
    func linearInvertido() {
        let a = AjustesDeRolagem(inverterVertical: true, linhasPorDente: 5)
        #expect(Rolagem.transformar(dente, com: a, modificadores: []).linhasY == -5)
    }

    @Test("Segurando a tecla, o vertical vira horizontal")
    func deLado() {
        let a = AjustesDeRolagem(deLado: [.option])
        #expect(Rolagem.transformar(dente, com: a, modificadores: [.option])
                == Rolada(linhasY: 0, linhasX: 3, pontosY: 0, pontosX: 36))
        // sem a tecla, segue vertical
        #expect(Rolagem.transformar(dente, com: a, modificadores: []) == dente)
    }

    @Test("O deslize suave soma a distância exata e desacelera")
    func suave() {
        let p = Rolagem.passosSuaves(distancia: 100, quadros: 20)
        #expect(p.count == 20)
        #expect(abs(p.reduce(0, +) - 100) < 1e-9)
        #expect(p.first! > p.last!)
        #expect(Rolagem.passosSuaves(distancia: 7, quadros: 0) == [7])
    }

    @Test("Botões laterais: voltar, avançar, e o da Órbita fica com ela")
    func botoes() {
        #expect(Rolagem.navegacao(botao: 3, botaoDaOrbita: -1) == .voltar)
        #expect(Rolagem.navegacao(botao: 4, botaoDaOrbita: -1) == .avancar)
        #expect(Rolagem.navegacao(botao: 3, botaoDaOrbita: 3) == nil)
        #expect(Rolagem.navegacao(botao: 2, botaoDaOrbita: -1) == nil)
    }
}
