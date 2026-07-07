import SwiftUI
import AppKit

// Painel flutuante que vive na borda inferior da tela, ao lado do Dock.
// Aparece quando o cursor encosta na borda (ou empurra o canto, no modo Pressure Zone).
final class TrayController {
    static let shared = TrayController()

    private var panel: NSPanel!
    private var timer: Timer?
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var cancellable: Any?

    private let trayHeight: CGFloat = 170

    func start() {
        buildPanel()
        // repõe o painel quando a lista de apps ou ajustes mudam
        cancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.layoutPanel() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func buildPanel() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .mainMenu                       // acima de tudo, como o Dock
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true

        let host = NSHostingView(rootView: TrayView().environmentObject(store))
        panel.contentView = host
        layoutPanel()
        panel.orderFrontRegardless()
    }

    // tela onde a bandeja está atualmente (segue o mouse entre monitores)
    private var currentScreen: NSScreen? = NSScreen.main

    private func screenUnderMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
    }

    private func layoutPanel() {
        guard let screen = currentScreen else { return }
        let count = max(1, store.apps.count)
        let icon = store.iconSize
        // largura: ícones + espaçamentos + padding do vidro + margem p/ magnificação
        let width = CGFloat(count) * (icon + 14) + 150
        let x = screen.frame.maxX - width - store.offsetX
        panel.setFrame(NSRect(x: x, y: screen.frame.minY, width: width, height: trayHeight),
                       display: true)
    }

    // MARK: - Detecção do mouse (polling, sem permissões)

    private func tick() {
        guard store.onboarded, !store.apps.isEmpty else { return }
        let loc = NSEvent.mouseLocation

        // multi-monitor: a bandeja acompanha a tela onde o cursor está
        if !store.trayVisible, let s = screenUnderMouse(), s != currentScreen {
            currentScreen = s
            layoutPanel()
        }
        guard let screen = currentScreen else { return }
        let f = panel.frame
        let bottomY = screen.frame.minY

        if !store.trayVisible {
            let inZoneX = loc.x >= f.minX - 8 && loc.x <= f.maxX + 8
            let shouldReveal: Bool
            if store.pressureZone {
                // só quando o cursor é EMPURRADO contra o canto inferior direito
                shouldReveal = loc.y <= bottomY + 1
                    && loc.x >= screen.frame.maxX - f.width - store.offsetX - 8
            } else {
                shouldReveal = loc.y <= bottomY + 2 && inZoneX
            }
            if shouldReveal { reveal() }
        } else if !store.pinnedOpen {
            // esconde quando o cursor sai da região da bandeja (exceto se fixada por atalho)
            let inside = loc.x >= f.minX - 30 && loc.x <= f.maxX + 30
                && loc.y <= bottomY + trayHeight + 30
            if inside {
                hideDelay = 0
            } else {
                hideDelay += 0.05
                if hideDelay > 0.35 { hide() }
            }
        }
    }

    private func reveal() {
        hideDelay = 0
        store.playSound("Pop")
        withAnimation(.spring(duration: 0.42, bounce: 0.28)) {
            store.trayVisible = true
        }
    }

    private func hide() {
        store.pinnedOpen = false
        withAnimation(.spring(duration: 0.32)) {
            store.trayVisible = false
        }
    }

    // alternado pelo atalho global ⌘⇧D
    func toggleFromHotKey() {
        if store.trayVisible {
            hide()
        } else {
            currentScreen = screenUnderMouse()
            layoutPanel()
            store.pinnedOpen = true
            reveal()
        }
    }

    // modo demo: fixa a bandeja aberta e varre um hover simulado pelos ícones
    func startDemo() {
        store.demoMode = true
        store.pinnedOpen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            reveal()
            let start = Date()
            let sweepWidth = CGFloat(max(1, store.apps.count)) * (store.iconSize + 14) + 40
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                let t = Date().timeIntervalSince(start)
                let phase = 0.5 + 0.5 * sin(t * 2.0 * .pi / 3.0)   // ciclo de 3 s
                self.store.demoHoverX = 15 + (sweepWidth - 30) * phase
            }
        }
    }
}

// MARK: - A bandeja em si (vidro + ícones com magnificação estilo Dock)

