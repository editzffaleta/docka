import Testing
import CoreGraphics
@testable import DockaCore

private let size: CGFloat = 48
private let range: CGFloat = 200
private let peak: CGFloat = 1.75

private func escala(a distancia: CGFloat,
                    maxRange: CGFloat = range,
                    maxScale: CGFloat = peak) -> CGFloat {
    Magnification.scale(pointer: 500 + distancia, itemCenter: 500, itemSize: size,
                        maxRange: maxRange, maxScale: maxScale)
}

@Suite("Curva de ampliação")
struct MagnificationTests {

    @Test("Sob o cursor, o ícone atinge exatamente o pico")
    func picoSobOCursor() {
        #expect(abs(escala(a: 0) - peak) < 0.0001)
    }

    @Test("Fora do alcance a escala é EXATAMENTE 1")
    func foraDoAlcanceEExatamenteUm() {
        // é a diferença central para a gaussiana antiga, que decaía para sempre
        // e deixava a bandeja inteira respirando junto com o cursor
        #expect(escala(a: range) == 1)
        #expect(escala(a: range + 1) == 1)
        #expect(escala(a: 10_000) == 1)
    }

    @Test("Logo antes do limite a ampliação já é desprezível")
    func transicaoSuaveNoLimite() {
        // se a curva chegasse no limite ainda alta, o ícone saltaria para 1
        let quaseNoLimite = escala(a: range - 1)
        #expect(quaseNoLimite > 1)
        #expect(quaseNoLimite < 1.01)
    }

    @Test("A escala cai conforme o ícone se afasta do cursor")
    func decaimentoMonotonico() {
        let distancias: [CGFloat] = [0, 20, 40, 64, 100, 160, 199]
        let escalas = distancias.map { escala(a: $0) }
        for (a, b) in zip(escalas, escalas.dropFirst()) {
            #expect(a > b)
        }
    }

    @Test("A curva é simétrica dos dois lados do cursor")
    func simetrica() {
        #expect(abs(escala(a: 30) - escala(a: -30)) < 0.0001)
        #expect(abs(escala(a: 120) - escala(a: -120)) < 0.0001)
    }

    @Test("A escala nunca passa do pico nem fica abaixo de 1")
    func sempreDentroDosLimites() {
        for d in stride(from: CGFloat(-260), through: 260, by: 3) {
            let s = escala(a: d)
            #expect(s >= 1)
            #expect(s <= peak + 0.0001)
        }
    }

    @Test("Ampliação 1× desliga o efeito por completo")
    func picoUmDesliga() {
        // é o valor que o slider "Ampliação: Desativada" grava
        #expect(escala(a: 0, maxScale: 1) == 1)
        #expect(escala(a: 20, maxScale: 1) == 1)
        #expect(escala(a: 0, maxScale: 0.5) == 1)   // valor absurdo não encolhe o ícone
    }

    @Test("Alcance zero ou negativo desliga o efeito")
    func alcanceZeroDesliga() {
        #expect(escala(a: 0, maxRange: 0) == 1)
        #expect(escala(a: 0, maxRange: -10) == 1)
    }

    @Test("Um alcance menor concentra a ampliação em menos ícones")
    func alcanceControlaEspalhamento() {
        // a 100 pt do cursor: dentro de um alcance de 200 ainda cresce,
        // com alcance de 80 já está em repouso
        #expect(escala(a: 100, maxRange: 200) > 1)
        #expect(escala(a: 100, maxRange: 80) == 1)
    }

    @Test("Só o ícone apontado mostra o nome")
    func balaoSoNoIconeApontado() {
        // com a curva do Dock, um vizinho a 90 pt ainda está em ~1,53× — um
        // limiar de escala acenderia vários balões ao mesmo tempo
        #expect(escala(a: 90) > 1.5)

        let centro: CGFloat = 100
        #expect(Magnification.isHovered(pointer: 100, itemCenter: centro, size: 48, gap: 6))
        #expect(Magnification.isHovered(pointer: 120, itemCenter: centro, size: 48, gap: 6))
        #expect(!Magnification.isHovered(pointer: 145, itemCenter: centro, size: 48, gap: 6))
        #expect(!Magnification.isHovered(pointer: 190, itemCenter: centro, size: 48, gap: 6))
    }

