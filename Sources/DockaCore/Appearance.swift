import Foundation
import CoreGraphics

/// Aparência da bandeja, espelhando o controle de Aparência do sistema.
public enum TrayAppearance: String, CaseIterable, Sendable {
    case automatico
    case claro
    case escuro

    public init(persisted: String) {
        self = TrayAppearance(rawValue: persisted) ?? .automatico
    }

    public var titulo: String {
        switch self {
        case .automatico: return "Automático"
        case .claro:      return "Tom claro"
        case .escuro:     return "Tom escuro"
        }
    }
}

/// Tonalização do vidro — o análogo do slider "Liquid Glass" das Configurações.
///
/// O sistema guarda o dele em `NSGlassTintAmount` (0 = transparente, 1 = tonalizado).
/// O `.glassEffect` não aceita esse número direto, então mapeamos para as duas
/// alavancas que a API oferece: a variante do vidro e a opacidade do tint.
public enum GlassTint {

    /// Abaixo disto o vidro usa a variante `.clear`, que é a ponta transparente
    /// do controle da Apple. Acima, `.regular` com tonalização crescente.
    public static let clearThreshold: Double = 0.12

    /// Opacidade máxima do tint preto no topo do slider.
    ///
    /// Passar disto fecha o vidro a ponto de virar um retângulo sólido — deixa
    /// de ser vidro e passa a ser fundo.
    public static let maxOverlay: Double = 0.42

    public static func usesClearGlass(_ amount: Double) -> Bool {
        clamp(amount) < clearThreshold
    }

    /// Opacidade do tint preto para um valor do slider.
    public static func overlayOpacity(_ amount: Double) -> Double {
        let a = clamp(amount)
        guard a >= clearThreshold else { return 0 }
        // reescala [limiar, 1] para [0, máximo] — sem degrau ao cruzar o limiar
        return (a - clearThreshold) / (1 - clearThreshold) * maxOverlay
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
