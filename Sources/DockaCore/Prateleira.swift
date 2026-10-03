import Foundation
import CoreGraphics

/// Uma coisa estacionada na prateleira: arquivo, texto ou link.
public struct ItemDaPrateleira: Identifiable, Codable, Equatable, Sendable {
    public enum Tipo: String, Codable, Sendable {
        case arquivo, texto, link
    }

    public var id: UUID
    public var tipo: Tipo
    /// Caminho do arquivo, o texto em si ou o endereço do link.
    public var valor: String

    public init(id: UUID = UUID(), tipo: Tipo, valor: String) {
        self.id = id
        self.tipo = tipo
        self.valor = valor
    }

    /// O que a linha mostra em destaque.
    public var titulo: String {
        switch tipo {
        case .arquivo:
            return (valor as NSString).lastPathComponent
        case .texto:
            let linha = valor.split(whereSeparator: \.isNewline).first.map(String.init) ?? valor
            return Prateleira.encurtar(linha.trimmingCharacters(in: .whitespaces), ate: 60)
        case .link:
            return URL(string: valor)?.host ?? valor
        }
    }

    /// A linha de baixo: pasta do arquivo, tamanho do texto, endereço do link.
    public var detalhe: String {
        switch tipo {
        case .arquivo:
            let pasta = (valor as NSString).deletingLastPathComponent
            return (pasta as NSString).abbreviatingWithTildeInPath
        case .texto:
            let n = valor.count
            return n == 1 ? "1 caractere" : "\(n) caracteres"
        case .link:
            return Prateleira.encurtar(valor, ate: 80)
        }
    }
}

public enum Prateleira {

    /// Acima disto a lista vira depósito, e a prateleira é para o que está de
    /// passagem. Os mais antigos saem primeiro.
    public static let maximoDeItens = 40
    /// Texto gigante colado por engano não pode ir parar inteiro no plist.
    public static let maximoDeCaracteres = 100_000

    /// Texto solto que é só um endereço web vira link — é como o usuário pensa
    /// nele, e um link abre no navegador em vez de num editor.
    public static func classificar(_ texto: String) -> ItemDaPrateleira? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return nil }
        if !limpo.contains(where: \.isWhitespace),
           let url = URL(string: limpo),
           let esquema = url.scheme?.lowercased(),
           esquema == "http" || esquema == "https",
           url.host != nil {
            return ItemDaPrateleira(tipo: .link, valor: limpo)
        }
        return ItemDaPrateleira(tipo: .texto, valor: String(limpo.prefix(maximoDeCaracteres)))
    }

    /// Junta os novos no topo, sem repetir o que já está lá e sem passar do
    /// limite.
    ///
    /// Repetido não duplica: soltar de novo o mesmo arquivo só o traz para o
    /// topo, que é o que a pessoa quis dizer com o gesto.
    public static func adicionar(_ novos: [ItemDaPrateleira],
                                 a itens: [ItemDaPrateleira]) -> [ItemDaPrateleira] {
        var resultado = itens
        for novo in novos.reversed() {
            resultado.removeAll { $0.tipo == novo.tipo && $0.valor == novo.valor }
            resultado.insert(novo, at: 0)
        }
        return Array(resultado.prefix(maximoDeItens))
    }

    /// Tira os arquivos que sumiram do disco — movidos para outro lugar a
    /// partir da própria prateleira, ou apagados.
    public static func semArquivosSumidos(_ itens: [ItemDaPrateleira],
                                          existe: (String) -> Bool) -> [ItemDaPrateleira] {
        itens.filter { $0.tipo != .arquivo || existe($0.valor) }
    }

    /// O que a alça "Tudo" leva.
    ///
    /// Havendo arquivos, só eles: o Finder recusa a soltura INTEIRA quando
    /// arquivos chegam misturados com texto ou link — a pessoa arrastava cinco
    /// itens e nada acontecia. Sem arquivos, vai tudo.
    public static func paraLevarTudo(_ itens: [ItemDaPrateleira]) -> [ItemDaPrateleira] {
        let arquivos = itens.filter { $0.tipo == .arquivo }
        return arquivos.isEmpty ? itens : arquivos
    }

    public static func encurtar(_ s: String, ate n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }

    // MARK: painel

    /// Só laterais: a lista é vertical, como a régua.
    public static let bordasPermitidas: [TrayEdge] = [.left, .right]

    public static func edge(persisted: String) -> TrayEdge {
        let e = TrayEdge(persisted: persisted)
        return bordasPermitidas.contains(e) ? e : .right
    }

    /// Comprimento do painel ao longo da borda e espessura.
    public static let comprimento: CGFloat = 400
    public static let espessura: CGFloat = 270

    // MARK: abrir ao arrastar

    /// Um arrasto começou desde a última olhada?
    ///
    /// O macOS escreve o que está sendo arrastado numa área de transferência
    /// própria, e o contador dela muda a cada arrasto novo. Ler o contador não
    /// pede permissão; o botão apertado separa o arrasto em curso de um que já
    /// terminou.
    public static func arrastoComecou(botaoApertado: Bool,
                                      contadorAtual: Int,
                                      contadorVisto: Int) -> Bool {
        botaoApertado && contadorAtual != contadorVisto
    }
}
