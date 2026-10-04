import Testing
import CoreGraphics
@testable import DockaCore

@Suite("Encaixe de janelas")
struct EncaixeTests {
    // área útil de uma tela 1710 × 1112 com barra de menus de 33 pt
    private let area = CGRect(x: 0, y: 0, width: 1710, height: 1079)

    @Test("Metades, quartos e terços dividem a área útil")
    func layouts() {
        #expect(Encaixe.quadro(.esquerda, em: area) == CGRect(x: 0, y: 0, width: 855, height: 1079))
        #expect(Encaixe.quadro(.direita, em: area) == CGRect(x: 855, y: 0, width: 855, height: 1079))
        // AppKit: "cima" é y alto
        #expect(Encaixe.quadro(.cima, em: area)?.minY == 539.5)
        #expect(Encaixe.quadro(.superiorDireito, em: area) == CGRect(x: 855, y: 539.5, width: 855, height: 539.5))
        #expect(Encaixe.quadro(.tercoCentral, em: area) == CGRect(x: 570, y: 0, width: 570, height: 1079))
        #expect(Encaixe.quadro(.maximizar, em: area) == area)
    }

    @Test("Repetir a metade passa por ½, ⅓ e ⅔ e volta")
    func ciclo() {
        #expect(Encaixe.proximoPasso(depois: nil) == 0)
        #expect(Encaixe.proximoPasso(depois: 0) == 1)
        #expect(Encaixe.proximoPasso(depois: 2) == 0)
        #expect(Encaixe.quadro(.esquerda, em: area, passo: 1)?.width == 570)
        #expect(Encaixe.quadro(.direita, em: area, passo: 2) == CGRect(x: 570, y: 0, width: 1140, height: 1079))
    }

    @Test("Centralizar mantém o tamanho, sem passar da tela")
    func centralizar() {
        let atual = CGRect(x: 10, y: 10, width: 800, height: 600)
        #expect(Encaixe.quadro(.centralizar, em: area, atual: atual) == CGRect(x: 455, y: 239.5, width: 800, height: 600))
        let grande = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        #expect(Encaixe.quadro(.centralizar, em: area, atual: grande) == area)
    }

    @Test("Próxima tela e restaurar ficam com a casca")
    func casca() {
        #expect(Encaixe.quadro(.proximaTela, em: area) == nil)
        #expect(Encaixe.quadro(.restaurar, em: area) == nil)
    }

    @Test("Levar para outra tela mantém a proporção")
    func levar() {
        let externa = CGRect(x: 1710, y: 0, width: 2560, height: 1415)
        let metade = Encaixe.quadro(.esquerda, em: area)!
        #expect(Encaixe.levar(metade, de: area, para: externa) == CGRect(x: 1710, y: 0, width: 1280, height: 1415))
    }

    @Test("Ida e volta entre AppKit e Acessibilidade")
    func coordenadas() {
        let r = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = Encaixe.paraAcessibilidade(r, alturaDaPrincipal: 1112)
        #expect(ax == CGRect(x: 100, y: 512, width: 300, height: 400))
        #expect(Encaixe.doAcessibilidade(ax, alturaDaPrincipal: 1112) == r)
    }

    @Test("Quase igual tolera o arredondamento dos apps")
    func quaseIgual() {
        let a = CGRect(x: 0, y: 0, width: 855, height: 1079)
        #expect(Encaixe.quaseIgual(a, CGRect(x: 0, y: 4, width: 850, height: 1075)))
        #expect(!Encaixe.quaseIgual(a, CGRect(x: 0, y: 0, width: 570, height: 1079)))
    }

    @Test("Cada layout é um atalho próprio")
    func atalho() {
        for l in LayoutDeJanela.allCases {
            #expect(AcaoDeAtalho(id: AcaoDeAtalho.janela(l).id) == .janela(l))
        }
    }

    @Test("Zonas de arrastar: bordas, cantos e a de baixo que não faz nada")
    func zonas() {
        let t = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        #expect(Encaixe.zona(cursor: CGPoint(x: 0, y: 500), tela: t) == .esquerda)
        #expect(Encaixe.zona(cursor: CGPoint(x: 1709, y: 500), tela: t) == .direita)
        #expect(Encaixe.zona(cursor: CGPoint(x: 800, y: 1111), tela: t) == .maximizar)
        #expect(Encaixe.zona(cursor: CGPoint(x: 0, y: 1100), tela: t) == .superiorEsquerdo)
        #expect(Encaixe.zona(cursor: CGPoint(x: 1650, y: 1111), tela: t) == .superiorDireito)
        #expect(Encaixe.zona(cursor: CGPoint(x: 1709, y: 20), tela: t) == .inferiorDireito)
        #expect(Encaixe.zona(cursor: CGPoint(x: 800, y: 0), tela: t) == nil)
        #expect(Encaixe.zona(cursor: CGPoint(x: 800, y: 500), tela: t) == nil)
    }

    @Test("Zona numa segunda tela à direita")
    func zonaSegundaTela() {
        let t = CGRect(x: 1710, y: -200, width: 2560, height: 1440)
        #expect(Encaixe.zona(cursor: CGPoint(x: 1710, y: 400), tela: t) == .esquerda)
        #expect(Encaixe.zona(cursor: CGPoint(x: 3000, y: 1239), tela: t) == .maximizar)
    }
}
