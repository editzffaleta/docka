import SwiftUI
import DockaCore

/// A régua de brilho: barra escura com traços, faixa acesa no nível atual.
struct BrightnessRuler: View {
    @Binding var level: Double
    /// Comprimento da régua no eixo em que ela cresce.
    var comprimento: CGFloat = 240
    var espessura: CGFloat = 52

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
                        // a régua cresce de baixo para cima
                        let fracao = 1 - g.location.y / geo.size.height
                        aplicar(Brightness.levelFromDrag(fraction: Double(fracao)))
                    }
                    .onEnded { _ in arrastando = false }
            )
        }
        .frame(width: espessura, height: comprimento)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: espessura * 0.42, style: .continuous)
                .fill(Color(nsColor: .black).opacity(0.82))
        )
        .accessibilityElement()
        .accessibilityLabel("Brilho da tela")
        .accessibilityValue("\(Int(level * 100)) por cento")
        .accessibilityAdjustableAction { direcao in
            aplicar(Brightness.applying(direcao == .increment ? 1 : -1, to: level))
        }
    }

    private func traco(_ i: Int) -> some View {
        let destaque = Brightness.tickHighlight(i, level: level)
        let graude = Brightness.isMajorTick(i)
        return Capsule()
            .fill(destaque > 0
                  ? Color.accentColor.opacity(0.35 + 0.65 * destaque)
                  : Color.white.opacity(graude ? 0.32 : 0.16))
            .frame(width: espessura * (graude ? 0.52 : 0.34) + destaque * espessura * 0.12,
                   height: graude ? 2.5 : 1.5)
    }

    /// Fala com o sistema em PASSOS e só então move o modelo — assim o que a
    /// régua mostra é exatamente o que foi mandado para a tela.
    private func aplicar(_ novo: Double) {
        let passos = Brightness.stepsBetween(from: level, to: novo)
        guard passos != 0 else { return }
        BrightnessKeys.nudge(passos)
        level = Brightness.applying(passos, to: level)
    }
}
