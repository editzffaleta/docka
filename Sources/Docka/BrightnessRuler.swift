import SwiftUI
import DockaCore

/// A régua de brilho: barra escura com traços, faixa acesa no nível atual.
struct BrightnessRuler: View {
    @Binding var level: Double
    /// Comprimento da régua no eixo em que ela cresce.
    var comprimento: CGFloat = Brightness.rulerLength
    var espessura: CGFloat = Brightness.rulerThickness
    /// Tonalização do vidro, a mesma da bandeja.
    var tint: Double = 0.5

    @State private var arrastando = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<Brightness.tickCount, id: \.self) { i in
                    traco(i)
                        .position(x: geo.size.width / 2,
                                  y: geo.size.height * (1 - Brightness.tickLevel(i)))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        arrastando = true
                        // a régua cresce de baixo para cima. Aqui a posição do
                        // cursor é absoluta na régua (que não se move), então
                        // não há realimentação — só a suavização, para o valor
                        // não pular a cada micro-movimento.
                        let alvo = Brightness.clamp(Double(1 - g.location.y / geo.size.height))
                        aplicar(level + (alvo - level) * Brightness.dragSmoothing)
                    }
                    .onEnded { _ in arrastando = false }
            )
        }
        .frame(width: espessura, height: comprimento)
        .padding(.vertical, 10)
        // mesma vibrância do painel da bandeja: é o que parece vidro sobre o
        // desktop. O preto sólido de antes não reagia ao fundo.
        .dockGlass(cornerRadius: espessura * 0.46, tint: tint)
        .accessibilityElement()
        .accessibilityLabel("Brilho da tela")
        .accessibilityValue("\(Int(level * 100)) por cento")
        .accessibilityAdjustableAction { direcao in
            aplicar(level + (direcao == .increment ? Brightness.stepSize : -Brightness.stepSize))
        }
    }

    private func traco(_ i: Int) -> some View {
        let destaque = Brightness.tickHighlight(i, level: level)
        let graude = Brightness.isMajorTick(i)
        return Capsule()
            .fill(destaque > 0
                  ? Color.accentColor.opacity(0.35 + 0.65 * destaque)
                  : Color.white.opacity(graude ? 0.32 : 0.16))
            .frame(width: espessura * (graude ? 0.62 : 0.40) + destaque * espessura * 0.16,
                   height: graude ? 2.5 : 1.5)
    }

    /// Escreve o valor no sistema e relê: a régua mostra o brilho REAL, não uma
    /// estimativa. Ler é justamente o que a tecla de mídia não permitia.
    private func aplicar(_ novo: Double) {
        guard abs(novo - level) > 0.0001 else { return }
        BrightnessBackend.escrever(novo)
        level = BrightnessBackend.ler() ?? novo
    }
}
