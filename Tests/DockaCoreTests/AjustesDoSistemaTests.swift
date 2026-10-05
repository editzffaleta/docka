import Testing
@testable import DockaCore

@Suite("Ajustes do sistema")
struct AjustesDoSistemaTests {
    @Test("Música: só fecha o que abriu sozinho, atrás")
    func musica() {
        #expect(AjustesDoSistema.fecharMusica(estaNaFrente: false, abertoPorVoce: false))
        #expect(!AjustesDoSistema.fecharMusica(estaNaFrente: true, abertoPorVoce: false))
        #expect(!AjustesDoSistema.fecharMusica(estaNaFrente: false, abertoPorVoce: true))
    }

    @Test("Bluetooth: desliga ao dormir e só religa o que o Docka desligou")
    func bluetooth() {
        #expect(AjustesDoSistema.aoDormir(ligado: true) == (true, true))
        #expect(AjustesDoSistema.aoDormir(ligado: false) == (false, false))
        #expect(AjustesDoSistema.aoAcordar(desligadoPeloDocka: true))
        #expect(!AjustesDoSistema.aoAcordar(desligadoPeloDocka: false))
    }

    @Test("Aceleração: ponto fixo do sistema e faixa")
    func aceleracao() {
        #expect(AjustesDoSistema.pontoFixo(0.875) == 57344)        // o valor lido no Mac do usuário
        #expect(AjustesDoSistema.dePontoFixo(57344) == 0.875)
        #expect(AjustesDoSistema.pontoFixo(-1) == -65536)
        #expect(AjustesDoSistema.limitar(-0.2) == -1)
        #expect(AjustesDoSistema.limitar(5) == 3)
    }
}
