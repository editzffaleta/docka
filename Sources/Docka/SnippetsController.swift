import SwiftUI
import AppKit
import DockaCore

// MARK: - Os snippets

/// Os snippets, num arquivo próprio em Application Support.
final class SnippetsModelo: ObservableObject {
    static let shared = SnippetsModelo()

    @Published var lista: [Snippet] = [] {
        didSet {
            gravar()
            // o tap dos gatilhos só existe se algum snippet tem gatilho
            GatilhosController.shared.sincronizar()
        }
    }

    static var arquivo: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Docka", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    private init() {
        if let dados = try? Data(contentsOf: Self.arquivo),
           let lidos = try? JSONDecoder().decode([Snippet].self, from: dados) {
            lista = lidos
        } else {
            // primeira vez: exemplos que mostram as variáveis funcionando
            lista = Snippets.exemplos
        }
    }

    func novo() -> Snippet {
        let s = Snippet(nome: "Novo snippet", texto: "")
        lista.append(s)
        return s
    }

    func remover(_ id: UUID) { lista.removeAll { $0.id == id } }

    private func gravar() {
        guard let json = try? JSONEncoder().encode(lista) else { return }
        let url = Self.arquivo
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? json.write(to: url, options: .atomic)
    }

    /// O texto final, com as variáveis trocadas na hora de inserir.
    static func expandido(_ s: Snippet) -> String {
        Snippets.expandir(s.texto, agora: Date(),
                          clipboard: NSPasteboard.general.string(forType: .string))
    }
}

// MARK: - O painel

final class SnippetsEstado: ObservableObject {
    @Published var visivel = false
    @Published var busca = ""
    @Published var selecao = 0
    @Published var pedidoDeFoco = 0
}

/// Mesmo jeito do histórico: abre no meio da tela, recebe o teclado sem
/// ativar o Docka e some ao escolher, no Esc ou ao clicar fora.
final class SnippetsController {
    static let shared = SnippetsController()

    private var panel: PainelDeNotas?
    let estado = SnippetsEstado()
    private var observadorDeFoco: NSObjectProtocol?

    static let largura: CGFloat = 460
    static let altura: CGFloat = 380

    func alternar() { estado.visivel ? fechar() : abrir() }

    private func construir() -> PainelDeNotas {
        let p = PainelDeNotas(contentRect: NSRect(x: 0, y: 0, width: Self.largura, height: Self.altura),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isFloatingPanel = true
        p.level = .mainMenu
        p.aoEsc = { [weak self] in self?.fechar() }
        p.contentView = NSHostingView(
            rootView: SnippetsView(escolher: { [weak self] in self?.escolher($0) })
                .environmentObject(estado)
                .environmentObject(SnippetsModelo.shared)
                .environmentObject(DockaStore.shared))
        observadorDeFoco = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak self] _ in self?.fechar() }
        return p
    }

    func abrir() {
        let p = panel ?? construir()
        panel = p
        let loc = NSEvent.mouseLocation
        if let v = (NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            p.setFrame(NSRect(x: v.midX - Self.largura / 2, y: v.midY - Self.altura / 2 + v.height * 0.1,
                              width: Self.largura, height: Self.altura), display: true)
        }
        estado.busca = ""
        estado.selecao = 0
        p.orderFrontRegardless()
        p.makeKey()
        withAnimation(.spring(duration: 0.28, bounce: 0.15)) { estado.visivel = true }
        estado.pedidoDeFoco += 1
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

    private func escolher(_ s: Snippet) {
        let texto = SnippetsModelo.expandido(s)   // antes de mexer na área de transferência
        DockaStore.shared.playSound("Tink", volume: 0.3)
        fechar()
        Colagem.inserir(texto)
    }
}

struct SnippetsView: View {
    let escolher: (Snippet) -> Void
    @EnvironmentObject var estado: SnippetsEstado
    @EnvironmentObject var modelo: SnippetsModelo
    @EnvironmentObject var store: DockaStore
    @FocusState private var focado: Bool

    private var lista: [Snippet] { Snippets.buscar(estado.busca, em: modelo.lista) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.plus").foregroundStyle(.secondary)
                TextField("Buscar snippet", text: $estado.busca)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focado)
                    .onSubmit {
                        if lista.indices.contains(estado.selecao) { escolher(lista[estado.selecao]) }
                    }
                    .onChange(of: estado.busca) { _, _ in estado.selecao = 0 }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().opacity(0.5)

            if lista.isEmpty {
                Text(modelo.lista.isEmpty ? "Nenhum snippet — crie nos ajustes." : "Nada encontrado.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(lista.enumerated()), id: \.element.id) { i, s in
                            Button { escolher(s) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.nome).font(.system(size: 12, weight: .semibold))
                                    Text(SnippetsModelo.expandido(s))
                                        .font(.system(size: 11))
                                        .lineLimit(2)
                                        .opacity(0.75)
                                }
                                .foregroundStyle(i == estado.selecao ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(i == estado.selecao ? Color.accentColor : Color.clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }
            Divider().opacity(0.5)
            Text(Colagem.podeColar ? "↩ insere no app da frente  ·  esc fecha"
                                   : "↩ copia — depois é só ⌘V  ·  esc fecha")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: SnippetsController.largura - 16, height: SnippetsController.altura - 16)
        .dockGlass(cornerRadius: 16, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .scaleEffect(estado.visivel ? 1 : 0.96)
        .opacity(estado.visivel ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onKeyPress(.downArrow) {
            estado.selecao = min(estado.selecao + 1, max(lista.count - 1, 0)); return .handled
        }
        .onKeyPress(.upArrow) { estado.selecao = max(estado.selecao - 1, 0); return .handled }
        .onChange(of: estado.pedidoDeFoco) { _, _ in focado = true }
    }
}
