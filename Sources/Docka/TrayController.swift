import SwiftUI
import AppKit
import DockaCore

// Painel flutuante que vive na borda inferior da tela, ao lado do Dock.
// Aparece quando o cursor encosta na borda (ou empurra o canto, no modo Pressure Zone).
final class TrayController {
    static let shared = TrayController()

    private var panel: NSPanel!
    private var timer: Timer?
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var cancellable: Any?
    private var screenObserver: NSObjectProtocol?

    private let trayHeight: CGFloat = 170

    func start() {
        buildPanel()
        // repõe o painel quando a lista de apps ou ajustes mudam
        cancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.layoutPanel() }
        }
        // "Seguir mudanças do Dock": o macOS publica esta notificação quando o Dock
        // muda de tamanho ou de lado, e também ao ligar/desligar um monitor.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.layoutPanel()
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
        // nasce fora da tela: quem traz o painel para frente é o reveal()
    }

    // tela onde a bandeja está atualmente (segue o mouse entre monitores)
    private var currentScreen: NSScreen? = NSScreen.main

    private func screenUnderMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
    }

    /// Aparência da bandeja: nil = automático, e aí o painel segue o sistema.
    private func applyAppearance() {
        switch TrayAppearance(persisted: store.appearance) {
        case .automatico: panel.appearance = nil
        case .claro:      panel.appearance = NSAppearance(named: .aqua)
        case .escuro:     panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func layoutPanel() {
        guard let screen = currentScreen else { return }
        applyAppearance()
        panel.setFrame(TrayGeometry.frame(screenFrame: screen.frame,
                                          visibleFrame: screen.visibleFrame,
                                          appCount: store.apps.count,
                                          size: store.iconSize,
                                          maxScale: store.maxScale,
                                          maxRange: store.maxRange,
                                          position: .init(persisted: store.position),
                                          offsetX: store.offsetX,
                                          followDock: store.followDock,
                                          height: trayHeight),
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
            if TrayGeometry.shouldReveal(cursor: loc, trayFrame: f,
                                         screenBottomY: bottomY,
                                         pressureZone: store.pressureZone) {
                reveal()
            }
        } else if !store.pinnedOpen {
            // esconde quando o cursor sai da região da bandeja (exceto se fixada por atalho)
            if TrayGeometry.isInsideTray(cursor: loc, trayFrame: f) {
                hideDelay = 0
            } else {
                hideDelay += 0.05
                if hideDelay > 0.35 { hide() }
            }
        }
    }

    // Reduzir Movimento do sistema. Aqui vem do NSWorkspace porque estamos fora
    // de uma View — nas telas, o SwiftUI entrega isso pelo Environment.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Tira o painel da tela depois que a animação de saída termina.
    private var retirada: DispatchWorkItem?

    private func reveal() {
        hideDelay = 0
        retirada?.cancel()
        retirada = nil
        // O painel só fica na tela enquanto a bandeja está aberta. Antes ele vivia
        // ali com opacidade 0, e o Liquid Glass seguia amostrando o fundo o tempo
        // todo — vidro custa GPU mesmo invisível.
        panel.orderFrontRegardless()
        store.playSound("Pop")
        // com Reduzir Movimento a bandeja aparece por opacidade, sem subir nem quicar
        withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                   : .spring(duration: 0.42, bounce: 0.28)) {
            store.trayVisible = true
        }
    }

    private func hide() {
        store.pinnedOpen = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.32)) {
            store.trayVisible = false
        }
        let item = DispatchWorkItem { [weak self] in
            // um reveal no meio da saída cancela isto, mas confere de novo
            guard let self, !self.store.trayVisible else { return }
            self.panel.orderOut(nil)
        }
        retirada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
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
            // varre exatamente a faixa de ícones, no mesmo espaço de coordenadas
            // que o hover real usa
            let sweepWidth = TrayGeometry.restingContentWidth(appCount: store.apps.count,
                                                              size: store.iconSize)
                + 2 * TrayGeometry.padding(size: store.iconSize)
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
    @State private var tamanhoAoIniciarArrasto: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Arrastar o separador redimensiona os ícones, como no Dock. O tamanho de
    /// referência é o do INÍCIO do arrasto — acumular sobre o valor corrente
    /// faria o tamanho acelerar sozinho.
    private var redimensionarPeloSeparador: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if tamanhoAoIniciarArrasto == nil { tamanhoAoIniciarArrasto = store.iconSize }
                store.iconSize = TrayGeometry.iconSizeDragged(
                    from: tamanhoAoIniciarArrasto ?? store.iconSize,
                    verticalTranslation: g.translation.height)
            }
            .onEnded { _ in tamanhoAoIniciarArrasto = nil }
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            tray
                // sem o deslize de baixo quando o sistema pede menos movimento:
                // a bandeja só surge e some
                .offset(y: store.trayVisible || reduceMotion ? 0 : 200)
                .opacity(store.trayVisible ? 1 : 0)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { refreshRunning() }
        .onChange(of: store.trayVisible) { _, visible in
            if visible { refreshRunning() }
        }
        // o macOS avisa quando qualquer app abre ou fecha: sem isso a bolinha
        // continuava acesa depois de encerrar o app com a bandeja aberta
        .onReceive(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
                refreshRunning()
            }
        .onReceive(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
                refreshRunning()
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
        HStack(alignment: .bottom, spacing: TrayGeometry.gap(size: store.iconSize)) {
            ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                TrayIcon(app: app,
                         // o centro vem da posição EM REPOUSO, calculada pelo índice:
                         // medir o centro já ampliado realimentaria a conta
                         center: Magnification.restingCenter(index: index,
                                                             size: store.iconSize,
                                                             gap: TrayGeometry.gap(size: store.iconSize),
                                                             padding: TrayGeometry.padding(size: store.iconSize)),
                         hoverX: effectiveHoverX,
                         size: store.iconSize,
                         maxScale: store.maxScale,
                         maxRange: store.maxRange,
                         isRunning: running.contains(app.path) && store.showIndicators,
                         bounceEnabled: store.bounceOnLaunch) {
                    store.playSound("Tink")
                    app.launch()
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
            // O traço do Dock: discreto, quase da altura do ícone — e uma ALÇA.
            // Arrastar para cima/baixo redimensiona os ícones ao vivo, e o
            // clique-direito abre o menu de posição, como no separador do Dock.
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: store.iconSize * 0.9)
                .padding(.horizontal, TrayGeometry.gap(size: store.iconSize) + 3)
                .padding(.bottom, TrayGeometry.indicatorRow(size: store.iconSize))
                .contentShape(Rectangle())          // pegada maior que o traço de 1 pt
                .onHover { dentro in
                    if dentro { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(redimensionarPeloSeparador)
                .contextMenu {
                    Picker("Posição na Tela", selection: $store.position) {
                        Text("Esquerda").tag("left")
                        Text("Centro").tag("center")
                        Text("Direita").tag("right")
                    }
                    Divider()
                    Button("Configurações do Docka…") { SettingsWindowController.shared.show() }
                }
                .accessibilityLabel("Tamanho dos ícones")
                .accessibilityValue("\(Int(store.iconSize)) pontos")
                .accessibilityHint("Arraste para cima ou para baixo para redimensionar")

            Button {
                SettingsWindowController.shared.show()
            } label: {
                // mesmo tile dos apps, como o Lixo no Dock
                Image(systemName: "gearshape.fill")
                    .font(.system(size: store.iconSize * 0.5))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: store.iconSize, height: store.iconSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, TrayGeometry.indicatorRow(size: store.iconSize))
            .accessibilityLabel("Configurações do Docka")
        }
        .padding(.horizontal, TrayGeometry.padding(size: store.iconSize))
        // O vidro é desenhado à parte, ancorado embaixo e com a altura de
        // REPOUSO: assim o ícone ampliado sobe para fora dele, como no Dock,
        // em vez de esticar o painel.
        .background(alignment: .bottom) {
            Color.clear
                .frame(height: TrayGeometry.glassHeight(size: store.iconSize))
                .dockGlass(cornerRadius: TrayGeometry.cornerRadius(size: store.iconSize),
                           tint: store.glassTint)
        }
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
    /// Centro do ícone com a bandeja em repouso, no espaço "tray".
    let center: CGFloat
    let hoverX: CGFloat?
    let size: Double
    var maxScale: Double = 1.75                // 1 = ampliação desativada
    var maxRange: Double = 200
    let isRunning: Bool
    var bounceEnabled = true
    let action: () -> Void

    @State private var bounce: CGFloat = 0     // deslocamento Y do quique
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat {
        guard let hx = hoverX else { return 1 }
        return Magnification.scale(pointer: hx, itemCenter: center, itemSize: size,
                                   maxRange: maxRange, maxScale: maxScale)
    }

    /// Só o ícone apontado mostra o nome, como no Dock.
    private var magnified: Bool {
        Magnification.isHovered(pointer: hoverX, itemCenter: center,
                                size: size, gap: TrayGeometry.gap(size: size))
    }

    /// A bolinha do Dock é pequena e proporcional ao tile.
    private var indicatorSize: CGFloat { TrayGeometry.indicatorSize(size: size) }

    var body: some View {
        Button {
            action()
            launchBounce()
        } label: {
            VStack(spacing: TrayGeometry.indicatorSpacing(size: size)) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * scale, height: size * scale)
                    // sem sombra: o Dock não põe sombra sob os ícones. A arte do
                    // ícone já traz o próprio sombreado, e uma sombra por cima é
                    // o que mais denunciava que isto não era o Dock.
                    .offset(y: bounce)

                // bolinha de app em execução, proporcional ao ícone e SEM escalar
                // com a magnificação — no Dock ela tem tamanho fixo
                Circle()
                    .fill(Color(nsColor: .labelColor).opacity(isRunning ? 0.85 : 0))
                    .frame(width: indicatorSize, height: indicatorSize)
            }
            // container de altura fixa alinhado embaixo: o ícone cresce PARA CIMA.
            // A largura acompanha a escala — é ela que empurra os vizinhos.
            .frame(width: size * scale,
                   height: size * maxScale + TrayGeometry.indicatorRow(size: size)
                          + TrayGeometry.paddingBottom(size: size),
                   alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // o VoiceOver anuncia "Safari, em execução, botão" — o nome está no balão,
        // que é visual e some quando o ícone não está sob o cursor
        .accessibilityLabel(app.name)
        .accessibilityValue(isRunning ? "Em execução" : "")
        .accessibilityHint("Abre o aplicativo")
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
        // balão com o nome. No Dock ele acompanha o TOPO DO ÍCONE — com um
        // deslocamento fixo ele flutuava alto sobre os ícones em repouso.
        .overlay(alignment: .bottom) {
            if magnified {
                DockLabel(text: app.name)
                    .offset(y: -(size * scale) - 16)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)   // o nome já vai no rótulo do botão
            }
        }
        .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.78), value: scale)
        .animation(.spring(duration: 0.25), value: magnified)
        .zIndex(magnified ? 1 : 0)
    }

    // quique duplo, como o Dock ao abrir um app
    private func launchBounce() {
        // Reduzir Movimento vence o ajuste do app: é uma preferência do sistema
        guard bounceEnabled, !reduceMotion else { return }
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
