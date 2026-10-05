import Testing
@testable import DockaCore

@Suite("Som")
struct SomTests {

    @Test("Saída do app: a da regra se conectada, senão a padrão")
    func saida() {
        #expect(Som.saidaEfetiva(regra: "fone", conectadas: ["fone", "mac"], padrao: "mac") == "fone")
        #expect(Som.saidaEfetiva(regra: "fone", conectadas: ["mac"], padrao: "mac") == "mac")
        #expect(Som.saidaEfetiva(regra: nil, conectadas: ["mac"], padrao: "mac") == "mac")
    }

    @Test("Só desvia com volume próprio ou saída diferente")
    func desviar() {
        #expect(!Som.precisaDesviar(controle: 1, saida: "mac", padrao: "mac"))
        #expect(Som.precisaDesviar(controle: 0.5, saida: "mac", padrao: "mac"))
        #expect(Som.precisaDesviar(controle: 1, saida: "fone", padrao: "mac"))
        #expect(!Som.precisaDesviar(controle: 1, saida: nil, padrao: "mac"))
    }

    @Test("Próxima saída dá a volta")
    func proxima() {
        #expect(Som.proxima(atual: "a", lista: ["a", "b", "c"]) == "b")
        #expect(Som.proxima(atual: "c", lista: ["a", "b", "c"]) == "a")
        #expect(Som.proxima(atual: "x", lista: ["a", "b"]) == "a")
        #expect(Som.proxima(atual: "a", lista: []) == nil)
    }

    @Test("Fone: Bluetooth ou a saída de fones; tirar baixa o volume, nunca sobe")
    func fones() {
        #expect(Som.ehFone(transporte: 0x626C7565, fonteDeDados: nil))
        #expect(Som.ehFone(transporte: 0x626C746E, fonteDeDados: 0x6864706E))
        #expect(!Som.ehFone(transporte: 0x626C746E, fonteDeDados: 0x6973706B))
        #expect(Som.volumeAoTirarFone(antes: true, agora: false, volume: 0.8, limite: 0.25) == 0.25)
        #expect(Som.volumeAoTirarFone(antes: true, agora: false, volume: 0.1, limite: 0.25) == nil)
        #expect(Som.volumeAoTirarFone(antes: false, agora: false, volume: 0.8, limite: 0.25) == nil)
        #expect(Som.volumeAoTirarFone(antes: false, agora: true, volume: 0.8, limite: 0.25) == nil)
    }

    @Test("Entrada preferida só quando conectada e diferente da atual")
    func entrada() {
        #expect(Som.entradaParaUsar(preferida: "mac", conectadas: ["mac", "airpods"], atual: "airpods") == "mac")
        #expect(Som.entradaParaUsar(preferida: "mac", conectadas: ["mac"], atual: "mac") == nil)
        #expect(Som.entradaParaUsar(preferida: "usb", conectadas: ["mac"], atual: "mac") == nil)
        #expect(Som.entradaParaUsar(preferida: nil, conectadas: ["mac"], atual: "mac") == nil)
    }

    @Test("Silenciar todos e devolver como estava")
    func mudo() {
        var m = Som.Mudo()
        #expect(m.silenciar(["a": false, "b": true]) == ["a", "b"])
        #expect(m.ativo)
        // um microfone que chega com tudo silenciado também é silenciado
        #expect(m.silenciar(["a": true, "b": true, "c": false]) == ["c"])
        // b já estava mudo antes: continua mudo
        #expect(m.religar() == ["a", "c"])
        #expect(!m.ativo)
    }
}
