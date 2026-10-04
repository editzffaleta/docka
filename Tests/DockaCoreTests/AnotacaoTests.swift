import Testing
import CoreGraphics
@testable import DockaCore

@Suite("Editor de anotação")
struct AnotacaoTests {

    @Test("Retângulo em qualquer direção do arrasto")
    func retangulo() {
        let r = GeometriaDeAnotacao.retangulo(CGPoint(x: 50, y: 80), CGPoint(x: 10, y: 20))
        #expect(r == CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    @Test("A cabeça da seta é simétrica e fica atrás da ponta")
    func cabeca() {
        let (a, b) = GeometriaDeAnotacao.cabeca(de: CGPoint(x: 0, y: 0), para: CGPoint(x: 200, y: 0), espessura: 4)
        #expect(a.x < 200 && b.x < 200)
        #expect(abs(a.y + b.y) < 1e-9)          // uma para cada lado do corpo
        #expect(abs(a.x - b.x) < 1e-9)
    }

    @Test("Numa seta curta a cabeça não passa de metade do corpo")
    func cabecaCurta() {
        let (a, _) = GeometriaDeAnotacao.cabeca(de: CGPoint(x: 0, y: 0), para: CGPoint(x: 20, y: 0), espessura: 10)
        #expect(20 - a.x <= 10.0001)
    }

    @Test("Captura Retina aparece no tamanho da tela, e encolhe para caber")
    func encaixe() {
        // 2000×1000 pixels numa tela 2×: 1000×500 pontos cabem numa área 1200×800
        let e1 = GeometriaDeAnotacao.encaixe(imagem: CGSize(width: 2000, height: 1000),
                                             area: CGSize(width: 1200, height: 800), escalaDaTela: 2)
        #expect(e1.escala == 0.5)
        #expect(e1.deslocamento == CGPoint(x: 100, y: 150))
        // área menor: encolhe mais, sem distorcer
        let e2 = GeometriaDeAnotacao.encaixe(imagem: CGSize(width: 2000, height: 1000),
                                             area: CGSize(width: 500, height: 800), escalaDaTela: 2)
        #expect(e2.escala == 0.25)
    }

    @Test("Ida da janela para os pixels da imagem")
    func paraImagem() {
        let p = GeometriaDeAnotacao.paraImagem(CGPoint(x: 150, y: 200), escala: 0.5, deslocamento: CGPoint(x: 100, y: 150))
        #expect(p == CGPoint(x: 100, y: 100))
    }

    @Test("Recorte preso à imagem; clique sem arrasto não recorta")
    func recorte() {
        let tam = CGSize(width: 100, height: 100)
        #expect(GeometriaDeAnotacao.recorte(CGRect(x: 80, y: -10, width: 50, height: 40.4), imagem: tam)
                == CGRect(x: 80, y: 0, width: 20, height: 31))
        #expect(GeometriaDeAnotacao.recorte(CGRect(x: 10, y: 10, width: 2, height: 2), imagem: tam) == nil)
        #expect(GeometriaDeAnotacao.recorte(CGRect(x: 200, y: 200, width: 10, height: 10), imagem: tam) == nil)
    }

    @Test("Bloco do borrão acompanha o tamanho da imagem")
    func bloco() {
        #expect(GeometriaDeAnotacao.blocoDoBorrao(imagem: CGSize(width: 400, height: 300)) == 12)
        #expect(GeometriaDeAnotacao.blocoDoBorrao(imagem: CGSize(width: 5120, height: 2880)) == 64)
    }

    @Test("Cada ferramenta tem uma tecla diferente")
    func teclas() {
        let t = FerramentaDeAnotacao.allCases.map(\.tecla)
        #expect(Set(t).count == t.count)
    }
}
