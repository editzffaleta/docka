import Testing
import Foundation
@testable import DockaCore

@Suite("Prateleira")
struct PrateleiraTests {

    private func arquivo(_ p: String) -> ItemDaPrateleira { .init(tipo: .arquivo, valor: p) }

    @Test("Endereço web vira link; o resto vira texto")
    func classificar() {
        #expect(Prateleira.classificar("https://apple.com/mac")?.tipo == .link)
        #expect(Prateleira.classificar("  http://exemplo.com.br \n")?.valor == "http://exemplo.com.br")
        #expect(Prateleira.classificar("veja https://apple.com")?.tipo == .texto)
        #expect(Prateleira.classificar("ftp://servidor")?.tipo == .texto)
        #expect(Prateleira.classificar("apple.com")?.tipo == .texto)
        #expect(Prateleira.classificar("   \n ") == nil)
    }

    @Test("Texto gigante é cortado")
    func textoGrande() {
        let enorme = String(repeating: "a", count: Prateleira.maximoDeCaracteres + 10)
        #expect(Prateleira.classificar(enorme)?.valor.count == Prateleira.maximoDeCaracteres)
    }

    @Test("Os novos entram no topo, na ordem em que vieram")
    func ordem() {
        let antigos = [arquivo("/a")]
        let r = Prateleira.adicionar([arquivo("/b"), arquivo("/c")], a: antigos)
        #expect(r.map(\.valor) == ["/b", "/c", "/a"])
    }

    @Test("Soltar de novo não duplica, só traz para o topo")
    func semRepetir() {
        let r = Prateleira.adicionar([arquivo("/a")], a: [arquivo("/b"), arquivo("/a")])
        #expect(r.map(\.valor) == ["/a", "/b"])
    }

    @Test("O limite descarta os mais antigos")
    func limite() {
        let cheios = (0..<Prateleira.maximoDeItens).map { arquivo("/\($0)") }
        let r = Prateleira.adicionar([arquivo("/novo")], a: cheios)
        #expect(r.count == Prateleira.maximoDeItens)
        #expect(r.first?.valor == "/novo")
        #expect(!r.contains { $0.valor == "/\(Prateleira.maximoDeItens - 1)" })
    }

    @Test("Arquivo que sumiu sai; texto e link ficam")
    func sumidos() {
        let itens = [arquivo("/existe"), arquivo("/sumiu"),
                     .init(tipo: .texto, valor: "oi"), .init(tipo: .link, valor: "https://a.com")]
        let r = Prateleira.semArquivosSumidos(itens) { $0 == "/existe" }
        #expect(r.map(\.valor) == ["/existe", "oi", "https://a.com"])
    }

    @Test("Títulos e detalhes")
    func titulos() {
        let f = arquivo("/Users/x/Desktop/foto.png")
        #expect(f.titulo == "foto.png")
        let t = ItemDaPrateleira(tipo: .texto, valor: "primeira linha\nsegunda")
        #expect(t.titulo == "primeira linha")
        #expect(t.detalhe == "22 caracteres")
        let l = ItemDaPrateleira(tipo: .link, valor: "https://www.apple.com/mac/")
        #expect(l.titulo == "www.apple.com")
    }

    @Test("\"Tudo\" leva só os arquivos quando há arquivos")
    func levarTudo() {
        let t = ItemDaPrateleira(tipo: .texto, valor: "oi")
        let l = ItemDaPrateleira(tipo: .link, valor: "https://a.com")
        let misto = [arquivo("/a"), t, arquivo("/b"), l]
        #expect(Prateleira.paraLevarTudo(misto).map(\.valor) == ["/a", "/b"])
        #expect(Prateleira.paraLevarTudo([t, l]).count == 2)
        #expect(Prateleira.paraLevarTudo([]).isEmpty)
    }

    @Test("Só laterais")
    func bordas() {
        #expect(Prateleira.edge(persisted: "left") == .left)
        #expect(Prateleira.edge(persisted: "bottom") == .right)
        #expect(Prateleira.edge(persisted: "lixo") == .right)
    }

    @Test("Arrasto novo só com o botão apertado")
    func arrasto() {
        #expect(Prateleira.arrastoComecou(botaoApertado: true, contadorAtual: 5, contadorVisto: 4))
        #expect(!Prateleira.arrastoComecou(botaoApertado: true, contadorAtual: 4, contadorVisto: 4))
        // o contador mudou, mas o arrasto já acabou: não abre atrasado
        #expect(!Prateleira.arrastoComecou(botaoApertado: false, contadorAtual: 5, contadorVisto: 4))
    }

    @Test("A prateleira é um atalho próprio")
    func atalho() {
        #expect(AcaoDeAtalho(id: AcaoDeAtalho.prateleira.id) == .prateleira)
    }
}
