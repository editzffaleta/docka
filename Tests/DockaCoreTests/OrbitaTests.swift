import Testing
import CoreGraphics
import Foundation
@testable import DockaCore

@Suite("Órbita — geometria do anel")
struct OrbitaTests {

    @Test("O primeiro item nasce no topo e os demais seguem o relógio")
    func primeiroNoTopo() {
        let p0 = Orbita.posicao(indice: 0, total: 4)
        #expect(abs(p0.x) < 0.001)
        #expect(p0.y < 0)                       // y do SwiftUI cresce para baixo
        let p1 = Orbita.posicao(indice: 1, total: 4)
        #expect(p1.x > 0 && abs(p1.y) < 0.001)  // três horas
    }

    @Test("Todos ficam no mesmo raio, e espaçados por igual")
    func distribuicaoUniforme() {
        let n = 7
        let r = Orbita.raio(total: n)
        let ps = (0..<n).map { Orbita.posicao(indice: $0, total: n) }
        for p in ps {
            #expect(abs(sqrt(p.x * p.x + p.y * p.y) - r) < 0.001)
        }
        let passo = 2 * CGFloat.pi / CGFloat(n)
        for i in 0..<n {
            let a = Orbita.angulo(indice: i, total: n)
            let b = Orbita.angulo(indice: (i + 1) % n, total: n)
            var d = b - a
            if d < 0 { d += 2 * .pi }
            #expect(abs(d - passo) < 0.001)
        }
    }

    @Test("Com mais apps o anel cresce, para os ícones não se encostarem")
    func anelCresceComOsApps() {
        let poucos = Orbita.raio(total: 4)
        let muitos = Orbita.raio(total: 16)
        #expect(muitos > poucos)
        // a distância entre vizinhos nunca fica menor que o ícone
        for n in 2...24 {
            let a = Orbita.posicao(indice: 0, total: n)
            let b = Orbita.posicao(indice: 1, total: n)
            let d = sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
            #expect(d >= Orbita.tamanhoItem, "com \(n) apps a distância foi \(d)")
        }
    }

    @Test("O miolo é zona morta: nada é selecionado ali")
    func mioloNaoSeleciona() {
        // sem isso, o anel já nasceria com um app escolhido — o cursor começa
        // exatamente no centro — e um clique sem querer lançaria alguma coisa
        #expect(Orbita.indiceSob(.zero, total: 8) == nil)
        #expect(Orbita.indiceSob(CGPoint(x: Orbita.raioInterno - 1, y: 0), total: 8) == nil)
        #expect(Orbita.indiceSob(CGPoint(x: Orbita.raioInterno + 1, y: 0), total: 8) != nil)
    }

    @Test("Vale a direção, não a distância — apontar de longe já seleciona")
    func direcaoBasta() {
        // é o que torna a órbita rápida: não é preciso acertar o ícone
        let longe = CGPoint(x: 0, y: -4000)
        #expect(Orbita.indiceSob(longe, total: 8) == 0)
        let perto = CGPoint(x: 0, y: -(Orbita.raioInterno + 2))
        #expect(Orbita.indiceSob(perto, total: 8) == 0)
    }

    @Test("Apontar para o centro de cada item devolve aquele item")
    func cadaSetorDevolveOSeu() {
        for n in [1, 2, 3, 5, 8, 12] {
            for i in 0..<n {
                let p = Orbita.posicao(indice: i, total: n)
                #expect(Orbita.indiceSob(p, total: n) == i, "n=\(n) i=\(i)")
            }
        }
    }

    @Test("A volta completa não repete nem pula setor")
    func varreduraCobreTodos() {
        let n = 6
        var vistos = Set<Int>()
        let r = Orbita.raio(total: n)
        for grau in stride(from: 0, to: 360, by: 1) {
            let a = CGFloat(grau) * .pi / 180
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if let i = Orbita.indiceSob(p, total: n) {
                #expect((0..<n).contains(i))
                vistos.insert(i)
            }
        }
        #expect(vistos.count == n)
    }

    @Test("Só o apontado cresce")
    func soOApontadoCresce() {
        #expect(Orbita.escala(indice: 2, apontado: 2) == Orbita.ampliacao)
        #expect(Orbita.escala(indice: 2, apontado: 3) == 1)
        #expect(Orbita.escala(indice: 2, apontado: nil) == 1)
    }
}

@Suite("Órbita — onde ela abre")
struct OrbitaQuadroTests {
    private let tela = CGRect(x: 0, y: 0, width: 1710, height: 1112)

    @Test("No meio da tela, o anel fica centrado no cursor")
    func centradoNoCursor() {
        let c = CGPoint(x: 800, y: 500)
        let q = Orbita.quadro(centro: c, total: 8, tela: tela)
        #expect(abs(q.midX - c.x) < 0.001)
        #expect(abs(q.midY - c.y) < 0.001)
    }

    @Test("Chamada na quina, ela se encaixa dentro da tela")
    func presaNaTela() {
        // aberta pelo canto, sem isto metade dos itens ficaria fora do alcance
        for c in [CGPoint(x: 0, y: 0), CGPoint(x: 1710, y: 1112),
                  CGPoint(x: 0, y: 1112), CGPoint(x: 1710, y: 0)] {
            let q = Orbita.quadro(centro: c, total: 8, tela: tela)
            #expect(tela.contains(q), "canto \(c) devolveu \(q)")
        }
    }

    @Test("O painel comporta o anel inteiro, já com o item ampliado")
    func painelCabeOAnel() {
        for n in [1, 4, 8, 20] {
            let lado = Orbita.tamanhoDoPainel(total: n)
            let precisa = 2 * (Orbita.raio(total: n) + Orbita.tamanhoItem * Orbita.ampliacao / 2)
            #expect(lado >= precisa)
        }
    }
}

@Suite("Órbita — gatilho de canto")
struct OrbitaCantoTests {
    private let tela = CGRect(x: 0, y: 0, width: 1710, height: 1112)

    @Test("Cada quina reconhece só a si mesma")
    func cadaQuinaAsua() {
        // AppKit: y cresce para cima, então o superior esquerdo é (minX, maxY)
        let pontos: [CantoDaTela: CGPoint] = [
            .superiorEsquerdo: CGPoint(x: 0, y: 1112),
            .superiorDireito:  CGPoint(x: 1710, y: 1112),
            .inferiorEsquerdo: CGPoint(x: 0, y: 0),
            .inferiorDireito:  CGPoint(x: 1710, y: 0)]
        for (canto, ponto) in pontos {
            #expect(Orbita.noCanto(canto, cursor: ponto, tela: tela))
            for outro in CantoDaTela.allCases where outro != canto {
                #expect(!Orbita.noCanto(outro, cursor: ponto, tela: tela))
            }
        }
    }

    @Test("Longe da quina, não dispara")
    func longeNaoDispara() {
        // a zona é estreita de propósito: o canto também é das Hot Corners do
        // macOS, e uma área larga roubaria o gesto de quem as usa
        let centro = CGPoint(x: 855, y: 556)
        for c in CantoDaTela.allCases {
            #expect(!Orbita.noCanto(c, cursor: centro, tela: tela))
        }
        #expect(!Orbita.noCanto(.inferiorEsquerdo,
                                cursor: CGPoint(x: Orbita.alcanceDoCanto + 1, y: 0), tela: tela))
    }
}
