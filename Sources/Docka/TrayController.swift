import SwiftUI
import AppKit
import Combine
import DockaCore

// Uma bandeja = um NSPanel numa borda da tela. O TrayManager mantém um
// controlador por bandeja configurada; a geometria por borda mora no DockaCore.

/// Estado de exibição de UMA bandeja.
final class TrayState: ObservableObject {
    @Published var visible = false
    @Published var pinned = false          // aberta pelo atalho: não auto-esconde
    @Published var demoHover: CGFloat? = nil
    var demoMode = false
}

final class TrayController {
    let dockID: UUID
    let state = TrayState()

    private var panel: NSPanel!
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var retirada: DispatchWorkItem?

    init(dockID: UUID) {
        self.dockID = dockID
        buildPanel()
    }

    private var dock: DockConfig? { store.dock(dockID) }

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

        panel.contentView = NSHostingView(
            rootView: TrayView(dockID: dockID)
                .environmentObject(store)
                .environmentObject(state))
        layout()
        // nasce fora da tela: quem traz o painel para frente é o reveal()
    }

    func encerrar() {
        retirada?.cancel()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // tela onde a bandeja está (segue o mouse entre monitores)
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

    func layout() {
        guard let screen = currentScreen, let d = dock else { return }
        applyAppearance()
        let size = store.iconSize
        panel.setFrame(
            TrayGeometry.frame(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                edge: d.edge,
                alignment: d.alignment,
                offset: d.offset,
                followDock: store.followDock,
                extent: TrayGeometry.trayExtent(appCount: d.apps.count, size: size,
                                                maxScale: store.maxScale,
                                                maxRange: store.maxRange),
                thickness: TrayGeometry.panelThickness(size: size, maxScale: store.maxScale,
                                                       edge: d.edge)),
            display: true)
    }

    // MARK: - Detecção do mouse (polling, sem permissões)

    func tick() {
        guard store.onboarded, let d = dock, !d.apps.isEmpty else { return }
        let loc = NSEvent.mouseLocation

        // multi-monitor: a bandeja acompanha a tela onde o cursor está
        if !state.visible, let s = screenUnderMouse(), s != currentScreen {
            currentScreen = s
            layout()
        }
        guard let screen = currentScreen else { return }
        let f = panel.frame

        if !state.visible {
            if TrayGeometry.shouldReveal(cursor: loc, trayFrame: f,
                                         screenFrame: screen.frame, edge: d.edge,
                                         pressureZone: store.pressureZone) {
                reveal()
            }
        } else if !state.pinned {
            if TrayGeometry.isInsideTray(cursor: loc, trayFrame: f, edge: d.edge) {
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

    private func reveal() {
        hideDelay = 0
        retirada?.cancel()
        retirada = nil
        // O painel só fica na tela enquanto a bandeja está aberta: vidro custa
        // GPU mesmo invisível.
        panel.orderFrontRegardless()
        store.playSound("Pop")
        withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                   : .spring(duration: 0.42, bounce: 0.28)) {
            state.visible = true
        }
    }

    private func hide() {
        state.pinned = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.32)) {
            state.visible = false
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel.orderOut(nil)
        }
        retirada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func toggleFromHotKey() {
        if state.visible {
            hide()
        } else {
            currentScreen = screenUnderMouse()
            layout()
            state.pinned = true
            reveal()
        }
    }

    /// Modo demo: bandeja fixa com um hover simulado varrendo os ícones.
    func startDemo() {
        guard let d = dock else { return }
        state.demoMode = true
        state.pinned = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            reveal()
            let start = Date()
            let extensao = TrayGeometry.restingRowWidth(appCount: d.apps.count,
                                                        size: store.iconSize)
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                let t = Date().timeIntervalSince(start)
                let fase = 0.5 + 0.5 * sin(t * 2.0 * .pi / 3.0)   // ciclo de 3 s
                self.state.demoHover = 15 + (extensao - 30) * fase
            }
        }
    }
}

// MARK: - Gerente das bandejas

final class TrayManager {
    static let shared = TrayManager()

