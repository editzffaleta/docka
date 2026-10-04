import Foundation

/// O que um item da órbita lança.
///
/// A referência lança quatro tipos: aplicativo, site, arquivo e pasta. O
/// `valor` guarda o caminho (app, arquivo, pasta) ou a URL (site).
///
/// Mais dois não lançam nada de fora: `anel` abre outro anel no mesmo lugar,
/// como um submenu (o `valor` é o id dele), e `acao` executa uma ação rápida
/// (o `valor` é o `rawValue` da `AcaoRapida`).
public enum TipoDeItem: String, Codable, CaseIterable, Sendable {
    case app, site, arquivo, pasta, anel, acao

    public var titulo: String {
        switch self {
        case .app:     return "Aplicativo"
        case .site:    return "Site"
        case .arquivo: return "Arquivo"
        case .pasta:   return "Pasta"
        case .anel:    return "Submenu"
        case .acao:    return "Ação rápida"
        }
    }

    /// Símbolo SF que representa o tipo nos ajustes.
    public var simbolo: String {
        switch self {
        case .app:     return "app.dashed"
        case .site:    return "globe"
        case .arquivo: return "doc"
        case .pasta:   return "folder"
        case .anel:    return "circle.circle"
        case .acao:    return "bolt.fill"
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
        case .anel:
            return "Submenu"
        case .acao:
            return AcaoRapida(rawValue: valor)?.titulo ?? valor
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

/// Por onde a órbita andou ao entrar em submenus — para o "voltar".
public struct NavegacaoDaOrbita: Equatable, Sendable {
    /// Os anéis de onde se entrou, do mais antigo ao mais recente.
    public private(set) var pilha: [UUID] = []
    /// O anel mostrado agora, quando é um submenu; `nil` = o anel ativo.
    public private(set) var exibido: UUID?

    /// Profundidade máxima. Submenus que se apontam em roda não podem fazer
    /// a pilha crescer sem fim.
    public static let profundidade = 8

    public init() {}

    public var emSubmenu: Bool { exibido != nil }

    /// Entra no anel `destino`, guardando `atual` para voltar.
    public mutating func entrar(_ destino: UUID, vindoDe atual: UUID) {
        guard destino != atual else { return }
        pilha.append(atual)
        if pilha.count > Self.profundidade { pilha.removeFirst() }
        exibido = destino
    }

    /// Volta um nível. Devolve `false` se já estava no anel de partida —
    /// aí quem chamou fecha a órbita.
    @discardableResult
    public mutating func voltar() -> Bool {
        guard emSubmenu, let anterior = pilha.popLast() else { return false }
        // a base da pilha é o anel ativo: voltar até ela é sair do submenu
        exibido = pilha.isEmpty ? nil : anterior
        return true
    }

    /// Esquece o caminho — ao fechar, ou ao trocar de anel pela rolagem.
    public mutating func zerar() {
        pilha = []
        exibido = nil
    }
}

public enum Aneis {
    /// Limite da referência. Mais que isso e a troca por rolagem vira roleta.
    public static let maximo = 8

    /// Itens por anel: acima disso os setores ficam finos demais para apontar.
    public static let maximoDeItens = 12

    /// Anéis que podem virar submenu de `anel`: todos menos ele mesmo e os que
    /// ele já tem como item. Um anel que abre a si mesmo não leva a lugar
    /// nenhum.
    public static func destinosDeSubmenu(de anel: AnelDaOrbita,
                                         em aneis: [AnelDaOrbita]) -> [AnelDaOrbita] {
        let jaTem = Set(anel.itens.filter { $0.tipo == .anel }.map(\.valor))
        return aneis.filter { $0.id != anel.id && !jaTem.contains($0.id.uuidString) }
    }

    /// Apaga um anel e, junto, os itens dos outros que abriam ele — sem isso
    /// sobraria um setor que não leva a lugar nenhum.
    public static func removendo(_ id: UUID, de aneis: [AnelDaOrbita]) -> [AnelDaOrbita] {
        aneis.filter { $0.id != id }.map { a in
            var a = a
            a.itens.removeAll { $0.tipo == .anel && $0.valor == id.uuidString }
            return a
        }
    }

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
