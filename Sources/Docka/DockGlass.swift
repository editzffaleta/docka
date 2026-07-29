import SwiftUI
import DockaCore

/// O vidro do painel.
///
/// No macOS 26+ o Dock usa **Liquid Glass**, e o sistema expõe esse material
/// pelo `.glassEffect`. Usar o material de verdade é o que faz a bandeja parecer
/// nativa: a imitação anterior (`.regularMaterial` + camada branca + borda
/// branca + sombra) sempre ia errar o brilho da borda e a refração, porque
/// nenhum dos dois reage ao conteúdo que passa por baixo.
///
/// Abaixo do 26 cai no material antigo, que é o melhor disponível lá.
struct DockGlass: ViewModifier {
    let cornerRadius: CGFloat
    /// 0 = transparente, 1 = tonalizado — o mesmo eixo do slider do sistema.
    var tint: Double = 0.5

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Duas alavancas para um só slider: a ponta transparente usa a
            // variante .clear; do limiar para cima é .regular (o vidro de chrome
            // do sistema) com tint preto crescente.
            if GlassTint.usesClearGlass(tint) {
                content.glassEffect(.clear,
                                    in: .rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content.glassEffect(
                    .regular.tint(.black.opacity(GlassTint.overlayOpacity(tint))),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content.background(legado)
        }
    }

    private var legado: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
    }
}

extension View {
    func dockGlass(cornerRadius: CGFloat, tint: Double) -> some View {
        modifier(DockGlass(cornerRadius: cornerRadius, tint: tint))
    }
}

/// O balão com o nome do app.
///
/// Cápsula escura sólida, de propósito: ela fica POR CIMA do vidro da bandeja, e
/// vidro não consegue amostrar vidro — empilhar `glassEffect` aqui é vidro sobre
/// vidro, que o próprio sistema não resolve. Também é o que o Dock faz: o rótulo
/// dele é uma cápsula escura, não um painel de vidro.
struct DockLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            // cores semânticas: o rótulo precisa virar escuro-sobre-claro
            // quando a bandeja está em Tom claro
            .foregroundStyle(Color(nsColor: .labelColor))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.92)))
            .fixedSize()
    }
}