struct TrayView: View {
    @EnvironmentObject var store: DockaStore
    @State private var hoverX: CGFloat? = nil     // posição do mouse p/ magnificação
    @State private var running: Set<String> = []  // caminhos dos apps abertos

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            tray
                .offset(y: store.trayVisible ? 0 : 200)
                .opacity(store.trayVisible ? 1 : 0)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: store.trayVisible) { _, visible in
            if visible { refreshRunning() }
        }
    }

    private func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleURL?.path })
    }

    // no modo demo o hover vem do varredor simulado
    private var effectiveHoverX: CGFloat? {
        store.demoMode ? store.demoHoverX : hoverX
    }

    private var tray: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(store.apps) { app in
                TrayIcon(app: app, hoverX: effectiveHoverX, baseSize: store.iconSize,
                         isRunning: running.contains(app.path)) {
                    store.playSound("Tink")
                    app.launch()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshRunning() }
                }
                // arrastar o ícone (reordenar) — o payload é a URL do próprio .app
                .draggable(URL(fileURLWithPath: app.path))
                // soltar em cima: outro ícone do Docka = reordenar; arquivos = abrir com o app
                .dropDestination(for: URL.self) { urls, _ in
                    guard let first = urls.first else { return false }
                    if store.apps.contains(where: { $0.path == first.path }) {
                        withAnimation(.spring(duration: 0.35)) {
                            store.move(first.path, before: app.path)
                        }
                    } else {
                        app.open(files: urls)
                        store.playSound("Tink")
                    }
                    return true
                }
            }

            // separador + engrenagem
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.2))
                .frame(width: 1, height: store.iconSize * 0.75)
                .padding(.horizontal, 3)
                .padding(.bottom, 10)

            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0 is NSPanel == false }?.makeKeyAndOrderFront(nil)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
        // visual do Dock real: vidro claro translúcido, padding justo, borda fina
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 5)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        )
        .coordinateSpace(name: "tray")
        .onContinuousHover(coordinateSpace: .named("tray")) { phase in
            switch phase {
            case .active(let p): hoverX = p.x
            case .ended: withAnimation(.spring(duration: 0.35)) { hoverX = nil }
            }
        }
    }
}

// Ícone com magnificação fiel ao Dock: cresce PARA CIMA a partir da linha de base,
// empurra os vizinhos (a largura do frame acompanha a escala), mostra o nome num
// balão quando ampliado, tem bolinha de "app aberto" e quica ao lançar.
struct TrayIcon: View {
    let app: PinnedApp
    let hoverX: CGFloat?
    let baseSize: Double
    let isRunning: Bool
    let action: () -> Void

    @State private var frameX: CGFloat = 0
    @State private var pressed = false
    @State private var bounce: CGFloat = 0     // deslocamento Y do quique

    private let maxBoost: CGFloat = 0.75       // até 1.75× como o Dock

    private var scale: CGFloat {
        guard let hx = hoverX, frameX > 0 else { return 1 }
        let d = abs(hx - frameX)
        let sigma: CGFloat = 64
        let boost = exp(-(d * d) / (2 * sigma * sigma))   // curva gaussiana 0…1
        return 1 + maxBoost * boost
    }

    private var magnified: Bool { scale > 1.55 }

    var body: some View {
        Button {
            pressed = true
            action()
            launchBounce()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pressed = false }
        } label: {
            VStack(spacing: 2) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: baseSize * scale, height: baseSize * scale)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                    .scaleEffect(pressed ? 0.85 : 1, anchor: .bottom)
                    .offset(y: bounce)

                // bolinha de app em execução (como no Dock)
                Circle()
                    .fill(.white.opacity(isRunning ? 0.7 : 0))
                    .frame(width: 4, height: 4)
                    .shadow(color: .white.opacity(isRunning ? 0.8 : 0), radius: 2)
            }
            // container de altura fixa alinhado embaixo: o ícone cresce PARA CIMA
            .frame(width: baseSize * scale + 6,
                   height: baseSize * (1 + maxBoost) + 10,
                   alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // clique-direito: ações do ícone
        .contextMenu {
            Button("Abrir") { action() }
            Button("Mostrar no Finder") { app.revealInFinder() }
            Divider()
            Button("Remover do Docka", role: .destructive) {
                withAnimation(.spring(duration: 0.35)) {
                    DockaStore.shared.toggle(app.path)
                }
            }
        }
        // balão com o nome sobre o ícone ampliado
        .overlay(alignment: .top) {
            if magnified {
                Text(app.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.black.opacity(0.35)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                    )
                    .fixedSize()
                    .offset(y: -30)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frameX = geo.frame(in: .named("tray")).midX }
                    .onChange(of: geo.frame(in: .named("tray")).midX) { _, x in frameX = x }
            }
        )
        .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.78), value: scale)
        .animation(.spring(duration: 0.25), value: magnified)
        .animation(.spring(duration: 0.2), value: pressed)
        .zIndex(magnified ? 1 : 0)
    }

    // quique duplo, como o Dock ao abrir um app
    private func launchBounce() {
        func hop(_ height: CGFloat, delay: Double, fall: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.22)) { bounce = -height }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.easeIn(duration: fall)) { bounce = 0 }
                }
            }
        }
        hop(26, delay: 0, fall: 0.2)
        hop(14, delay: 0.46, fall: 0.24)
    }
}
