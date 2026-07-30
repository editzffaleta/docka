import Foundation
import CoreGraphics

/// O controle de brilho.
///
/// A matemática — geometria da régua, curva do arrasto, degraus, tique — é a
/// mesma do volume e mora em `Deslizante`. Aqui ficam só os nomes de brilho e
/// o que é dele: a lateral padrão e o texto do botão.
///
/// **Sobre ler o brilho:** não há API pública para isso em Apple Silicon, e por
/// um tempo este arquivo modelou o nível por conta própria, contando os passos
/// que mandava pela tecla de mídia. Hoje `BrightnessBackend` lê e escreve pelo
/// DisplayServices, então o nível guardado é sempre o real; os passos continuam
/// aqui porque a grade de 1/16 do sistema ainda governa o tique e a régua.
public enum Brightness {

    public static let steps = Deslizante.steps
    public static var stepSize: Double { Deslizante.stepSize }

    public static func clamp(_ v: Double) -> Double { Deslizante.clamp(v) }
    public static func quantize(_ level: Double) -> Double { Deslizante.quantize(level) }

    public static func stepsBetween(from: Double, to: Double) -> Int {
        Deslizante.stepsBetween(from: from, to: to)
    }

    public static func applying(_ n: Int, to level: Double) -> Double {
        Deslizante.applying(n, to: level)
    }

    /// O controle só existe nas laterais: a régua é vertical por natureza, e
    /// deitada na borda inferior ela viraria outra coisa.
    public static let bordasPermitidas = Deslizante.bordasPermitidas

    public static func edge(persisted: String) -> TrayEdge {
        Deslizante.edge(persisted: persisted, padrao: .right)
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

    public static func levelFromKnob(offset: CGFloat, rulerLength: CGFloat) -> Double {
        Deslizante.levelFromKnob(offset: offset, rulerLength: rulerLength)
    }

    // MARK: gesto

    public static let dragSpan = Deslizante.dragSpan
    public static let dragThreshold = Deslizante.dragThreshold
    public static let dragSmoothing = Deslizante.dragSmoothing

    public static func scrub(from inicio: Double, translation: CGFloat) -> Double {
        Deslizante.scrub(from: inicio, translation: translation)
    }

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

    public static func levelFromDrag(fraction: Double) -> Double {
        Deslizante.levelFromDrag(fraction: fraction)
    }
}
