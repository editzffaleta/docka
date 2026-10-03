import SwiftUI
import AppKit
import DockaCore

// MARK: - Os itens

/// O conteúdo da prateleira. Fora do `DockaStore` pelo mesmo motivo do
/// "manter acordado": cada item solto publicaria no store, e o store acorda o
/// TrayManager, que refaz o layout de todas as bandejas.
final class PrateleiraModelo: ObservableObject {
    static let shared = PrateleiraModelo()
    private let chave = "docka.shelfItems"

    @Published private(set) var itens: [ItemDaPrateleira] = [] {
        didSet {
            if let dados = try? JSONEncoder().encode(itens) {
                UserDefaults.standard.set(dados, forKey: chave)
            }
        }
    }

    private init() {
        if let dados = UserDefaults.standard.data(forKey: chave),
           let gravados = try? JSONDecoder().decode([ItemDaPrateleira].self, from: dados) {
            itens = gravados
        }
        limparSumidos()
    }

    func adicionar(_ novos: [ItemDaPrateleira]) {
        guard !novos.isEmpty else { return }
        itens = Prateleira.adicionar(novos, a: itens)
    }

    func remover(_ id: UUID) { itens.removeAll { $0.id == id } }
    func esvaziar() { itens = [] }

    /// Chamado a cada vez que o painel aparece: um arquivo arrastado da
    /// prateleira para outra pasta com ⌘ foi MOVIDO, e não existe mais aqui.
    func limparSumidos() {
        let limpos = Prateleira.semArquivosSumidos(itens) {
            FileManager.default.fileExists(atPath: $0)
        }
        if limpos != itens { itens = limpos }
    }

    // MARK: o que cada item vira

    /// O que vai na área de transferência do arrasto ou da cópia.
    static func escritor(_ item: ItemDaPrateleira) -> NSPasteboardWriting {
        switch item.tipo {
        case .arquivo: return URL(fileURLWithPath: item.valor) as NSURL
        case .link:    return (URL(string: item.valor) as NSURL?) ?? item.valor as NSString
        case .texto:   return item.valor as NSString
        }
    }

    static func abrir(_ item: ItemDaPrateleira) {
        switch item.tipo {
        case .arquivo: NSWorkspace.shared.open(URL(fileURLWithPath: item.valor))
        case .link:    URL(string: item.valor).map { _ = NSWorkspace.shared.open($0) }
        case .texto:   copiar(item)   // texto não tem onde "abrir": clicar copia
        }
    }

    static func copiar(_ item: ItemDaPrateleira) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([escritor(item)])
    }

    static func icone(_ item: ItemDaPrateleira) -> NSImage? {
        guard item.tipo == .arquivo else { return nil }
        let img = NSWorkspace.shared.icon(forFile: item.valor)
        img.size = NSSize(width: 64, height: 64)
        return img
    }

    // MARK: o que chega soltando

    /// Lê o que foi solto, item por item, na ordem: arquivo, link, texto.
    ///
    /// Item por item, e não "todos os arquivos, depois todos os textos": um
    /// arquivo do Finder também se oferece como texto, e um .txt ainda traz o
    /// próprio conteúdo. Pegar só a forma mais específica de cada item evita
    /// que um arquivo vire três linhas — ou vire o texto de dentro dele, que
    /// era o que o `onDrop` do SwiftUI entregava.
    func receber(_ pb: NSPasteboard) -> Bool {
        let novos: [ItemDaPrateleira] = (pb.pasteboardItems ?? []).compactMap { item in
            if let s = item.string(forType: .fileURL), let url = URL(string: s), url.isFileURL {
                return ItemDaPrateleira(tipo: .arquivo, valor: url.path)
            }
            if let s = item.string(forType: .URL) {
                return Prateleira.classificar(s)
            }
            if let s = item.string(forType: .string) {
                return Prateleira.classificar(s)
            }
            return nil
        }
        guard !novos.isEmpty else { return false }
        adicionar(novos)
        DockaStore.shared.playSound("Pop", volume: 0.5)
        return true
    }
}

