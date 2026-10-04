import Testing
import Foundation
import CoreGraphics
@testable import DockaCore

@Suite("Captura")
struct CapturaTests {

    @Test("A cor nos quatro formatos")
    func cores() {
        let (r, g, b) = (30.0 / 255, 144.0 / 255, 1.0)
        #expect(Captura.texto(r: r, g: g, b: b, formato: .hex) == "#1E90FF")
        #expect(Captura.texto(r: r, g: g, b: b, formato: .rgb) == "rgb(30, 144, 255)")
        #expect(Captura.texto(r: r, g: g, b: b, formato: .hsl) == "hsl(210, 100%, 56%)")
        #expect(Captura.texto(r: 1, g: 0, b: 0, formato: .swiftUI) == "Color(red: 1.000, green: 0.000, blue: 0.000)")
    }

    @Test("Cinza não tem matiz; fora da faixa é cortado")
    func bordas() {
        #expect(Captura.texto(r: 0.5, g: 0.5, b: 0.5, formato: .hsl) == "hsl(0, 0%, 50%)")
        #expect(Captura.texto(r: 1.4, g: -1, b: 0, formato: .hex) == "#FF0000")
    }

    @Test("Trechos juntados na ordem de leitura")
    func juntar() {
        // origem embaixo: y maior = mais alto na tela
        let t: [Captura.Trecho] = [
            .init(texto: "mundo", quadro: CGRect(x: 0.5, y: 0.80, width: 0.2, height: 0.05)),
            .init(texto: "segunda", quadro: CGRect(x: 0.1, y: 0.60, width: 0.3, height: 0.05)),
            // um pixel abaixo, mas na mesma linha de "mundo"
            .init(texto: "olá", quadro: CGRect(x: 0.1, y: 0.79, width: 0.2, height: 0.05)),
        ]
        #expect(Captura.juntar(t) == "olá mundo\nsegunda")
        #expect(Captura.juntar([]) == "")
    }

    @Test("Nome do arquivo sem dois-pontos")
    func nome() {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 3; c.hour = 22; c.minute = 15; c.second = 7
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        let d = Calendar(identifier: .gregorian).date(from: c)!
        let n = Captura.nomeDoArquivo(em: d, fuso: TimeZone(identifier: "America/Sao_Paulo")!)
        #expect(n == "Captura 2026-10-03 às 22.15.07.png")
        #expect(!n.contains(":"))
    }

    @Test("Atalhos da captura")
    func atalhos() {
        for a in [AcaoDeAtalho.contaGotas, .textoDaTela, .capturaArea] {
            #expect(AcaoDeAtalho(id: a.id) == a)
        }
    }
}
