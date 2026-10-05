import Testing
import Foundation
import CoreGraphics
@testable import DockaCore

@Suite("Janelas e o Dock")
struct JanelasEDockTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// As respostas do vigia, leitura a leitura.
    private func respostas(_ leituras: [Int]) -> (encerrou: [Bool], vigia: SairAoFechar.Vigia) {
        var v = SairAoFechar.Vigia()
        var r: [Bool] = []
        for n in leituras { r.append(v.leu(n)) }
        return (r, v)
    }

    @Test("Sair ao fechar: zero repetido depois de ter tido janela")
    func sair() {
        // recém-aberto sem janela; teve 2; três zeros seguidos encerram — uma vez só
        #expect(respostas([0, 2, 0, 0, 0, 0]).encerrou == [false, false, false, false, true, false])
        #expect(SairAoFechar.nuncaEncerrar.contains("com.apple.finder"))
    }

    @Test("Janela minimizada conta como aberta, mesmo virando AXDialog")
    func minimizadaConta() {
        // o que a Acessibilidade informou de verdade para o TextEdit minimizado
        #expect(SairAoFechar.contar([(subpapel: "AXDialog", minimizada: true)]) == 1)
        #expect(SairAoFechar.contar([(subpapel: "AXStandardWindow", minimizada: false),
                                     (subpapel: "AXDialog", minimizada: true)]) == 2)
        // painel ou diálogo de verdade (não minimizado) não conta
        #expect(SairAoFechar.contar([(subpapel: "AXDialog", minimizada: false),
                                     (subpapel: "AXFloatingWindow", minimizada: false)]) == 0)
    }

    @Test("Zero de passagem (tela cheia, troca de Espaço) não encerra")
    func zeroDePassagem() {
        let r = respostas([1, 0, 1, 0, 0, 1])
        #expect(!r.encerrou.contains(true))
        #expect(r.vigia.zerosSeguidos == 0)
    }

    @Test("Segurar: soltar antes desiste, segurar até o fim confirma")
    func segurar() {
        var p = ProtecaoDeAtalho(modo: .segurar)
        #expect(p.apertou(em: t0, comOpcao: false, nome: "⌘Q") == .segurarComDica("Segure ⌘Q para confirmar", progresso: 0))
        if case .segurarComDica(_, let prog?) = p.segurando(em: t0.addingTimeInterval(0.4), nome: "⌘Q") {
            #expect(abs(prog - 0.5) < 1e-6)   // datas perdem precisão na 7ª casa
        } else { Issue.record("deveria mostrar progresso") }
        #expect(p.soltou() == .cancelar)

        _ = p.apertou(em: t0, comOpcao: false, nome: "⌘Q")
        #expect(p.segurando(em: t0.addingTimeInterval(0.81), nome: "⌘Q") == .confirmar)
        #expect(p.soltou() == .deixar)   // já confirmou: soltar não cancela nada
    }

    @Test("Duas vezes: o segundo toque dentro do tempo confirma")
    func duplo() {
        var p = ProtecaoDeAtalho(modo: .duploToque)
        #expect(p.apertou(em: t0, comOpcao: false, nome: "⌘W") == .segurarComDica("Aperte ⌘W de novo para confirmar", progresso: nil))
        #expect(p.apertou(em: t0.addingTimeInterval(0.5), comOpcao: false, nome: "⌘W") == .confirmar)
        // demorou demais: o segundo vira um primeiro toque novo
        _ = p.apertou(em: t0, comOpcao: false, nome: "⌘W")
        #expect(p.duploExpirou(em: t0.addingTimeInterval(1.5)))
        #expect(p.apertou(em: t0.addingTimeInterval(1.5), comOpcao: false, nome: "⌘W") != .confirmar)
    }

    @Test("Com ⌥: só o atalho com ⌥ confirma")
    func teclaExtra() {
        var p = ProtecaoDeAtalho(modo: .teclaExtra)
        #expect(p.apertou(em: t0, comOpcao: false, nome: "⌘Q") == .segurarComDica("Use ⌥⌘Q para confirmar", progresso: nil))
        #expect(p.apertou(em: t0, comOpcao: true, nome: "⌘Q") == .confirmar)
    }

    @Test("Botão verde: maximiza, volta, e com ⌥ fica como sempre")
    func botaoVerde() {
        let area = CGRect(x: 0, y: 0, width: 1710, height: 1079)
        let janela = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(BotaoVerde.acao(comOpcao: false, quadro: janela, areaUtil: area, temAnterior: false) == .maximizar)
        #expect(BotaoVerde.acao(comOpcao: false, quadro: area, areaUtil: area, temAnterior: true) == .restaurar)
        // maximizada mas sem quadro de antes guardado: maximiza de novo, não some
        #expect(BotaoVerde.acao(comOpcao: false, quadro: area, areaUtil: area, temAnterior: false) == .maximizar)
        #expect(BotaoVerde.acao(comOpcao: true, quadro: janela, areaUtil: area, temAnterior: false) == .deixar)
    }

    @Test("Cliques no Dock: só com o app na frente e janela à vista")
    func dock() {
        #expect(CliqueNoDock.assumir(appNaFrente: true, janelasVisiveis: 2))
        #expect(!CliqueNoDock.assumir(appNaFrente: false, janelasVisiveis: 2))   // o Dock traz para a frente
        #expect(!CliqueNoDock.assumir(appNaFrente: true, janelasVisiveis: 0))    // o Dock desminimiza
        #expect(CliqueNoDock.proxima(atual: 2, total: 3) == 0)
        #expect(CliqueNoDock.proxima(atual: 0, total: 0) == 0)
    }

    @Test("Valores gravados desconhecidos voltam ao padrão")
    func persistidos() {
        #expect(ModoDeProtecao(persisted: "lixo") == .segurar)
        #expect(AcaoNoCliqueDoDock(persisted: "lixo") == .minimizar)
    }
}
