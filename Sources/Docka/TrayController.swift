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
        panel.acceptsMouseMovedEvents = true   // necessário para o cursorUpdate da alça

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

// Cursor sobre a alça do separador.
//
// NSCursor.set() chamado por um app INATIVO é ignorado — o cursor pertence ao
// app ativo, e o Docka vive em segundo plano. O canal que o AppKit oferece
// para janelas sem foco é o evento cursorUpdate de uma NSTrackingArea com
// .activeAlways: o sistema pede o cursor à janela sob o mouse (é assim que o
// Safari mostra a mãozinha em links mesmo desfocado).
private struct CursorDeRedimensionar: NSViewRepresentable {
    final class V: NSView {
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self))
        }
        override func cursorUpdate(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
        }
        // invisível ao clique: o arrasto e o menu continuam com a SwiftUI abaixo
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - A bandeja em si (vidro + ícones com magnificação estilo Dock)

struct TrayView: View {
    @EnvironmentObject var store: DockaStore
    @State private var hoverX: CGFloat? = nil     // posição do mouse p/ magnificação
    @State private var running: Set<String> = []  // caminhos dos apps abertos
    @State private var tamanhoAoIniciarArrasto: Double? = nil
    /// Força do efeito (0…1), atenuada pela distância vertical do cursor.
    @State private var hoverForca: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A ampliação máxima, atenuada pela rampa vertical.
    private var ampliacaoEfetiva: Double {
        1 + (store.maxScale - 1) * Double(hoverForca)
    }

    /// Escalas da fileira: pico CHEIO sob o cursor — o ícone "passa" da barra,
    /// como no Dock real — com a vizinhança estreitada pelo alcance limitado.
    /// A fileira cresce o pouco correspondente; a ancoragem mantém o ponto sob
    /// o cursor parado. (O soma-zero foi tentado e diluía o pico: com poucos
    /// ícones não existe pico cheio E vidro imóvel — o Dock real também cresce.)
    private var escalas: [CGFloat] {
        let n = store.apps.count
        guard n > 0, let p = effectiveHoverX else {
            return Array(repeating: 1, count: max(0, n))
        }
        let size = store.iconSize
        let gap = TrayGeometry.gap(size: size)
        let alcance = Magnification.cappedRange(count: n, size: size, gap: gap,
                                                maxRange: store.maxRange)
        return (0..<n).map { i in
            Magnification.scale(
                pointer: p,
                itemCenter: Magnification.restingCenter(
                    index: i, size: size, gap: gap,
                    padding: TrayGeometry.padding(size: size)),
                itemSize: size,
                maxRange: alcance,
                maxScale: ampliacaoEfetiva)
        }
    }

    /// Mantém PARADO o ponto sob o cursor enquanto a fileira cresce.
    private var deslocamentoDaFileira: CGFloat {
        let size = store.iconSize
        let gap = TrayGeometry.gap(size: size)
        return Magnification.centeredRowShift(
            pointer: effectiveHoverX,
            count: store.apps.count,
            size: size, gap: gap,
            padding: TrayGeometry.padding(size: size),
            maxScale: ampliacaoEfetiva,
            maxRange: Magnification.cappedRange(count: store.apps.count, size: size,
                                               gap: gap, maxRange: store.maxRange))
    }

    /// Converte o cursor do espaço do painel para o do vidro em repouso.
    ///
    /// Duas regras vindas do Dock real:
    /// - dentro do efeito o rastreio é 1:1, SEM mola — a suavidade vem da curva
    ///   de proximidade, não do tempo; elástico aqui fazia a bandeja "nadar";
    /// - a saída vertical é uma RAMPA, não um degrau: subir o cursor desfaz a
    ///   ampliação gradualmente. Degrau fazia a bandeja pular ao cruzar a linha.
    private func atualizarHover(_ fase: HoverPhase, painel: CGSize) {
        switch fase {
        case .active(let p):
            let fileira = TrayGeometry.restingRowWidth(appCount: store.apps.count,
                                                       size: store.iconSize)
            let vidroEsq = (painel.width - fileira) / 2
            let topoDoVidro = painel.height - 8
                - TrayGeometry.glassHeight(size: store.iconSize)
            let dentroX = p.x >= vidroEsq - 6 && p.x <= vidroEsq + fileira + 6
            let acima = topoDoVidro - p.y                 // >0 = cursor acima do vidro
            let rampa: CGFloat = 36
            let forca = dentroX ? max(0, min(1, 1 - acima / rampa)) : 0

            if forca <= 0 {
                encerrarHover()
            } else if hoverX == nil {
                // entrada: uma mola curta para o efeito nascer sem estalo
                withAnimation(.smooth(duration: 0.18)) {
                    hoverX = p.x - vidroEsq
                    hoverForca = forca
                }
            } else {
                hoverX = p.x - vidroEsq
                hoverForca = forca
            }
        case .ended:
            encerrarHover()
        }
    }

