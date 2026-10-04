import Foundation

/// Um texto pronto para inserir.
public struct Snippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var nome: String
    public var texto: String

    public init(id: UUID = UUID(), nome: String, texto: String) {
        self.id = id
        self.nome = nome
        self.texto = texto
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
        Snippet(nome: "Data de hoje", texto: "{data}"),
        Snippet(nome: "Carimbo", texto: "{dia}, {data} às {hora}"),
    ]
}
