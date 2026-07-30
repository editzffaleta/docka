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
    /// Abre a órbita no cursor, no último anel usado.
    case orbita
    /// Abre a órbita já num anel específico.
    case anel(UUID)

    /// Chave estável usada no disco e no registro do Carbon.
    public var id: String {
        switch self {
        case .bandeja(let uuid): return "bandeja:\(uuid.uuidString)"
        case .brilho:            return "brilho"
        case .volume:            return "volume"
        case .ajustes:           return "ajustes"
        case .orbita:            return "orbita"
        case .anel(let uuid):    return "anel:\(uuid.uuidString)"
        }
    }

    public init?(id: String) {
        switch id {
        case "brilho":  self = .brilho
        case "volume":  self = .volume
        case "ajustes": self = .ajustes
        case "orbita":  self = .orbita
        default:
            if id.hasPrefix("bandeja:"),
               let uuid = UUID(uuidString: String(id.dropFirst("bandeja:".count))) {
                self = .bandeja(uuid)
            } else if id.hasPrefix("anel:"),
                      let uuid = UUID(uuidString: String(id.dropFirst("anel:".count))) {
                self = .anel(uuid)
            } else {
                return nil
            }
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

    /// Só as ações que ainda existem — bandeja ou anel apagado leva o atalho
    /// junto.
    ///
    /// Sem esta limpeza, o atalho de algo removido continuaria registrado no
    /// sistema, ocupando a combinação e sem fazer nada ao ser pressionado.
    public static func limpar(_ mapa: [String: Shortcut],
                              bandejasExistentes: Set<UUID>,
                              aneisExistentes: Set<UUID> = []) -> [String: Shortcut] {
        mapa.filter { chave, _ in
            guard let acao = AcaoDeAtalho(id: chave) else { return false }
            switch acao {
            case .bandeja(let uuid): return bandejasExistentes.contains(uuid)
            case .anel(let uuid):    return aneisExistentes.contains(uuid)
            default:                 return true
            }
        }
    }
}
