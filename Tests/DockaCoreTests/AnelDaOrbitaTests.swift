import Testing
import Foundation
@testable import DockaCore

@Suite("Anéis da órbita")
struct AneisTests {

    private func anel(_ nome: String) -> AnelDaOrbita { AnelDaOrbita(nome: nome) }

    @Test("No máximo 8 anéis, como na referência")
    func limiteDeAneis() {
        #expect(Aneis.podeCriar(Array(repeating: anel("x"), count: 7)))
        #expect(!Aneis.podeCriar(Array(repeating: anel("x"), count: 8)))
    }

    @Test("O nome novo foge dos já usados")
    func nomeNovoNaoRepete() {
        let atuais = [anel("Anel 1"), anel("Anel 2")]
        #expect(Aneis.nomeNovo(atuais) == "Anel 3")
        // buraco na numeração não engana: "Anel 2" existe, pula
        let comBuraco = [anel("Anel 1"), anel("Anel 3"), anel("Anel 2")]
        #expect(Aneis.nomeNovo(comBuraco) == "Anel 4")
    }

    @Test("A rolagem percorre os anéis e fecha a volta")
    func rolagemFechaAVolta() {
        let a = anel("A"), b = anel("B"), c = anel("C")
        let todos = [a, b, c]
        #expect(Aneis.proximo(de: a.id, em: todos, passo: 1) == b.id)
        #expect(Aneis.proximo(de: c.id, em: todos, passo: 1) == a.id)   // volta
        #expect(Aneis.proximo(de: a.id, em: todos, passo: -1) == c.id)  // para trás
    }

    @Test("Com um anel só (ou ativo desconhecido), a rolagem não inventa")
    func rolagemDegenerada() {
        let a = anel("A")
        #expect(Aneis.proximo(de: a.id, em: [a], passo: 1) == a.id)
        #expect(Aneis.proximo(de: nil, em: [a], passo: 1) == a.id)
        // ativo que não existe mais: volta para o primeiro
        let b = anel("B")
        #expect(Aneis.proximo(de: UUID(), em: [a, b], passo: 1) == a.id)
        #expect(Aneis.proximo(de: nil, em: [], passo: 1) == nil)
    }
}

@Suite("Itens da órbita")
struct ItemDaOrbitaTests {

    @Test("URL de site: sem esquema assume https")
    func siteSemEsquema() {
        #expect(ItemDaOrbita.urlDeSite("exemplo.com") == "https://exemplo.com")
        #expect(ItemDaOrbita.urlDeSite("  exemplo.com.br  ") == "https://exemplo.com.br")
        #expect(ItemDaOrbita.urlDeSite("http://ja.tem") == "http://ja.tem")
    }

    @Test("Texto que não é site é recusado")
    func siteInvalido() {
        // é o que impede o item quebrado de entrar no anel
        #expect(ItemDaOrbita.urlDeSite("") == nil)
        #expect(ItemDaOrbita.urlDeSite("não é url") == nil)
        #expect(ItemDaOrbita.urlDeSite("semponto") == nil)
        #expect(ItemDaOrbita.urlDeSite("ftp://arquivo.com") == nil)   // só http(s)
    }

    @Test("localhost vale sem ponto — é o site do desenvolvedor")
    func localhostVale() {
        #expect(ItemDaOrbita.urlDeSite("localhost:3000") != nil)
    }

    @Test("O nome derivado fala a língua de cada tipo")
    func nomesDerivados() {
        #expect(ItemDaOrbita(tipo: .site, valor: "https://exemplo.com/x").nomeDerivado == "exemplo.com")
        #expect(ItemDaOrbita(tipo: .app, valor: "/Applications/Notas.app").nomeDerivado == "Notas")
        #expect(ItemDaOrbita(tipo: .pasta, valor: "/Users/x/Projetos").nomeDerivado == "Projetos")
        #expect(ItemDaOrbita(tipo: .arquivo, valor: "/tmp/nota.txt").nomeDerivado == "nota.txt")
    }

    @Test("O anel sobrevive à ida e volta do disco")
    func codavel() throws {
        let anel = AnelDaOrbita(nome: "Trabalho", itens: [
            ItemDaOrbita(tipo: .app, valor: "/Applications/A.app"),
            ItemDaOrbita(tipo: .site, valor: "https://exemplo.com"),
            ItemDaOrbita(tipo: .pasta, valor: "/Users/x/Docs")])
        let volta = try JSONDecoder().decode([AnelDaOrbita].self,
                                             from: JSONEncoder().encode([anel]))
        #expect(volta == [anel])
    }
}

