import SwiftUI
import AppKit
import DockaCore

// MARK: - O histórico

/// Acompanha a área de transferência e guarda o histórico.
///
/// Ler o pasteboard não pede permissão. O vigia olha só o `changeCount` a
/// cada meio segundo — um número inteiro, sem tocar no conteúdo — e lê o
/// conteúdo apenas quando ele muda.
final class HistoricoModelo: ObservableObject {
    static let shared = HistoricoModelo()

    @Published private(set) var itens: [ItemCopiado] = []

    private let pb = NSPasteboard.general
    private var visto: Int
    private var relogio: Timer?
    private var gravacao: DispatchWorkItem?
    private var apagarEm: Date?
    private let store = DockaStore.shared

    static var arquivo: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Docka", isDirectory: true)
            .appendingPathComponent("historico.json")
    }

    private init() {
        visto = NSPasteboard.general.changeCount
        if let dados = try? Data(contentsOf: Self.arquivo),
           let lidos = try? JSONDecoder().decode([ItemCopiado].self, from: dados) {
            itens = lidos
        }
    }

    /// Liga ou desliga o vigia. Desligado, nada roda.
    func ligar(_ sim: Bool) {
        if sim, relogio == nil {
            visto = pb.changeCount   // o que já estava copiado não entra
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.olhar() }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            relogio = t
        } else if !sim {
            relogio?.invalidate()
            relogio = nil
        }
    }

    private func olhar() {
        if let quando = apagarEm, Date() >= quando {
            apagarEm = nil
            // só apaga se o conteúdo ainda for o mesmo: copiou outra coisa
            // no meio, o relógio recomeça por ela
            if pb.changeCount == visto { pb.clearContents(); visto = pb.changeCount }
        }
        guard pb.changeCount != visto else { return }
        visto = pb.changeCount
        agendarApagar()

        let tipos = (pb.types ?? []).map(\.rawValue)
        guard !HistoricoDeCopias.deveIgnorar(tipos: tipos) else { return }

        if store.limparLinksAoCopiar, let s = pb.string(forType: .string),
           let limpo = LimparLink.limpar(s) {
            escrever(limpo)
        }

        guard store.historicoControl, let novo = lerAtual() else { return }
        itens = HistoricoDeCopias.registrar(novo, em: itens, limite: store.historicoLimite)
        agendarGravacao()
    }

    private func agendarApagar() {
        let opcao = ApagarClipboard(persisted: store.apagarClipboard)
        apagarEm = opcao == .nunca ? nil : Date().addingTimeInterval(TimeInterval(opcao.rawValue))
    }

    private func lerAtual() -> ItemCopiado? { Self.item(em: pb) }

    /// O que está numa área de transferência, como item do histórico.
    /// Estático e com o pasteboard de parâmetro: o autoteste usa um privado,
    /// sem tocar no que a pessoa copiou.
    static func item(em pb: NSPasteboard) -> ItemCopiado? {
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return ItemCopiado(tipo: .arquivos, valor: urls.map(\.path).joined(separator: "\n"))
        }
        if let s = pb.string(forType: .string) { return HistoricoDeCopias.item(deTexto: s) }
        return nil
    }

    /// Confere leitura, sigilo, texto puro e limpeza de link num pasteboard
    /// PRIVADO — a área de transferência da pessoa não é tocada.
    static func autoteste() -> String {
        let pb = NSPasteboard(name: NSPasteboard.Name("docka.autoteste.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        var r: [String] = []
        func conferir(_ nome: String, _ ok: Bool) { r.append("\(ok ? "OK" : "FALHOU") — \(nome)") }

        pb.clearContents(); pb.setString("olá, mundo", forType: .string)
        conferir("texto lido como texto", item(em: pb)?.tipo == .texto)

        pb.clearContents(); pb.setString("https://apple.com/mac", forType: .string)
        conferir("endereço lido como link", item(em: pb)?.tipo == .link)

        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/Applications") as NSURL,
                         URL(fileURLWithPath: "/System") as NSURL])
        conferir("dois arquivos lidos como arquivos",
                 item(em: pb)?.caminhos == ["/Applications", "/System"])

        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("senha123", forType: .string)
        conferir("senha marcada como sigilosa é ignorada",
                 HistoricoDeCopias.deveIgnorar(tipos: (pb.types ?? []).map(\.rawValue)))

        pb.clearContents()
        let rico = NSAttributedString(string: "negrito", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        pb.writeObjects([rico])
        let tinhaRTF = pb.types?.contains(.rtf) ?? false
        if let s = pb.string(forType: .string) { pb.clearContents(); pb.setString(s, forType: .string) }
        conferir("texto rico vira só texto (tinha RTF: \(tinhaRTF))",
                 // o macOS lista também o nome antigo do tipo texto; o que
                 // importa é a formatação (RTF) ter sumido
                 tinhaRTF && pb.data(forType: .rtf) == nil && pb.string(forType: .string) == "negrito")

        let sujo = "https://site.com/p?id=7&utm_source=news&fbclid=abc"
        conferir("link limpo", LimparLink.limpar(sujo) == "https://site.com/p?id=7")
        return r.joined(separator: "\n")
    }

    // MARK: escrever

    /// Escreve texto puro e marca como visto: o que o próprio Docka põe na
    /// área de transferência não entra de novo no histórico como novidade.
    private func escrever(_ texto: String) {
        pb.clearContents()
        pb.setString(texto, forType: .string)
        visto = pb.changeCount
    }

    /// Devolve um item à área de transferência, pronto para ⌘V, e o sobe
    /// para o topo do histórico.
    func copiar(_ item: ItemCopiado) {
        pb.clearContents()
        if item.tipo == .arquivos {
            pb.writeObjects(item.caminhos.map { URL(fileURLWithPath: $0) as NSURL })
        } else {
            pb.setString(item.valor, forType: .string)
        }
        visto = pb.changeCount
        itens = HistoricoDeCopias.registrar(item, em: itens, limite: store.historicoLimite)
        agendarApagar()
        agendarGravacao()
    }

    /// Troca o que está copiado pela versão sem formatação: negrito, cores e
    /// fontes ficam para trás, o texto vai.
    @discardableResult
    func soTexto() -> Bool {
        guard let s = pb.string(forType: .string) else { NSSound.beep(); return false }
        escrever(s)
        return true
    }

    /// Tira os rastreadores do link copiado.
    @discardableResult
    func limparLinkCopiado() -> Bool {
        guard let s = pb.string(forType: .string), let limpo = LimparLink.limpar(s) else {
            NSSound.beep(); return false
        }
        escrever(limpo)
        return true
    }

    func alternarFixado(_ id: UUID) {
        guard let i = itens.firstIndex(where: { $0.id == id }) else { return }
        itens[i].fixado.toggle()
        agendarGravacao()
    }

    func remover(_ id: UUID) {
        itens.removeAll { $0.id == id }
        agendarGravacao()
    }

    /// Apaga tudo menos os fixados.
    func apagarHistorico() {
        itens.removeAll { !$0.fixado }
        agendarGravacao()
    }

    // MARK: gravar

    private func agendarGravacao() {
        gravacao?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.gravarAgora() }
        gravacao = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    /// Só grava em disco se a pessoa quer o histórico entre aberturas; sem
    /// isso, apaga o arquivo — o histórico vive só na memória.
    func gravarAgora() {
        gravacao?.cancel()
        gravacao = nil
        let url = Self.arquivo
        guard store.historicoLembrar else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let json = try? JSONEncoder().encode(itens) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? json.write(to: url, options: .atomic)
    }
}

