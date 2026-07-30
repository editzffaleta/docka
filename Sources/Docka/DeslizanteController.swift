import SwiftUI
import AppKit
import DockaCore

/// O painel de um controle deslizante de borda — brilho ou volume.
///
/// Não é item de bandeja: tem janela própria, mora numa lateral e aparece do
/// mesmo jeito que a bandeja, encostando o cursor na borda. Só laterais porque
/// a régua é vertical.
///
/// Um controlador por `Deslizador`. Este arquivo já foi `BrightnessController`,
/// com o brilho embutido; ao chegar o volume, a escolha foi generalizar em vez
/// de copiar — os dois painéis se comportam igual até no detalhe de esconder.
final class DeslizanteController {
    let deslizador: Deslizador
    let state = TrayState()

    /// Quadro de outro controle a evitar, quando os dois dividem a lateral.
    var evitar: (() -> CGRect?)?

    private var panel: NSPanel!
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var retirada: DispatchWorkItem?
    private var currentScreen: NSScreen? = NSScreen.main

    init(_ deslizador: Deslizador) {
        self.deslizador = deslizador
        buildPanel()
    }

    /// Onde o painel está agora — o irmão consulta isto para não sentar em cima.
    var quadro: CGRect { panel.frame }

    private var edge: TrayEdge { deslizador.bordaAtual(store) }

