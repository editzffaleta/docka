import Testing
import Foundation
@testable import DockaCore

@Suite("Botão do mouse como gatilho")
struct BotaoDoMouseTests {

    @Test("O esquerdo e o direito nunca são aceitos")
    func cliqueNormalNuncaEntra() {
        // sequestrar esses dois no sistema inteiro deixaria o Mac inutilizável
        #expect(!BotaoDoMouse.valido(0))
        #expect(!BotaoDoMouse.valido(1))
        #expect(BotaoDoMouse.recusa(0) != nil)
        #expect(BotaoDoMouse.recusa(1) != nil)
    }

    @Test("Do botão do meio para cima é aceito")
    func extrasSaoAceitos() {
        #expect(BotaoDoMouse.valido(2))     // roda
        #expect(BotaoDoMouse.valido(3))     // lateral 1
        #expect(BotaoDoMouse.valido(4))     // lateral 2
        #expect(BotaoDoMouse.recusa(3) == nil)
    }

    @Test("Números absurdos são recusados")
    func absurdoRecusado() {
        #expect(!BotaoDoMouse.valido(99))
        #expect(!BotaoDoMouse.valido(BotaoDoMouse.nenhum))
        #expect(BotaoDoMouse.recusa(BotaoDoMouse.nenhum) == nil)   // "nenhum" não é erro
    }

    @Test("Os nomes falam a linguagem do mouse, contando de 1")
    func nomes() {
        #expect(BotaoDoMouse.nome(BotaoDoMouse.nenhum) == "Nenhum")
        #expect(BotaoDoMouse.nome(3).contains("4"))
        #expect(BotaoDoMouse.nome(4).contains("5"))
    }

    @Test("Segurar e soltar apontando lança; um toque não")
    func segurarLanca() {
        let t = BotaoDoMouse.limiarDeSegurar
        #expect(BotaoDoMouse.soltouEscolhendo(duracao: t + 0.1, temSelecao: true))
        // toque rápido só deixa o anel aberto, para escolher com calma
        #expect(!BotaoDoMouse.soltouEscolhendo(duracao: 0.05, temSelecao: true))
        // segurar sem apontar nada não pode lançar coisa nenhuma
        #expect(!BotaoDoMouse.soltouEscolhendo(duracao: t + 0.5, temSelecao: false))
    }
}