// MARK: - O painel do histórico

final class HistoricoEstado: ObservableObject {
    @Published var visivel = false
    @Published var busca = ""
    @Published var selecao = 0
    @Published var pedidoDeFoco = 0
}

/// Abre no meio da tela onde está o cursor, recebe o teclado sem ativar o
/// Docka (como o bloco de notas) e some ao escolher, no Esc ou ao clicar fora.
final class HistoricoController {
    static let shared = HistoricoController()

    private var panel: PainelDeNotas?
    let estado = HistoricoEstado()
    private var observadorDeFoco: NSObjectProtocol?

    static let largura: CGFloat = 460
    static let altura: CGFloat = 420

    func alternar() {
        if estado.visivel { fechar() } else { abrir() }
    }

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
            rootView: HistoricoView(escolher: { [weak self] in self?.escolher($0) },
                                    fechar: { [weak self] in self?.fechar() })
                .environmentObject(estado)
                .environmentObject(HistoricoModelo.shared)
                .environmentObject(DockaStore.shared))
        // clicou em outro app: o histórico some, como um menu
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

    private func escolher(_ item: ItemCopiado) {
        HistoricoModelo.shared.copiar(item)
        DockaStore.shared.playSound("Tink", volume: 0.3)
        fechar()
        // com o módulo de colar ligado e permitido, vai direto para o app
        Colagem.colarSePuder()
    }
}

