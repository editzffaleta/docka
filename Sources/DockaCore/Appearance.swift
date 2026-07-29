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

/// Tonalização do vidro — um controle de **desvio** em relação ao sistema.
///
/// O ponto que custou uma rodada de testes: `.glassEffect(.regular)` é o material
/// do próprio macOS e **já obedece** ao slider Liquid Glass do usuário
/// (`NSGlassTintAmount`). Somar um tint preto por cima aplicava a tonalização
/// duas vezes: o vidro fechava e o brilho especular da borda — a assinatura do
/// Liquid Glass — desaparecia. Verificado em captura, com e sem tint.
///
/// Por isso o meio do controle não faz nada: é o material do sistema, puro.
/// Para a esquerda vai para a variante transparente; para a direita adiciona uma
/// tonalização discreta, com teto baixo para não matar a borda de novo.
public enum GlassTint {

    /// Posição neutra: exatamente o vidro do sistema, sem nada por cima.
    public static let systemNeutral: Double = 0.5

    /// Abaixo disto o vidro usa a variante `.clear` — a ponta transparente.
    public static let clearThreshold: Double = 0.12

    /// Teto do tint. Baixo de propósito: acima de ~0,25 a borda some.
    public static let maxOverlay: Double = 0.20

    public static func usesClearGlass(_ amount: Double) -> Bool {
        clamp(amount) < clearThreshold
    }

    /// Opacidade do tint preto para um valor do controle.
    /// Zero em toda a metade esquerda: lá o vidro é o do sistema.
    public static func overlayOpacity(_ amount: Double) -> Double {
        let a = clamp(amount)
        guard a > systemNeutral else { return 0 }
        return (a - systemNeutral) / (1 - systemNeutral) * maxOverlay
    }

    /// O controle está na posição em que a bandeja é idêntica ao sistema?
    public static func isSystemNeutral(_ amount: Double) -> Bool {
        let a = clamp(amount)
        return a >= clearThreshold && a <= systemNeutral
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
