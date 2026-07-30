import Testing
import Foundation
@testable import DockaCore

@Suite("Ações de atalho")
struct AcaoDeAtalhoTests {

    @Test("A identidade sobrevive à ida e volta do disco")
    func idaEVolta() {
        let uuid = UUID()
        let casos: [AcaoDeAtalho] = [.bandeja(uuid), .brilho, .volume, .ajustes,
                                     .orbita, .anel(uuid)]
        for c in casos {
            #expect(AcaoDeAtalho(id: c.id) == c)
        }
    }

    @Test("Chave estragada não vira ação")
    func chaveInvalida() {
        // um plist corrompido não pode virar uma bandeja fantasma
        #expect(AcaoDeAtalho(id: "bandeja:nao-e-uuid") == nil)
        #expect(AcaoDeAtalho(id: "anel:nao-e-uuid") == nil)
        #expect(AcaoDeAtalho(id: "bandeja:") == nil)
        #expect(AcaoDeAtalho(id: "qualquer") == nil)
    }

    @Test("O atalho é Codable — é assim que o conjunto é gravado")
    func atalhoCodavel() throws {
        let s = Shortcut(keyCode: 2, modifiers: [.command, .shift])
        let dados = try JSONEncoder().encode(["bandeja:x": s])
        let volta = try JSONDecoder().decode([String: Shortcut].self, from: dados)
        #expect(volta["bandeja:x"] == s)
    }
}

@Suite("Conjunto de atalhos")
struct AtalhosTests {
    private let a = Shortcut(keyCode: 2, modifiers: [.command, .shift])
    private let b = Shortcut(keyCode: 3, modifiers: [.command, .option])

    @Test("Combinação repetida é apontada pela ação que já a usa")
    func repetidaEApontada() {
        // o Carbon recusaria com um "já em uso" genérico, indistinguível de
        // conflito com outro app — e o usuário procuraria culpado fora do Docka
        let mapa = ["brilho": a, "volume": b]
        #expect(Atalhos.jaUsadaPor(a, em: mapa, ignorando: "ajustes") == "brilho")
        #expect(Atalhos.jaUsadaPor(b, em: mapa, ignorando: "ajustes") == "volume")
    }

    @Test("Regravar a mesma combinação na MESMA ação não é conflito")
    func mesmaAcaoNaoConflita() {
        let mapa = ["brilho": a]
        #expect(Atalhos.jaUsadaPor(a, em: mapa, ignorando: "brilho") == nil)
    }

    @Test("Combinação livre não acusa nada")
    func livreNaoAcusa() {
        #expect(Atalhos.jaUsadaPor(b, em: ["brilho": a], ignorando: "volume") == nil)
        #expect(Atalhos.jaUsadaPor(a, em: [:], ignorando: "brilho") == nil)
    }

    @Test("Anel apagado leva o atalho junto, como bandeja")
    func anelApagadoLevaOAtalho() {
        let vivo = UUID(), morto = UUID()
        let mapa = ["anel:\(vivo.uuidString)": a,
                    "anel:\(morto.uuidString)": b,
                    "orbita": a]
        let limpo = Atalhos.limpar(mapa, bandejasExistentes: [], aneisExistentes: [vivo])
        #expect(limpo.count == 2)
        #expect(limpo["anel:\(morto.uuidString)"] == nil)
        #expect(limpo["orbita"] == a)      // a ação genérica não depende de anel
    }

    @Test("Bandeja apagada leva o atalho junto")
    func bandejaApagadaLevaOAtalho() {
        // sem isto o atalho ficaria registrado no sistema, ocupando a
        // combinação e sem fazer nada ao ser pressionado
        let viva = UUID(), morta = UUID()
        let mapa = ["bandeja:\(viva.uuidString)": a,
                    "bandeja:\(morta.uuidString)": b,
                    "brilho": a]
        let limpo = Atalhos.limpar(mapa, bandejasExistentes: [viva])
        #expect(limpo.count == 2)
        #expect(limpo["bandeja:\(viva.uuidString)"] == a)
        #expect(limpo["bandeja:\(morta.uuidString)"] == nil)
        #expect(limpo["brilho"] == a)      // as ações fixas não são bandejas
    }

    @Test("Chave irreconhecível também é descartada")
    func chaveIrreconhecivelSai() {
        #expect(Atalhos.limpar(["lixo": a], bandejasExistentes: []).isEmpty)
    }
}