struct HistoricoView: View {
    let escolher: (ItemCopiado) -> Void
    let fechar: () -> Void
    @EnvironmentObject var estado: HistoricoEstado
    @EnvironmentObject var modelo: HistoricoModelo
    @EnvironmentObject var store: DockaStore
    @FocusState private var focado: Bool

    private var lista: [ItemCopiado] {
        HistoricoDeCopias.ordenados(HistoricoDeCopias.buscar(estado.busca, em: modelo.itens))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar no que você copiou", text: $estado.busca)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focado)
                    .onSubmit { escolherSelecionado() }
                    .onChange(of: estado.busca) { _, _ in estado.selecao = 0 }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().opacity(0.5)

            if lista.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(modelo.itens.isEmpty ? "Nada copiado ainda." : "Nada encontrado.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { rolar in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(lista.enumerated()), id: \.element.id) { i, item in
                                LinhaDoHistorico(item: item, selecionada: i == estado.selecao,
                                                 escolher: { escolher(item) })
                                    .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: estado.selecao) { _, novo in
                        if lista.indices.contains(novo) { rolar.scrollTo(lista[novo].id) }
                    }
                }
            }
            Divider().opacity(0.5)
            HStack {
                Text("↩ copia  ·  ↑↓ escolhe  ·  esc fecha")
                Spacer()
                Text("\(modelo.itens.count) \(modelo.itens.count == 1 ? "item" : "itens")")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: HistoricoController.largura - 16, height: HistoricoController.altura - 16)
        .dockGlass(cornerRadius: 16, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .scaleEffect(estado.visivel ? 1 : 0.96)
        .opacity(estado.visivel ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onKeyPress(.downArrow) { mover(1); return .handled }
        .onKeyPress(.upArrow) { mover(-1); return .handled }
        .onChange(of: estado.pedidoDeFoco) { _, _ in focado = true }
    }

    private func mover(_ passo: Int) {
        guard !lista.isEmpty else { return }
        estado.selecao = min(max(estado.selecao + passo, 0), lista.count - 1)
    }

    private func escolherSelecionado() {
        guard lista.indices.contains(estado.selecao) else { return }
        escolher(lista[estado.selecao])
    }
}

private struct LinhaDoHistorico: View {
    let item: ItemCopiado
    let selecionada: Bool
    let escolher: () -> Void
    @EnvironmentObject var modelo: HistoricoModelo

    var body: some View {
        HStack(spacing: 8) {
            // Button: num painel não-ativante gesto cru não recebe clique
            Button(action: escolher) {
                HStack(spacing: 10) {
                    Image(systemName: simbolo)
                        .frame(width: 18)
                        .foregroundStyle(selecionada ? Color.white : Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.resumo)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .foregroundStyle(selecionada ? Color.white : Color.primary)
                        Text(item.copiadoEm, format: .relative(presentation: .named))
                            .font(.system(size: 10))
                            .foregroundStyle(selecionada ? Color.white.opacity(0.8) : Color.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { modelo.alternarFixado(item.id) } label: {
                Image(systemName: item.fixado ? "pin.fill" : "pin")
                    .foregroundStyle(selecionada ? Color.white : (item.fixado ? Color.accentColor : Color.secondary))
            }
            .buttonStyle(.plain)
            .help(item.fixado ? "Desafixar" : "Fixar no topo")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selecionada ? Color.accentColor : Color.clear))
        .contextMenu {
            Button("Copiar") { escolher() }
            Button(item.fixado ? "Desafixar" : "Fixar no topo") { modelo.alternarFixado(item.id) }
            Divider()
            Button("Apagar do histórico") { modelo.remover(item.id) }
        }
    }

    private var simbolo: String {
        switch item.tipo {
        case .texto:    return "text.alignleft"
        case .link:     return "link"
        case .arquivos: return "doc"
        }
    }
}
