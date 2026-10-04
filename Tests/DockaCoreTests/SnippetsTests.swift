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

    @Test("O gatilho dispara no fim do que foi digitado, e só uma vez")
    func gatilho() {
        let lista = [Snippet(nome: "e", texto: "eu@x.com", gatilho: ";email"),
                     Snippet(nome: "curto", texto: "?", gatilho: ";em")]
        var d = DetectorDeGatilho()
        d.digitou("oi ;e")
        #expect(d.procurar(em: lista) == nil)
        d.digitou("m")
        // ";em" já completou — e é o que dispara aqui
        #expect(d.procurar(em: lista)?.nome == "curto")
        d.digitou("ail")
        #expect(d.procurar(em: lista) == nil)   // zerou: ";email" não sobrou inteiro
    }

    @Test("Entre dois gatilhos que terminam igual, vence o mais longo")
    func maisLongo() {
        let lista = [Snippet(nome: "curto", texto: "", gatilho: "il"),
                     Snippet(nome: "longo", texto: "", gatilho: ";email")]
        var d = DetectorDeGatilho()
        d.digitou(";email")
        #expect(d.procurar(em: lista)?.nome == "longo")
    }

    @Test("Apagar corrige, zerar esquece, e a memória é curta")
    func memoria() {
        let lista = [Snippet(nome: "x", texto: "", gatilho: ";ok")]
        var d = DetectorDeGatilho(capacidade: 8)
        d.digitou(";oj"); d.apagou(); d.digitou("k")
        #expect(d.procurar(em: lista)?.nome == "x")
        d.digitou(";o"); d.zerar(); d.digitou("k")
        #expect(d.procurar(em: lista) == nil)
        d.digitou("1234567890")
        #expect(d.digitado.count == 8)
    }

    @Test("Gatilho sem espaço, de 2 a 20 caracteres e sem repetir")
    func valido() {
        let a = Snippet(nome: "a", texto: "", gatilho: ";a")
        #expect(Snippets.gatilhoValido(";email", entre: [a], ignorando: UUID()))
        #expect(!Snippets.gatilhoValido("; e", entre: [a], ignorando: UUID()))
        #expect(!Snippets.gatilhoValido(";", entre: [a], ignorando: UUID()))
        #expect(!Snippets.gatilhoValido(";a", entre: [a], ignorando: UUID()))
        #expect(Snippets.gatilhoValido(";a", entre: [a], ignorando: a.id))
        // começo de outro, nos dois sentidos: o curto engoliria o longo
        let email = Snippet(nome: "e", texto: "", gatilho: ";email")
        #expect(!Snippets.gatilhoValido(";em", entre: [email], ignorando: UUID()))
        #expect(!Snippets.gatilhoValido(";emailx", entre: [email], ignorando: UUID()))
    }

    @Test("Snippet gravado antes do gatilho continua lendo")
    func antigo() throws {
        let json = #"[{"id":"6B1E5C1A-3A33-4C9B-9E43-1A2B3C4D5E6F","nome":"n","texto":"t"}]"#
        let lidos = try JSONDecoder().decode([Snippet].self, from: Data(json.utf8))
        #expect(lidos.first?.gatilho == "")
    }
}
