import SwiftUI

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

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // .regular é o vidro de chrome do sistema. O .clear existe para vidro
            // sobre mídia (fotos, vídeo) e some demais sobre conteúdo claro.
            content.glassEffect(.regular,
                                in: .rect(cornerRadius: cornerRadius, style: .continuous))
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
    func dockGlass(cornerRadius: CGFloat) -> some View {
        modifier(DockGlass(cornerRadius: cornerRadius))
    }
}

/// O balão com o nome do app.
///
/// No Dock ele é uma cápsula escura simples, sem borda clara — a borda branca
/// que estava aqui é o tipo de detalhe que denuncia um app de terceiros.
struct DockLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(capsule)
            .fixedSize()
    }

    @ViewBuilder
    private var capsule: some View {
        if #available(macOS 26.0, *) {
            Capsule().fill(.black.opacity(0.55)).glassEffect(.regular, in: .capsule)
        } else {
            Capsule().fill(.black.opacity(0.75))
        }
    }
}
