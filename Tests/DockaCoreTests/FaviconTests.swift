import Testing
import Foundation
@testable import DockaCore

@Suite("Busca da logo do site")
struct FaviconTests {

    @Test("As candidatas apontam SÓ para o próprio site, na ordem certa")
    func candidatasSoNoProprioSite() {
        let urls = Favicon.candidatos(para: "https://exemplo.com/pagina/funda")
        #expect(urls.map(\.absoluteString) == [
            "https://exemplo.com/apple-touch-icon.png",
            "https://exemplo.com/apple-touch-icon-precomposed.png",
            "https://exemplo.com/favicon.ico",
        ])
        // nenhuma candidata sai do host digitado: é a garantia de que a lista
        // de sites do usuário não vaza para um resolvedor de terceiros
        #expect(urls.allSatisfy { $0.host == "exemplo.com" })
    }

    @Test("Porta e http são preservados — o site do desenvolvedor")
    func portaEEsquema() {
        let urls = Favicon.candidatos(para: "http://localhost:3000/app")
        #expect(urls.first?.absoluteString == "http://localhost:3000/apple-touch-icon.png")
    }

    @Test("Entrada que não é site não gera candidata nenhuma")
    func entradaInvalida() {
        #expect(Favicon.candidatos(para: "não é url").isEmpty)
        #expect(Favicon.candidatos(para: "ftp://x.com").isEmpty)
        #expect(Favicon.candidatos(para: "").isEmpty)
    }

    @Test("Um arquivo de cache por host, com a porta quando houver")
    func nomeDoCachePorHost() {
        // caminhos diferentes do mesmo site dividem o mesmo ícone
        #expect(Favicon.nomeDoCache(para: "https://exemplo.com/a")
                == Favicon.nomeDoCache(para: "https://exemplo.com/b"))
        #expect(Favicon.nomeDoCache(para: "https://Exemplo.COM") == "exemplo.com.png")
        #expect(Favicon.nomeDoCache(para: "http://localhost:3000") == "localhost_3000.png")
        #expect(Favicon.nomeDoCache(para: "lixo") == nil)
    }
}