    private var controllers: [UUID: TrayController] = [:]
    private var timer: Timer?
    private var cancellable: Any?
    private var screenObserver: NSObjectProtocol?
    private let store = DockaStore.shared

    func start() {
        sincronizar()
        // repõe os painéis quando as bandejas ou os ajustes mudam
        cancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.sincronizar() }
        }
        // "Seguir mudanças do Dock": o macOS publica isto quando o Dock muda de
        // tamanho ou de lado, e também ao ligar/desligar um monitor.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.controllers.values.forEach { $0.layout() }
        }
        // um timer só para todas as bandejas: N timers a 20 Hz seria desperdício
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.controllers.values.forEach { $0.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Cria e remove controladores para bater com as bandejas configuradas.
    private func sincronizar() {
        let atuais = Set(store.docks.map(\.id))
        for id in controllers.keys where !atuais.contains(id) {
            controllers.removeValue(forKey: id)?.encerrar()
        }
        for d in store.docks where controllers[d.id] == nil {
            controllers[d.id] = TrayController(dockID: d.id)
        }
        controllers.values.forEach { $0.layout() }
    }

    /// O atalho global age na bandeja principal.
    func toggleFromHotKey() {
        guard let id = store.docks.first?.id else { return }
        controllers[id]?.toggleFromHotKey()
    }

    func startDemo() {
        guard let id = store.docks.first?.id else { return }
        controllers[id]?.startDemo()
    }
}

// MARK: - Cursor sobre a alça do separador
//
// NSCursor.set() chamado por um app INATIVO é ignorado — o cursor pertence ao
// app ativo, e o Docka vive em segundo plano. O canal que o AppKit oferece
// para janelas sem foco é o evento cursorUpdate de uma NSTrackingArea com
// .activeAlways: o sistema pede o cursor à janela sob o mouse (é assim que o
// Safari mostra a mãozinha em links mesmo desfocado).
private struct CursorDeRedimensionar: NSViewRepresentable {
    let vertical: Bool

    final class V: NSView {
        var vertical = true
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self))
        }
        override func cursorUpdate(with event: NSEvent) {
            (vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
        }
        // invisível ao clique: o arrasto e o menu continuam com a SwiftUI abaixo
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let v = V(); v.vertical = vertical; return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? V)?.vertical = vertical
    }
}

// MARK: - A bandeja em si (vidro + ícones com magnificação estilo Dock)

struct TrayView: View {
    let dockID: UUID
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var state: TrayState

    @State private var hoverAlong: CGFloat? = nil   // posição do cursor AO LONGO da borda
    @State private var running: Set<String> = []
    @State private var tamanhoAoIniciarArrasto: Double? = nil
    /// Força do efeito (0…1), atenuada pela distância perpendicular do cursor.
    @State private var forca: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dock: DockConfig { store.dock(dockID) ?? DockConfig() }
    private var edge: TrayEdge { dock.edge }
    private var apps: [PinnedApp] { store.apps(of: dock) }
    private var size: CGFloat { store.iconSize }

    /// A ampliação máxima, atenuada pela rampa perpendicular.
    private var ampliacaoEfetiva: Double {
        1 + (store.maxScale - 1) * Double(forca)
    }

    /// No modo demo o hover vem do varredor simulado.
    private var hoverEfetivo: CGFloat? {
        state.demoMode ? state.demoHover : hoverAlong
    }