    private func encerrarHover() {
        guard hoverX != nil else { return }
        withAnimation(.smooth(duration: 0.22)) {
            hoverX = nil
            hoverForca = 1
        }
    }

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
                // o cursor sai da alça durante o arrasto e o hover termina —
                // sem isto a seta vertical viraria seta comum no meio do gesto
                NSCursor.resizeUpDown.set()
            }
            .onEnded { _ in
                tamanhoAoIniciarArrasto = nil
                NSCursor.arrow.set()
            }
    }

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer(minLength: 0)
                tray
                    // ancora o ponto sob o cursor enquanto a fileira cresce
                    .offset(x: deslocamentoDaFileira)
                    // sem o deslize de baixo quando o sistema pede menos movimento:
                    // a bandeja só surge e some
                    .offset(y: store.trayVisible || reduceMotion ? 0 : 200)
                    .opacity(store.trayVisible ? 1 : 0)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // O hover mora no espaço FIXO do painel, não no da fileira: a fileira
            // muda de largura com a ampliação e a origem dela se move — medir o
            // cursor num referencial móvel realimentava a conta e a ampliação
            // tremia sob um cursor parado, com o pico escorregando de ícone.
            .onContinuousHover { fase in atualizarHover(fase, painel: geo.size) }
        }
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
                         scale: escalas[index],
                         apontado: Magnification.isHovered(
                             pointer: effectiveHoverX,
                             itemCenter: Magnification.restingCenter(
                                 index: index,
                                 size: store.iconSize,
                                 gap: TrayGeometry.gap(size: store.iconSize),
                                 padding: TrayGeometry.padding(size: store.iconSize)),
                             size: store.iconSize,
                             gap: TrayGeometry.gap(size: store.iconSize)),
                         size: store.iconSize,
                         slotScale: store.maxScale,
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
                .padding(.bottom, TrayGeometry.indicatorRow(size: store.iconSize)
                                + TrayGeometry.paddingBottom(size: store.iconSize))
                .contentShape(Rectangle())          // pegada maior que o traço de 1 pt
                .overlay(CursorDeRedimensionar())
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
            .padding(.bottom, TrayGeometry.indicatorRow(size: store.iconSize)
                            + TrayGeometry.paddingBottom(size: store.iconSize))
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

    }
}

// Ícone com magnificação fiel ao Dock: cresce PARA CIMA a partir da linha de base,
// empurra os vizinhos (a largura do frame acompanha a escala), mostra o nome num
// balão quando ampliado, tem bolinha de "app aberto" e quica ao lançar.
struct TrayIcon: View {
    let app: PinnedApp
    /// Escala deste ícone, já resolvida pela redistribuição soma-zero da fileira.
    let scale: CGFloat
    /// O cursor está sobre ESTE ícone — decide o balão de nome.
    let apontado: Bool
    let size: Double
    /// Teto de ampliação — só para a ALTURA do slot não pulsar com o hover.
    var slotScale: Double = 1.75
    let isRunning: Bool
    var bounceEnabled = true
    let action: () -> Void

    @State private var bounce: CGFloat = 0     // deslocamento Y do quique
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                   height: size * slotScale + TrayGeometry.indicatorRow(size: size),
                   alignment: .bottom)
            // padding de verdade: dentro do frame com alignment .bottom, a folga
            // ia para CIMA e a bolinha ficava em cima da borda do vidro
            .padding(.bottom, TrayGeometry.paddingBottom(size: size))
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
            if apontado {
                // sem transição: no Dock real o rótulo troca SECO ao passar de um
                // ícone ao outro — o crossfade deixava dois balões na tela
                DockLabel(text: app.name)
                    .offset(y: -(size * scale) - 6)
                    .transition(.identity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)   // o nome já vai no rótulo do botão
            }
        }
        .zIndex(apontado ? 1 : 0)
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
