import Testing
import Foundation
import CoreGraphics
@testable import DockaCore

@Suite("Prévia do Dock")
struct PreviaDoDockTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test("Mostra depois de parar no ícone, esconde depois da folga")
    func mostrarEsconder() {
        var v = PreviaDoDock.Vigia()
        var r: [PreviaDoDock.Vigia.Acao] = []
        r.append(v.leu(icone: "A", sobreOPainel: false, em: t(0), atraso: 0.5))
        r.append(v.leu(icone: "A", sobreOPainel: false, em: t(0.3), atraso: 0.5))
        r.append(v.leu(icone: "A", sobreOPainel: false, em: t(0.6), atraso: 0.5))
        r.append(v.leu(icone: "A", sobreOPainel: false, em: t(0.7), atraso: 0.5))
        r.append(v.leu(icone: nil, sobreOPainel: false, em: t(0.8), atraso: 0.5))
        r.append(v.leu(icone: nil, sobreOPainel: false, em: t(1.0), atraso: 0.5))
        r.append(v.leu(icone: nil, sobreOPainel: false, em: t(1.3), atraso: 0.5))
        #expect(r == [.nada, .nada, .mostrar("A"), .nada, .nada, .nada, .esconder])
    }

    @Test("Passar direto pelo ícone não mostra nada")
    func passarDireto() {
        var v = PreviaDoDock.Vigia()
        var r: [PreviaDoDock.Vigia.Acao] = []
        r.append(v.leu(icone: "A", sobreOPainel: false, em: t(0), atraso: 0.5))
        r.append(v.leu(icone: "B", sobreOPainel: false, em: t(0.3), atraso: 0.5))
        r.append(v.leu(icone: "C", sobreOPainel: false, em: t(0.6), atraso: 0.5))
        #expect(r == [.nada, .nada, .nada])
    }

    @Test("Com a prévia aberta, parar noutro ícone troca rápido; passar por cima não")
    func trocar() {
        var v = PreviaDoDock.Vigia()
        _ = v.leu(icone: "A", sobreOPainel: false, em: t(0), atraso: 0.5)
        _ = v.leu(icone: "A", sobreOPainel: false, em: t(0.5), atraso: 0.5)
        // a caminho da prévia, em diagonal: B e C passam em 0,1 s cada
        #expect(v.leu(icone: "B", sobreOPainel: false, em: t(0.6), atraso: 0.5) == .nada)
        #expect(v.leu(icone: "C", sobreOPainel: false, em: t(0.7), atraso: 0.5) == .nada)
        #expect(v.leu(icone: nil, sobreOPainel: true, em: t(0.8), atraso: 0.5) == .nada)
        #expect(v.mostrando == "A")
        // parar em B: troca depois de 0,2 s, sem esperar o atraso inteiro
        _ = v.leu(icone: "B", sobreOPainel: false, em: t(1.0), atraso: 0.5)
        #expect(v.leu(icone: "B", sobreOPainel: false, em: t(1.2), atraso: 0.5) == .mostrar("B"))
    }

    @Test("Cursor na prévia segura ela aberta")
    func sobreOPainel() {
        var v = PreviaDoDock.Vigia()
        _ = v.leu(icone: "A", sobreOPainel: false, em: t(0), atraso: 0)
        _ = v.leu(icone: nil, sobreOPainel: false, em: t(0.1), atraso: 0)
        #expect(v.leu(icone: nil, sobreOPainel: true, em: t(5), atraso: 0) == .nada)
        #expect(v.mostrando == "A")
        // saiu da prévia: conta a folga de novo, do zero
        #expect(v.leu(icone: nil, sobreOPainel: false, em: t(5.1), atraso: 0) == .nada)
        #expect(v.leu(icone: nil, sobreOPainel: false, em: t(5.6), atraso: 0) == .esconder)
    }

    @Test("Clique no ícone esconde e não reabre até sair dele")
    func clique() {
        var v = PreviaDoDock.Vigia()
        _ = v.leu(icone: "A", sobreOPainel: false, em: t(0), atraso: 0)
        #expect(v.clicou(icone: "A") == .esconder)
        #expect(v.leu(icone: "A", sobreOPainel: false, em: t(2), atraso: 0) == .nada)
        _ = v.leu(icone: nil, sobreOPainel: false, em: t(3), atraso: 0)
        #expect(v.leu(icone: "A", sobreOPainel: false, em: t(4), atraso: 0) == .mostrar("A"))
    }

    @Test("Posição: acima do ícone no Dock de baixo, ao lado nos laterais, sem sair da tela")
    func posicao() {
        let tela = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let tam = CGSize(width: 400, height: 200)
        let embaixo = CGRect(x: 800, y: 4, width: 60, height: 60)
        #expect(PreviaDoDock.borda(icone: embaixo, tela: tela) == .baixo)
        #expect(PreviaDoDock.quadro(tamanho: tam, icone: embaixo, tela: tela) == CGRect(x: 630, y: 98, width: 400, height: 200))
        // ícone no canto: o painel encosta na margem em vez de sair
        let canto = CGRect(x: 10, y: 4, width: 60, height: 60)
        #expect(PreviaDoDock.quadro(tamanho: tam, icone: canto, tela: tela).minX == 8)

        let esquerda = CGRect(x: 4, y: 500, width: 60, height: 60)
        #expect(PreviaDoDock.borda(icone: esquerda, tela: tela) == .esquerda)
        #expect(PreviaDoDock.quadro(tamanho: tam, icone: esquerda, tela: tela).minX == 98)
        let direita = CGRect(x: 1646, y: 500, width: 60, height: 60)
        #expect(PreviaDoDock.borda(icone: direita, tela: tela) == .direita)
        #expect(PreviaDoDock.quadro(tamanho: tam, icone: direita, tela: tela).maxX == 1612)
    }
}
