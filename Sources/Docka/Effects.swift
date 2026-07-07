import SwiftUI

// Efeitos compartilhados (mesmo padrão do design system Cleaner)

struct GlassCard: ViewModifier {
    var hoverLift = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.card.opacity(0.85))
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.05), .clear],
                                             startPoint: .topLeading, endPoint: .center))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(hovering ? 0.35 : 0.16),
                                                .white.opacity(0.03),
                                                Theme.accent.opacity(hovering ? 0.35 : 0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: hovering ? 22 : 12, y: hovering ? 12 : 6)
            .offset(y: hovering && hoverLift ? -3 : 0)
            .animation(.spring(duration: 0.35), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func glassCard(hoverLift: Bool = true) -> some View {
        modifier(GlassCard(hoverLift: hoverLift))
    }
}

private func rnd(_ n: Double) -> Double {
    let s = sin(n) * 43758.5453
    return s - s.rounded(.down)
}

struct ParticleField: View {
    var tint: Color
    var count = 34

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let fi = Double(i)
                    let speed = 6 + rnd(fi * 7.7) * 14
                    let x = rnd(fi * 1.3) * size.width + sin(t * 0.25 + fi * 2) * 24
                    var y = (rnd(fi * 2.7) * size.height - t * speed)
                        .truncatingRemainder(dividingBy: size.height)
                    if y < 0 { y += size.height }
                    let alpha = 0.05 + 0.15 * (0.5 + 0.5 * sin(t * 1.6 + fi * 3.1))
                    let r = 0.8 + rnd(fi * 4.2) * 1.8
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color((i % 3 == 0 ? tint : Color.white).opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct AuroraBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)

            Circle().fill(Theme.accent.opacity(0.13))
                .frame(width: 520, height: 520).blur(radius: 130)
                .offset(x: drift ? -180 : -320, y: drift ? -220 : -120)

            Circle().fill(Color(red: 0.55, green: 0.40, blue: 0.95).opacity(0.10))
                .frame(width: 460, height: 460).blur(radius: 140)
                .offset(x: drift ? 320 : 200, y: drift ? 180 : 320)

            ParticleField(tint: Theme.accent)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

struct AppearReveal: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                withAnimation(.spring(duration: 0.7).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func reveal(delay: Double) -> some View { modifier(AppearReveal(delay: delay)) }
}

struct PulseGlow: ViewModifier {
    let color: Color
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(pulse ? 0.65 : 0.25), radius: pulse ? 42 : 22)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    func pulseGlow(_ color: Color) -> some View { modifier(PulseGlow(color: color)) }
}

// Botão primário padrão
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.8))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(
                LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
            .shadow(color: Theme.accent.opacity(hovering ? 0.7 : 0.35),
                    radius: hovering ? 20 : 10, y: 4)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: hovering)
        .onHover { hovering = $0 }
    }
}

// Logo do app (carregada dos recursos do pacote)
struct AppLogo: View {
    var size: CGFloat

    var body: some View {
        if let url = Bundle.module.url(forResource: "logo-256", withExtension: "png",
                                       subdirectory: "Assets"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: Theme.accent.opacity(0.45), radius: size * 0.16, y: 3)
        } else {
            Image(systemName: "tray.full.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(Theme.accent)
        }
    }
}
