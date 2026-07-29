import Foundation
import CoreGraphics

/// A curva de ampliação dos ícones, igual em espírito à do Dock: o ícone sob o
/// cursor cresce e os vizinhos acompanham suavemente, decaindo por uma gaussiana.
public enum Magnification {

    /// Desvio-padrão da curva, em pontos: define o alcance da ampliação ao redor
    /// do cursor. Maior = mais ícones sentem o efeito.
    public static let sigma: CGFloat = 64

    /// Fração do pico a partir da qual o ícone é considerado "sob o cursor" —
    /// é o que decide se o balão com o nome aparece.
    public static let magnifiedThreshold: CGFloat = 0.72

    /// Escala do ícone a `distance` pontos do cursor.
    /// Vale 1 no repouso e `1 + maxBoost` exatamente sob o cursor.
    public static func scale(distance: CGFloat, maxBoost: CGFloat) -> CGFloat {
        guard maxBoost > 0 else { return 1 }
        let boost = exp(-(distance * distance) / (2 * sigma * sigma))
        return 1 + maxBoost * boost
    }

    /// O ícone está perto o bastante do topo da curva para mostrar o nome?
    public static func isMagnified(scale: CGFloat, maxBoost: CGFloat) -> Bool {
        maxBoost > 0 && scale > 1 + maxBoost * magnifiedThreshold
    }
}
