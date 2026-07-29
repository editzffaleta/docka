import SwiftUI
import DockaCore

/// Vibrância do sistema, com amostragem **atrás da janela**.
///
/// É o que o Dock e a barra de menus usam. Ao contrário do `.glassEffect`, ela
/// enxerga o desktop através da janela — verificado lado a lado: com um gradiente
/// atrás da janela, só esta pega a cor; o `glassEffect` fica chapado.
struct Vibrancia: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow      // a diferença que faz o fundo aparecer
        v.state = .active                   // ativa mesmo com o painel sem foco
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

extension GlassTint.Material {
    var appKit: NSVisualEffectView.Material {
        switch self {
        case .translucido: return .popover      // deixa o fundo atravessar
        case .fosco:       return .hudWindow    // escuro translúcido da barra
        }
    }
}

/// O fundo do painel da bandeja.
///
/// Este arquivo já usou `.glassEffect` do Liquid Glass. **Não funciona aqui:**
/// esse efeito só refrata conteúdo que esteja DENTRO da própria janela, e a
/// bandeja é um painel transparente sobre a área de trabalho. Sem nada para
/// refratar, ele degradava para um retângulo chapado.
struct DockGlass: ViewModifier {
    let cornerRadius: CGFloat
    /// 0 = translúcido, 1 = fosco e tonalizado.
    var tint: Double = 0.5

    func body(content: Content) -> some View {
        content.background(fundo)
    }

    private var forma: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var fundo: some View {
        ZStack {
            Vibrancia(material: GlassTint.material(for: tint).appKit)
            let escurecer = GlassTint.overlayOpacity(tint)
            if escurecer > 0 { Color.black.opacity(escurecer) }
        }
        .clipShape(forma)
        // A vibrância não desenha o brilho de contorno que o Dock tem. Aqui o
        // traço à mão se justifica: sem glassEffect, o sistema não o fornece.
        .overlay(
            forma.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }
}

extension View {
    func dockGlass(cornerRadius: CGFloat, tint: Double) -> some View {
        modifier(DockGlass(cornerRadius: cornerRadius, tint: tint))
    }
}

/// O balão com o nome do app — cápsula sólida, como a do Dock.
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
