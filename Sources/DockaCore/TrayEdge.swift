import Foundation
import CoreGraphics

/// A borda da tela onde uma bandeja mora.
///
/// A geometria toda é escrita num eixo abstrato — "ao longo da borda" e
/// "espessura" — e só o mapeamento para coordenadas de tela conhece a borda.
/// Sem isso, cada conta precisaria de uma versão horizontal e outra vertical.
public enum TrayEdge: String, CaseIterable, Sendable, Codable {
    case bottom, left, right

    public init(persisted: String) { self = TrayEdge(rawValue: persisted) ?? .bottom }

    /// Bordas laterais empilham os ícones; a inferior os enfileira.
    public var isVertical: Bool { self != .bottom }

    public var titulo: String {
        switch self {
        case .bottom: return "Borda inferior"
        case .left:   return "Lateral esquerda"
        case .right:  return "Lateral direita"
        }
    }
}

/// Onde a bandeja se ancora AO LONGO da borda.
///
/// Os valores brutos são os antigos (`left`/`center`/`right`) para as
/// preferências já gravadas continuarem válidas; o significado é relativo à
/// borda: numa lateral, `start` é o topo da tela.
public enum TrayAlignment: String, CaseIterable, Sendable, Codable {
    case start = "left"
    case center
    case end = "right"

    public init(persisted: String) { self = TrayAlignment(rawValue: persisted) ?? .end }

    public func titulo(for edge: TrayEdge) -> String {
        switch (self, edge.isVertical) {
        case (.start, false):  return "Esquerda"
        case (.center, _):     return "Centro"
        case (.end, false):    return "Direita"
        case (.start, true):   return "Topo"
        case (.end, true):     return "Base"
        }
    }
}