    /// Escalas da fileira: pico CHEIO sob o cursor — o ícone "passa" da barra,
    /// como no Dock real — com a vizinhança estreitada pelo alcance limitado.
    private var escalas: [CGFloat] {
        let n = apps.count
        guard n > 0, let p = hoverEfetivo else {
            return Array(repeating: 1, count: max(0, n))
        }
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
    private var deslocamento: CGFloat {
        let gap = TrayGeometry.gap(size: size)
        return Magnification.centeredRowShift(
            pointer: hoverEfetivo,
            count: apps.count,
            size: size, gap: gap,
            padding: TrayGeometry.padding(size: size),
            maxScale: ampliacaoEfetiva,
            maxRange: Magnification.cappedRange(count: apps.count, size: size,
                                                gap: gap, maxRange: store.maxRange))
    }

    var body: some View {
        GeometryReader { geo in
            bandeja
                .offset(x: edge.isVertical ? 0 : deslocamento,
                        y: edge.isVertical ? deslocamento : 0)
                .offset(deslizeDeEntrada)
                .opacity(state.visible ? 1 : 0)
                .padding(bordaInterna, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: alinhamentoDoVidro)
                .onContinuousHover { fase in atualizarHover(fase, painel: geo.size) }
        }
        .ignoresSafeArea()
        .onAppear { refreshRunning() }
        .onChange(of: state.visible) { _, v in if v { refreshRunning() } }
        .onReceive(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshRunning() }
    }

    /// Deslize de entrada/saída: a bandeja desliza a partir da borda dela.
    private var deslizeDeEntrada: CGSize {
        guard !(state.visible || reduceMotion) else { return .zero }
        switch edge {
        case .bottom: return CGSize(width: 0, height: 200)
        case .left:   return CGSize(width: -200, height: 0)
        case .right:  return CGSize(width: 200, height: 0)
        }
    }

    private var alinhamentoDoVidro: Alignment {
        switch edge {
        case .bottom: return .bottom
        case .left:   return .leading
        case .right:  return .trailing
        }
    }

    /// A borda da tela, do ponto de vista do conteúdo: é para lá que a bolinha
    /// aponta e é dela que sai a folga interna.
    private var bordaInterna: Edge.Set {
        switch edge {
        case .bottom: return .bottom
        case .left:   return .leading
        case .right:  return .trailing
        }
    }

    private func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
    }

    // MARK: a fileira

