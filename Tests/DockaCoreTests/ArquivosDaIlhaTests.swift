import Testing
import Foundation
@testable import DockaCore

@Suite("Arquivos da ilha")
struct ArquivosDaIlhaTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func a(_ nome: String, _ s: Double) -> ArquivosDaIlha.Arquivo {
        .init(caminho: "/Users/x/Downloads/\(nome)", data: t0.addingTimeInterval(s), tamanho: 10)
    }

    @Test("Recentes: mais novos primeiro, sem ocultos nem downloads pela metade")
    func recentes() {
        let lista = [a("velho.pdf", 0), a(".DS_Store", 50), a("novo.zip", 40), a("filme.mp4.crdownload", 60),
                     a("meio.dmg.download", 70), a("foto.jpg", 30)]
        #expect(ArquivosDaIlha.recentes(lista, limite: 2).map(\.nome) == ["novo.zip", "foto.jpg"])
    }

    @Test("Capturas: só imagem e vídeo")
    func capturas() {
        let lista = [a("Captura de Tela.png", 10), a("relatorio.pdf", 20), a("Gravação.mov", 5), a("notas.txt", 30)]
        #expect(ArquivosDaIlha.capturas(lista, limite: 5).map(\.nome) == ["Captura de Tela.png", "Gravação.mov"])
    }

    @Test("Nome final do download parcial")
    func nomeFinal() {
        #expect(ArquivosDaIlha.nomeFinal("foto.jpg.crdownload") == "foto.jpg")
        #expect(ArquivosDaIlha.nomeFinal("app.dmg.download") == "app.dmg")
        #expect(ArquivosDaIlha.nomeFinal("pronto.zip") == "pronto.zip")
    }

    @Test("Pasta de capturas: a escolhida, com ~, ou a Mesa")
    func pasta() {
        #expect(ArquivosDaIlha.pastaDeCapturas(gravada: nil, home: "/Users/x") == "/Users/x/Desktop")
        #expect(ArquivosDaIlha.pastaDeCapturas(gravada: "  ", home: "/Users/x") == "/Users/x/Desktop")
        #expect(ArquivosDaIlha.pastaDeCapturas(gravada: "~/Pictures/Capturas", home: "/Users/x") == "/Users/x/Pictures/Capturas")
        #expect(ArquivosDaIlha.pastaDeCapturas(gravada: "/Volumes/D/Shots", home: "/Users/x") == "/Volumes/D/Shots")
    }

    @Test("Quando, porcentagem e progresso geral")
    func textos() {
        #expect(ArquivosDaIlha.quando(t0, agora: t0.addingTimeInterval(30)) == "agora")
        #expect(ArquivosDaIlha.quando(t0, agora: t0.addingTimeInterval(300)) == "há 5 min")
        #expect(ArquivosDaIlha.quando(t0, agora: t0.addingTimeInterval(7200)) == "há 2 h")
        #expect(ArquivosDaIlha.quando(t0, agora: t0.addingTimeInterval(90_000)) == "ontem")
        #expect(ArquivosDaIlha.quando(t0, agora: t0.addingTimeInterval(3 * 86_400)) == "há 3 dias")
        #expect(ArquivosDaIlha.porcentagem(0.429) == "42%")
        #expect(ArquivosDaIlha.porcentagem(1.2) == "100%")
        #expect(ArquivosDaIlha.progressoGeral([]) == nil)
        #expect(ArquivosDaIlha.progressoGeral([0.2, 0.6]) == 0.4)
    }
}
