import AppKit
import SwiftUI
import DockaCore

/// Uma linha da barra: o que mostrar e o que fazer ao escolher.
struct ItemDaBarra: Identifiable {
    enum Icone {
        case simbolo(String)
        /// O ícone do Finder para este caminho (app, pasta, arquivo).
        case arquivo(String)
        case imagem(NSImage)
        /// Um emoji desenhado como ícone.
        case texto(String)
    }

    let candidato: BarraDeComando.Candidato
    var id: String { candidato.id }
    let icone: Icone
    var atalho: String? = nil
    let executar: () -> Void
}

final class BarraEstado: ObservableObject {
    @Published var visivel = false
    @Published var busca = ""
    @Published var selecao = 0
    @Published var itens: [ItemDaBarra] = []
    @Published var pedidoDeFoco = 0
}

/// A barra de comando: abre no meio da tela, recebe o teclado sem ativar o
/// Docka (o app da frente continua na frente, e os menus dele continuam
/// sendo os que valem) e some ao escolher, no Esc ou ao clicar fora.
final class BarraDeComandoController {
    static let shared = BarraDeComandoController()

    let estado = BarraEstado()
    private var panel: PainelDeNotas?
    private var observadorDeFoco: NSObjectProtocol?
    private var store: DockaStore { .shared }

    /// Lidos ao abrir: o que muda pouco enquanto a barra está aberta.
    private var fixos: [ItemDaBarra] = []
    /// Os comandos de menu do app da frente, lidos em segundo plano.
    private var menus: [ItemDaBarra] = []
    private var arquivos: [ItemDaBarra] = []
    private var consulta: NSMetadataQuery?
    private var observadorDaConsulta: NSObjectProtocol?
    private var buscaDeArquivos: DispatchWorkItem?
    private var appDaFrente: NSRunningApplication?
    private var leituraDosMenus = 0

    private var apps: [(nome: String, caminho: String)] = []
    private var appsLidosEm: Date?

    static let largura: CGFloat = 640
    static let altura: CGFloat = 440

    func alternar() { estado.visivel ? fechar() : abrir() }

    // MARK: abrir e fechar

    func abrir() {
        let p = panel ?? construir()
        panel = p
        let frente = NSWorkspace.shared.frontmostApplication
        appDaFrente = frente?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frente
        fixos = lerFixos()
        menus = []
        arquivos = []
        lerMenus()

        let loc = NSEvent.mouseLocation
        if let v = (NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            p.setFrame(NSRect(x: v.midX - Self.largura / 2, y: v.midY - Self.altura / 2 + v.height * 0.1,
                              width: Self.largura, height: Self.altura), display: true)
        }
        estado.busca = ""
        estado.selecao = 0
        estado.itens = []
        p.orderFrontRegardless()
        p.makeKey()
        withAnimation(.spring(duration: 0.28, bounce: 0.15)) { estado.visivel = true }
        estado.pedidoDeFoco += 1
        // o foco do SwiftUI não chega sozinho num painel que não ativa o
        // Docka (na primeira abertura o onChange nem dispara): entrega o
        // campo ao painel pelo AppKit, depois do layout
        DispatchQueue.main.async { [weak p] in
            guard let p, let campo = Self.campo(em: p.contentView) else { return }
            p.makeFirstResponder(campo)
        }
    }

    private static func campo(em v: NSView?) -> NSTextField? {
        guard let v else { return nil }
        if let t = v as? NSTextField, t.isEditable { return t }
        for f in v.subviews { if let t = campo(em: f) { return t } }
        return nil
    }