@Suite("Reordenação no anel")
struct MoverItemTests {
    private func anelCom(_ n: Int) -> AnelDaOrbita {
        AnelDaOrbita(nome: "x", itens: (0..<n).map {
            ItemDaOrbita(tipo: .app, valor: "/a/\($0).app")
        })
    }

    @Test("Move uma casa em cada sentido")
    func umaCasa() {
        var anel = anelCom(3)
        let meio = anel.itens[1].id
        anel.mover(meio, passo: 1)
        #expect(anel.itens[2].id == meio)
        anel.mover(meio, passo: -1)
        #expect(anel.itens[1].id == meio)
    }

    @Test("Nas pontas ele para — não dá a volta")
    func naoDaAVolta() {
        // num anel, atravessar a ponta ao reordenar confunde mais do que ajuda
        var anel = anelCom(3)
        let primeiro = anel.itens[0].id
        let antes = anel.itens
        anel.mover(primeiro, passo: -1)
        #expect(anel.itens == antes)
        let ultimo = anel.itens[2].id
        anel.mover(ultimo, passo: 1)
        #expect(anel.itens == antes)
    }

    @Test("Item desconhecido não mexe em nada")
    func desconhecidoNaoMexe() {
        var anel = anelCom(3)
        let antes = anel.itens
        anel.mover(UUID(), passo: 1)
        #expect(anel.itens == antes)
    }
}

@Suite("Submenus da órbita")
struct SubmenusDaOrbitaTests {

    @Test("Entrar e voltar pelos submenus")
    func navegar() {
        let a = UUID(), b = UUID(), c = UUID()
        var n = NavegacaoDaOrbita()
        #expect(!n.emSubmenu)
        n.entrar(b, vindoDe: a)
        #expect(n.exibido == b)
        n.entrar(c, vindoDe: b)
        #expect(n.exibido == c)
        let voltou1 = n.voltar()
        #expect(voltou1)
        #expect(n.exibido == b)
        let voltou2 = n.voltar()
        #expect(voltou2)
        // de volta ao anel de partida: não é mais submenu
        #expect(n.exibido == nil)
        let voltou3 = n.voltar()
        #expect(!voltou3)
    }

    @Test("Entrar no próprio anel não faz nada")
    func mesmoAnel() {
        let a = UUID()
        var n = NavegacaoDaOrbita()
        n.entrar(a, vindoDe: a)
        #expect(!n.emSubmenu)
    }

    @Test("Submenus em roda não estouram a pilha")
    func emRoda() {
        let a = UUID(), b = UUID()
        var n = NavegacaoDaOrbita()
        for k in 0..<50 { n.entrar(k % 2 == 0 ? b : a, vindoDe: k % 2 == 0 ? a : b) }
        #expect(n.pilha.count == NavegacaoDaOrbita.profundidade)
    }

    @Test("Destinos de submenu excluem o próprio anel e os que já estão nele")
    func destinos() {
        let b = AnelDaOrbita(nome: "B"), c = AnelDaOrbita(nome: "C")
        let a = AnelDaOrbita(nome: "A", itens: [ItemDaOrbita(tipo: .anel, valor: b.id.uuidString)])
        #expect(Aneis.destinosDeSubmenu(de: a, em: [a, b, c]).map(\.nome) == ["C"])
    }

    @Test("Apagar um anel leva junto os itens que abriam ele")
    func removerAnel() {
        let b = AnelDaOrbita(nome: "B")
        let app = ItemDaOrbita(tipo: .app, valor: "/Applications/Safari.app")
        let a = AnelDaOrbita(nome: "A", itens: [app, ItemDaOrbita(tipo: .anel, valor: b.id.uuidString)])
        let r = Aneis.removendo(b.id, de: [a, b])
        #expect(r.map(\.nome) == ["A"])
        #expect(r[0].itens == [app])
    }

    @Test("Nome de ação rápida e tipos antigos continuam lendo")
    func compatibilidade() throws {
        #expect(ItemDaOrbita(tipo: .acao, valor: "travarTela").nomeDerivado == "Travar a tela")
        // um anel gravado antes dos tipos novos continua decodificando
        let antigo = #"{"id":"6B1E5C1A-3A33-4C9B-9E43-1A2B3C4D5E6F","tipo":"pasta","valor":"/tmp"}"#
        let item = try JSONDecoder().decode(ItemDaOrbita.self, from: Data(antigo.utf8))
        #expect(item.tipo == .pasta)
    }
}