// MARK: - O painel

/// Estado de exibição da prateleira.
final class PrateleiraEstado: ObservableObject {
    @Published var visible = false
    @Published var pinned = false
    /// Algo está sendo arrastado para fora: o painel não pode sumir no meio,
    /// senão o arrasto perde a origem.
    var arrastandoParaFora = false
    /// Aberta porque um arrasto começou, e não pela borda.
    var abertaPorArrasto = false
    /// Um arrasto está passando por cima — o contorno acende.
    @Published var alvo = false
}

final class PrateleiraController {
    let state = PrateleiraEstado()
    private var panel: NSPanel!
    private let store = DockaStore.shared
    private var hideDelay: TimeInterval = 0
    private var retirada: DispatchWorkItem?
    private var currentScreen: NSScreen? = NSScreen.main
    private var contadorDoArrasto = NSPasteboard(name: .drag).changeCount

    init() { buildPanel() }

    private var edge: TrayEdge { Prateleira.edge(persisted: store.prateleiraBorda) }

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
        // depois de isFloatingPanel — ver o TrayController
        panel.level = .mainMenu
        panel.contentView = ConteinerDaPrateleira(
            estado: state,
            conteudo: NSHostingView(rootView: PrateleiraView()
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(PrateleiraModelo.shared)))
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
                               alignment: TrayAlignment(persisted: store.prateleiraAlinhamento),
                               offset: 24,
                               followDock: store.followDock,
                               extent: Prateleira.comprimento,
                               thickness: Prateleira.espessura),
            display: true)
    }

    private func telaSobOCursor() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
    }

    func tick() {
        guard store.onboarded else { return }
        let loc = NSEvent.mouseLocation
        let botaoApertado = NSEvent.pressedMouseButtons & 1 != 0

        if !state.visible, let s = telaSobOCursor(), s != currentScreen {
            currentScreen = s
            layout()
        }
        guard let screen = currentScreen else { return }
        let f = panel.frame

        // abrir ao arrastar: o contador da área de arrasto muda a cada arrasto
        let contador = NSPasteboard(name: .drag).changeCount
        let comecou = Prateleira.arrastoComecou(botaoApertado: botaoApertado,
                                                contadorAtual: contador,
                                                contadorVisto: contadorDoArrasto)
        if !botaoApertado || comecou { contadorDoArrasto = contador }

        if !state.visible {
            if comecou && store.prateleiraAoArrastar && !state.arrastandoParaFora {
                state.abertaPorArrasto = true
                reveal()
            } else if TrayGeometry.shouldReveal(cursor: loc, trayFrame: f,
                                                screenFrame: screen.frame, edge: edge,
                                                pressureZone: store.pressureZone) {
                reveal()
            }
            return
        }

        let segurar = state.pinned || state.arrastandoParaFora
            // aberta pelo arrasto: espera o arrasto acabar
            || (state.abertaPorArrasto && botaoApertado)
            || TrayGeometry.isInsideTray(cursor: loc, trayFrame: f, edge: edge)
        if segurar {
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
        PrateleiraModelo.shared.limparSumidos()
        panel.orderFrontRegardless()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                   : .spring(duration: 0.42, bounce: 0.24)) {
            state.visible = true
        }
    }

    private func hide() {
        state.pinned = false
        state.abertaPorArrasto = false
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
            currentScreen = telaSobOCursor()
            layout()
            state.pinned = true
            reveal()
        }
    }
}

// MARK: - A vista

struct PrateleiraView: View {
    @EnvironmentObject var store: DockaStore
    @EnvironmentObject var state: PrateleiraEstado
    @EnvironmentObject var modelo: PrateleiraModelo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var edge: TrayEdge { Prateleira.edge(persisted: store.prateleiraBorda) }