    func fechar() {
        guard estado.visivel else { return }
        pararConsulta()
        withAnimation(.easeIn(duration: 0.12)) { estado.visivel = false }
        panel?.resignKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.estado.visivel else { return }
            self.panel?.orderOut(nil)
        }
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
            rootView: BarraDeComandoView(buscou: { [weak self] in self?.buscou($0) },
                                         escolher: { [weak self] in self?.escolher($0) })
                .environmentObject(estado)
                .environmentObject(DockaStore.shared))
        observadorDeFoco = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: p, queue: .main
        ) { [weak self] _ in self?.fechar() }
        return p
    }

    // MARK: buscar

    func buscou(_ termo: String) {
        estado.selecao = 0
        recalcular()
        buscaDeArquivos?.cancel()
        let t = termo.trimmingCharacters(in: .whitespaces)
        guard store.barraArquivos, t.count >= 2,
              Calculadora.avaliar(t) == nil, Conversao.converter(t) == nil else {
            pararConsulta()
            if !arquivos.isEmpty { arquivos = []; recalcular() }
            return
        }
        // espera a pessoa parar de digitar: cada letra seria uma busca no disco
        let item = DispatchWorkItem { [weak self] in self?.buscarArquivos(t) }
        buscaDeArquivos = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func recalcular() {
        let termo = estado.busca
        guard !termo.trimmingCharacters(in: .whitespaces).isEmpty else {
            estado.itens = []
            estado.selecao = 0
            return
        }
        let todos = dinamicos(termo) + fixos + menus + arquivos
        let porId = Dictionary(todos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // menus e arquivos chegam depois: a escolha feita com as setas fica
        let escolhido = estado.itens.indices.contains(estado.selecao) && estado.selecao > 0
            ? estado.itens[estado.selecao].id : nil
        estado.itens = BarraDeComando.ordenar(todos.map(\.candidato), termo: termo).compactMap { porId[$0.id] }
        estado.selecao = escolhido.flatMap { id in estado.itens.firstIndex { $0.id == id } } ?? 0
    }

    func escolher(_ indice: Int?) {
        let i = indice ?? estado.selecao
        guard estado.itens.indices.contains(i) else { return }
        let item = estado.itens[i]
        fechar()
        item.executar()
    }

    // MARK: as fontes

    private func lerFixos() -> [ItemDaBarra] {
        var lista: [ItemDaBarra] = []
        typealias C = BarraDeComando.Candidato

        for app in listaDeApps() {
            lista.append(ItemDaBarra(candidato: C(id: "app:\(app.caminho)", tipo: .app, titulo: app.nome),
                                     icone: .arquivo(app.caminho)) {
                let c = NSWorkspace.OpenConfiguration()
                c.activates = true
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.caminho), configuration: c,
                                                   completionHandler: nil)
            })
        }

        if Colagem.permitido { lista += lerJanelas() }

        for a in Ferramentas.disponiveis() where a != .barraDeComando {
            let r: AcaoRapida? = { if case .rapida(let r) = a { return r }; return nil }()
            lista.append(ItemDaBarra(candidato: C(id: "acao:\(a.id)", tipo: .acao, titulo: Ferramentas.titulo(a),
                                                  detalhe: r?.descricao ?? "",
                                                  palavras: "docka " + (r?.titulo ?? "")),
                                     icone: .simbolo(Ferramentas.simbolo(a)),
                                     atalho: store.atalho(de: a)?.display) {
                Ferramentas.executar(a)
            })
        }

        if store.historicoControl {
            for item in HistoricoModelo.shared.itens.prefix(60) {
                let linha = item.valor.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.valor
                let simbolo = item.tipo == .link ? "link" : (item.tipo == .arquivos ? "doc.on.doc" : "doc.on.clipboard")
                lista.append(ItemDaBarra(candidato: C(id: "copiado:\(item.id)", tipo: .historico,
                                                      titulo: String(linha.prefix(90)), palavras: item.valor),
                                         icone: .simbolo(simbolo)) {
                    HistoricoModelo.shared.copiar(item)
                    Colagem.colarSePuder()
                })
            }
        }

        for s in SnippetsModelo.shared.lista {
            let texto = SnippetsModelo.expandido(s)
            lista.append(ItemDaBarra(candidato: C(id: "snippet:\(s.id)", tipo: .snippet, titulo: s.nome,
                                                  detalhe: texto.split(whereSeparator: \.isNewline).first.map(String.init) ?? "",
                                                  palavras: s.texto + " " + s.gatilho),
                                     icone: .simbolo("text.badge.plus"), atalho: s.gatilho.isEmpty ? nil : s.gatilho) {
                Colagem.inserir(texto)
            })
        }

        for s in store.scripts {
            lista.append(ItemDaBarra(candidato: C(id: "script:\(s.id)", tipo: .script, titulo: s.nome,
                                                  detalhe: s.comando, palavras: "script " + s.comando),
                                     icone: .simbolo("terminal")) { [weak self] in
                self?.rodar(s)
            })
        }
        return lista
    }

    /// Contas, conversões e emoji: dependem só do que foi digitado.
    private func dinamicos(_ termo: String) -> [ItemDaBarra] {
        typealias C = BarraDeComando.Candidato
        var lista: [ItemDaBarra] = []
        if let c = Calculadora.avaliar(termo) {
            lista.append(ItemDaBarra(candidato: C(id: "conta", tipo: .resultado, titulo: "= \(c.texto)",
                                                  detalhe: "↩ copia o resultado"),
                                     icone: .simbolo("equal.square")) { Self.copiar(c.copia) })
        }
        if let r = Conversao.converter(termo) {
            lista.append(ItemDaBarra(candidato: C(id: "conversao", tipo: .resultado, titulo: r.texto,
                                                  detalhe: "↩ copia o valor"),
                                     icone: .simbolo("arrow.left.arrow.right.square")) { Self.copiar(r.copia) })
        }
        for e in Emojis.buscar(termo) {
            let nome = e.nome.prefix(1).uppercased() + e.nome.dropFirst()
            lista.append(ItemDaBarra(candidato: C(id: "emoji:\(e.caractere)", tipo: .emoji, titulo: nome),
                                     icone: .texto(e.caractere)) { Colagem.inserir(e.caractere) })
        }
        return lista
    }

    private static func copiar(_ texto: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texto, forType: .string)
        DockaStore.shared.playSound("Tink", volume: 0.3)
        DicaDeTecla.shared.mostrar("Copiado: \(texto)", progresso: nil)
    }

    // MARK: apps

    /// As pastas de apps, um nível (e as Utilidades). Relido a cada minuto,
    /// no máximo: um app instalado agora aparece na próxima abertura.
    private func listaDeApps() -> [(nome: String, caminho: String)] {
        if let t = appsLidosEm, Date().timeIntervalSince(t) < 60 { return apps }
        let fm = FileManager.default
        let pastas = ["/Applications", "/Applications/Utilities", "/System/Applications",
                      "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var vistos = Set<String>()
        var lista: [(nome: String, caminho: String)] = []
        for pasta in pastas {
            for nome in (try? fm.contentsOfDirectory(atPath: pasta)) ?? [] where nome.hasSuffix(".app") {
                let caminho = pasta + "/" + nome
                guard vistos.insert(caminho).inserted else { continue }
                var exibido = fm.displayName(atPath: caminho)
                if exibido.hasSuffix(".app") { exibido.removeLast(4) }
                lista.append((exibido, caminho))
            }
        }
        lista.append(("Finder", "/System/Library/CoreServices/Finder.app"))
        apps = lista
        appsLidosEm = Date()
        return lista
    }

    // MARK: janelas

    /// As janelas abertas, pela Acessibilidade — o título vem junto.
    private func lerJanelas() -> [ItemDaBarra] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        var lista: [ItemDaBarra] = []
        for app in apps {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 0.3)
            guard let janelas: [AXUIElement] = Self.valor(el, kAXWindowsAttribute) else { continue }
            let nomeDoApp = app.localizedName ?? ""
            for (i, w) in janelas.enumerated() {
                guard Self.valor(w, kAXSubroleAttribute) as String? == kAXStandardWindowSubrole as String,
                      let titulo: String = Self.valor(w, kAXTitleAttribute), !titulo.isEmpty else { continue }
                let c = BarraDeComando.Candidato(id: "janela:\(app.processIdentifier):\(i)", tipo: .janela,
                                                 titulo: titulo, detalhe: nomeDoApp, palavras: nomeDoApp)
                lista.append(ItemDaBarra(candidato: c, icone: app.icon.map { .imagem($0) } ?? .simbolo("macwindow")) {
                    AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                    // pelo LaunchServices, como o Dock: o activate() de um app
                    // em segundo plano pode ser recusado
                    if let url = app.bundleURL {
                        let conf = NSWorkspace.OpenConfiguration()
                        conf.activates = true
                        NSWorkspace.shared.openApplication(at: url, configuration: conf, completionHandler: nil)
                    } else {
                        app.activate()
                    }
                })
            }
        }
        return lista
    }

    static func valor<T>(_ el: AXUIElement, _ atributo: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, atributo as CFString, &v) == .success else { return nil }
        return v as? T
    }

    // MARK: menus do app da frente

    /// Percorre a barra de menus do app da frente fora da main thread: um app
    /// com menus grandes leva um instante para responder.
    private func lerMenus() {
        guard store.barraMenus, Colagem.permitido, let app = appDaFrente else { return }
        leituraDosMenus += 1
        let leitura = leituraDosMenus
        let nomeDoApp = app.localizedName ?? ""
        let icone = app.icon
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let achados = Self.comandos(de: app.processIdentifier)
            DispatchQueue.main.async {
                guard let self, self.leituraDosMenus == leitura, self.estado.visivel else { return }
                self.menus = achados.enumerated().map { i, m in
                    let c = BarraDeComando.Candidato(
                        id: "menu:\(i)", tipo: .menu, titulo: m.caminho.last ?? "",
                        detalhe: BarraDeComando.caminhoDoMenu([nomeDoApp] + m.caminho.dropLast()),
                        palavras: m.caminho.joined(separator: " "))
                    return ItemDaBarra(candidato: c, icone: icone.map { .imagem($0) } ?? .simbolo("filemenu.and.selection"),
                                       atalho: m.atalho) {
                        AXUIElementPerformAction(m.elemento, kAXPressAction as CFString)
                    }
                }
                self.recalcular()
            }
        }
    }

    private static func comandos(de pid: pid_t, limite: Int = 1500)
        -> [(caminho: [String], atalho: String?, elemento: AXUIElement)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let barra: AXUIElement = valor(app, kAXMenuBarAttribute) else { return [] }
        var saida: [(caminho: [String], atalho: String?, elemento: AXUIElement)] = []

        func andar(_ el: AXUIElement, _ caminho: [String], _ profundidade: Int) {
            guard saida.count < limite, profundidade < 5 else { return }
            for f in (valor(el, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
                let papel: String = valor(f, kAXRoleAttribute) ?? ""
                if papel == kAXMenuRole as String { andar(f, caminho, profundidade + 1); continue }
                guard papel == kAXMenuItemRole as String,
                      let titulo: String = valor(f, kAXTitleAttribute), !titulo.isEmpty else { continue }
                let filhos: [AXUIElement] = valor(f, kAXChildrenAttribute) ?? []
                if !filhos.isEmpty {
                    andar(f, caminho + [titulo], profundidade + 1)
                } else if (valor(f, kAXEnabledAttribute) as Bool?) ?? true {
                    let atalho = BarraDeComando.atalhoDoMenu(
                        tecla: valor(f, kAXMenuItemCmdCharAttribute),
                        modificadores: (valor(f, kAXMenuItemCmdModifiersAttribute) as NSNumber?)?.intValue ?? 0)
                    saida.append((caminho + [titulo], atalho, f))
                }
            }
        }

        let topo: [AXUIElement] = valor(barra, kAXChildrenAttribute) ?? []
        // o primeiro é o menu da Apple: Desligar e Reiniciar não são deste app
        for item in topo.dropFirst() {
            andar(item, [valor(item, kAXTitleAttribute) ?? ""], 0)
        }
        return saida
    }

    // MARK: arquivos

    /// Pelo Spotlight, só na pasta pessoal, os usados por último primeiro.
    private func buscarArquivos(_ termo: String) {
        pararConsulta()
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, termo)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        observadorDaConsulta = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
        ) { [weak self] _ in self?.recebeuArquivos(q) }
        consulta = q
        q.start()
    }

    private func recebeuArquivos(_ q: NSMetadataQuery) {
        q.disableUpdates()
        let casa = NSHomeDirectory()
        var lista: [ItemDaBarra] = []
        for i in 0..<min(q.resultCount, 400) where lista.count < 30 {
            guard let r = q.result(at: i) as? NSMetadataItem,
                  let caminho = r.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !caminho.hasSuffix(".app"),
                  BarraDeComando.arquivoRelevante(caminho, casa: casa) else { continue }
            let nome = (caminho as NSString).lastPathComponent
            var pasta = (caminho as NSString).deletingLastPathComponent
            if pasta.hasPrefix(casa) { pasta = "~" + pasta.dropFirst(casa.count) }
            let c = BarraDeComando.Candidato(id: "arquivo:\(caminho)", tipo: .arquivo, titulo: nome, detalhe: pasta)
            lista.append(ItemDaBarra(candidato: c, icone: .arquivo(caminho)) {
                let url = URL(fileURLWithPath: caminho)
                // ⌘↩ mostra no Finder em vez de abrir
                if NSEvent.modifierFlags.contains(.command) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(url)
                }
            })
        }
        pararConsulta()
        arquivos = lista
        recalcular()
    }

    private func pararConsulta() {
        consulta?.stop()
        consulta = nil
        if let o = observadorDaConsulta { NotificationCenter.default.removeObserver(o) }
        observadorDaConsulta = nil
    }

    // MARK: scripts

    /// Roda no shell de login (o PATH do Terminal, com o Homebrew), fora da
    /// main thread, e mostra a primeira linha do que ele disse.
    private func rodar(_ s: ScriptSalvo) {
        DicaDeTecla.shared.mostrar("Rodando \(s.nome)…", progresso: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", s.comando]
            p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
            let saida = Pipe()
            p.standardOutput = saida
            p.standardError = saida
            p.standardInput = FileHandle.nullDevice
            var resumo: String
            do {
                try p.run()
                let dados = saida.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                resumo = BarraDeComando.resumoDoScript(saida: String(decoding: dados, as: UTF8.self),
                                                       codigo: p.terminationStatus)
            } catch {
                resumo = "Não deu para rodar: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                DicaDeTecla.shared.mostrar("\(s.nome): \(resumo)", progresso: nil)
            }
        }
    }
}

