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
/// O controle tem três trechos: translúcido (deixa o fundo atravessar), fosco
/// (o escuro clássico da barra) e fosco com tonalização crescente.
public enum GlassTint {

    /// Material do painel.
    ///
    /// **Por que não é `.glassEffect`:** medido em captura, o `.glassEffect` só
    /// refrata conteúdo que esteja DENTRO da própria janela. A bandeja é um
    /// painel transparente sobre a área de trabalho — não há o que refratar, e o
    /// efeito degrada para um preenchimento chapado. Quem amostra atrás da
    /// janela é o `NSVisualEffectView` com `blendingMode = .behindWindow`, que é
    /// o que o Dock e a barra de menus usam.
    public enum Material: Sendable, Equatable {
        /// Deixa o fundo atravessar bastante.
        case translucido
        /// O escuro translúcido clássico da barra do sistema.
        case fosco
    }

    /// Posição padrão: o escuro translúcido, como a barra do Dock.
    public static let systemNeutral: Double = 0.5

    /// Até aqui o material é o mais translúcido.
    public static let clearThreshold: Double = 0.34

    public static func material(for amount: Double) -> Material {
        usesClearGlass(amount) ? .translucido : .fosco
    }

    /// Teto do tint. Baixo de propósito: acima de ~0,25 a borda some.
    public static let maxOverlay: Double = 0.20

    public static func usesClearGlass(_ amount: Double) -> Bool {
        clamp(amount) < clearThreshold
    }

    /// Opacidade do tint preto para um valor do controle.
    /// Zero em toda a metade esquerda: lá o vidro é o do sistema.
    /// A tonalização só entra no terço final; antes disso é a variante pura.
    public static let tintStart: Double = 0.66

    public static func overlayOpacity(_ amount: Double) -> Double {
        let a = clamp(amount)
        guard a > tintStart else { return 0 }
        return (a - tintStart) / (1 - tintStart) * maxOverlay
    }

    /// O controle está no padrão?
    public static func isSystemNeutral(_ amount: Double) -> Bool {
        let a = clamp(amount)
        return a >= clearThreshold && a <= tintStart
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
