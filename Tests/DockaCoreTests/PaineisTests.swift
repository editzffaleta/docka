import Foundation
import Testing
@testable import DockaCore

@Suite("Barra de comando")
struct BarraDeComandoTests {

    @Test("Pontuação: igual > começo > palavra > iniciais > meio > letras em ordem")
    func pontuacao() {
        let igual = BarraDeComando.pontuar("safari", "Safari")!
        let comeco = BarraDeComando.pontuar("saf", "Safari")!
        let palavra = BarraDeComando.pontuar("studio", "Visual Studio Code")!
        let iniciais = BarraDeComando.pontuar("vsc", "Visual Studio Code")!
        let meio = BarraDeComando.pontuar("tudi", "Visual Studio Code")!
        let letras = BarraDeComando.pontuar("vscd", "Visual Studio Code")!
        #expect(igual > comeco && comeco > palavra && palavra > iniciais && iniciais > meio && meio > letras)
        #expect(BarraDeComando.pontuar("musica", "Música") == 1000)
        #expect(BarraDeComando.pontuar("xyz", "Safari") == nil)
        #expect(BarraDeComando.pontuar("", "Safari") == nil)
    }

    @Test("Ordem: resultado primeiro, limite por tipo, palavras extras valem menos")
    func ordem() {
        typealias C = BarraDeComando.Candidato
        let arquivos = (1...10).map { C(id: "a\($0)", tipo: .arquivo, titulo: "nota \($0).txt") }
        let lista = arquivos + [
            C(id: "app", tipo: .app, titulo: "Notas"),
            C(id: "conta", tipo: .resultado, titulo: "4"),
            C(id: "snip", tipo: .snippet, titulo: "Assinatura", palavras: "notas do dia"),
        ]
        let r = BarraDeComando.ordenar(lista, termo: "nota", porTipo: 3)
        #expect(r.first?.id == "conta")
        #expect(r[1].id == "app")
        #expect(r.filter { $0.tipo == .arquivo }.count == 3)
        // o snippet só casa pelo conteúdo: fica atrás do app que casa pelo nome
        #expect(r.firstIndex { $0.id == "snip" }! > r.firstIndex { $0.id == "app" }!)
    }

    @Test("Comando de menu passa na frente de arquivo com nome parecido")
    func menuAntesDeArquivo() {
        typealias C = BarraDeComando.Candidato
        let r = BarraDeComando.ordenar([C(id: "f", tipo: .arquivo, titulo: "FontElement.d.ts"),
                                        C(id: "m", tipo: .menu, titulo: "Mostrar Fontes")], termo: "fonte")
        #expect(r.map(\.id) == ["m", "f"])
    }

    @Test("Arquivos de dependências e ocultos ficam fora")
    func relevantes() {
        let casa = "/Users/x"
        #expect(BarraDeComando.arquivoRelevante("/Users/x/Documents/fonte.txt", casa: casa))
        #expect(!BarraDeComando.arquivoRelevante("/Users/x/dev/app/node_modules/a/fonte.js", casa: casa))
        #expect(!BarraDeComando.arquivoRelevante("/Users/x/.cache/fonte", casa: casa))
        #expect(!BarraDeComando.arquivoRelevante("/Users/x/Library/Caches/fonte", casa: casa))
    }

    @Test("Caminho e atalho dos menus")
    func menus() {
        #expect(BarraDeComando.caminhoDoMenu(["Arquivo", "", "Exportar"]) == "Arquivo › Exportar")
        #expect(BarraDeComando.atalhoDoMenu(tecla: "n", modificadores: 0) == "⌘N")
        #expect(BarraDeComando.atalhoDoMenu(tecla: "s", modificadores: 1 | 2) == "⌥⇧⌘S")
        #expect(BarraDeComando.atalhoDoMenu(tecla: "f", modificadores: 4 | 8) == "⌃F")
        #expect(BarraDeComando.atalhoDoMenu(tecla: nil, modificadores: 0) == nil)
    }

    @Test("Resumo do script")
    func script() {
        #expect(BarraDeComando.resumoDoScript(saida: "\n  pronto \nmais", codigo: 0) == "pronto")
        #expect(BarraDeComando.resumoDoScript(saida: "", codigo: 0) == "Terminou")
        #expect(BarraDeComando.resumoDoScript(saida: "não achei", codigo: 2) == "Falhou (código 2): não achei")
    }
}

@Suite("Calculadora")
struct CalculadoraTests {

    private func valor(_ s: String) -> Double? { Calculadora.avaliar(s)?.valor }

    @Test("Operações, precedência e parênteses")
    func operacoes() {
        #expect(valor("2+2") == 4)
        #expect(valor("2 + 3 * 4") == 14)
        #expect(valor("(2 + 3) * 4") == 20)
        #expect(valor("2^10") == 1024)
        #expect(valor("10 / 4") == 2.5)
        #expect(valor("3 x 3") == 9)
        #expect(valor("8 ÷ 2 × 3") == 12)
        #expect(valor("-3 + 5") == 2)
    }

    @Test("Vírgula decimal, milhar, porcentagem e funções")
    func extras() {
        #expect(valor("2,5 * 2") == 5)
        #expect(valor("1.000,5 + 1") == 1001.5)
        #expect(valor("15% de 80") == 12)
        #expect(valor("200 + 10%") == 220)
        #expect(valor("raiz(16) + 1") == 5)
        #expect(valor("=pi")! > 3.14 && valor("=pi")! < 3.15)
    }