    private func buildPanel() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        // DEPOIS de isFloatingPanel, de propósito: essa propriedade rebaixa a
        // janela para o nível .floating (3) e sobrescreve o nível pedido antes.
        // Com ela primeiro, o painel ficava ABAIXO do Dock da Apple (nível 20).
        panel.level = .mainMenu
        panel.contentView = NSHostingView(
            rootView: DeslizantePanelView(deslizador: deslizador)
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
        let pedido = TrayGeometry.frame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            edge: edge,
            alignment: TrayAlignment(persisted: store[keyPath: deslizador.alinhamento]),
            offset: 24,
            followDock: store.followDock,
            extent: Deslizante.panelExtent,
            thickness: Deslizante.panelThickness)
        // brilho e volume podem ser postos na mesma lateral e na mesma posição;
        // aí o segundo se acomoda em vez de cobrir o primeiro
        panel.setFrame(Deslizante.desviar(pedido, de: evitar?(), dentro: screen.frame),
                       display: true)
    }

    func tick() {
        guard store.onboarded, store[keyPath: deslizador.ligado] else { return }
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
        } else if state.demoMode || state.pinned
                    || TrayGeometry.isInsideTray(cursor: loc, trayFrame: f, edge: edge) {
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
        // pode ter mudado pelo teclado, ou pela troca de fone, enquanto sumido
        if let real = deslizador.ler() { store[keyPath: deslizador.nivel] = real }
        withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                   : .spring(duration: 0.42, bounce: 0.28)) {
            state.visible = true
        }
    }

    /// Fixa o painel aberto pelo atalho, e o esconde no segundo toque.
    ///
    /// Fixado ele não some quando o cursor sai — é o que diferencia o atalho de
    /// simplesmente encostar na borda.
    func toggleFromHotKey() {
        if state.visible {
            state.pinned = false
            hide()
        } else {
            currentScreen = NSScreen.screens.first {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            } ?? NSScreen.main
            layout()
            state.pinned = true
            reveal()
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
/// nível ao longo da régua e, enquanto se arrasta, troca o ícone pela
/// porcentagem.
struct DeslizantePanelView: View {
    let deslizador: Deslizador
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var state: TrayState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var esfregando = false
    @State private var nivelAoIniciar: Double?

    private var edge: TrayEdge { deslizador.bordaAtual(store) }
    private let comprimento = Deslizante.rulerLength

    private var nivel: Double { store[keyPath: deslizador.nivel] }

    var body: some View {
        conteudo
            // o Tom escolhido vale também para as cores semânticas de dentro,
            // não só para o material do painel
            .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
            .offset(x: state.visible || reduceMotion ? 0
                     : (edge == .left ? -160 : 160))
            .opacity(state.visible ? 1 : 0)
            .scaleEffect(state.visible || reduceMotion ? 1 : 0.94,
                         anchor: edge == .left ? .leading : .trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: edge == .left ? .leading : .trailing)
            .padding(edge == .left ? .leading : .trailing, 10)
            .ignoresSafeArea()
    }

    /// O botão fica do lado de DENTRO da tela, para não sair pela borda.
    @ViewBuilder
    private var conteudo: some View {
        let regua = ReguaVertical(
            deslizador: deslizador,
            level: Binding(get: { nivel },
                           set: { store[keyPath: deslizador.nivel] = $0 }),
            comprimento: comprimento,
            espessura: Deslizante.rulerThickness,
            tint: store.glassTint)
        HStack(spacing: 12) {
            if edge == .left { regua; botao } else { botao; regua }
        }
    }

    /// Botão-alça: mostra o ícone parado e a porcentagem enquanto arrasta, e
    /// desliza ao longo da régua acompanhando o nível.
    private var botao: some View {
        ZStack {
            GlassCircle(tint: store.glassTint)
            Circle().strokeBorder(Color.accentColor.opacity(esfregando ? 0.95 : 0.35),
                                  lineWidth: esfregando ? 2 : 1)
            if esfregando {
                Text(Deslizante.knobLabel(level: nivel))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
            } else {
                Image(systemName: deslizador.simbolo(nivel))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: Deslizante.knobSize, height: Deslizante.knobSize)
        .contentShape(Circle())
        // A área de arrasto entra ANTES do .offset, de propósito: `.offset`
        // desloca só o desenho, e um overlay aplicado depois fica no frame de
        // layout, parado no centro. Era esse o defeito — o ícone subia com o
        // nível e a área clicável ficava para trás; só em 50% os dois
        // coincidiam. Aplicado aqui, os dois deslocam juntos.
        .overlay(
            ArrastoAppKit(
                aoArrastar: { d in
                    if nivelAoIniciar == nil { nivelAoIniciar = nivel }
                    // até o limiar ainda pode ser clique: não mexe no valor
                    guard !Deslizante.isTap(translation: d.height) else { return }
                    esfregando = true
                    aplicar(Deslizante.dragStep(inicio: nivelAoIniciar ?? nivel,
                                                translation: d.height,
                                                atual: nivel,
                                                span: comprimento))
                },
                aoSoltar: { d in
                    nivelAoIniciar = nil
                    esfregando = false
                    if Deslizante.isTap(translation: d.height) {
                        store[keyPath: deslizador.nivel] =
                            deslizador.aoTocar(nivel)
                    }
                },
                cursor: .openHand)
        )
        // acompanha o nível ao longo da régua — desenho E área de toque
        .offset(y: Deslizante.knobOffset(level: nivel, rulerLength: comprimento))
        // mola curta: o botão persegue o valor sem parecer preso a um trilho
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: nivel)
        .frame(height: comprimento + Deslizante.knobSize, alignment: .center)
        .accessibilityLabel(deslizador.titulo)
        .accessibilityValue("\(Deslizante.knobLabel(level: nivel)) por cento")
        .accessibilityHint(deslizador.dica)
        .accessibilityAdjustableAction { direcao in
            aplicar(nivel + (direcao == .increment ? Deslizante.stepSize : -Deslizante.stepSize))
        }
    }

    private func aplicar(_ novo: Double) {
        store[keyPath: deslizador.nivel] =
            NivelDoSistema.aplicar(novo, atual: nivel, com: deslizador)
    }
}

/// Aplica o Tom escolhido ao ambiente; automático segue o sistema.
struct EsquemaEscolhido: ViewModifier {
    let appearance: TrayAppearance
    func body(content: Content) -> some View {
        switch appearance {
        case .automatico: content
        case .claro:      content.environment(\.colorScheme, .light)
        case .escuro:     content.environment(\.colorScheme, .dark)
        }
    }
}
