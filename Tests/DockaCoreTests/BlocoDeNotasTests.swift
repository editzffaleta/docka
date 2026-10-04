import Testing
import Foundation
@testable import DockaCore

@Suite("Bloco de notas")
struct BlocoDeNotasTests {

    @Test("O título vem da primeira linha com conteúdo, sem o #")
    func titulo() {
        #expect(Nota(texto: "\n\n# Compras\n- pão").titulo == "Compras")
        #expect(Nota(texto: "  ideia solta  ").titulo == "ideia solta")
        #expect(Nota(texto: "\n   \n").titulo == "Nota vazia")
        #expect(Nota(texto: "###").titulo == "Nota vazia")
        #expect(Nota(texto: String(repeating: "x", count: 40)).titulo.count == 24)
    }

    @Test("Contagem de palavras")
    func palavras() {
        #expect(Nota(texto: "um  dois\ntrês").palavras == 3)
        #expect(Nota(texto: "").palavras == 0)
        #expect(Nota(texto: "# Teste do Docka\n- [ ] primeira tarefa").palavras == 5)
    }

    @Test("Fechar a aba seleciona a vizinha e nunca zera o bloco")
    func remover() {
        let a = Nota(), b = Nota(), c = Nota()
        let meio = BlocoDeNotas.remover(b.id, de: [a, b, c])
        #expect(meio.notas.map(\.id) == [a.id, c.id])
        #expect(meio.selecionada == c.id)

        let ultima = BlocoDeNotas.remover(c.id, de: [a, b, c])
        #expect(ultima.selecionada == b.id)

        let unica = BlocoDeNotas.remover(a.id, de: [a])
        #expect(unica.notas.count == 1)
        #expect(unica.notas[0].id != a.id)
        #expect(unica.selecionada == unica.notas[0].id)
    }

    @Test("Marcar e desmarcar tarefa mexe só na linha certa")
    func tarefa() {
        let t = "# Hoje\n- [ ] pão\n- [x] leite\n- texto [ ] solto"
        #expect(BlocoDeNotas.alternarTarefa(t, linha: 1) == "# Hoje\n- [x] pão\n- [x] leite\n- texto [ ] solto")
        #expect(BlocoDeNotas.alternarTarefa(t, linha: 2) == "# Hoje\n- [ ] pão\n- [ ] leite\n- texto [ ] solto")
        // não é tarefa: o "[ ]" no meio do texto fica como está
        #expect(BlocoDeNotas.alternarTarefa(t, linha: 3) == t)
        #expect(BlocoDeNotas.alternarTarefa(t, linha: 99) == t)
    }

    @Test("Blocos de Markdown")
    func blocos() {
        let t = """
        # Título
        ## Sub
        - item
        - [ ] fazer
        - [x] feito
        1. primeiro
        > citação
        ---
        texto **forte**


        ```
        let x = 1
        ```
        #semespaço
        """
        #expect(Markdown.blocos(t) == [
            .titulo(nivel: 1, texto: "Título"),
            .titulo(nivel: 2, texto: "Sub"),
            .item(texto: "item"),
            .tarefa(feita: false, texto: "fazer", linha: 3),
            .tarefa(feita: true, texto: "feito", linha: 4),
            .numerado(numero: "1", texto: "primeiro"),
            .citacao(texto: "citação"),
            .divisor,
            .paragrafo(texto: "texto **forte**"),
            .vazio,
            .codigo(texto: "let x = 1"),
            .paragrafo(texto: "#semespaço"),
        ])
    }

    @Test("Código sem fechamento não some")
    func codigoAberto() {
        #expect(Markdown.blocos("```\nlinha") == [.codigo(texto: "linha")])
    }

    @Test("O bloco de notas é um atalho próprio")
    func atalho() {
        #expect(AcaoDeAtalho(id: AcaoDeAtalho.blocoDeNotas.id) == .blocoDeNotas)
    }
}
