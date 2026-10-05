import Testing
@testable import DockaCore

@Suite("Permissões")
struct PermissoesTests {
    private let recursos = [
        RecursoComPermissao(nome: "Colar sozinho", permissoes: [.acessibilidade], ligado: true),
        RecursoComPermissao(nome: "Encaixar janelas", permissoes: [.acessibilidade], ligado: false),
        RecursoComPermissao(nome: "Captura", permissoes: [.gravacaoDeTela], ligado: false),
        RecursoComPermissao(nome: "Gatilhos", permissoes: [.monitoramentoDeEntrada, .acessibilidade], ligado: true),
    ]

    @Test("Usada por: só os recursos ligados")
    func usadaPor() {
        #expect(Permissoes.usadaPor(.acessibilidade, em: recursos) == ["Colar sozinho", "Gatilhos"])
        #expect(Permissoes.usadaPor(.gravacaoDeTela, em: recursos).isEmpty)
        #expect(Permissoes.podeSerUsadaPor(.gravacaoDeTela, em: recursos) == ["Captura"])
    }

    @Test("As quatro situações de uma permissão")
    func situacoes() {
        #expect(Permissoes.situacao(.acessibilidade, concedida: true, recursos: recursos) == .emUso)
        #expect(Permissoes.situacao(.gravacaoDeTela, concedida: true, recursos: recursos) == .concedidaSemUso)
        #expect(Permissoes.situacao(.monitoramentoDeEntrada, concedida: false, recursos: recursos) == .falta)
        #expect(Permissoes.situacao(.gravacaoDeTela, concedida: false, recursos: recursos) == .desnecessaria)
    }

    @Test("Lista em português, com \"e\" no fim")
    func lista() {
        #expect(Permissoes.lista([]) == "")
        #expect(Permissoes.lista(["A"]) == "A")
        #expect(Permissoes.lista(["A", "B"]) == "A e B")
        #expect(Permissoes.lista(["A", "B", "C"]) == "A, B e C")
    }

    @Test("Cada permissão abre o painel certo dos Ajustes")
    func enderecos() {
        #expect(Permissao.gravacaoDeTela.enderecoDosAjustes.hasSuffix("Privacy_ScreenCapture"))
        #expect(Set(Permissao.allCases.map(\.enderecoDosAjustes)).count == Permissao.allCases.count)
    }
}
