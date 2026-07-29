import Foundation
import CoreGraphics

/// O controle de volume — o irmão do brilho.
///
/// Mesma régua, mesmo botão, mesma curva de arrasto: tudo isso vem de
/// `Deslizante`. O que muda é o que ele mexe (a saída de áudio, pelo CoreAudio)
/// e a lateral padrão, que é a oposta à do brilho para os dois não nascerem um
/// em cima do outro.
///
/// **Diferença que importa em relação ao brilho:** aqui a API é PÚBLICA. O
/// brilho depende do DisplayServices, não documentado, e por isso o controle
/// some se o símbolo sumir. O volume usa CoreAudio, que é documentado e
/// estável — não há esse risco.
public enum Volume {

    public static let steps = Deslizante.steps
    public static var stepSize: Double { Deslizante.stepSize }

    public static func clamp(_ v: Double) -> Double { Deslizante.clamp(v) }
    public static func quantize(_ level: Double) -> Double { Deslizante.quantize(level) }

    /// Também só nas laterais, pelo mesmo motivo do brilho.
    public static let bordasPermitidas = Deslizante.bordasPermitidas

    /// Padrão à esquerda: o brilho nasce à direita, e assim os dois cabem sem
    /// se cobrir quando o usuário liga o segundo sem mexer em posição.
    public static func edge(persisted: String) -> TrayEdge {
        Deslizante.edge(persisted: persisted, padrao: .left)
    }

    // MARK: geometria

    public static let rulerLength = Deslizante.rulerLength
    public static let rulerThickness = Deslizante.rulerThickness
    public static let knobSize = Deslizante.knobSize

    public static var panelExtent: CGFloat { Deslizante.panelExtent }
    public static var panelThickness: CGFloat { Deslizante.panelThickness }

    public static func knobOffset(level: Double, rulerLength: CGFloat) -> CGFloat {
        Deslizante.knobOffset(level: level, rulerLength: rulerLength)
    }

    // MARK: gesto

    public static let dragSpan = Deslizante.dragSpan
    public static let dragSmoothing = Deslizante.dragSmoothing

    public static func isTap(translation: CGFloat) -> Bool {
        Deslizante.isTap(translation: translation)
    }

    public static func dragStep(inicio: Double, translation: CGFloat,
                                atual: Double, span: CGFloat) -> Double {
        Deslizante.dragStep(inicio: inicio, translation: translation,
                            atual: atual, span: span)
    }

    public static func knobLabel(level: Double) -> String {
        Deslizante.knobLabel(level: level)
    }

    public static func crossedStep(from: Double, to: Double) -> Bool {
        Deslizante.crossedStep(from: from, to: to)
    }

    // MARK: régua

    public static let tickCount = Deslizante.tickCount

    public static func tickLevel(_ i: Int) -> Double { Deslizante.tickLevel(i) }

    public static func tickHighlight(_ i: Int, level: Double) -> Double {
        Deslizante.tickHighlight(i, level: level)
    }

    public static func isMajorTick(_ i: Int) -> Bool { Deslizante.isMajorTick(i) }

    // MARK: o ícone

    /// Símbolo SF que representa o nível, como o macOS faz no menu de som:
    /// as ondas vão aparecendo conforme o volume sobe, e no zero vira mudo.
    ///
    /// É o equivalente do sol do brilho — só que aqui o ícone também informa,
    /// porque volume zero e volume baixo são estados que o usuário confunde.
    public static func simbolo(level: Double) -> String {
        switch clamp(level) {
        case 0:              return "speaker.slash.fill"
        case ..<0.34:        return "speaker.wave.1.fill"
        case ..<0.67:        return "speaker.wave.2.fill"
        default:             return "speaker.wave.3.fill"
        }
    }

    /// Está mudo? Serve para o texto de acessibilidade e para o ícone.
    public static func mudo(level: Double) -> Bool { clamp(level) == 0 }
}
