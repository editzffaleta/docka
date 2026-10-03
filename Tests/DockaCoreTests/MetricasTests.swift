import Testing
import CoreGraphics
@testable import DockaCore

@Suite("Monitor do sistema")
struct MetricasTests {

    private func t(_ u: UInt64, _ s: UInt64, _ o: UInt64) -> Metricas.TiquesDeCPU {
        .init(usuario: u, sistema: s, ocioso: o, nice: 0)
    }

    @Test("Uso da CPU é o do intervalo, não a média desde o boot")
    func cpu() {
        // desde o boot quase tudo ocioso; no intervalo, metade ocupada
        let antes = t(100, 100, 10_000)
        let depois = t(150, 150, 10_100)
        #expect(Metricas.usoDeCPU(de: antes, para: depois) == 0.5)
        #expect(Metricas.usoDeCPU(de: antes, para: antes) == 0)
    }

    @Test("Memória em uso conta apps, fixa e comprimida")
    func memoria() {
        let m = Metricas.memoriaEmUso(internas: 1000, descartaveis: 200, fixas: 300,
                                      comprimidas: 100, tamanhoDaPagina: 16384)
        #expect(m == 1200 * 16384)
        // descartáveis maiores que as internas não viram número negativo
        #expect(Metricas.memoriaEmUso(internas: 10, descartaveis: 50, fixas: 0,
                                      comprimidas: 0, tamanhoDaPagina: 1) == 0)
    }

    @Test("O contador de 32 bits da rede vira sem dar salto negativo")
    func virada() {
        #expect(Metricas.delta32(de: 100, para: 350) == 250)
        let quaseNoFim = UInt64(UInt32.max) - 99   // faltam 100 para virar
        #expect(Metricas.delta32(de: quaseNoFim, para: 50) == 150)
    }

    @Test("Só as interfaces físicas contam")
    func interfaces() {
        #expect(Metricas.contaNoTrafego("en0"))
        #expect(Metricas.contaNoTrafego("en7"))
        #expect(!Metricas.contaNoTrafego("lo0"))
        #expect(!Metricas.contaNoTrafego("utun4"))
        #expect(!Metricas.contaNoTrafego("awdl0"))
    }

    @Test("Texto de bytes, taxas, porcentagens e tempo")
    func texto() {
        #expect(Metricas.bytes(512) == "512 B")
        #expect(Metricas.bytes(1_400_000_000) == "1,4 GB")
        #expect(Metricas.bytes(238_000_000_000) == "238 GB")
        // memória em 1024: um Mac de 16 GB não pode virar "17 GB"
        #expect(Metricas.bytes(17_179_869_184, binario: true) == "16 GB")
        #expect(Metricas.bytes(17_179_869_184) == "17 GB")
        #expect(Metricas.taxa(143) == "0 KB/s")
        #expect(Metricas.taxa(850_000) == "850 KB/s")
        #expect(Metricas.taxa(2_300_000) == "2,3 MB/s")
        #expect(Metricas.taxa(-5) == "0 KB/s")
        #expect(Metricas.porcentagem(0.237) == "24%")
        #expect(Metricas.porcentagem(1.4) == "100%")
        #expect(Metricas.tempo(minutos: 135) == "2h 15min")
        #expect(Metricas.tempo(minutos: 45) == "45min")
        #expect(Metricas.tempo(minutos: 120) == "2h")
        #expect(Metricas.tempo(minutos: -1) == nil)
        #expect(Metricas.tempo(minutos: nil) == nil)
    }

    @Test("O histórico guarda só os últimos")
    func historico() {
        var h = Historico(capacidade: 3)
        for v in [1.0, 2, 3, 4] { h.adicionar(v) }
        #expect(h.valores == [2, 3, 4])
        #expect(h.ultimo == 4)
    }

    @Test("O gráfico nasce na direita e respeita o teto")
    func pontos() {
        var h = Historico(capacidade: 5)
        h.adicionar(0.5)
        h.adicionar(1)
        let p = h.pontos(largura: 100, altura: 10, teto: 1)
        #expect(p.count == 2)
        #expect(p.last == CGPoint(x: 100, y: 0))
        #expect(p.first == CGPoint(x: 75, y: 5))
        // sem teto, escala pelo maior valor
        #expect(h.pontos(largura: 100, altura: 10).last?.y == 0)
    }

    @Test("Leitura gravada desconhecida vira nenhuma")
    func leitura() {
        #expect(LeituraDaBarra(persisted: "cpu") == .cpu)
        #expect(LeituraDaBarra(persisted: "lixo") == .nenhuma)
    }

    @Test("O monitor é um atalho próprio")
    func atalho() {
        #expect(AcaoDeAtalho(id: AcaoDeAtalho.monitor.id) == .monitor)
    }
}