    var body: some View {
        conteudo
            .frame(width: Prateleira.espessura - 20, height: Prateleira.comprimento - 20)
            .dockGlass(cornerRadius: 18, tint: store.glassTint)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: state.alvo ? 2 : 0)
            )
            .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
            .offset(x: state.visible || reduceMotion ? 0 : (edge == .left ? -300 : 300))
            .opacity(state.visible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: edge == .left ? .leading : .trailing)
            .padding(edge == .left ? .leading : .trailing, 10)
            .ignoresSafeArea()
    }

    private var conteudo: some View {
        VStack(spacing: 0) {
            cabecalho
            Divider().opacity(0.5)
            if modelo.itens.isEmpty {
                vazio
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(modelo.itens) { item in
                            LinhaDaPrateleira(item: item)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var cabecalho: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(Color.accentColor)
            Text("Prateleira").font(.system(size: 13, weight: .semibold))
            if !modelo.itens.isEmpty {
                Text("\(modelo.itens.count)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !modelo.itens.isEmpty {
                // a alça leva TUDO de uma vez — soltar dez arquivos numa pasta
                // não deveria custar dez arrastos
                ArrastoDeSaida(itens: modelo.itens, estado: state) {
                    Label("Tudo", systemImage: "hand.draw")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .help("Arraste para levar todos os itens")
                Button {
                    modelo.esvaziar()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Esvaziar a prateleira")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var vazio: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("Solte arquivos, textos ou links aqui")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(10)
        )
    }
}

private struct LinhaDaPrateleira: View {
    let item: ItemDaPrateleira
    @EnvironmentObject var state: PrateleiraEstado
    @EnvironmentObject var modelo: PrateleiraModelo
    @State private var sobre = false

    var body: some View {
        HStack(spacing: 8) {
            ArrastoDeSaida(itens: [item], estado: state,
                           aoClicar: { PrateleiraModelo.abrir(item) }, preencher: true) {
                HStack(spacing: 8) {
                    icone.frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.titulo)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                        Text(item.detalhe)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                modelo.remover(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(sobre ? 1 : 0)
            .help("Tirar da prateleira")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(sobre ? 0.08 : 0)))
        .onHover { sobre = $0 }
        .contextMenu {
            Button(item.tipo == .texto ? "Copiar" : "Abrir") { PrateleiraModelo.abrir(item) }
            if item.tipo == .arquivo {
                Button("Mostrar no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.valor)])
                }
            }
            if item.tipo != .texto {
                Button("Copiar") { PrateleiraModelo.copiar(item) }
            }
            Divider()
            Button("Tirar da prateleira") { modelo.remover(item.id) }
        }
        .help(item.tipo == .texto ? "Clique para copiar; arraste para levar" : "Clique para abrir; arraste para levar")
    }

    @ViewBuilder
    private var icone: some View {
        if let img = PrateleiraModelo.icone(item) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: item.tipo == .link ? "link" : "text.alignleft")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.15)))
        }
    }
}

// MARK: - Soltar

/// O destino de soltura é a raiz do painel, em AppKit.
///
/// Ser a raiz importa: o AppKit procura quem aceita a soltura subindo a partir
/// da view sob o cursor, e as linhas (SwiftUI e as origens de arrasto) não se
/// registram para nada — então tudo sobe até aqui.
final class ConteinerDaPrateleira: NSView {
    private let estado: PrateleiraEstado

    init(estado: PrateleiraEstado, conteudo: NSView) {
        self.estado = estado
        super.init(frame: .zero)
        conteudo.autoresizingMask = [.width, .height]
        addSubview(conteudo)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Soltar de volta na própria prateleira não faz nada — senão um arrasto
    /// desistido no meio duplicaria o item no topo.
    private func aceita(_ info: NSDraggingInfo) -> Bool {
        !estado.arrastandoParaFora
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard aceita(info) else { return [] }
        estado.alvo = true
        return .copy
    }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        aceita(info) ? .copy : []
    }
    override func draggingExited(_ info: NSDraggingInfo?) { estado.alvo = false }
    override func draggingEnded(_ info: NSDraggingInfo) { estado.alvo = false }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        estado.alvo = false
        guard aceita(info) else { return false }
        return PrateleiraModelo.shared.receber(info.draggingPasteboard)
    }
}

