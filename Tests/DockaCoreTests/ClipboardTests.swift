import Testing
import Foundation
@testable import DockaCore

@Suite("Histórico da área de transferência")
struct ClipboardTests {

    private func texto(_ s: String) -> ItemCopiado { ItemCopiado(tipo: .texto, valor: s) }

    @Test("Senha de gerenciador não entra no histórico")
    func sigiloso() {
        #expect(HistoricoDeCopias.deveIgnorar(tipos: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(HistoricoDeCopias.deveIgnorar(tipos: ["org.nspasteboard.TransientType"]))
        #expect(!HistoricoDeCopias.deveIgnorar(tipos: ["public.utf8-plain-text"]))
    }

    @Test("Endereço vira link; texto mantém os espaços originais")
    func classificar() {
        #expect(HistoricoDeCopias.item(deTexto: " https://apple.com ")?.tipo == .link)
        #expect(HistoricoDeCopias.item(deTexto: "  oi\n mundo")?.valor == "  oi\n mundo")
        #expect(HistoricoDeCopias.item(deTexto: " \n ") == nil)
    }

    @Test("Copiar de novo traz para o topo e mantém o fixado")
    func registrar() {
        var a = texto("a"); a.fixado = true
        let r = HistoricoDeCopias.registrar(texto("a"), em: [texto("b"), a])
        #expect(r.map(\.valor) == ["a", "b"])
        #expect(r[0].fixado)
        #expect(r[0].id == a.id)
    }

    @Test("O limite não leva os fixados")
    func limite() {
        var fixo = texto("fixo"); fixo.fixado = true
        let r = HistoricoDeCopias.registrar(texto("novo"), em: [texto("x"), fixo, texto("y")], limite: 2)
        #expect(r.map(\.valor) == ["novo", "x", "fixo"])
    }

    @Test("Busca ignora maiúscula e acento")
    func busca() {
        let itens = [texto("Ação rápida"), texto("outra coisa")]
        #expect(HistoricoDeCopias.buscar("acao", em: itens).map(\.valor) == ["Ação rápida"])
        #expect(HistoricoDeCopias.buscar("  ", em: itens).count == 2)
    }

    @Test("Fixados primeiro na lista")
    func ordem() {
        var f = texto("f"); f.fixado = true
        #expect(HistoricoDeCopias.ordenados([texto("a"), f, texto("b")]).map(\.valor) == ["f", "a", "b"])
    }

    @Test("Resumo numa linha só")
    func resumo() {
        #expect(texto("um\n\n  dois\tTrês").resumo == "um dois Três")
        let arq = ItemCopiado(tipo: .arquivos, valor: "/a/foto.png\n/b/doc.pdf")
        #expect(arq.resumo == "2 arquivos — foto.png, doc.pdf")
    }

    @Test("Limpar link tira os rastreadores e mantém o resto")
    func limparLink() {
        #expect(LimparLink.limpar("https://site.com/p?id=7&utm_source=x&utm_medium=y&fbclid=abc")
                == "https://site.com/p?id=7")
        #expect(LimparLink.limpar("https://site.com/p?utm_source=x") == "https://site.com/p")
        // nada a tirar: devolve nil
        #expect(LimparLink.limpar("https://site.com/p?id=7") == nil)
        #expect(LimparLink.limpar("texto qualquer") == nil)
    }

    @Test("Rastreador por site só sai daquele site")
    func porSite() {
        #expect(LimparLink.limpar("https://youtu.be/abc?si=XYZ&t=30") == "https://youtu.be/abc?t=30")
        #expect(LimparLink.limpar("https://www.youtube.com/watch?v=abc&si=XYZ")
                == "https://www.youtube.com/watch?v=abc")
        // em outro site, `si` pode ser parte do endereço
        #expect(LimparLink.limpar("https://outro.com/busca?si=1") == nil)
    }

    @Test("Opção gravada desconhecida vira nunca")
    func apagar() {
        #expect(ApagarClipboard(persisted: 300) == .cincoMinutos)
        #expect(ApagarClipboard(persisted: 7) == .nunca)
    }
}
