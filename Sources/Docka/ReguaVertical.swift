import SwiftUI
import DockaCore

/// A régua: barra de vidro com traços e uma faixa acesa no nível atual.
///
/// Serve brilho e volume — quem manda no comportamento é o `Deslizador`
/// recebido. Antes isto era `BrightnessRuler`, com o backend de brilho fixo por
/// dentro; ao chegar o volume, generalizar custou menos do que ter duas réguas
/// idênticas se desencontrando com o tempo.
struct ReguaVertical: View {
    let deslizador: Deslizador
    @Binding var level: Double
    /// Comprimento da régua no eixo em que ela cresce.
    var comprimento: CGFloat = Deslizante.rulerLength
    var espessura: CGFloat = Deslizante.rulerThickness
    /// Tonalização do vidro, a mesma da bandeja.
    var tint: Double = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<Deslizante.tickCount, id: \.self) { i in
                    traco(i)
                        .position(x: geo.size.width / 2,
                                  y: geo.size.height * (1 - Deslizante.tickLevel(i)))
                }
                // a faixa acesa desliza junto com o valor em vez de saltar de
                // traço em traço
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: level)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // a régua cresce de baixo para cima. Aqui a posição do
                        // cursor é absoluta na régua (que não se move), então
                        // não há realimentação — só a suavização, para o valor
                        // não pular a cada micro-movimento.
                        let alvo = Deslizante.clamp(Double(1 - g.location.y / geo.size.height))
                        aplicar(level + (alvo - level) * Deslizante.dragSmoothing)
                    }
            )
        }
        .frame(width: espessura, height: comprimento)
        .padding(.vertical, 10)
        // mesma vibrância do painel da bandeja: é o que parece vidro sobre o
        // desktop. O preto sólido de antes não reagia ao fundo.
        .dockGlass(cornerRadius: espessura * 0.46, tint: tint)
        .accessibilityElement()
        .accessibilityLabel(deslizador.rotulo)
        .accessibilityValue("\(Int(level * 100)) por cento")
        .accessibilityAdjustableAction { direcao in
            aplicar(level + (direcao == .increment ? Deslizante.stepSize : -Deslizante.stepSize))
        }
    }

    private func traco(_ i: Int) -> some View {
        let destaque = Deslizante.tickHighlight(i, level: level)
        let graude = Deslizante.isMajorTick(i)
        return Capsule()
            // semântica, não branco fixo: em Tom claro o branco sumiria no vidro
            .fill(destaque > 0
                  ? Color.accentColor.opacity(0.35 + 0.65 * destaque)
                  : Color(nsColor: .labelColor).opacity(graude ? 0.55 : 0.30))
            .frame(width: espessura * (graude ? 0.62 : 0.40) + destaque * espessura * 0.16,
                   height: graude ? 2.5 : 1.5)
    }

    private func aplicar(_ novo: Double) {
        level = NivelDoSistema.aplicar(novo, atual: level, com: deslizador)
    }
}
