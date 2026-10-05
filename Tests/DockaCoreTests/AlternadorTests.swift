import Testing
import CoreGraphics
@testable import DockaCore

@Suite("Alternador de apps")
struct AlternadorTests {

    @Test("Ordena pelo uso; quem nunca foi ativado vai para o fim")
    func porUso() {
        #expect(Alternador.porUso([10, 20, 30, 40], historico: [30, 10]) == [30, 10, 20, 40])
        #expect(Alternador.porUso([1, 2], historico: []) == [1, 2])
    }

    @Test("Ativar leva para a frente, sem repetir e com limite")
    func registrar() {
        #expect(Alternador.registrar(5, em: [1, 5, 2]) == [5, 1, 2])
        #expect(Alternador.registrar(9, em: [1, 2, 3], limite: 3) == [9, 1, 2])
    }

    @Test("Abre no segundo, como o ⌘Tab")
    func inicial() {
        #expect(Alternador.selecaoInicial(total: 5) == 1)
        #expect(Alternador.selecaoInicial(total: 1) == 0)
        #expect(Alternador.selecaoInicial(total: 0) == 0)
    }

    @Test("Avançar e voltar dão a volta nas pontas")
    func mover() {
        #expect(Alternador.mover(3, passo: 1, total: 4) == 0)
        #expect(Alternador.mover(0, passo: -1, total: 4) == 3)
        #expect(Alternador.mover(0, passo: 1, total: 0) == 0)
    }

    @Test("Soltar qualquer modificador do gatilho confirma")
    func segurando() {
        #expect(Alternador.aindaSegurando(gatilho: [.option], agora: [.option]))
        #expect(Alternador.aindaSegurando(gatilho: [.option], agora: [.option, .shift]))
        #expect(!Alternador.aindaSegurando(gatilho: [.option], agora: []))
        #expect(!Alternador.aindaSegurando(gatilho: [.command, .option], agora: [.command]))
        // só shift não segura nada: sem ⌘/⌥/⌃ não há o que soltar
        #expect(!Alternador.aindaSegurando(gatilho: [.shift], agora: [.shift]))
    }

    @Test("O alternador é um atalho próprio")
    func atalho() {
        #expect(AcaoDeAtalho(id: AcaoDeAtalho.alternador.id) == .alternador)
    }

    @Test("Casa as janelas pelo quadro, não pelo título")
    func casar() {
        let ax = [CGRect(x: 0, y: 25, width: 800, height: 600), CGRect(x: 900, y: 25, width: 500, height: 400)]
        let sc: [(id: UInt32, quadro: CGRect)] = [
            (7, CGRect(x: 900, y: 25, width: 500, height: 400)),
            (3, CGRect(x: 1, y: 25, width: 800, height: 601)),
        ]
        #expect(Alternador.casar(ax, com: sc) == [3, 7])
    }

    @Test("Janela sem par na captura fica sem prévia, e nenhuma casa duas vezes")
    func semPar() {
        let ax = [CGRect(x: 0, y: 0, width: 400, height: 300), CGRect(x: 2, y: 0, width: 400, height: 300)]
        let sc: [(id: UInt32, quadro: CGRect)] = [(1, CGRect(x: 0, y: 0, width: 400, height: 300))]
        #expect(Alternador.casar(ax, com: sc) == [1, nil])
        #expect(Alternador.casar([CGRect(x: 0, y: 0, width: 10, height: 10)],
                                 com: [(9, CGRect(x: 500, y: 500, width: 300, height: 300))]) == [nil])
    }

    @Test("Miniatura cabe na caixa sem distorcer")
    func miniatura() {
        #expect(Alternador.miniatura(CGSize(width: 1600, height: 900), caixa: CGSize(width: 160, height: 100))
                == CGSize(width: 160, height: 90))
        #expect(Alternador.miniatura(CGSize(width: 500, height: 1000), caixa: CGSize(width: 160, height: 100))
                == CGSize(width: 50, height: 100))
    }

    @Test("Busca por palavras, no nome ou no título, sem acento")
    func busca() {
        #expect(Alternador.combina("safari git", nome: "Safari", titulo: "GitHub — editzffaleta"))
        #expect(Alternador.combina("acao", nome: "Notas", titulo: "Ação rápida"))
        #expect(!Alternador.combina("safari mail", nome: "Safari", titulo: "GitHub"))
        #expect(Alternador.combina("  ", nome: "Qualquer", titulo: nil))
        #expect(Alternador.combina("term", nome: "Terminal", titulo: nil))
    }

    @Test("Filtros: tela do cursor e apps sem janela")
    func filtros() {
        let esquerda = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let direita = CGRect(x: 1710, y: 0, width: 2560, height: 1440)
        let naEsquerda = CGRect(x: 100, y: 100, width: 800, height: 600)
        let naDireita = CGRect(x: 2000, y: 100, width: 800, height: 600)
        #expect(Alternador.passa(janelas: [naEsquerda], semJanelaEsconde: false, soTela: esquerda))
        #expect(!Alternador.passa(janelas: [naDireita], semJanelaEsconde: false, soTela: esquerda))
        #expect(Alternador.passa(janelas: [naDireita, naEsquerda], semJanelaEsconde: false, soTela: esquerda))
        #expect(!Alternador.passa(janelas: [], semJanelaEsconde: true, soTela: nil))
        #expect(Alternador.passa(janelas: [], semJanelaEsconde: false, soTela: nil))
        // sem permissão não dá para saber: não esconde nada
        #expect(Alternador.passa(janelas: nil, semJanelaEsconde: true, soTela: direita))
        // meio a meio: vale onde está o centro
        #expect(Alternador.naTela(CGRect(x: 1500, y: 0, width: 600, height: 400), tela: direita))
    }
}
