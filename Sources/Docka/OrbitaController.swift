import SwiftUI
import AppKit
import DockaCore

/// A órbita: os apps num anel em volta do cursor.
///
/// Painel próprio, como os controles de borda — mas este não mora numa borda:
/// ele nasce onde o cursor está, no momento em que é chamado, e some assim que
/// o usuário escolhe ou desiste.
final class OrbitaController {
    let state = TrayState()

    private var panel: NSPanel!
    private let store = DockaStore.shared
    /// Índice apontado agora, calculado pela posição do cursor.
    private let selecao = SelecaoDaOrbita()
    private var centro: CGPoint = .zero
    private var currentScreen: NSScreen? = NSScreen.main
    private var retirada: DispatchWorkItem?
    private var monitorDeTecla: Any?

    init() { buildPanel() }

    /// Os apps que a órbita mostra: a lista própria dela, dos ajustes.
    private var apps: [PinnedApp] { store.appsDaOrbita }

    private func buildPanel() {
        // Nasce já do tamanho certo, e não em .zero: uma janela de tamanho zero
        // hospedando uma view que pede `maxWidth: .infinity` põe o NSHostingView
        // num laço de recálculo de safe area, e o AppKit aborta o app com
        // "more Update Constraints in Window passes than there are views".
        let lado = Orbita.tamanhoDoPainel(total: max(1, apps.count))
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: lado, height: lado),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        // depois de isFloatingPanel: ela rebaixa a janela para o nível .floating
        panel.level = .mainMenu
        aplicarTom()
        panel.contentView = NSHostingView(
            rootView: OrbitaView(aoEscolher: { [weak self] in self?.escolher() })
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(selecao))
    }

    /// O Tom dos ajustes vale para o material do painel, como nos outros.
    private func aplicarTom() {
        switch TrayAppearance(persisted: store.appearance) {
        case .automatico: panel.appearance = nil
        case .claro:      panel.appearance = NSAppearance(named: .aqua)
        case .escuro:     panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func encerrar() {
        retirada?.cancel()
        pararMonitor()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// Abre no cursor, ou fecha se já estiver aberta.
    func alternar() {
        state.visible ? fechar() : abrir()
    }

    func abrir() {
        guard !apps.isEmpty else { return }
        let loc = NSEvent.mouseLocation
        currentScreen = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        guard let tela = currentScreen?.frame else { return }

        centro = loc
        aplicarTom()
        retirada?.cancel(); retirada = nil
        selecao.indice = nil
        panel.setFrame(Orbita.quadro(centro: loc, total: apps.count, tela: tela), display: true)
        panel.orderFrontRegardless()
        withAnimation(reduceMotion ? .easeOut(duration: 0.14)
                                   : .spring(duration: 0.34, bounce: 0.3)) {
            state.visible = true
        }
        comecarMonitor()
    }

    func fechar() {
        pararMonitor()
        selecao.indice = nil
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.26)) {
            state.visible = false
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel.orderOut(nil)
        }
        retirada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Há um item apontado agora? O botão do mouse consulta isto ao soltar.
    var temSelecao: Bool { state.visible && selecao.indice != nil }

    /// Lança o que estiver apontado e fecha. Chamado pelo clique.
    func escolher() {
        let lista = apps
        if let i = selecao.indice, lista.indices.contains(i) {
            store.playSound("Tink")
            lista[i].launch()
        }
        fechar()
    }

    /// Acompanha o cursor a 20 Hz, como o resto do app.
    ///
    /// A seleção sai da posição do cursor, e não de hover do SwiftUI: o cursor
    /// pode estar FORA do anel — apontar na direção já basta — e nesse caso
    /// nenhuma view receberia o hover.
    func tick() {
        guard state.visible else { return }
        let loc = NSEvent.mouseLocation
        // do AppKit (y para cima) para o eixo do desenho (y para baixo)
        let rel = CGPoint(x: loc.x - centro.x, y: centro.y - loc.y)
        let novo = Orbita.indiceSob(rel, total: apps.count)
        if novo != selecao.indice {
            selecao.indice = novo
            if novo != nil { store.playSound("Tink", volume: 0.10) }
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Esc fecha sem escolher. Monitor **local**: só enquanto a órbita está
    /// aberta e sem permissão nenhuma.
    private func comecarMonitor() {
        guard monitorDeTecla == nil else { return }
        monitorDeTecla = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53 else { return e }
            self?.fechar()
            return nil
        }
    }

    private func pararMonitor() {
        if let m = monitorDeTecla { NSEvent.removeMonitor(m) }
        monitorDeTecla = nil
    }
}

/// O que está apontado agora. Fica separado do `TrayState` porque muda a cada
/// leitura do cursor e só interessa à órbita.
final class SelecaoDaOrbita: ObservableObject {
    @Published var indice: Int?
}

/// O anel: vidro com um buraco no meio e os ícones em volta.
struct OrbitaView: View {
    let aoEscolher: () -> Void
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var state: TrayState
    @EnvironmentObject var selecao: SelecaoDaOrbita
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var apps: [PinnedApp] { store.appsDaOrbita }

    var body: some View {
        ZStack {
            anel
            ForEach(Array(apps.enumerated()), id: \.element.id) { i, app in
                icone(app, indice: i)
            }
            // o nome do apontado, no miolo: é o espaço vazio do anel, e ali ele
            // não cobre ícone nenhum
            if let i = selecao.indice, apps.indices.contains(i) {
                Text(apps[i].name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    // fundo próprio: o miolo é vazado e mostra o que estiver
                    // atrás da janela, então o rótulo não pode contar com
                    // contraste nenhum — sem isto ele sumia sobre fundo claro
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.94)))
                    .frame(maxWidth: Orbita.raioInterno * 1.8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(state.visible || reduceMotion ? 1 : 0.82)
        .opacity(state.visible ? 1 : 0)
        .ignoresSafeArea()
    }

    /// O anel de vidro, com buraco de verdade no meio.
    ///
    /// O recorte é feito na PRÓPRIA vibrância, com um caminho de dois círculos
    /// e preenchimento par-ímpar. A primeira versão furava com
    /// `blendMode(.destinationOut)`, que atua só na camada SwiftUI — a
    /// `NSVisualEffectView`, que é AppKit, seguia inteira e o miolo ficava
    /// opaco em vez de mostrar a área de trabalho.
    ///
    /// A área também recebe cliques: a vibrância não desenha pixel, e sem isso
    /// o clique atravessaria a janela.
    private var anel: some View {
        let r = Orbita.raio(total: apps.count)
        let externo = 2 * r + Orbita.tamanhoItem
        let forma = Anel(raioInterno: Orbita.raioInterno)
        return ZStack {
            Vibrancia(material: GlassTint.material(for: store.glassTint).appKit)
            let escurecer = GlassTint.overlayOpacity(store.glassTint)
            if escurecer > 0 { Color.black.opacity(escurecer) }
        }
        .frame(width: externo, height: externo)
        .clipShape(forma, style: FillStyle(eoFill: true))
        // o brilho de contorno que o vidro do sistema não desenha sozinho
        .overlay(
            forma.stroke(
                LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
                .frame(width: externo, height: externo)
        )
        .shadow(color: .black.opacity(0.30), radius: 18, y: 6)
        .overlay(
            ArrastoAppKit(aoArrastar: { _ in },
                          aoSoltar: { _ in aoEscolher() },
                          cursor: .arrow,
                          receberCliques: true)
                .frame(width: externo, height: externo)
                .clipShape(forma, style: FillStyle(eoFill: true))
        )
    }

    private func icone(_ app: PinnedApp, indice i: Int) -> some View {
        let p = Orbita.posicao(indice: i, total: apps.count)
        let escala = Orbita.escala(indice: i, apontado: selecao.indice)
        return Image(nsImage: app.icon)
            .resizable()
            .frame(width: Orbita.tamanhoItem, height: Orbita.tamanhoItem)
            .scaleEffect(escala)
            .shadow(color: .black.opacity(selecao.indice == i ? 0.35 : 0), radius: 8, y: 3)
            .offset(x: p.x, y: p.y)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.7),
                       value: escala)
            // Transparente ao clique, de propósito: quem recebe é o anel, uma
            // camada só. O ícone é uma `Image` e absorveria o clique sem fazer
            // nada — e mirar no ícone nem é preciso, basta apontar a direção.
            .allowsHitTesting(false)
            .accessibilityLabel(app.name)
    }
}

/// Anel: círculo externo com um furo concêntrico. Preenchido em par-ímpar, o
/// segundo círculo vira buraco.
struct Anel: Shape {
    var raioInterno: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect)
        p.addEllipse(in: CGRect(x: rect.midX - raioInterno, y: rect.midY - raioInterno,
                                width: raioInterno * 2, height: raioInterno * 2))
        return p
    }
}