// MARK: - A vista

struct BarraDeComandoView: View {
    let buscou: (String) -> Void
    let escolher: (Int?) -> Void
    @EnvironmentObject var estado: BarraEstado
    @EnvironmentObject var store: DockaStore
    @FocusState private var focado: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(.secondary)
                TextField("Buscar apps, janelas, arquivos, comandos…", text: $estado.busca)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($focado)
                    .onSubmit { escolher(nil) }
                    .onChange(of: estado.busca) { _, novo in buscou(novo) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider().opacity(0.5)

            if estado.itens.isEmpty {
                vazio
            } else {
                ScrollViewReader { rolagem in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(estado.itens.enumerated()), id: \.element.id) { i, item in
                                Button { escolher(i) } label: { linha(item, selecionada: i == estado.selecao) }
                                    .buttonStyle(.plain)
                                    .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: estado.selecao) { _, novo in
                        guard estado.itens.indices.contains(novo) else { return }
                        rolagem.scrollTo(estado.itens[novo].id)
                    }
                }
            }
            Divider().opacity(0.5)
            Text("↩ escolhe  ·  ⌘↩ mostra o arquivo no Finder  ·  esc fecha")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: BarraDeComandoController.largura - 16, height: BarraDeComandoController.altura - 16)
        .dockGlass(cornerRadius: 18, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .scaleEffect(estado.visivel ? 1 : 0.96)
        .opacity(estado.visivel ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onKeyPress(.downArrow) {
            estado.selecao = min(estado.selecao + 1, max(estado.itens.count - 1, 0)); return .handled
        }
        .onKeyPress(.upArrow) { estado.selecao = max(estado.selecao - 1, 0); return .handled }
        // o @FocusState continuava verdadeiro depois de fechar, e pedir foco
        // de novo não mudava nada: na segunda abertura o campo ficava sem
        // cursor. Solta ao fechar e pede no ciclo seguinte ao abrir.
        .onChange(of: estado.pedidoDeFoco) { _, _ in
            focado = false
            DispatchQueue.main.async { focado = true }
        }
        .onChange(of: estado.visivel) { _, visivel in if !visivel { focado = false } }
    }

    private var vazio: some View {
        VStack(spacing: 8) {
            if estado.busca.trimmingCharacters(in: .whitespaces).isEmpty {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 26)).foregroundStyle(.tertiary)
                Text("Apps, janelas, arquivos, o que você copiou, snippets,\ncomandos do menu e as ferramentas do Docka.")
                    .multilineTextAlignment(.center)
                Text("Também faz contas (15% de 80), converte (10 km em mi) e acha emoji (joinha).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("Nada encontrado.").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func linha(_ item: ItemDaBarra, selecionada: Bool) -> some View {
        HStack(spacing: 10) {
            icone(item.icone)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.candidato.titulo)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !item.candidato.detalhe.isEmpty {
                    Text(item.candidato.detalhe)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(0.7)
                }
            }
            Spacer(minLength: 8)
            Text(item.atalho ?? item.candidato.tipo.titulo)
                .font(.system(size: 10.5, design: item.atalho == nil ? .default : .rounded))
                .opacity(0.6)
        }
        .foregroundStyle(selecionada ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selecionada ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icone(_ i: ItemDaBarra.Icone) -> some View {
        switch i {
        case .simbolo(let s):
            Image(systemName: s).font(.system(size: 15)).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .arquivo(let caminho):
            Image(nsImage: NSWorkspace.shared.icon(forFile: caminho)).resizable().interpolation(.high)
        case .imagem(let img):
            Image(nsImage: img).resizable().interpolation(.high)
        case .texto(let t):
            Text(t).font(.system(size: 20))
        }
    }
}

// MARK: - Autoteste

extension BarraDeComandoController {
    /// Desenha a barra fora da tela com uma busca, para o autoteste dos ajustes.
    static func desenhar(pasta: String, busca: String, arquivo: String) -> String {
        let c = BarraDeComandoController()
        c.fixos = c.lerFixos()
        c.estado.visivel = true
        c.estado.busca = busca
        c.recalcular()
        let resumo = c.estado.itens.prefix(6).map { "\($0.candidato.tipo.titulo): \($0.candidato.titulo)" }
            .joined(separator: " | ")
        let ok = desenharVista(BarraDeComandoView(buscou: { _ in }, escolher: { _ in })
                                .environmentObject(c.estado).environmentObject(DockaStore.shared),
                               tamanho: NSSize(width: largura, height: altura), caminho: "\(pasta)/\(arquivo)")
        return (ok ? "OK — " : "FALHOU — ") + "\(arquivo) [\(busca)] \(resumo)"
    }
}

extension PainelRapidoController {
    static func desenhar(pasta: String) -> String {
        let e = PainelRapidoEstado()
        let ids = Set(Ferramentas.disponiveis().map(\.id))
        e.itens = PainelRapido.favoritos(gravados: DockaStore.shared.painelRapidoItens) { ids.contains($0) }
            .compactMap(AcaoDeAtalho.init(id:))
        e.colunas = PainelRapido.colunas(e.itens.count)
        e.visivel = true
        let tam = tamanho(itens: e.itens.count, colunas: e.colunas)
        let ok = desenharVista(PainelRapidoView(escolher: { _ in }).environmentObject(e).environmentObject(DockaStore.shared),
                               tamanho: NSSize(width: tam.width, height: tam.height), caminho: "\(pasta)/painel-rapido.png")
        return (ok ? "OK — " : "FALHOU — ") + "painel-rapido.png (\(e.itens.count) ferramentas)"
    }
}

/// Uma vista num PNG, numa janela fora da tela, sobre cinza.
func desenharVista<V: View>(_ vista: V, tamanho: NSSize, caminho: String) -> Bool {
    let hv = NSHostingView(rootView: vista.background(Color.gray))
    let w = NSWindow(contentRect: NSRect(x: -8000, y: -8000, width: tamanho.width, height: tamanho.height),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = hv
    for _ in 0..<8 { hv.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds) else { return false }
    hv.cacheDisplay(in: hv.bounds, to: rep)
    return (try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: caminho))) != nil
}
