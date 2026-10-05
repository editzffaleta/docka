import Testing
import Foundation
import CoreGraphics
@testable import DockaCore

@Suite("Mouse e teclado")
struct MouseETecladoTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test("Foco segue o mouse: depois de parado, uma vez; arrastando, nunca")
    func foco() {
        var v = MouseETeclado.Vigia()
        var r: [Int32?] = []
        r.append(v.leu(sob: 20, frente: 10, em: t(0), atraso: 0.3, botaoApertado: false, modificador: false))
        r.append(v.leu(sob: 20, frente: 10, em: t(0.31), atraso: 0.3, botaoApertado: false, modificador: false))
        r.append(v.leu(sob: 20, frente: 10, em: t(0.5), atraso: 0.3, botaoApertado: false, modificador: false))
        r.append(v.leu(sob: 10, frente: 10, em: t(1), atraso: 0.3, botaoApertado: false, modificador: false))
        #expect(r == [nil, 20, nil, nil])
        // arrastando por cima de outra janela: não pula
        var a = MouseETeclado.Vigia()
        let a1 = a.leu(sob: 30, frente: 10, em: t(0), atraso: 0.3, botaoApertado: true, modificador: false)
        let a2 = a.leu(sob: 30, frente: 10, em: t(1), atraso: 0.3, botaoApertado: true, modificador: false)
        #expect(a1 == nil && a2 == nil)
    }

    @Test("Repique: engole o apertar que volta em poucos ms, e o soltar dele")
    func repique() {
        var r = MouseETeclado.Repique()
        var x: [Bool] = []
        x.append(r.apertou(1, em: t(0), limiar: 0.06))
        x.append(r.soltou(1, em: t(0.08)))
        x.append(r.apertou(1, em: t(0.10), limiar: 0.06))     // 20 ms depois de soltar: repique
        x.append(r.soltou(1, em: t(0.12)))                     // o par dele também some
        x.append(r.apertou(1, em: t(0.40), limiar: 0.06))     // de propósito
        #expect(x == [false, false, true, true, false])
        // clique duplo de verdade (150 ms entre soltar e apertar) passa
        var d = MouseETeclado.Repique()
        _ = d.apertou(1, em: t(0), limiar: 0.06)
        _ = d.soltou(1, em: t(0.05))
        let duplo = d.apertou(1, em: t(0.20), limiar: 0.06)
        #expect(!duplo)
        // em outro lugar da tela não é repique
        var l = MouseETeclado.Repique()
        _ = l.soltou(1, em: t(0), onde: CGPoint(x: 0, y: 0))
        let longe = l.apertou(1, em: t(0.01), onde: CGPoint(x: 50, y: 0), limiar: 0.06)
        #expect(!longe)
    }

    @Test("Ações dos botões")
    func botoes() {
        #expect(MouseETeclado.acao(botao: 3, gravadas: ["3": "missionControl"]) == .missionControl)
        #expect(MouseETeclado.acao(botao: 3, gravadas: ["3": "nada"]) == nil)
        #expect(MouseETeclado.acao(botao: 4, gravadas: [:]) == nil)
        #expect(MouseETeclado.AcaoDoBotao.copiar.tecla == "c")
        #expect(MouseETeclado.nomeDoBotao(3) == "Botão lateral de trás")
    }

    @Test("Tecla super: soma o remapeamento aos de antes e tira só o do Docka")
    func superTecla() {
        let outro: [String: UInt64] = ["HIDKeyboardModifierMappingSrc": 0x7_0000_00E3, "HIDKeyboardModifierMappingDst": 0x7_0000_00E2]
        let com = MouseETeclado.mapeamentos([outro], remover: false)
        #expect(com.count == 2 && com.contains(outro))
        #expect(MouseETeclado.mapeamentos(com, remover: false).count == 2)   // sem duplicar
        #expect(MouseETeclado.mapeamentos(com, remover: true) == [outro])
    }
}
