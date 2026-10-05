import Foundation
import CoreGraphics
import Testing
@testable import DockaCore

@Suite("Mídia e gravação")
struct MidiaTests {

    @Test("Tipo pelo nome")
    func tipo() {
        #expect(Midia.tipo("/a/praia.MOV") == .video)
        #expect(Midia.tipo("/a/foto.heic") == .imagem)
        #expect(Midia.tipo("/a/nota.txt") == .outro)
    }

    @Test("Nome de saída nunca sobrescreve")
    func nome() {
        let existentes: Set<String> = ["/v/praia-comprimido.mp4", "/v/praia-comprimido 2.mp4"]
        #expect(Midia.nomeDeSaida(original: "/v/praia.mov", sufixo: "comprimido", extensao: "mp4") { existentes.contains($0) }
                == "/v/praia-comprimido 3.mp4")
        #expect(Midia.nomeDeSaida(original: "/v/foto.png", sufixo: "convertido", extensao: "jpg") { _ in false }
                == "/v/foto-convertido.jpg")
    }

    @Test("Tamanho mantém a proporção, não aumenta e fica par para vídeo")
    func tamanho() {
        #expect(Midia.tamanhoAlvo(largura: 3840, altura: 2160, maximo: 1920) == (1920, 1080))
        #expect(Midia.tamanhoAlvo(largura: 800, altura: 600, maximo: 1920) == (800, 600))
        #expect(Midia.tamanhoAlvo(largura: 1001, altura: 777, maximo: 640, par: true) == (640, 496))
        #expect(Midia.tamanhoAlvo(largura: 0, altura: 10, maximo: 5) == (0, 0))
    }

    @Test("Quadros do GIF: fps e teto")
    func gif() {
        #expect(Midia.instantesDoGif(duracao: 2, fps: 10, maxQuadros: 100).count == 20)
        let longo = Midia.instantesDoGif(duracao: 60, fps: 10, maxQuadros: 150)
        #expect(longo.count == 150)
        #expect(longo.first == 0 && longo.last! < 60)
        #expect(Midia.instantesDoGif(duracao: 0, fps: 10, maxQuadros: 10).isEmpty)
        #expect(Midia.atrasoDoGif(duracao: 60, quadros: 150) == 0.4)
    }

    @Test("Marca d'água nos cantos, com margem")
    func marca() {
        let img = CGSize(width: 1000, height: 500), m = CGSize(width: 100, height: 20)
        #expect(Midia.quadroDaMarca(imagem: img, marca: m, canto: .inferiorDireito) == CGRect(x: 885, y: 15, width: 100, height: 20))
        #expect(Midia.quadroDaMarca(imagem: img, marca: m, canto: .superiorEsquerdo) == CGRect(x: 15, y: 465, width: 100, height: 20))
        #expect(Midia.quadroDaMarca(imagem: img, marca: m, canto: .centro) == CGRect(x: 450, y: 240, width: 100, height: 20))
    }

    @Test("Resumo de tamanho")
    func resumo() {
        #expect(Midia.resumo(antes: 2_000_000, depois: 700_000).hasSuffix("(−65%)"))
        #expect(Midia.resumo(antes: 1000, depois: 1000).hasSuffix("(0%)"))
    }

    @Test("Gravação: nome, área e relógio")
    func gravacao() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 5; c.hour = 14; c.minute = 3; c.second = 12
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        let d = Calendar(identifier: .gregorian).date(from: c)!
        #expect(Gravacao.nomeDoArquivo(em: d, fuso: TimeZone(identifier: "America/Sao_Paulo")!)
                == "Gravação 2026-10-05 às 14.03.12.mov")
        let tela = CGRect(x: 0, y: 0, width: 1470, height: 956)
        #expect(Gravacao.area(de: CGPoint(x: 300, y: 200), ate: CGPoint(x: 100.5, y: 50), tela: tela)
                == CGRect(x: 100, y: 50, width: 198, height: 150))
        #expect(Gravacao.area(de: CGPoint(x: 10, y: 10), ate: CGPoint(x: 20, y: 20), tela: tela) == nil)
        #expect(Gravacao.area(de: CGPoint(x: 1400, y: 900), ate: CGPoint(x: 2000, y: 1200), tela: tela)
                == CGRect(x: 1400, y: 900, width: 70, height: 56))
        #expect(Gravacao.relogio(7) == "0:07" && Gravacao.relogio(750) == "12:30" && Gravacao.relogio(3723) == "1:02:03")
    }
}
