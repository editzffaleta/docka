import Testing
@testable import DockaCore

@Suite("Escurecimento por software")
struct EscurecimentoTests {

    @Test("Nunca escurece até o preto")
    func limite() {
        #expect(Escurecimento.limitar(1) == Escurecimento.maximo)
        #expect(Escurecimento.limitar(-0.3) == 0)
        #expect(abs(Escurecimento.teto(1) - 0.2) < 1e-9)
        #expect(Escurecimento.teto(0) == 1)
    }

    @Test("A régua e o escurecimento são o mesmo controle, nos dois sentidos")
    func regua() {
        #expect(Escurecimento.nivelDaRegua(escurecimento: 0) == 1)
        #expect(Escurecimento.nivelDaRegua(escurecimento: Escurecimento.maximo) == 0)
        #expect(Escurecimento.escurecimento(nivelDaRegua: 1) == 0)
        #expect(Escurecimento.escurecimento(nivelDaRegua: 0) == Escurecimento.maximo)
        for v in [0.0, 0.2, 0.55, 0.8] {
            let ida = Escurecimento.nivelDaRegua(escurecimento: v)
            #expect(abs(Escurecimento.escurecimento(nivelDaRegua: ida) - v) < 1e-9)
        }
    }

    @Test("A chave da tela não depende do id que muda a cada religada")
    func chave() {
        #expect(Escurecimento.chave(fabricante: 1552, modelo: 41_000, serie: 7) == "1552-41000-7")
        #expect(Escurecimento.chave(fabricante: 1552, modelo: 41_000, serie: 7)
                != Escurecimento.chave(fabricante: 1552, modelo: 41_000, serie: 8))
    }
}
