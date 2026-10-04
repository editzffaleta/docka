import Foundation

/// Um texto pronto para inserir.
public struct Snippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var nome: String
    public var texto: String
    /// O que, digitado em qualquer app, vira este snippet (ex.: ";email").
    /// Vazio = só pelo painel.
    public var gatilho: String

    public init(id: UUID = UUID(), nome: String, texto: String, gatilho: String = "") {
        self.id = id
        self.nome = nome
        self.texto = texto
        self.gatilho = gatilho
    }

    // snippets gravados antes do gatilho existir não têm o campo
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nome = try c.decode(String.self, forKey: .nome)
        texto = try c.decode(String.self, forKey: .texto)
        gatilho = try c.decodeIfPresent(String.self, forKey: .gatilho) ?? ""
    }
}

/// Acha um gatilho no fim do que foi digitado.
///
/// Guarda só os últimos caracteres, na memória — o bastante para o maior
/// gatilho, e nada além. Qualquer tecla que muda o cursor de lugar (setas,
/// ↩, clique) zera: o que estava antes já não está colado ao que vem.
public struct DetectorDeGatilho: Sendable {
    public private(set) var digitado = ""
    public let capacidade: Int

    public init(capacidade: Int = 32) { self.capacidade = capacidade }

    public mutating func digitou(_ texto: String) {
        digitado += texto
        if digitado.count > capacidade { digitado = String(digitado.suffix(capacidade)) }
    }

    public mutating func apagou() {
        if !digitado.isEmpty { digitado.removeLast() }
    }

    public mutating func zerar() { digitado = "" }

    /// O snippet cujo gatilho acabou de ser completado — o mais longo, se dois
    /// terminarem igual (";em" e ";email"). Zera ao achar: o mesmo gatilho não
    /// pode disparar duas vezes.
    public mutating func procurar(em snippets: [Snippet]) -> Snippet? {
        let achado = snippets
            .filter { !$0.gatilho.isEmpty && digitado.hasSuffix($0.gatilho) }
            .max { $0.gatilho.count < $1.gatilho.count }
        if achado != nil { zerar() }
        return achado
    }
}

public enum Snippets {

    /// As variáveis que o texto aceita, com o que cada uma vira — é também a
    /// legenda dos ajustes.
    public static let variaveis: [(chave: String, descricao: String)] = [
        ("{data}", "a data de hoje, como 03/10/2026"),
        ("{hora}", "a hora agora, como 14:05"),
        ("{dia}", "o dia da semana, como sexta-feira"),
        ("{clipboard}", "o que está copiado"),
    ]

    /// Troca as variáveis pelos valores. Variável desconhecida fica como
    /// está: melhor mostrar "{nome}" do que sumir com o texto.
    public static func expandir(_ texto: String, agora: Date, clipboard: String?,
                                fuso: TimeZone = .current) -> String {
        func formato(_ f: String) -> String {
            let d = DateFormatter()
            d.locale = Locale(identifier: "pt_BR")
            d.timeZone = fuso
            d.dateFormat = f
            return d.string(from: agora)
        }
        return texto
            .replacingOccurrences(of: "{data}", with: formato("dd/MM/yyyy"))
            .replacingOccurrences(of: "{hora}", with: formato("HH:mm"))
            .replacingOccurrences(of: "{dia}", with: formato("EEEE"))
            .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
    }

    /// Busca no nome e no texto, sem diferenciar maiúscula nem acento.
    public static func buscar(_ termo: String, em lista: [Snippet]) -> [Snippet] {
        let t = termo.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return lista }
        let opcoes: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return lista.filter {
            $0.nome.range(of: t, options: opcoes) != nil || $0.texto.range(of: t, options: opcoes) != nil
        }
    }

    /// Exemplos para quem abre a seção pela primeira vez — mostram as
    /// variáveis funcionando melhor que qualquer explicação.
    public static let exemplos: [Snippet] = [
        Snippet(nome: "Assinatura", texto: "Abraço,\n{clipboard}"),
        Snippet(nome: "Data de hoje", texto: "{data}", gatilho: ";hoje"),
        Snippet(nome: "Carimbo", texto: "{dia}, {data} às {hora}", gatilho: ";agora"),
    ]

    /// Gatilho válido: sem espaço (o espaço é o que separa as palavras, um
    /// gatilho com ele nunca terminaria de ser digitado) e com 2 a 20
    /// caracteres.
    ///
    /// Nem repetido, nem começo de outro: com ";em" e ";email", o ";em"
    /// dispara no "m" e o ";email" nunca chega a ser digitado inteiro.
    public static func gatilhoValido(_ g: String, entre outros: [Snippet], ignorando id: UUID) -> Bool {
        guard (2...20).contains(g.count), !g.contains(where: \.isWhitespace) else { return false }
        return !outros.contains { o in
            o.id != id && !o.gatilho.isEmpty && (o.gatilho.hasPrefix(g) || g.hasPrefix(o.gatilho))
        }
    }
}