    @Test("O que não é conta fica de fora")
    func naoConta() {
        #expect(valor("2026") == nil)
        #expect(valor("safari") == nil)
        #expect(valor("1/0") == nil)
        #expect(valor("2 +") == nil)
        #expect(valor("(2+3") == nil)
    }

    @Test("Formato brasileiro")
    func formato() {
        let c = Calculadora.avaliar("1234.5 * 1")!
        #expect(c.texto == "1.234,5")
        #expect(c.copia == "1234,5")
        #expect(Calculadora.avaliar("0.1 + 0.2")!.texto == "0,3")
    }
}

@Suite("Conversões")
struct ConversaoTests {

    private func texto(_ s: String) -> String? { Conversao.converter(s)?.texto }

    @Test("Unidades comuns, em português e inglês")
    func comuns() {
        #expect(texto("10 km em mi") == "6,21 mi")
        #expect(texto("100 f para c") == "37,78 °C")
        #expect(texto("1 gb em mb") == "1.000 MB")
        #expect(texto("90 min em horas") == "1,5 h")
        #expect(texto("5 lb to kg") == "2,27 kg")
        #expect(texto("2 dias em h") == "48 h")
        #expect(texto("10km->m") == "10.000 m")
        #expect(Conversao.converter("1 gb em mb")?.copia == "1000")
    }

    @Test("\"in\" é polegada quando há outro separador")
    func polegada() {
        #expect(texto("10 in to cm") == "25,4 cm")
        #expect(texto("2,54 cm em pol") == "1 pol")
    }

    @Test("Categorias diferentes ou unidade desconhecida não convertem")
    func invalidas() {
        #expect(texto("10 km em kg") == nil)
        #expect(texto("10 parsecs em km") == nil)
        #expect(texto("km em mi") == nil)
        #expect(texto("10 km") == nil)
    }
}

@Suite("Emoji")
struct EmojiTests {

    @Test("Acha pelo apelido em português e pelo nome do Unicode")
    func busca() {
        #expect(Emojis.buscar("joinha").first?.caractere == "👍")
        #expect(Emojis.buscar("coração").contains { $0.caractere == "❤️" })
        #expect(Emojis.buscar("rocket").first?.caractere == "🚀")
        #expect(Emojis.buscar("a").isEmpty)
        #expect(!Emojis.buscar("term").contains { $0.caractere == "🍉" })
        #expect(Emojis.todos.count > 1000)
    }
}

@Suite("Modo de limpeza e painel rápido")
struct PaineisTests {

    @Test("O prazo acaba sozinho e nunca é curto demais")
    func prazo() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let m = ModoDeLimpeza(inicio: t0, duracao: 60)
        #expect(m.ativo(em: t0.addingTimeInterval(59)))
        #expect(!m.ativo(em: t0.addingTimeInterval(60)))
        #expect(m.restante(em: t0.addingTimeInterval(55)) == 5)
        #expect(ModoDeLimpeza(inicio: t0, duracao: 0).fim == t0.addingTimeInterval(10))
        #expect(ModoDeLimpeza.relogio(65) == "1:05")
    }

    @Test("Engole só o teclado")
    func engole() {
        #expect(ModoDeLimpeza.engole(tipo: 10) && ModoDeLimpeza.engole(tipo: 12) && ModoDeLimpeza.engole(tipo: 14))
        #expect(!ModoDeLimpeza.engole(tipo: 1))   // clique
        #expect(!ModoDeLimpeza.engole(tipo: 5))   // movimento
    }

    @Test("Segurar para sair")
    func sair() {
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(ModoDeLimpeza.progressoDeSaida(desde: nil, agora: t0) == 0)
        #expect(abs(ModoDeLimpeza.progressoDeSaida(desde: t0, agora: t0.addingTimeInterval(0.6)) - 0.5) < 1e-4)
        #expect(ModoDeLimpeza.progressoDeSaida(desde: t0, agora: t0.addingTimeInterval(5)) == 1)
    }

    @Test("Favoritos: padrão, sem repetidos, só o que existe")
    func favoritos() {
        #expect(PainelRapido.favoritos(gravados: nil) { _ in true } == PainelRapido.padrao)
        #expect(PainelRapido.favoritos(gravados: ["a", "b", "a", "x"]) { $0 != "x" } == ["a", "b"])
        #expect(PainelRapido.alternar("b", em: ["a", "b", "c"]) == ["a", "c"])
        #expect(PainelRapido.alternar("d", em: ["a"]) == ["a", "d"])
        #expect(PainelRapido.colunas(2) == 2 && PainelRapido.colunas(12) == 4 && PainelRapido.colunas(0) == 1)
        // todo favorito padrão é uma ação de atalho de verdade
        #expect(PainelRapido.padrao.allSatisfy { AcaoDeAtalho(id: $0) != nil })
    }

    @Test("Ações novas viram atalho e voltam")
    func atalhos() {
        for a in [AcaoDeAtalho.barraDeComando, .painelRapido, .limpeza] {
            #expect(AcaoDeAtalho(id: a.id) == a)
        }
        #expect(AcaoRapida.aparencia.alternancia && !AcaoRapida.esvaziarLixo.alternancia)
    }
}
