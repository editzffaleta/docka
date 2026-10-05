import Testing
import Foundation
@testable import DockaCore

@Suite("Avisos rápidos da ilha")
struct AvisosDaIlhaTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func a(_ id: String) -> Ilha.Atividade { .init(id: id, tipo: .aviso, simbolo: "x", valor: "", prioridade: 80) }

    @Test("Temporárias: a do mesmo tipo é trocada, as vencidas saem")
    func temporarias() {
        var l = AvisosDaIlha.juntar(.init(a("volume"), ate: t0.addingTimeInterval(2)), a: [], agora: t0)
        l = AvisosDaIlha.juntar(.init(a("fones"), ate: t0.addingTimeInterval(4)), a: l, agora: t0)
        l = AvisosDaIlha.juntar(.init(a("volume"), ate: t0.addingTimeInterval(3)), a: l, agora: t0.addingTimeInterval(1))
        #expect(l.map(\.atividade.id) == ["volume", "fones"])
        #expect(AvisosDaIlha.vivas(l, agora: t0.addingTimeInterval(3.5)).map(\.id) == ["fones"])
    }

    @Test("Bateria: tomada, fora da tomada e baixa só ao cruzar o limite")
    func bateria() {
        #expect(AvisosDaIlha.bateria(antes: nil, agora: (0.5, true)) == nil)
        #expect(AvisosDaIlha.bateria(antes: (0.5, false), agora: (0.5, true)) == .conectou(0.5))
        #expect(AvisosDaIlha.bateria(antes: (0.5, true), agora: (0.5, false)) == .desconectou(0.5))
        #expect(AvisosDaIlha.bateria(antes: (0.21, false), agora: (0.20, false)) == .baixa(0.20))
        #expect(AvisosDaIlha.bateria(antes: (0.19, false), agora: (0.18, false)) == nil)
        #expect(AvisosDaIlha.bateria(antes: (0.11, true), agora: (0.09, true)) == nil)     // na tomada, não
        #expect(AvisosDaIlha.simboloDaBateria(0.3, carregando: false) == "battery.25percent")
    }

    @Test("Fones: Bluetooth sempre; com fio pelo nome")
    func fones() {
        #expect(AvisosDaIlha.ehFone(nome: "Caixinha da sala", bluetooth: true))
        #expect(AvisosDaIlha.ehFone(nome: "Fones de ouvido externos", bluetooth: false))
        #expect(!AvisosDaIlha.ehFone(nome: "Alto-falantes (MacBook Air)", bluetooth: false))
        #expect(AvisosDaIlha.simboloDoFone("AirPods Pro de Bruno") == "airpodspro")
    }

    @Test("Nível: ruído de leitura não conta")
    func nivel() {
        #expect(!AvisosDaIlha.mudou(nil, 0.5))
        #expect(!AvisosDaIlha.mudou(0.500, 0.502))
        #expect(AvisosDaIlha.mudou(0.5, 0.56))
        #expect(AvisosDaIlha.porcentagem(0.555) == "56%")
    }
}