    @Test("Sem cursor sobre a bandeja, nenhum balão aparece")
    func semCursorNenhumBalao() {
        #expect(!Magnification.isHovered(pointer: nil, itemCenter: 100, size: 48, gap: 6))
    }

    @Test("Ícones vizinhos não acendem o balão ao mesmo tempo")
    func balaoNaoDuplica() {
        // as faixas se encostam mas não se sobrepõem: no máximo um ícone por
        // posição do cursor (a borda exata é o único empate possível)
        let centros = (0..<5).map {
            Magnification.restingCenter(index: $0, size: 48, gap: 6, padding: 10)
        }
        for p in stride(from: CGFloat(0), through: 320, by: 1) {
            let acesos = centros.filter {
                Magnification.isHovered(pointer: p, itemCenter: $0, size: 48, gap: 6)
            }
            #expect(acesos.count <= 1)
        }
    }

    @Test("O alcance padrão dá o relevo do Dock, e não um topo chato")
    func alcancePadraoTemRelevo() {
        // Com maxRange 200 (o padrão do dockbar) e ícones de 48 pt, o primeiro
        // vizinho fica em 91% do pico: nada se destaca e a bandeja inteira
        // parece só inchar. Este teste guarda a calibragem.
        let passo = size + 6                       // size + gap
        func fracaoDoPico(_ n: Int, _ range: CGFloat) -> CGFloat {
            (escala(a: passo * CGFloat(n), maxRange: range) - 1) / (peak - 1)
        }

        let vizinho1 = fracaoDoPico(1, Magnification.defaultMaxRange)
        let vizinho2 = fracaoDoPico(2, Magnification.defaultMaxRange)
        let vizinho3 = fracaoDoPico(3, Magnification.defaultMaxRange)

        #expect(vizinho1 > 0.7 && vizinho1 < 0.87)   // claramente menor que o apontado
        #expect(vizinho2 > 0.15 && vizinho2 < 0.5)   // ainda participa
        #expect(vizinho3 == 0)                       // já em repouso

        // e o padrão do dockbar realmente achataria o topo
        #expect(fracaoDoPico(1, 200) > 0.9)
    }

    // MARK: redistribuição soma-zero (o vidro parado)

    private func somaZero(_ p: CGFloat?, count: Int = 5,
                          maxScale: CGFloat = 1.7) -> [CGFloat] {
        Magnification.zeroSumScales(pointer: p, count: count, size: 48, gap: 6,
                                    padding: 10, maxScale: maxScale, maxRange: 140)
    }

    @Test("Sem cursor, todos em repouso")
    func somaZeroSemCursor() {
        #expect(somaZero(nil) == [1, 1, 1, 1, 1])
        #expect(somaZero(100, maxScale: 1) == [1, 1, 1, 1, 1])
        #expect(somaZero(100, count: 0).isEmpty)
    }

    @Test("A largura total da fileira NÃO muda com o cursor")
    func larguraConstante() {
        // é o que deixa o vidro parado — a reclamação era o fundo se mexendo
        for p in stride(from: CGFloat(10), through: 270, by: 13) {
            let soma = somaZero(p).reduce(0, +)
            #expect(abs(soma - 5) < 0.02, "cursor em \(p): soma \(soma)")
        }
    }

    @Test("O apontado é o maior; os distantes cedem abaixo do repouso")
    func apontadoCresceDistantesCedem() {
        // cursor no centro do primeiro ícone
        let e = somaZero(34)
        #expect(e[0] == e.max())
        #expect(e[0] > 1.2)
        #expect(e[4] < 1)                       // o mais distante cedeu
        #expect(e[4] >= Magnification.minScale) // mas nunca abaixo do piso
    }

    @Test("O alcance numa fileira curta é limitado a ~metade da fileira")
    func alcanceLimitado() {
        // range 400 do usuário não pode cobrir a fileira inteira de 4 ícones
        let fileira: CGFloat = 4 * 48 + 3 * 6
        let capped = Magnification.cappedRange(count: 4, size: 48, gap: 6, maxRange: 400)
        #expect(capped < fileira / 2 + 1)
        // mas um range pequeno do usuário é respeitado
        #expect(Magnification.cappedRange(count: 4, size: 48, gap: 6, maxRange: 70) == 70)
    }

