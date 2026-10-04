import Testing
import Foundation
@testable import DockaCore

@Suite("Alertas")
struct AlertasTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func min(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    @Test("CPU só avisa depois de ficar alta pelo tempo todo")
    func cpuContinua() {
        var v = VigiaDeAlertas(limites: .init(cpu: 0.85, cpuMinutos: 2))
        #expect(v.cpu(0.95, em: min(0)) == nil)
        #expect(v.cpu(0.95, em: min(1.9)) == nil)
        #expect(v.cpu(0.95, em: min(2))?.tipo == .cpu)
        // já avisou: não repete enquanto continua alta
        #expect(v.cpu(0.99, em: min(5)) == nil)
    }

    @Test("Um vale no meio zera a contagem da CPU")
    func cpuInterrompida() {
        var v = VigiaDeAlertas(limites: .init(cpu: 0.85, cpuMinutos: 2))
        _ = v.cpu(0.95, em: min(0))
        _ = v.cpu(0.50, em: min(1.5))
        #expect(v.cpu(0.95, em: min(2)) == nil)
        #expect(v.cpu(0.95, em: min(4))?.tipo == .cpu)
    }

    @Test("A CPU só rearma caindo bem abaixo do limite")
    func cpuRearme() {
        var v = VigiaDeAlertas(limites: .init(cpu: 0.85, cpuMinutos: 0))
        #expect(v.cpu(0.90, em: min(0)) != nil)
        // caiu um pouco, mas dentro da folga: oscilar no limite não reavisa
        _ = v.cpu(0.80, em: min(1))
        #expect(v.cpu(0.90, em: min(2)) == nil)
        _ = v.cpu(0.70, em: min(3))
        #expect(v.cpu(0.90, em: min(4)) != nil)
    }

    @Test("Disco avisa uma vez e rearma com folga")
    func disco() {
        var v = VigiaDeAlertas(limites: .init(discoLivreGB: 10))
        #expect(v.disco(livre: 20_000_000_000) == nil)
        #expect(v.disco(livre: 9_000_000_000)?.tipo == .disco)
        #expect(v.disco(livre: 8_000_000_000) == nil)
        _ = v.disco(livre: 11_000_000_000)          // folga insuficiente
        #expect(v.disco(livre: 9_000_000_000) == nil)
        _ = v.disco(livre: 13_000_000_000)          // passou de 12 GB
        #expect(v.disco(livre: 9_000_000_000) != nil)
    }

    @Test("Bateria: só descarregando, uma vez por descarga")
    func bateria() {
        var v = VigiaDeAlertas(limites: .init(bateria: 0.20))
        #expect(v.bateria(0.15, carregando: true, naTomada: true) == nil)
        #expect(v.bateria(0.19, carregando: false, naTomada: false)?.tipo == .bateria)
        #expect(v.bateria(0.12, carregando: false, naTomada: false) == nil)
        // ligou na tomada: rearma para a próxima descarga
        _ = v.bateria(0.12, carregando: true, naTomada: true)
        #expect(v.bateria(0.11, carregando: false, naTomada: false) != nil)
    }

    @Test("Temperatura avisa ao chegar em sério e rearma no normal")
    func temperatura() {
        var v = VigiaDeAlertas()
        #expect(v.temperatura(nivel: 1) == nil)
        #expect(v.temperatura(nivel: 2)?.titulo == "Mac esquentando")
        #expect(v.temperatura(nivel: 3) == nil)
        _ = v.temperatura(nivel: 0)
        #expect(v.temperatura(nivel: 3)?.titulo == "Mac muito quente")
    }

    @Test("Memória não repete o aviso dentro do intervalo")
    func memoria() {
        var v = VigiaDeAlertas()
        #expect(v.pressaoDeMemoria(critica: false, em: min(0)) != nil)
        #expect(v.pressaoDeMemoria(critica: true, em: min(5)) == nil)
        #expect(v.pressaoDeMemoria(critica: true, em: min(11))?.titulo == "Memória esgotando")
    }
}
