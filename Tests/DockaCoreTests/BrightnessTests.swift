import Testing
import CoreGraphics
@testable import DockaCore

@Suite("Controle de brilho")
struct BrightnessTests {

    @Test("O nível anda na grade de 1/16 do sistema")
    func grade() {
        // guardar um valor fora da grade faria o modelo divergir do sistema
        // já no primeiro toque de tecla
        #expect(Brightness.quantize(0.5) == 0.5)
        #expect(Brightness.quantize(0.51) == 0.5)
        #expect(Brightness.quantize(0.5625) == 0.5625)   // já é um passo
        #expect(Brightness.quantize(0.55) == 0.5625)      // arredonda para o mais próximo
        #expect(Brightness.quantize(-1) == 0)
        #expect(Brightness.quantize(9) == 1)
    }

    @Test("A distância entre dois níveis vira a contagem de teclas")
    func passos() {
        #expect(Brightness.stepsBetween(from: 0.5, to: 0.5625) == 1)
        #expect(Brightness.stepsBetween(from: 0.5, to: 0.25) == -4)
        #expect(Brightness.stepsBetween(from: 0.5, to: 0.5) == 0)
        // do mínimo ao máximo são exatamente os 16 passos do sistema
        #expect(Brightness.stepsBetween(from: 0, to: 1) == Brightness.steps)
    }

    @Test("Aplicar passos é o inverso de contá-los")
    func idaEVolta() {
        for inicio in stride(from: 0.0, through: 1.0, by: 0.0625) {
            for alvo in stride(from: 0.0, through: 1.0, by: 0.0625) {
                let n = Brightness.stepsBetween(from: inicio, to: alvo)
                #expect(abs(Brightness.applying(n, to: inicio) - alvo) < 0.0001)
            }
        }
    }

    @Test("O nível nunca escapa de 0…1")
    func limites() {
        #expect(Brightness.applying(99, to: 0.5) == 1)
        #expect(Brightness.applying(-99, to: 0.5) == 0)
    }

    @Test("Cada toque de tecla cai sobre um traço da régua")
    func reguaAlinhada() {
        // 33 traços para 16 passos: o passo cai exatamente de 2 em 2 traços
        #expect((Brightness.tickCount - 1) % Brightness.steps == 0)
        #expect(Brightness.tickLevel(0) == 0)
        #expect(Brightness.tickLevel(Brightness.tickCount - 1) == 1)
    }

    @Test("A faixa acesa segue o nível e some longe dele")
    func faixaAcesa() {
        let meio = (Brightness.tickCount - 1) / 2
        let nivel = Brightness.tickLevel(meio)
        #expect(Brightness.tickHighlight(meio, level: nivel) == 1)
        #expect(Brightness.tickHighlight(meio + 1, level: nivel) > 0)
        #expect(Brightness.tickHighlight(0, level: nivel) == 0)
        #expect(Brightness.tickHighlight(Brightness.tickCount - 1, level: nivel) == 0)
    }

    @Test("O botão fica na altura do nível ao longo da régua")
    func botaoSegueONivel() {
        let L: CGFloat = 250
        #expect(Brightness.knobOffset(level: 0.5, rulerLength: L) == 0)      // meio
        #expect(Brightness.knobOffset(level: 1, rulerLength: L) == -L / 2)   // topo
        #expect(Brightness.knobOffset(level: 0, rulerLength: L) == L / 2)    // base
    }

    @Test("Arrastar o botão é posicional: ele não escorrega do cursor")
    func botaoPosicional() {
        let L: CGFloat = 250
        for nivel in stride(from: 0.0, through: 1.0, by: 0.1) {
            let off = Brightness.knobOffset(level: nivel, rulerLength: L)
            #expect(abs(Brightness.levelFromKnob(offset: off, rulerLength: L) - nivel) < 0.0001)
        }
        // além das pontas, trava
        #expect(Brightness.levelFromKnob(offset: -999, rulerLength: L) == 1)
        #expect(Brightness.levelFromKnob(offset: 999, rulerLength: L) == 0)
    }

    @Test("O rótulo do botão é a porcentagem inteira")
    func rotuloDoBotao() {
        #expect(Brightness.knobLabel(level: 0.99) == "99")
        #expect(Brightness.knobLabel(level: 0.094) == "9")
        #expect(Brightness.knobLabel(level: 1) == "100")
        #expect(Brightness.knobLabel(level: 0) == "0")
    }

    @Test("O arrasto parte do nível do INÍCIO, sem realimentar")
    func arrastoNaoRealimenta() {
        // O defeito relatado: calcular a partir do valor corrente fazia o brilho
        // disparar. Aqui o alvo depende só do início e do deslocamento, então
        // repetir o mesmo evento CONVERGE em vez de escapar.
        let inicio = 0.5, span: CGFloat = 250
        var atual = inicio
        for _ in 0..<40 {
            atual = Brightness.dragStep(inicio: inicio, translation: -25,
                                        atual: atual, span: span)
        }
        // -25 pt em 250 = +10%
        #expect(abs(atual - 0.6) < 0.001)
    }