    // MARK: ancoragem da fileira (o conserto do tremor)

    private func shift(_ p: CGFloat?, count: Int = 5, maxScale: CGFloat = 1.75) -> CGFloat {
        Magnification.centeredRowShift(pointer: p, count: count, size: 48, gap: 6,
                                       padding: 10, maxScale: maxScale, maxRange: 140)
    }

    @Test("Sem cursor ou sem ampliação, a fileira não se desloca")
    func semCursorSemDeslocamento() {
        #expect(shift(nil) == 0)
        #expect(shift(100, maxScale: 1) == 0)
        #expect(shift(100, count: 0) == 0)
    }

    @Test("Cursor no centro da fileira: simetria, deslocamento zero")
    func centroSimetrico() {
        let larguraDosIcones: CGFloat = 5 * 48 + 4 * 6
        let centro = 10 + larguraDosIcones / 2
        #expect(abs(shift(centro)) < 0.001)
    }

    @Test("O ponto sob o cursor fica PARADO — é a definição da ancoragem")
    func pontoSobOCursorParado() {
        // reconstitui a fileira ampliada e verifica que o centro do ícone
        // apontado, somado ao deslocamento, volta ao lugar de repouso
        let size: CGFloat = 48, gap: CGFloat = 6, padding: CGFloat = 10
        for alvo in 0..<5 {
            let centroRepouso = Magnification.restingCenter(index: alvo, size: size,
                                                            gap: gap, padding: padding)
            let s = shift(centroRepouso)
            let pFileira = centroRepouso - padding

            var scaledX: CGFloat = 0
            var extra: CGFloat = 0
            var centroAmpliado: CGFloat = 0
            for i in 0..<5 {
                let c = Magnification.restingCenter(index: i, size: size, gap: gap, padding: 0)
                let w = size * Magnification.scale(pointer: pFileira, itemCenter: c,
                                                   itemSize: size, maxRange: 140, maxScale: 1.75)
                if i == alvo { centroAmpliado = scaledX + w / 2 }
                extra += w - size
                scaledX += w + (i < 4 ? gap : 0)
            }
            // posição na tela = posição centralizada + deslocamento; o cursor está
            // no centro do ícone, então o centro ampliado deve cair no de repouso
            let naTela = centroAmpliado - extra / 2 + s
            #expect(abs(naTela - (centroRepouso - padding)) < 0.001,
                    "ícone \(alvo): \(naTela) vs \(centroRepouso - padding)")
        }
    }

    @Test("Cursor na ponta esquerda empurra a fileira para a direita")
    func pontaEsquerdaEmpurraParaDireita() {
        // com o cursor na borda do 1º ícone, todo o crescimento vai para a direita
        #expect(shift(10) > 0)
        // e na ponta direita, para a esquerda
        let fimDosIcones: CGFloat = 10 + 5 * 48 + 4 * 6
        #expect(shift(fimDosIcones) < 0)
    }

    // MARK: posições em repouso

    @Test("Os centros em repouso ficam espaçados por size + gap")
    func centrosEmRepouso() {
        let c0 = Magnification.restingCenter(index: 0, size: 48, gap: 6, padding: 10)
        let c1 = Magnification.restingCenter(index: 1, size: 48, gap: 6, padding: 10)
        let primeiro: CGFloat = 10 + 24   // padding + metade do ícone
        let passo: CGFloat = 48 + 6       // size + gap
        #expect(c0 == primeiro)
        #expect(c1 - c0 == passo)
    }

    @Test("O centro em repouso não depende da ampliação")
    func centroEmRepousoEEstavel() {
        // é o ponto do conserto: medir o centro já ampliado realimentava a conta
        // — o ícone crescia, o centro andava, a distância mudava
        let a = Magnification.restingCenter(index: 3, size: 48, gap: 6, padding: 10)
        let b = Magnification.restingCenter(index: 3, size: 48, gap: 6, padding: 10)
        #expect(a == b)
    }
}
