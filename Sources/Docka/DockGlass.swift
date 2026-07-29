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

/// Vidro em círculo — para o botão do controle de brilho.
///
/// Mesma vibrância do painel da bandeja: `.glassEffect` não serve aqui, porque
/// só refrata conteúdo de dentro da própria janela.
struct GlassCircle: View {
    var tint: Double = 0.5

    var body: some View {
        ZStack {
            Vibrancia(material: GlassTint.material(for: tint).appKit)
            let escurecer = GlassTint.overlayOpacity(tint)
            if escurecer > 0 { Color.black.opacity(escurecer) }
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(
            LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 0.8))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
    }
}

/// O balão de nome do Dock: retângulo arredondado com RABINHO apontando para o
/// ícone. Comparado lado a lado com uma foto do balão real ("Lixo"): cantos
/// menos redondos que uma cápsula, texto 13 semibold e a setinha embaixo.
struct DockLabel: View {
    let text: String
    var edge: TrayEdge = .bottom

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            // cores semânticas: o rótulo precisa virar escuro-sobre-claro
            // quando a bandeja está em Tom claro
            .foregroundStyle(Color(nsColor: .labelColor))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            // o rabinho aponta para o ícone, que está do lado da borda
            .padding(ladoDoRabinho, BalaoComRabinho.rabinhoAltura)
            .background(BalaoComRabinho(edge: edge)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94)))
            .fixedSize()
    }

    private var ladoDoRabinho: Edge.Set {
        switch edge {
        case .bottom: return .bottom
        case .left:   return .leading
        case .right:  return .trailing
        }
    }
}

/// Retângulo arredondado + triângulo central embaixo, num caminho só
/// (mesma cor, sem emenda visível).
struct BalaoComRabinho: Shape {
    static let rabinhoAltura: CGFloat = 7
    static let rabinhoLargura: CGFloat = 16
    var edge: TrayEdge = .bottom

    func path(in rect: CGRect) -> Path {
        let h = Self.rabinhoAltura, w = Self.rabinhoLargura
        let corpo: CGRect
        switch edge {
        case .bottom: corpo = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - h)
        case .left:   corpo = CGRect(x: h, y: 0, width: rect.width - h, height: rect.height)
        case .right:  corpo = CGRect(x: 0, y: 0, width: rect.width - h, height: rect.height)
        }
        var p = Path(roundedRect: corpo, cornerRadius: 9, style: .continuous)
        switch edge {
        case .bottom:
            p.move(to: CGPoint(x: rect.midX - w / 2, y: corpo.maxY - 0.5))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX + w / 2, y: corpo.maxY - 0.5))
        case .left:
            p.move(to: CGPoint(x: corpo.minX + 0.5, y: rect.midY - w / 2))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: corpo.minX + 0.5, y: rect.midY + w / 2))
        case .right:
            p.move(to: CGPoint(x: corpo.maxX - 0.5, y: rect.midY - w / 2))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: corpo.maxX - 0.5, y: rect.midY + w / 2))
        }
        p.closeSubpath()
        return p
    }
}
