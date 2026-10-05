import Foundation
import Testing
@testable import DockaCore

@Suite("Manutenção")
struct ManutencaoTests {

    @Test("Versões: números, partes faltando e sufixos")
    func versoes() {
        #expect(Manutencao.maisNova("1.10", que: "1.9"))
        #expect(!Manutencao.maisNova("2.0", que: "2"))
        #expect(Manutencao.maisNova("1.2.1", que: "1.2"))
        #expect(Manutencao.comparar("1.2 (45)", "1.2 (44)") == .orderedDescending)
        #expect(!Manutencao.maisNova("1.0", que: "1.0.0"))
    }

    @Test("Feed do Sparkle: versão no enclosure ou como elemento, e o mínimo do sistema")
    func feed() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><title>3.1</title><sparkle:version>310</sparkle:version><sparkle:shortVersionString>3.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion></item>
        <item><title>4.0</title><enclosure url="x" sparkle:version="400" sparkle:shortVersionString="4.0"/>
          <sparkle:minimumSystemVersion>30.0</sparkle:minimumSystemVersion></item>
        <item><title>3.0</title><enclosure url="y" sparkle:version="300" sparkle:shortVersionString="3.0"/></item>
        </channel></rss>
        """
        let itens = Manutencao.lerFeed(Data(xml.utf8))
        #expect(itens.count == 3)
        #expect(itens[1].versao == "400" && itens[1].versaoCurta == "4.0")
        // o 4.0 pede um sistema mais novo: o melhor aqui é o 3.1
        #expect(Manutencao.melhor(itens, sistema: "27.2")?.versaoCurta == "3.1")
        #expect(Manutencao.melhor(itens, sistema: "31")?.versaoCurta == "4.0")
    }

    @Test("Portas do lsof: escutando, sem conexões, exposta ou só local")
    func portas() {
        let saida = """
        COMMAND     PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      1234 zffaleta   23u  IPv4 0x1      0t0  TCP 127.0.0.1:3000 (LISTEN)
        rapportd   567 zffaleta    9u  IPv6 0x2      0t0  TCP *:49152 (LISTEN)
        Brave\\x20Br 890 zffaleta   40u  IPv4 0x3      0t0  TCP 192.168.0.2:50000->1.2.3.4:443 (ESTABLISHED)
        Spotify    321 zffaleta   80u  IPv4 0x4      0t0  UDP *:57621
        node      1234 zffaleta   24u  IPv6 0x5      0t0  TCP [::1]:3000 (LISTEN)
        """
        let p = Manutencao.lerPortas(saida)
        #expect(p.map(\.porta) == [3000, 3000, 49152, 57621])
        #expect(p[0].processo == "node" && !p[0].exposta)
        #expect(p[1].endereco == "[::1]" && !p[1].exposta)
        #expect(p[2].exposta && p[2].endereco == "0.0.0.0")
        #expect(p[3].protocolo == "UDP")
    }

    @Test("Restos: pelo identificador ou pelo nome exato")
    func restos() {
        let b = "com.tinyspeck.slackmacgap"
        #expect(Manutencao.pertence("com.tinyspeck.slackmacgap.plist", bundle: b, nome: "Slack"))
        #expect(Manutencao.pertence("com.tinyspeck.slackmacgap", bundle: b, nome: "Slack"))
        #expect(Manutencao.pertence("com.tinyspeck.slackmacgap.ShipIt", bundle: b, nome: "Slack"))
        #expect(Manutencao.pertence("BQR82RBBHL.com.tinyspeck.slackmacgap", bundle: b, nome: "Slack"))
        #expect(Manutencao.pertence("Slack", bundle: b, nome: "Slack"))
        #expect(!Manutencao.pertence("Slack Helper Data", bundle: b, nome: "Slack"))
        #expect(!Manutencao.pertence("com.tinyspeck.slackmacgapfoo", bundle: b, nome: "Slack"))
        // nome curto demais não conta
        #expect(!Manutencao.pertence("Zoo", bundle: "x.y.zoo", nome: "Zoo"))
        #expect(Manutencao.mesmoFabricante("com.docker.install", "com.docker.docker"))
        #expect(!Manutencao.mesmoFabricante("com.spotify.client", "com.docker.docker"))
        #expect(Manutencao.protegido("com.apple.Safari") && Manutencao.protegido("") && !Manutencao.protegido(b))
    }

    @Test("Busca do Homebrew: fórmulas e casks")
    func brew() {
        let r = Manutencao.lerBuscaDoBrew("==> Formulae\nwget\nwgetpaste\n\n==> Casks\nwget-gui\n")
        #expect(r.formulas == ["wget", "wgetpaste"] && r.casks == ["wget-gui"])
        #expect(Manutencao.lerBuscaDoBrew("jq\njqp\n").formulas == ["jq", "jqp"])
    }

    @Test("Downloads velhos pela regra de dias")
    func retencao() {
        let agora = Date(timeIntervalSince1970: 100 * 86_400)
        let arquivos = [("a", agora.addingTimeInterval(-40 * 86_400)), ("b", agora.addingTimeInterval(-10 * 86_400))]
            .map { (caminho: $0.0, data: $0.1) }
        #expect(Manutencao.paraLimpar(arquivos, dias: 30, agora: agora) == ["a"])
        #expect(Manutencao.paraLimpar(arquivos, dias: 0, agora: agora) == ["a", "b"])
    }
}
