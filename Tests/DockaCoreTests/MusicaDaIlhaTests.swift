import Testing
import Foundation
@testable import DockaCore

@Suite("Música da ilha")
struct MusicaDaIlhaTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("Linha do ajudante vira a faixa")
    func json() {
        let j: [String: Any] = ["pid": 123, "titulo": "Canção", "artista": "Banda", "album": "",
                                "duracao": 200, "decorrido": 42, "taxa": 1, "carimbo": 1_000_000.0, "tocando": 1]
        let f = TocandoAgora(json: j)
        #expect(f.titulo == "Canção" && f.artista == "Banda" && f.album == nil)
        #expect(f.tocando && f.temFaixa && f.pid == 123)
        #expect(!TocandoAgora(json: ["pid": 0, "tocando": 0]).temFaixa)
    }

    @Test("Posição anda com o tempo tocando, para pausada, não passa do fim")
    func posicao() {
        var f = TocandoAgora(titulo: "x", duracao: 200, decorrido: 42, taxa: 1, carimbo: t0, tocando: true)
        #expect(f.posicao(em: t0.addingTimeInterval(10)) == 52)
        #expect(f.posicao(em: t0.addingTimeInterval(1000)) == 200)
        f.tocando = false
        #expect(f.posicao(em: t0.addingTimeInterval(10)) == 42)
    }

    @Test("LRC: tempos, várias marcas na mesma linha, cabeçalho de fora")
    func lrc() {
        let l = Letra.ler("""
        [ar: Banda]
        [00:10.50] primeira
        [00:05.00][01:00.00] refrão
        sem tempo
        [00:20,25] terceira
        """)
        #expect(l.map(\.texto) == ["refrão", "primeira", "terceira", "refrão"])
        #expect(l.map(\.tempo) == [5, 10.5, 20.25, 60])
        #expect(Letra.atual(l, em: 2) == nil)
        #expect(Letra.atual(l, em: 10.6) == 1)
        #expect(Letra.atual(l, em: 30) == 2)
    }

    @Test("Faixas do equalizador: entre 0 e 1, grave forte aparece no começo")
    func faixas() {
        var espectro = [Float](repeating: 1e-6, count: 512)
        for i in 1..<4 { espectro[i] = 1 }                 // grave alto
        let f = Equalizador.faixas(espectro, quantas: 6)
        #expect(f.count == 6)
        #expect(f.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(f[0] > f[5])
        let s = Equalizador.suavizar([0, 1], [1, 0])
        #expect(s[0] > 0.5 && s[1] > 0.8)                  // sobe rápido, desce devagar
        #expect(Equalizador.enfeite(quantas: 4, em: 1.23).allSatisfy { $0 >= 0.12 && $0 <= 1 })
        // ganho: som baixo ocupa a altura; o maior recente cai devagar
        let g = Equalizador.ganho([0.2, 0.1], maior: 0)
        #expect(g.faixas[0] > 0.5 && g.maior == 0.35)
        let g2 = Equalizador.ganho([0.9, 0.1], maior: g.maior)
        #expect(g2.faixas[0] == 1 && g2.maior == 0.9)
    }
}
