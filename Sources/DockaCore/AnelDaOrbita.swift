import Foundation

/// O que um item da órbita lança.
///
/// A referência lança quatro tipos: aplicativo, site, arquivo e pasta. O
/// `valor` guarda o caminho (app, arquivo, pasta) ou a URL (site).
public enum TipoDeItem: String, Codable, CaseIterable, Sendable {
    case app, site, arquivo, pasta

    public var titulo: String {
        switch self {
        case .app:     return "Aplicativo"
        case .site:    return "Site"
        case .arquivo: return "Arquivo"
        case .pasta:   return "Pasta"
        }
    }

    /// Símbolo SF que representa o tipo nos ajustes.
    public var simbolo: String {
        switch self {
        case .app:     return "app.dashed"
        case .site:    return "globe"
        case .arquivo: return "doc"
        case .pasta:   return "folder"
        }
    }
}

/// Um item do anel.
public struct ItemDaOrbita: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var tipo: TipoDeItem
    /// Caminho no disco, ou URL quando o tipo é site.
    public var valor: String

    public init(id: UUID = UUID(), tipo: TipoDeItem, valor: String) {
        self.id = id
        self.tipo = tipo
        self.valor = valor
    }

    /// Normaliza a URL de um site: sem esquema, assume https.
    ///
    /// O usuário digita "exemplo.com" e é isso que ele espera que funcione —
    /// exigir o https:// na mão só produz um item quebrado.
    public static func urlDeSite(_ texto: String) -> String? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty, !limpo.contains(" ") else { return nil }
        let comEsquema = limpo.contains("://") ? limpo : "https://" + limpo
        guard let url = URL(string: comEsquema),
              let esquema = url.scheme?.lowercased(),
              ["http", "https"].contains(esquema),
              let host = url.host, host.contains(".") || host == "localhost"
        else { return nil }
        return comEsquema
    }

    /// Nome de exibição derivado do valor — para site é o domínio, para os
    /// demais é o nome do arquivo sem extensão.
    public var nomeDerivado: String {
        switch tipo {
        case .site:
            return URL(string: valor)?.host ?? valor
        case .app, .arquivo, .pasta:
            let base = (valor as NSString).lastPathComponent
            return tipo == .app ? (base as NSString).deletingPathExtension : base
        }
    }
}

/// Um anel nomeado — a referência chama de "setup" e aceita até oito.
public struct AnelDaOrbita: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var nome: String
    public var itens: [ItemDaOrbita]

    public init(id: UUID = UUID(), nome: String, itens: [ItemDaOrbita] = []) {
        self.id = id
        self.nome = nome
        self.itens = itens
    }

    /// Move um item uma casa no sentido do `passo` (+1 horário, -1 anti-horário).
    ///
    /// Troca de vizinho, e não `Reorder.move`: aqui o gesto é "uma casa por
    /// clique" nas setinhas da zona, e nas pontas ele simplesmente para — num
    /// anel, "dar a volta" ao reordenar confunde mais do que ajuda.
    public mutating func mover(_ itemID: UUID, passo: Int) {
        guard let i = itens.firstIndex(where: { $0.id == itemID }) else { return }
        let j = i + passo
        guard itens.indices.contains(j) else { return }
        itens.swapAt(i, j)
    }
}

public enum Aneis {
    /// Limite da referência. Mais que isso e a troca por rolagem vira roleta.
    public static let maximo = 8

    /// Itens por anel: acima disso os setores ficam finos demais para apontar.
    public static let maximoDeItens = 12

    public static func podeCriar(_ atuais: [AnelDaOrbita]) -> Bool {
        atuais.count < maximo
    }

    /// Nome para um anel novo, fugindo dos já usados.
    public static func nomeNovo(_ atuais: [AnelDaOrbita]) -> String {
        let usados = Set(atuais.map(\.nome))
        var n = atuais.count + 1
        while usados.contains("Anel \(n)") { n += 1 }
        return "Anel \(n)"
    }

    /// O anel seguinte na rolagem, com a volta fechada.
    ///
    /// `passo` +1 rola para frente, -1 para trás. Com um anel só (ou nenhum),
    /// devolve o que veio — nada a trocar.
    public static func proximo(de atual: UUID?, em aneis: [AnelDaOrbita],
                               passo: Int) -> UUID? {
        guard aneis.count > 1 else { return atual ?? aneis.first?.id }
        guard let atual, let i = aneis.firstIndex(where: { $0.id == atual }) else {
            return aneis.first?.id
        }
        let n = aneis.count
        return aneis[((i + passo) % n + n) % n].id
    }
}