    private var bandeja: some View {
        AoLongoDaBorda(edge: edge, spacing: TrayGeometry.gap(size: size)) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                TrayIcon(app: app,
                         edge: edge,
                         scale: escalas.indices.contains(index) ? escalas[index] : 1,
                         apontado: Magnification.isHovered(
                             pointer: hoverEfetivo,
                             itemCenter: Magnification.restingCenter(
                                 index: index, size: size,
                                 gap: TrayGeometry.gap(size: size),
                                 padding: TrayGeometry.padding(size: size)),
                             size: size,
                             gap: TrayGeometry.gap(size: size)),
                         size: size,
                         slotScale: store.maxScale,
                         isRunning: running.contains(app.path) && store.showIndicators,
                         bounceEnabled: store.bounceOnLaunch) {
                    store.playSound("Tink")
                    app.launch()
                }
                .draggable(URL(fileURLWithPath: app.path))
                .dropDestination(for: URL.self) { urls, _ in
                    guard let first = urls.first else { return false }
                    if dock.apps.contains(first.path) {
                        withAnimation(.spring(duration: 0.35)) {
                            store.moverApp(first.path, antesDe: app.path, em: dockID)
                        }
                    } else {
                        app.open(files: urls)
                        store.playSound("Tink")
                    }
                    return true
                }
                .contextMenu {
                    Button("Abrir") { app.launch() }
                    Button("Mostrar no Finder") { app.revealInFinder() }
                    Divider()
                    Button("Remover desta bandeja", role: .destructive) {
                        withAnimation(.spring(duration: 0.35)) {
                            store.alternarApp(app.path, em: dockID)
                        }
                    }
                }
            }
        }
        .padding(edge.isVertical ? .vertical : .horizontal, TrayGeometry.padding(size: size))
        // O vidro é a alça: arrastar redimensiona os ícones e o clique-direito
        // abre o menu da bandeja. Antes isso morava no traço separador, que só
        // existia para dividir os apps da engrenagem — sem ela, o traço ficava
        // pendurado no fim da fileira sem dividir nada.
        .contentShape(Rectangle())
        .overlay(CursorDeRedimensionar(vertical: !edge.isVertical).allowsHitTesting(false))
        .gesture(redimensionarPelaAlca)
        .contextMenu { menuDaBandeja }
        // O vidro é desenhado à parte, ancorado na borda e com a espessura de
        // REPOUSO: o ícone ampliado sai para fora dele, como no Dock.
        .background(alignment: alinhamentoDoVidro) {
            Color.clear
                .frame(width: edge.isVertical ? TrayGeometry.glassHeight(size: size) : nil,
                       height: edge.isVertical ? nil : TrayGeometry.glassHeight(size: size))
                .dockGlass(cornerRadius: TrayGeometry.cornerRadius(size: size),
                           tint: store.glassTint)
        }
    }

    @ViewBuilder
    private var menuDaBandeja: some View {
        Picker("Borda da Tela", selection: Binding(
            get: { dock.edge }, set: { store.definirBorda($0, em: dockID) })) {
            ForEach(TrayEdge.allCases, id: \.self) { Text($0.titulo).tag($0) }
        }
        Picker("Posição", selection: Binding(
            get: { dock.alignment }, set: { store.definirAlinhamento($0, em: dockID) })) {
            ForEach(TrayAlignment.allCases, id: \.self) {
                Text($0.titulo(for: dock.edge)).tag($0)
            }
        }
        Divider()
        Button("Configurações do Docka…") { SettingsWindowController.shared.show() }
    }

    /// Arrastar a alça redimensiona os ícones. O tamanho de referência é o do
    /// INÍCIO do arrasto — acumular sobre o corrente faria o tamanho acelerar.
    private var redimensionarPelaAlca: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if tamanhoAoIniciarArrasto == nil { tamanhoAoIniciarArrasto = size }
                // na lateral quem manda é o eixo horizontal, e o sentido de
                // "aumentar" aponta para dentro da tela
                let delta: CGFloat
                switch edge {
                case .bottom: delta = g.translation.height
                case .left:   delta = -g.translation.width
                case .right:  delta = g.translation.width
                }
                store.iconSize = TrayGeometry.iconSizeDragged(
                    from: tamanhoAoIniciarArrasto ?? size, verticalTranslation: delta)
                (edge.isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            }
            .onEnded { _ in
                tamanhoAoIniciarArrasto = nil
                NSCursor.arrow.set()
            }
    }

    // MARK: hover

    /// Converte o cursor do espaço do painel para o eixo da borda.
    ///
    /// Duas regras vindas do Dock real: dentro do efeito o rastreio é 1:1, sem
    /// mola; e a saída perpendicular é uma RAMPA, não um degrau.
    private func atualizarHover(_ fase: HoverPhase, painel: CGSize) {
        switch fase {
        case .active(let p):
            let fileira = TrayGeometry.restingRowWidth(appCount: apps.count, size: size)
            let vidro = TrayGeometry.glassHeight(size: size)
            let rampa: CGFloat = 36

            // `aoLongo` corre na direção da borda; `fora` mede o afastamento
            // perpendicular a partir da face interna do vidro
            let aoLongo: CGFloat, inicio: CGFloat, fora: CGFloat
            switch edge {
            case .bottom:
                inicio = (painel.width - fileira) / 2
                aoLongo = p.x
                fora = (painel.height - 8 - vidro) - p.y
            case .left:
                inicio = (painel.height - fileira) / 2
                aoLongo = p.y
                fora = p.x - (8 + vidro)
            case .right:
                inicio = (painel.height - fileira) / 2
                aoLongo = p.y
                fora = (painel.width - 8 - vidro) - p.x
            }

            let naFaixa = aoLongo >= inicio - 6 && aoLongo <= inicio + fileira + 6
            let f = naFaixa ? max(0, min(1, 1 - fora / rampa)) : 0

            if f <= 0 {
                encerrarHover()
            } else if hoverAlong == nil {
                // entrada: transição curta para o efeito nascer sem estalo
                withAnimation(.smooth(duration: 0.18)) {
                    hoverAlong = aoLongo - inicio
                    forca = f
                }
            } else {
                hoverAlong = aoLongo - inicio
                forca = f
            }
        case .ended:
            encerrarHover()
        }
    }

    private func encerrarHover() {
        guard hoverAlong != nil else { return }
        withAnimation(.smooth(duration: 0.22)) {
            hoverAlong = nil
            forca = 1
        }
    }
}

