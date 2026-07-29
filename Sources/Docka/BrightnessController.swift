import SwiftUI
import AppKit
import DockaCore

/// Painel próprio do controle de brilho — não é um item da bandeja.
///
/// Vive numa lateral e aparece do mesmo jeito que a bandeja: encostando o
/// cursor na borda. Só laterais porque a régua é vertical.
final class BrightnessController {
    let state = TrayState()

    private var panel: NSPanel!
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var retirada: DispatchWorkItem?
    private var currentScreen: NSScreen? = NSScreen.main

    init() { buildPanel() }

    private var edge: TrayEdge { Brightness.edge(persisted: store.brightnessEdge) }

    private func buildPanel() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .mainMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.contentView = NSHostingView(
            rootView: BrightnessPanelView()
                .environmentObject(store)
                .environmentObject(state))
        layout()
    }

    func encerrar() {
        retirada?.cancel()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func layout() {
        guard let screen = currentScreen else { return }
        switch TrayAppearance(persisted: store.appearance) {
        case .automatico: panel.appearance = nil
        case .claro:      panel.appearance = NSAppearance(named: .aqua)
        case .escuro:     panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.setFrame(
            TrayGeometry.frame(screenFrame: screen.frame,
                               visibleFrame: screen.visibleFrame,
                               edge: edge,
                               alignment: TrayAlignment(persisted: store.brightnessAlignment),
                               offset: 24,
                               followDock: store.followDock,
                               extent: Brightness.panelExtent,
                               thickness: Brightness.panelThickness),
            display: true)
    }

    func tick() {
        guard store.onboarded, store.brightnessControl else { return }
        let loc = NSEvent.mouseLocation
        if !state.visible,
           let s = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }),
           s != currentScreen {
            currentScreen = s
            layout()
        }
        guard let screen = currentScreen else { return }
        let f = panel.frame

        if !state.visible {
            if TrayGeometry.shouldReveal(cursor: loc, trayFrame: f,
                                         screenFrame: screen.frame, edge: edge,
                                         pressureZone: store.pressureZone) {
                reveal()
            }
        } else if state.demoMode || TrayGeometry.isInsideTray(cursor: loc, trayFrame: f, edge: edge) {
            hideDelay = 0
        } else {
            hideDelay += 0.05
            if hideDelay > 0.35 { hide() }
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func reveal() {
        hideDelay = 0
        retirada?.cancel(); retirada = nil
        panel.orderFrontRegardless()
        store.sincronizarBrilho()   // pode ter mudado pelo teclado enquanto sumido
        withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                   : .spring(duration: 0.42, bounce: 0.28)) {
            state.visible = true
        }
    }

    /// Modo demo: deixa o controle aberto, para capturas.
    func startDemo() {
        state.demoMode = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in reveal() }
    }

    private func hide() {
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
}

/// A régua e o botão, como no controle de referência: o botão acompanha o
/// nível ao longo da régua e, enquanto se arrasta, troca o sol pela
/// porcentagem.
struct BrightnessPanelView: View {
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var state: TrayState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var esfregando = false
    @State private var nivelAoIniciar: Double?

    private var edge: TrayEdge { Brightness.edge(persisted: store.brightnessEdge) }
    private let comprimento: CGFloat = 250

    var body: some View {
        conteudo
            .offset(x: state.visible || reduceMotion ? 0
                     : (edge == .left ? -160 : 160))
            .opacity(state.visible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: edge == .left ? .leading : .trailing)
            .padding(edge == .left ? .leading : .trailing, 10)
            .ignoresSafeArea()
    }

    /// O botão fica do lado de DENTRO da tela, para não sair pela borda.
    @ViewBuilder
    private var conteudo: some View {
        let regua = BrightnessRuler(
            level: Binding(get: { store.brightnessLevel },
                           set: { store.brightnessLevel = $0 }),
            comprimento: comprimento, espessura: 54)
        HStack(spacing: 14) {
            if edge == .left { regua; botao } else { botao; regua }
        }
    }

    /// Botão-alça: mostra o sol parado e a porcentagem enquanto arrasta, e
    /// desliza ao longo da régua acompanhando o nível.
    private var botao: some View {
        ZStack {
            Circle().fill(Color(nsColor: .black).opacity(0.82))
            Circle().strokeBorder(Color.accentColor.opacity(esfregando ? 0.95 : 0.45),
                                  lineWidth: esfregando ? 2 : 1)
            if esfregando {
                Text(Brightness.knobLabel(level: store.brightnessLevel))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
            } else {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 44, height: 44)
        // acompanha o nível ao longo da régua
        .offset(y: Brightness.knobOffset(level: store.brightnessLevel,
                                         rulerLength: comprimento))
        .animation(.smooth(duration: 0.12), value: store.brightnessLevel)
        .contentShape(Circle())
        .overlay(CursorDeMao().allowsHitTesting(false))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    // A referência é o nível do INÍCIO do gesto. Calcular a
                    // partir do corrente realimentava: o botão se movia, o
                    // cursor ficava noutra posição relativa a ele e o brilho
                    // disparava — o "muito rápido" relatado.
                    if nivelAoIniciar == nil { nivelAoIniciar = store.brightnessLevel }
                    esfregando = true
                    aplicar(Brightness.dragStep(inicio: nivelAoIniciar ?? store.brightnessLevel,
                                                translation: g.translation.height,
                                                atual: store.brightnessLevel,
                                                span: comprimento))
                }
                .onEnded { _ in
                    nivelAoIniciar = nil
                    esfregando = false
                }
        )
        .frame(height: comprimento + 44, alignment: .center)
        .accessibilityLabel("Brilho")
        .accessibilityValue("\(Brightness.knobLabel(level: store.brightnessLevel)) por cento")
        .accessibilityHint("Arraste para cima ou para baixo para ajustar")
        .accessibilityAdjustableAction { direcao in
            aplicar(store.brightnessLevel
                    + (direcao == .increment ? Brightness.stepSize : -Brightness.stepSize))
        }
    }

    private func aplicar(_ novo: Double) {
        guard abs(novo - store.brightnessLevel) > 0.0001 else { return }
        BrightnessBackend.escrever(novo)
        store.brightnessLevel = BrightnessBackend.ler() ?? novo
    }
}

/// Mãozinha sobre o botão. Mesmo motivo do cursor da alça da bandeja: um app
/// inativo não consegue impor cursor com set(); quem responde é o cursorUpdate.
private struct CursorDeMao: NSViewRepresentable {
    final class V: NSView {
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                           owner: self))
        }
        override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
