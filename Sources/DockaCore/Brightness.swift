import Foundation
import CoreGraphics

/// Modelo do controle de brilho.
///
/// **Por que o nível é modelado aqui e não lido do sistema:** em Apple Silicon
/// não existe API pública para LER o brilho — o `IODisplayConnect` não existe e
/// o `AppleARMBacklight` só expõe calibração. Os valores atuais só saem de
/// frameworks privados, que quebrariam a regra de API pública e somem em
/// atualizações. Já para AJUSTAR há caminho público: a tecla de mídia de brilho,
/// que o macOS aplica em passos fixos. Então guardamos o nível nós mesmos e
/// falamos com o sistema em passos.
public enum Brightness {

    /// O macOS move o brilho em 1/16 por toque de tecla.
    public static let steps = 16
    public static var stepSize: Double { 1.0 / Double(steps) }

    /// Quantos passos (com sinal) levam de um nível a outro.
    /// Positivo = aumentar; o chamador manda essa quantidade de teclas.
    public static func stepsBetween(from: Double, to: Double) -> Int {
        Int((clamp(to) - clamp(from)) / stepSize * 1.0000001)
    }

    /// Nível resultante depois de `n` passos — o modelo acompanha o que mandamos.
    public static func applying(_ n: Int, to level: Double) -> Double {
        quantize(level + Double(n) * stepSize)
    }

    /// Encaixa no passo mais próximo: o sistema só assume múltiplos de 1/16,
    /// então guardar um valor fora da grade faria o modelo divergir na hora.
    public static func quantize(_ level: Double) -> Double {
        let n = (clamp(level) / stepSize).rounded()
        return clamp(n * stepSize)
    }

    public static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    /// O controle só existe nas laterais: a régua é vertical por natureza, e
    /// deitada na borda inferior ela viraria outra coisa.
    public static let bordasPermitidas: [TrayEdge] = [.left, .right]

    public static func edge(persisted: String) -> TrayEdge {
        let e = TrayEdge(persisted: persisted)
        return bordasPermitidas.contains(e) ? e : .right
    }

    /// Tamanho do painel do controle: régua + botão de sol ao lado.
    public static let panelExtent: CGFloat = 300     // ao longo da borda
    public static let panelThickness: CGFloat = 130  // perpendicular

    /// Quantos pontos de arrasto cobrem a faixa inteira de brilho.
    /// Calibrado pelo comprimento da régua: esfregar no sol anda o mesmo tanto
    /// que arrastar a régua de ponta a ponta.
    public static let dragSpan: CGFloat = 250

    /// Distância a partir da qual um toque vira arrasto, e não clique.
    public static let dragThreshold: CGFloat = 3

    /// Nível ao esfregar: para CIMA aumenta (translation.height é negativo).
    public static func scrub(from inicio: Double, translation: CGFloat) -> Double {
        clamp(inicio - Double(translation / dragSpan))
    }

    // MARK: régua

    /// Quantidade de traços da régua. Múltiplo dos passos para cada toque de
    /// tecla cair exatamente sobre um traço.
    public static let tickCount = 33

    /// Nível (0…1) representado pelo traço `i`, de baixo para cima.
    public static func tickLevel(_ i: Int) -> Double {
        Double(i) / Double(tickCount - 1)
    }

    /// Traços destacados perto do nível — é o que forma a faixa acesa da régua.
    /// Devolve 0…1: 1 no traço do nível, caindo até sumir.
    public static func tickHighlight(_ i: Int, level: Double) -> Double {
        let d = abs(tickLevel(i) - clamp(level))
        let alcance = 2.5 * (1.0 / Double(tickCount - 1))
        return max(0, 1 - d / alcance)
    }

    /// Traço longo a cada 4 — a marcação graúda da régua do print.
    public static func isMajorTick(_ i: Int) -> Bool { i % 4 == 0 }

    /// Nível a partir da posição do arrasto na régua (0 na base, 1 no topo).
    public static func levelFromDrag(fraction: Double) -> Double {
        quantize(clamp(fraction))
    }
}
