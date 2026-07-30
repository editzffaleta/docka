import Foundation

/// O que um atalho global faz.
///
/// Antes existia um atalho só, e ele agia na PRIMEIRA bandeja — com mais de uma
/// configurada, as outras ficavam sem. Cada coisa que aparece na borda agora
/// tem a sua própria combinação, e é isto que as identifica no que fica gravado.
public enum AcaoDeAtalho: Hashable, Sendable {
    /// Fixa/esconde uma bandeja específica.
    case bandeja(UUID)
    /// Revela/esconde o controle de brilho.
    case brilho
    /// Revela/esconde o controle de volume.
    case volume
    /// Abre a janela de ajustes.
    case ajustes
    /// Abre a órbita no cursor.
    case orbita

    /// Chave estável usada no disco e no registro do Carbon.
    public var id: String {
        switch self {
        case .bandeja(let uuid): return "bandeja:\(uuid.uuidString)"
        case .brilho:            return "brilho"
        case .volume:            return "volume"
        case .ajustes:           return "ajustes"
        case .orbita:            return "orbita"
        }
    }

    public init?(id: String) {
        switch id {
        case "brilho":  self = .brilho
        case "volume":  self = .volume
        case "ajustes": self = .ajustes
        case "orbita":  self = .orbita
        default:
            guard id.hasPrefix("bandeja:"),
                  let uuid = UUID(uuidString: String(id.dropFirst("bandeja:".count)))
            else { return nil }
            self = .bandeja(uuid)
        }
    }
}

/// Regras do conjunto de atalhos.
public enum Atalhos {

    /// A ação que já usa esta combinação, se houver outra.
    ///
    /// O Carbon recusaria o segundo registro com um erro genérico de "já em
    /// uso", indistinguível de um conflito com outro app — e o usuário ficaria
    /// procurando culpado fora do Docka. Melhor detectar aqui e dizer o nome.
    public static func jaUsadaPor(_ atalho: Shortcut,
                                  em mapa: [String: Shortcut],
                                  ignorando acao: String) -> String? {
        mapa.first { $0.key != acao && $0.value == atalho }?.key
    }

    /// Só as ações que ainda existem — bandeja apagada leva o atalho junto.
    ///
    /// Sem esta limpeza, o atalho de uma bandeja removida continuaria registrado
    /// no sistema, ocupando a combinação e sem fazer nada ao ser pressionado.
    public static func limpar(_ mapa: [String: Shortcut],
                              bandejasExistentes: Set<UUID>) -> [String: Shortcut] {
        mapa.filter { chave, _ in
            guard let acao = AcaoDeAtalho(id: chave) else { return false }
            if case .bandeja(let uuid) = acao { return bandejasExistentes.contains(uuid) }
            return true
        }
    }
}
