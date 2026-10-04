import Testing
import Foundation
@testable import DockaCore

@Suite("Manter acordado")
struct AcordadoTests {
    private let inicio = Date(timeIntervalSince1970: 1_000_000)

    @Test("A duração vira o fim certo")
    func fim() {
        #expect(Acordado.fim(de: .umaHora, desde: inicio) == inicio.addingTimeInterval(3600))
        #expect(Acordado.fim(de: .quinzeMinutos, desde: inicio) == inicio.addingTimeInterval(900))
        #expect(Acordado.fim(de: .semLimite, desde: inicio) == nil)
    }

    @Test("Sem limite nunca expira")
    func semLimite() {
        #expect(!Acordado.expirou(ate: nil, agora: .distantFuture))
        #expect(Acordado.restante(ate: nil, agora: inicio) == nil)
    }

    @Test("Expira exatamente no fim, e o restante não fica negativo")
    func expira() {
        let fim = inicio.addingTimeInterval(60)
        #expect(!Acordado.expirou(ate: fim, agora: inicio))
        #expect(Acordado.expirou(ate: fim, agora: fim))
        #expect(Acordado.restante(ate: fim, agora: fim.addingTimeInterval(30)) == 0)
    }

    @Test("Rótulo do tempo restante")
    func rotulo() {
        #expect(Acordado.rotulo(restante: nil) == "sem limite")
        #expect(Acordado.rotulo(restante: 0) == "menos de 1min")
        #expect(Acordado.rotulo(restante: 59.5) == "1min")
        #expect(Acordado.rotulo(restante: 12 * 60) == "12min")
        #expect(Acordado.rotulo(restante: 3600) == "1h")
        #expect(Acordado.rotulo(restante: 3600 + 5 * 60) == "1h 05min")
        // arredonda para cima: 1h e 30 s ainda é "1h 01min"
        #expect(Acordado.rotulo(restante: 3630) == "1h 01min")
    }

    @Test("Valor gravado desconhecido volta para o padrão")
    func persistido() {
        #expect(DuracaoAcordado(persisted: 120) == .duasHoras)
        #expect(DuracaoAcordado(persisted: 0) == .semLimite)
        #expect(DuracaoAcordado(persisted: 7) == .umaHora)
    }
}