/// HStack na borda inferior, VStack nas laterais — o resto do layout é o mesmo.
private struct AoLongoDaBorda<Content: View>: View {
    let edge: TrayEdge
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if edge.isVertical {
            VStack(alignment: edge == .left ? .leading : .trailing, spacing: spacing) {
                content()
            }
        } else {
            HStack(alignment: .bottom, spacing: spacing) { content() }
        }
    }
}

// MARK: - Um ícone

struct TrayIcon: View {
    let app: PinnedApp
    let edge: TrayEdge
    /// Escala deste ícone, já resolvida pela fileira.
    let scale: CGFloat
    /// O cursor está sobre ESTE ícone — decide o balão de nome.
    let apontado: Bool
    let size: Double
    /// Teto de ampliação — só para o slot não pulsar com o hover.
    var slotScale: Double = 1.5
    let isRunning: Bool
    var bounceEnabled = true
    let action: () -> Void

    @State private var bounce: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { action(); launchBounce() } label: {
            conteudo
                .frame(width: edge.isVertical
                        ? size * slotScale + TrayGeometry.indicatorRow(size: size)
                        : size * scale,
                       height: edge.isVertical
                        ? size * scale
                        : size * slotScale + TrayGeometry.indicatorRow(size: size),
                       alignment: alinhamento)
                // padding de verdade: dentro do frame com alinhamento na borda,
                // a folga iria para o lado errado e a bolinha encostaria no vidro
                .padding(bordaInterna, TrayGeometry.paddingBottom(size: size))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .accessibilityValue(isRunning ? "Em execução" : "")
        .accessibilityHint("Abre o aplicativo")
        .overlay(alignment: alinhamento) {
            if apontado {
                // sem transição: no Dock o rótulo troca SECO ao passar de um
                // ícone ao outro — o crossfade deixava dois balões na tela
                DockLabel(text: app.name, edge: edge)
                    .offset(x: edge == .left ? size * scale + 6
                             : edge == .right ? -(size * scale) - 6 : 0,
                            y: edge == .bottom ? -(size * scale) - 6 : 0)
                    .transition(.identity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)   // o nome já vai no rótulo do botão
            }
        }
        .zIndex(apontado ? 1 : 0)
    }

    /// Ícone e bolinha: a bolinha fica sempre do lado da BORDA da tela.
    @ViewBuilder
    private var conteudo: some View {
        let icone = Image(nsImage: app.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size * scale, height: size * scale)
            // sem sombra: o Dock não põe sombra sob os ícones
            .offset(x: edge == .left ? bounce : (edge == .right ? -bounce : 0),
                    y: edge == .bottom ? bounce : 0)
        let ponto = Circle()
            .fill(Color(nsColor: .labelColor).opacity(isRunning ? 0.85 : 0))
            .frame(width: TrayGeometry.indicatorSize(size: size),
                   height: TrayGeometry.indicatorSize(size: size))

        switch edge {
        case .bottom:
            VStack(spacing: TrayGeometry.indicatorSpacing(size: size)) { icone; ponto }
        case .left:
            HStack(spacing: TrayGeometry.indicatorSpacing(size: size)) { ponto; icone }
        case .right:
            HStack(spacing: TrayGeometry.indicatorSpacing(size: size)) { icone; ponto }
        }
    }

    private var alinhamento: Alignment {
        switch edge {
        case .bottom: return .bottom
        case .left:   return .leading
        case .right:  return .trailing
        }
    }

    private var bordaInterna: Edge.Set {
        switch edge {
        case .bottom: return .bottom
        case .left:   return .leading
        case .right:  return .trailing
        }
    }

    /// Quique duplo, como o Dock ao abrir um app — na direção da borda.
    private func launchBounce() {
        // Reduzir Movimento vence o ajuste do app: é preferência do sistema
        guard bounceEnabled, !reduceMotion else { return }
        let sentido: CGFloat = edge == .bottom ? -1 : 1
        func hop(_ altura: CGFloat, delay: Double, queda: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.22)) { bounce = sentido * altura }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.easeIn(duration: queda)) { bounce = 0 }
                }
            }
        }
        hop(26, delay: 0, queda: 0.2)
        hop(14, delay: 0.46, queda: 0.24)
    }
}
