import AppKit
import SwiftUI
import DockaCore

final class PainelRapidoEstado: ObservableObject {
    @Published var visivel = false
    @Published var itens: [AcaoDeAtalho] = []
    @Published var selecao = 0
    @Published var colunas = 4
}

/// O painel rápido: as ferramentas favoritas numa paleta, em volta do
/// cursor. Clique, ↩ ou o número da posição escolhe; Esc ou clicar fora fecha.
final class PainelRapidoController {
    static let shared = PainelRapidoController()

    let estado = PainelRapidoEstado()
    private var panel: PainelComTeclas?
    private var observadorDeFoco: NSObjectProtocol?

    static let celula = CGSize(width: 92, height: 80)
    static let espaco: CGFloat = 8
    static let margem: CGFloat = 14

    func alternar() { estado.visivel ? fechar() : abrir() }

    func abrir() {
        let disponiveis = Set(Ferramentas.disponiveis().map(\.id))
        let ids = PainelRapido.favoritos(gravados: DockaStore.shared.painelRapidoItens) {
            disponiveis.contains($0) && $0 != AcaoDeAtalho.painelRapido.id
        }
        let itens = ids.compactMap(AcaoDeAtalho.init(id:))
        guard !itens.isEmpty else { NSSound.beep(); return }
        estado.itens = itens
        estado.selecao = 0
        estado.colunas = PainelRapido.colunas(itens.count)

        let p = panel ?? construir()
        panel = p
        let tam = Self.tamanho(itens: itens.count, colunas: estado.colunas)
        let loc = NSEvent.mouseLocation
        if let v = (NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            // em volta do cursor, sem sair da tela
            let x = min(max(loc.x - tam.width / 2, v.minX + 8), v.maxX - tam.width - 8)
            let y = min(max(loc.y - tam.height / 2, v.minY + 8), v.maxY - tam.height - 8)
            p.setFrame(NSRect(x: x, y: y, width: tam.width, height: tam.height), display: true)
        }
        p.orderFrontRegardless()
        p.makeKey()
        withAnimation(.spring(duration: 0.26, bounce: 0.2)) { estado.visivel = true }
    }

    func fechar() {
        guard estado.visivel else { return }
        withAnimation(.easeIn(duration: 0.12)) { estado.visivel = false }
        panel?.resignKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.estado.visivel else { return }
            self.panel?.orderOut(nil)
        }
    }

    func escolher(_ i: Int) {
        guard estado.itens.indices.contains(i) else { return }
        let a = estado.itens[i]
        fechar()
        Ferramentas.executar(a)
    }

    static func tamanho(itens: Int, colunas: Int) -> CGSize {
        let linhas = Int((Double(itens) / Double(colunas)).rounded(.up))
        return CGSize(width: CGFloat(colunas) * celula.width + CGFloat(colunas - 1) * espaco + margem * 2 + 16,
                      height: CGFloat(linhas) * celula.height + CGFloat(linhas - 1) * espaco + margem * 2 + 16 + 22)
    }

    private func construir() -> PainelComTeclas {
        let p = PainelComTeclas(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isFloatingPanel = true
        p.level = .mainMenu
        p.aoEsc = { [weak self] in self?.fechar() }
        p.aoTeclar = { [weak self] e in self?.tecla(e) ?? false }
        p.contentView = NSHostingView(
            rootView: PainelRapidoView(escolher: { [weak self] in self?.escolher($0) })
                .environmentObject(estado)
                .environmentObject(DockaStore.shared))
        observadorDeFoco = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak self] _ in self?.fechar() }
        return p
    }

    /// Setas andam na grade, ↩ e espaço escolhem, 1–9 escolhem pela posição.
    private func tecla(_ e: NSEvent) -> Bool {
        let n = estado.itens.count, c = estado.colunas
        switch e.keyCode {
        case 123: estado.selecao = max(0, estado.selecao - 1)
        case 124: estado.selecao = min(n - 1, estado.selecao + 1)
        case 125: if estado.selecao + c < n { estado.selecao += c }
        case 126: if estado.selecao - c >= 0 { estado.selecao -= c }
        case 36, 76, 49: escolher(estado.selecao)
        default:
            guard let ch = e.charactersIgnoringModifiers?.first, let d = ch.wholeNumberValue,
                  (1...9).contains(d) else { return false }
            escolher(d - 1)
        }
        return true
    }
}

/// Painel que entrega as teclas a quem o abriu — sem campo de texto, ninguém
/// mais as receberia.
final class PainelComTeclas: PainelDeNotas {
    var aoTeclar: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if aoTeclar?(event) != true { super.keyDown(with: event) }
    }
}

struct PainelRapidoView: View {
    let escolher: (Int) -> Void
    @EnvironmentObject var estado: PainelRapidoEstado
    @EnvironmentObject var store: DockaStore

    var body: some View {
        let colunas = Array(repeating: GridItem(.fixed(PainelRapidoController.celula.width),
                                                spacing: PainelRapidoController.espaco), count: estado.colunas)
        VStack(spacing: 8) {
            Text("PAINEL RÁPIDO")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 14)
            LazyVGrid(columns: colunas, spacing: PainelRapidoController.espaco) {
                ForEach(Array(estado.itens.enumerated()), id: \.element.id) { i, a in
                    Button { escolher(i) } label: { celula(a, i) }
                        .buttonStyle(.plain)
                        .help(Ferramentas.titulo(a))
                }
            }
        }
        .padding(PainelRapidoController.margem)
        .dockGlass(cornerRadius: 20, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .scaleEffect(estado.visivel ? 1 : 0.92)
        .opacity(estado.visivel ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func celula(_ a: AcaoDeAtalho, _ i: Int) -> some View {
        let ligada = Ferramentas.ligada(a) == true
        let selecionada = i == estado.selecao
        return VStack(spacing: 6) {
            Image(systemName: Ferramentas.simbolo(a))
                .font(.system(size: 18))
                .foregroundStyle(ligada ? Color.accentColor : Color.primary)
                .frame(height: 22)
            Text(Ferramentas.titulo(a))
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .frame(width: PainelRapidoController.celula.width, height: PainelRapidoController.celula.height)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(ligada ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: selecionada ? 2 : 0))
        .overlay(alignment: .topLeading) {
            if i < 9 {
                Text("\(i + 1)").font(.system(size: 8.5, weight: .medium)).opacity(0.4).padding(6)
            }
        }
        .contentShape(Rectangle())
    }
}