    @Test("A suavização aproxima do alvo sem passar dele")
    func suavizacaoConverge() {
        let inicio = 0.2, span: CGFloat = 250
        var atual = inicio
        var anterior = -1.0
        for _ in 0..<30 {
            atual = Brightness.dragStep(inicio: inicio, translation: -125,
                                        atual: atual, span: span)
            #expect(atual > anterior)      // sempre avança
            #expect(atual <= 0.7001)       // nunca ultrapassa o alvo (0,2 + 50%)
            anterior = atual
        }
        #expect(abs(atual - 0.7) < 0.01)
    }

    @Test("Um evento sozinho não salta o caminho inteiro")
    func umEventoNaoSalta() {
        // é o que tira o solavanco: o primeiro evento anda só uma fração
        let um = Brightness.dragStep(inicio: 0.5, translation: -250,
                                     atual: 0.5, span: 250)
        #expect(um > 0.5 && um < 0.7)
    }

    @Test("Esfregar para cima aumenta, para baixo diminui")
    func esfregar() {
        // translation.height é NEGATIVO ao arrastar para cima
        #expect(Brightness.scrub(from: 0.5, translation: -125) > 0.5)
        #expect(Brightness.scrub(from: 0.5, translation: 125) < 0.5)
        #expect(Brightness.scrub(from: 0.5, translation: 0) == 0.5)
    }

    @Test("A faixa inteira cabe num arrasto do tamanho da régua")
    func esfregarCobreTudo() {
        // esfregar no sol anda o mesmo que arrastar a régua de ponta a ponta
        #expect(Brightness.scrub(from: 0, translation: -Brightness.dragSpan) == 1)
        #expect(Brightness.scrub(from: 1, translation: Brightness.dragSpan) == 0)
    }

    @Test("Esfregar não escapa de 0…1")
    func esfregarLimites() {
        #expect(Brightness.scrub(from: 0.9, translation: -9999) == 1)
        #expect(Brightness.scrub(from: 0.1, translation: 9999) == 0)
    }

    @Test("O tique toca uma vez por degrau, não por evento")
    func tiquePorDegrau() {
        // dezenas de eventos por segundo com som viraria metralhadora
        #expect(!Brightness.crossedStep(from: 0.50, to: 0.505))   // mesmo degrau
        #expect(Brightness.crossedStep(from: 0.50, to: 0.57))     // degrau seguinte
        #expect(Brightness.crossedStep(from: 0.57, to: 0.50))     // e voltando
    }

    @Test("Um arrasto lento cruza cada degrau uma única vez")
    func tiqueNaoRepete() {
        var anterior = 0.0
        var tiques = 0
        for i in 0...160 {                        // arrasto fino de 0 a 1
            let atual = Double(i) / 160.0
            if Brightness.crossedStep(from: anterior, to: atual) { tiques += 1 }
            anterior = atual
        }
        #expect(tiques == Brightness.steps)       // exatamente 16 degraus
    }

    @Test("A régua é esguia como a da referência")
    func reguaEsguia() {
        // medido no vídeo do usuário: ~13% da altura. A primeira versão tinha
        // 22% e ficou grossa demais.
        let razao = Brightness.rulerThickness / Brightness.rulerLength
        #expect(razao > 0.11 && razao < 0.16)
        // o botão é um pouco mais estreito que a régua, como na referência
        #expect(Brightness.knobSize < Brightness.rulerThickness)
    }

    @Test("O painel cabe a régua e o botão lado a lado")
    func painelCabe() {
        #expect(Brightness.panelExtent > Brightness.rulerLength)
        #expect(Brightness.panelThickness > Brightness.rulerThickness + Brightness.knobSize)
    }

    @Test("O controle só aceita as laterais")
    func sóLaterais() {
        // a régua é vertical: deitada na borda inferior viraria outra coisa
        #expect(Brightness.bordasPermitidas == [.left, .right])
        #expect(Brightness.edge(persisted: "left") == .left)
        #expect(Brightness.edge(persisted: "right") == .right)
        #expect(Brightness.edge(persisted: "bottom") == .right)   // recai no padrão
        #expect(Brightness.edge(persisted: "xxx") == .right)
    }

    @Test("O arrasto fora da faixa não escapa de 0…1")
    func arrasto() {
        #expect(Brightness.clamp(-2) == 0)
        #expect(Brightness.clamp(2) == 1)
        #expect(Brightness.clamp(0.37) == 0.37)   // contínuo: o sistema aceita
    }
}