// MARK: - Arrastar para fora

/// Origem de arrasto em AppKit, com clique.
///
/// O `.draggable` do SwiftUI leva um item só, e o "Tudo" precisa levar
/// vários numa sessão. Além disso, num painel não-ativante o gesto do SwiftUI
/// não recebe clique (ver `ArrastoAppKit`) — aqui a própria `NSView` decide
/// entre clique e arrasto.
struct ArrastoDeSaida<Conteudo: View>: NSViewRepresentable {
    let itens: [ItemDaPrateleira]
    let estado: PrateleiraEstado
    var aoClicar: (() -> Void)? = nil
    /// Ocupa a largura oferecida (as linhas) em vez da do conteúdo (a alça).
    var preencher = false
    @ViewBuilder let conteudo: () -> Conteudo

    final class V: NSView, NSDraggingSource {
        var itens: [ItemDaPrateleira] = []
        var estado: PrateleiraEstado?
        var aoClicar: (() -> Void)?
        var hospede: NSHostingView<Conteudo>?
        private var inicio: NSPoint?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        // o conteúdo SwiftUI é só desenho: os eventos são desta view
        override func hitTest(_ point: NSPoint) -> NSView? {
            frame.contains(point) ? self : nil
        }

        override func layout() {
            super.layout()
            hospede?.frame = bounds
        }

        override func mouseDown(with e: NSEvent) { inicio = e.locationInWindow }

        override func mouseDragged(with e: NSEvent) {
            guard let inicio else { return }
            let d = hypot(e.locationInWindow.x - inicio.x, e.locationInWindow.y - inicio.y)
            guard d > 4 else { return }
            self.inicio = nil
            let imagem = bitmapImageRepForCachingDisplay(in: bounds).map { rep -> NSImage in
                cacheDisplay(in: bounds, to: rep)
                let img = NSImage(size: bounds.size)
                img.addRepresentation(rep)
                return img
            }
            let itensDeArrasto = itens.enumerated().map { i, item -> NSDraggingItem in
                let d = NSDraggingItem(pasteboardWriter: PrateleiraModelo.escritor(item))
                // empilha levemente as cópias quando são várias
                let quadro = bounds.offsetBy(dx: CGFloat(i) * 3, dy: CGFloat(-i) * 3)
                d.setDraggingFrame(quadro, contents: i < 3 ? imagem : nil)
                return d
            }
            estado?.arrastandoParaFora = true
            beginDraggingSession(with: itensDeArrasto, event: e, source: self)
        }

        override func mouseUp(with e: NSEvent) {
            if inicio != nil { aoClicar?() }
            inicio = nil
        }

        func draggingSession(_ s: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // copiar é o padrão; o Finder troca para mover com ⌘, como sempre
            context == .outsideApplication ? [.copy, .move, .link, .generic] : []
        }

        func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint,
                             operation: NSDragOperation) {
            estado?.arrastandoParaFora = false
            // um arquivo MOVIDO para outra pasta não está mais onde a
            // prateleira aponta
            if operation.contains(.move) { PrateleiraModelo.shared.limparSumidos() }
        }
    }

    func makeNSView(context: Context) -> V {
        let v = V()
        let h = NSHostingView(rootView: conteudo())
        v.addSubview(h)
        v.hospede = h
        atualizar(v)
        return v
    }

    func updateNSView(_ v: V, context: Context) {
        v.hospede?.rootView = conteudo()
        atualizar(v)
    }

    private func atualizar(_ v: V) {
        v.itens = itens
        v.estado = estado
        v.aoClicar = aoClicar
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: V, context: Context) -> CGSize? {
        guard let natural = nsView.hospede?.fittingSize else { return nil }
        guard preencher, let largura = proposal.width else { return natural }
        return CGSize(width: largura, height: natural.height)
    }
}
