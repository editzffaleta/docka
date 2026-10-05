import Testing
import Foundation
@testable import DockaCore

@Suite("Notificações da ilha")
struct NotificacoesDaIlhaTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("Nome do app tirado da descrição do aviso (como o macOS 27 monta)")
    func app() {
        #expect(NotificacoesDaIlha.app(descricao: "Editor de Scripts, Teste do Docka, Subtítulo, Corpo da mensagem de teste",
                                       titulo: "Teste do Docka", subtitulo: "Subtítulo", corpo: "Corpo da mensagem de teste")
                == "Editor de Scripts")
        // vírgula no título não confunde: o fim tem de bater inteiro
        #expect(NotificacoesDaIlha.app(descricao: "Mail, Oi, tudo bem?, Até amanhã", titulo: "Oi, tudo bem?", subtitulo: nil,
                                       corpo: "Até amanhã") == "Mail")
        #expect(NotificacoesDaIlha.app(descricao: "algo diferente", titulo: "x", subtitulo: nil, corpo: nil) == nil)
    }

    @Test("Juntar: sem repetir, mais novos primeiro, até o limite")
    func juntar() {
        let a = NotificacoesDaIlha.Aviso(id: "a", app: "Mail", titulo: "1", chegou: t0)
        let b = NotificacoesDaIlha.Aviso(id: "b", app: "Mail", titulo: "2", chegou: t0.addingTimeInterval(5))
        var l = NotificacoesDaIlha.juntar([a], a: [])
        l = NotificacoesDaIlha.juntar([a, b], a: l)
        #expect(l.map(\.id) == ["b", "a"])
        let muitos = (0..<40).map { NotificacoesDaIlha.Aviso(id: "\($0)", app: "X", titulo: "", chegou: t0.addingTimeInterval(Double($0))) }
        #expect(NotificacoesDaIlha.juntar(muitos, a: []).count == NotificacoesDaIlha.limite)
    }

    @Test("Por app, na ordem do mais recente")
    func porApp() {
        let l = [NotificacoesDaIlha.Aviso(id: "1", app: "Mail", titulo: "", chegou: t0),
                 NotificacoesDaIlha.Aviso(id: "2", app: "Slack", titulo: "", chegou: t0.addingTimeInterval(10)),
                 NotificacoesDaIlha.Aviso(id: "3", app: "Mail", titulo: "", chegou: t0.addingTimeInterval(20))]
        let g = NotificacoesDaIlha.porApp(l)
        #expect(g.map(\.app) == ["Mail", "Slack"])
        #expect(g[0].avisos.map(\.id) == ["3", "1"])
    }
}
