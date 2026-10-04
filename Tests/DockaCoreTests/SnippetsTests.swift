import Testing
import Foundation
@testable import DockaCore

@Suite("Snippets")
struct SnippetsTests {
    // 3 de outubro de 2026, 14:05, em São Paulo (um sábado)
    private let agora: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 3; c.hour = 14; c.minute = 5
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    private let sp = TimeZone(identifier: "America/Sao_Paulo")!

    @Test("Variáveis viram data, hora, dia e o copiado")
    func expandir() {
        let r = Snippets.expandir("{dia}, {data} às {hora} — {clipboard}",
                                  agora: agora, clipboard: "Bruno", fuso: sp)
        #expect(r == "sábado, 03/10/2026 às 14:05 — Bruno")
    }

    @Test("Sem nada copiado, {clipboard} some; variável desconhecida fica")
    func bordas() {
        #expect(Snippets.expandir("a{clipboard}b", agora: agora, clipboard: nil, fuso: sp) == "ab")
        #expect(Snippets.expandir("{nome}", agora: agora, clipboard: nil, fuso: sp) == "{nome}")
    }

    @Test("Busca no nome e no texto, sem acento")
    func busca() {
        let lista = [Snippet(nome: "Endereço", texto: "Rua A"), Snippet(nome: "Email", texto: "x@y.com")]
        #expect(Snippets.buscar("endereco", em: lista).map(\.nome) == ["Endereço"])
        #expect(Snippets.buscar("y.com", em: lista).map(\.nome) == ["Email"])
        #expect(Snippets.buscar("", em: lista).count == 2)
    }

    @Test("Os snippets são um atalho próprio")
    func atalho() {
        #expect(AcaoDeAtalho(id: AcaoDeAtalho.snippets.id) == .snippets)
    }
}
