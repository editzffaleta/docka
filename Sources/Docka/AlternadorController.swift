import SwiftUI
import AppKit
import ApplicationServices
import ScreenCaptureKit
import DockaCore

/// Um destino do alternador: um app, ou uma janela dele quando o modo de
/// janelas está ligado e permitido.
struct DestinoDoAlternador: Identifiable {
    let id: String
    let app: NSRunningApplication
    /// Título da janela; `nil` = o app inteiro.
    let janela: String?
    let elemento: AXUIElement?
    /// Quadro da janela pela Acessibilidade (origem no topo) — é o que casa
    /// com a janela da captura para achar a prévia.
    var quadro: CGRect? = nil

    var nome: String { app.localizedName ?? "App" }
}

/// O alternador: segure o modificador do atalho, aperte de novo para avançar,
/// solte para trocar.
///
/// Não substitui o ⌘Tab — interceptar o atalho do sistema exigiria ler o
/// teclado inteiro. Usa um atalho próprio (Carbon, sem permissão) e lê o
/// estado dos modificadores para saber quando foram soltos, o que também
/// dispensa permissão.
final class AlternadorController {
    static let shared = AlternadorController()

    let estado = AlternadorEstado()
    private var panel: PainelDeNotas?
    private var historico: [Int32] = []
    private var observadorDeAtivacao: NSObjectProtocol?
    private var relogio: Timer?
    private var monitorDeTecla: Any?
    private var gatilho: Shortcut.Modifiers = []

    /// Com prévia, o ladrilho alarga para caber a miniatura.
    static var comPrevias: Bool { DockaStore.shared.alternadorPrevias && CapturaController.permitido }
    static var lado: CGFloat { comPrevias ? 196 : 104 }
    static var colunas: Int { comPrevias ? 5 : 7 }
    static let caixaDaPrevia = CGSize(width: 176, height: 110)

    /// Liga o histórico de uso — sem ele a ordem seria a de abertura dos
    /// apps, e não a de uso.
    func ligar(_ sim: Bool) {
        if sim, observadorDeAtivacao == nil {
            if let frente = NSWorkspace.shared.frontmostApplication {
                historico = Alternador.registrar(frente.processIdentifier, em: historico)
            }
            observadorDeAtivacao = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] n in
                guard let self,
                      let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                self.historico = Alternador.registrar(app.processIdentifier, em: self.historico)
            }
        } else if !sim, let o = observadorDeAtivacao {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            observadorDeAtivacao = nil
            fechar()
        }
    }

    /// O atalho: abre, ou avança se já aberto.
    func atalho() {
        if estado.visivel { mover(1) } else { abrir() }
    }

    // MARK: destinos

    private func destinos() -> [DestinoDoAlternador] {
        let store = DockaStore.shared
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let porPid = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let ordem = Alternador.porUso(apps.map(\.processIdentifier), historico: historico)
        let comJanelas = store.alternadorJanelas && Colagem.permitido
        let filtros = store.alternadorSoTela || store.alternadorSemJanela
        let lerJanelas = (comJanelas || filtros) && Colagem.permitido
        // a tela do cursor, na convenção da Acessibilidade (origem no topo)
        let tela: CGRect? = store.alternadorSoTela ? {
            let loc = NSEvent.mouseLocation
            guard let f = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) })?.frame else { return nil }
            return Encaixe.paraAcessibilidade(f, alturaDaPrincipal: NSScreen.screens.first?.frame.height ?? 0)
        }() : nil

        return ordem.compactMap { porPid[$0] }.flatMap { app -> [DestinoDoAlternador] in
            let base = "\(app.processIdentifier)"
            let janelas = lerJanelas ? Self.janelas(de: app) : nil
            guard Alternador.passa(janelas: janelas?.compactMap(\.quadro),
                                   semJanelaEsconde: store.alternadorSemJanela, soTela: tela) else { return [] }
            guard comJanelas, var js = janelas, !js.isEmpty else {
                return [DestinoDoAlternador(id: base, app: app, janela: nil, elemento: nil)]
            }
            // só a tela do cursor: as janelas do app que estão nas outras saem
            if let tela { js = js.filter { $0.quadro.map { Alternador.naTela($0, tela: tela) } ?? true } }
            return js.enumerated().map { i, j in
                DestinoDoAlternador(id: "\(base):\(i)", app: app, janela: j.titulo, elemento: j.elemento,
                                    quadro: j.quadro)
            }
        }
    }

    /// As janelas de um app, pela Acessibilidade — o título vem junto, sem a
    /// Gravação de Tela que a lista de janelas do sistema exigiria.
    private static func janelas(de app: NSRunningApplication) -> [(titulo: String, elemento: AXUIElement, quadro: CGRect?)] {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &valor) == .success,
              let lista = valor as? [AXUIElement] else { return [] }
        return lista.compactMap { w in
            var papel: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &papel)
            // só janelas de verdade: painéis, folhas e paletas ficam de fora
            guard (papel as? String) == kAXStandardWindowSubrole as String else { return nil }
            var t: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
            let titulo = (t as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (app.localizedName ?? "Janela")
            return (titulo, w, quadroAX(w))
        }
    }

    private static func quadroAX(_ w: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, t: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &t) == .success,
              let p, let t else { return nil }
        var ponto = CGPoint.zero, tamanho = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &ponto)
        AXValueGetValue(t as! AXValue, .cgSize, &tamanho)
        return CGRect(origin: ponto, size: tamanho)
    }

    // MARK: abrir, mover, escolher

    func abrir() {
        let lista = destinos()
        guard !lista.isEmpty else { NSSound.beep(); return }
        estado.todos = lista
        estado.busca = ""
        estado.destinos = lista
        estado.previas = [:]
        if Self.comPrevias { PreviasDoAlternador.carregar(lista, em: estado) }
        estado.selecao = Alternador.selecaoInicial(total: lista.count)
        gatilho = DockaStore.shared.atalho(de: .alternador)?.modifiers ?? []

        let p = panel ?? construir()
        panel = p
        let colunas = min(lista.count, Self.colunas)
        let linhas = Int((Double(lista.count) / Double(Self.colunas)).rounded(.up))
        let largura = CGFloat(colunas) * Self.lado + 40
        let altura = CGFloat(min(linhas, 4)) * (Self.comPrevias ? Self.caixaDaPrevia.height + 70 : Self.lado + 18) + 100
        let loc = NSEvent.mouseLocation
        if let v = (NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            p.setFrame(NSRect(x: v.midX - largura / 2, y: v.midY - altura / 2,
                              width: largura, height: altura), display: true)
        }
        p.orderFrontRegardless()
        p.makeKey()
        estado.visivel = true
        comecarAVigiar()
    }

    func mover(_ passo: Int) {
        estado.selecao = Alternador.mover(estado.selecao, passo: passo, total: estado.destinos.count)
    }

    func escolher(_ indice: Int? = nil) {
        let i = indice ?? estado.selecao
        guard estado.destinos.indices.contains(i) else { fechar(); return }
        let d = estado.destinos[i]
        fechar()
        if let w = d.elemento {
            // a janela certa na frente; depois o app, que a traz junto
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        }
        ativar(d.app)
    }

    /// Traz o app para a frente pelo LaunchServices, como o Dock faz.
    ///
    /// `NSRunningApplication.activate` vindo de um app em segundo plano pode
    /// ser recusado pela ativação cooperativa do macOS 14+; abrir o app que
    /// já está aberto só o ativa, e funciona de qualquer lugar.
    private func ativar(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { app.activate(); return }
        let c = NSWorkspace.OpenConfiguration()
        c.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: c, completionHandler: nil)
    }

    func fechar() {
        relogio?.invalidate()
        relogio = nil
        if let m = monitorDeTecla { NSEvent.removeMonitor(m) }
        monitorDeTecla = nil
        estado.visivel = false
        panel?.resignKey()
        panel?.orderOut(nil)
    }

    /// Enquanto aberto: soltar o modificador escolhe; ⇧Tab e setas andam;
    /// ↩ escolhe; Esc (no painel) cancela.
    private func comecarAVigiar() {
        relogio?.invalidate()
        if !gatilho.isEmpty {
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.conferirModificadores() }
            RunLoop.main.add(t, forMode: .common)
            relogio = t
        }
        if monitorDeTecla == nil {
            monitorDeTecla = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.estado.visivel else { return e }
                switch e.keyCode {
                case 48:  self.mover(e.modifierFlags.contains(.shift) ? -1 : 1)   // Tab
                case 123: self.mover(-1)                                          // ←
                case 124: self.mover(1)                                           // →
                case 126: self.mover(-Self.colunas)                               // ↑
                case 125: self.mover(Self.colunas)                                // ↓
                case 36, 76: self.escolher()                                      // ↩
                case 51:  self.buscar(String(self.estado.busca.dropLast()))        // ⌫
                default:
                    // letra, número ou espaço vai para a busca (com ⌥ apertado
                    // o caractere sai trocado — vale o da tecla sem modificador)
                    guard !e.modifierFlags.contains(.command), !e.modifierFlags.contains(.control),
                          let c = e.charactersIgnoringModifiers?.first,
                          c.isLetter || c.isNumber || c == " " || c.isPunctuation else { return e }
                    self.buscar(self.estado.busca + String(c))
                }
                return nil
            }
        }
    }

    /// Estado atual do teclado, lido sem permissão.
    /// Refaz a lista com a busca. Começou a digitar: soltar o modificador
    /// deixa de confirmar — ninguém digita segurando ⌥; aí ↩ ou o clique
    /// escolhem.
    private func buscar(_ texto: String) {
        estado.busca = texto
        estado.destinos = estado.todos.filter { Alternador.combina(texto, nome: $0.nome, titulo: $0.janela) }
        estado.selecao = 0
        if !texto.isEmpty { relogio?.invalidate(); relogio = nil }
    }

    private func conferirModificadores() {
        let f = CGEventSource.flagsState(.combinedSessionState)
        var agora: Shortcut.Modifiers = []
        if f.contains(.maskCommand) { agora.insert(.command) }
        if f.contains(.maskAlternate) { agora.insert(.option) }
        if f.contains(.maskControl) { agora.insert(.control) }
        if f.contains(.maskShift) { agora.insert(.shift) }
        if !Alternador.aindaSegurando(gatilho: gatilho, agora: agora) { escolher() }
    }

    private func construir() -> PainelDeNotas {
        // nasce com tamanho de verdade, e não .zero: janela zerada hospedando
        // uma view com `maxWidth: .infinity` põe o NSHostingView num laço de
        // recálculo e o AppKit aborta o app (ver o OrbitaController)
        let p = PainelDeNotas(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isFloatingPanel = true
        p.level = .mainMenu
        // Esc com busca digitada limpa a busca; sem busca, fecha
        p.aoEsc = { [weak self] in
            guard let self else { return }
            if self.estado.busca.isEmpty { self.fechar() } else { self.buscar("") }
        }
        p.contentView = NSHostingView(
            rootView: AlternadorView(escolher: { [weak self] in self?.escolher($0) })
                .environmentObject(estado)
                .environmentObject(DockaStore.shared))
        return p
    }
}

final class AlternadorEstado: ObservableObject {
    @Published var visivel = false
    /// Todos os destinos ao abrir; `destinos` é o que sobra da busca.
    var todos: [DestinoDoAlternador] = []
    @Published var busca = ""
    @Published var destinos: [DestinoDoAlternador] = []
    @Published var selecao = 0
    /// Miniaturas por destino, chegando aos poucos.
    @Published var previas: [String: CGImage] = [:]
}

struct AlternadorView: View {
    let escolher: (Int) -> Void
    @EnvironmentObject var estado: AlternadorEstado
    @EnvironmentObject var store: DockaStore

    /// A miniatura da janela, quando chegou; senão, o ícone do app.
    @ViewBuilder
    private func imagem(_ d: DestinoDoAlternador) -> some View {
        let icone = Image(nsImage: d.app.icon ?? NSImage()).resizable()
        if AlternadorController.comPrevias {
            let caixa = AlternadorController.caixaDaPrevia
            ZStack(alignment: .bottomLeading) {
                if let p = estado.previas[d.id] {
                    let t = Alternador.miniatura(CGSize(width: p.width, height: p.height), caixa: caixa)
                    Image(decorative: p, scale: 1)
                        .resizable()
                        .frame(width: t.width, height: t.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .frame(width: caixa.width, height: caixa.height)
                    icone.frame(width: 34, height: 34).offset(x: -4, y: 6)
                } else {
                    icone.frame(width: 64, height: 64)
                        .frame(width: caixa.width, height: caixa.height)
                }
            }
        } else {
            icone.frame(width: 64, height: 64)
        }
    }

    private var grade: [GridItem] {
        Array(repeating: GridItem(.fixed(AlternadorController.lado), spacing: 0),
              count: min(max(estado.destinos.count, 1), AlternadorController.colunas))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(estado.busca.isEmpty ? "Digite para buscar" : estado.busca)
                    .foregroundStyle(estado.busca.isEmpty ? .tertiary : .primary)
                Spacer()
                if !estado.busca.isEmpty {
                    Text("\(estado.destinos.count) de \(estado.todos.count)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.top, 12)
            ScrollView {
                LazyVGrid(columns: grade, spacing: 18) {
                    ForEach(Array(estado.destinos.enumerated()), id: \.element.id) { i, d in
                        Button { escolher(i) } label: {
                            VStack(spacing: 4) {
                                imagem(d)
                                Text(d.janela ?? d.nome)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: AlternadorController.lado - 14)
                            }
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(i == estado.selecao ? Color.primary.opacity(0.16) : .clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(d.janela.map { "\(d.nome), \($0)" } ?? d.nome)
                    }
                }
                .padding(.top, 14)
            }
            .overlay {
                if estado.destinos.isEmpty {
                    Text("Nada com “\(estado.busca)”").foregroundStyle(.secondary)
                }
            }
            if estado.destinos.indices.contains(estado.selecao) {
                let d = estado.destinos[estado.selecao]
                Text(d.janela.map { "\(d.nome) — \($0)" } ?? d.nome)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dockGlass(cornerRadius: 22, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .padding(8)
        .ignoresSafeArea()
    }
}

// MARK: - Prévias

/// As miniaturas das janelas, pelo ScreenCaptureKit — pedem Gravação de Tela.
///
/// O alternador abre com os ícones; cada miniatura chega quando fica pronta.
/// Esperar todas antes de abrir faria o atalho parecer lento justo no gesto
/// que precisa ser instantâneo.
enum PreviasDoAlternador {

    static func carregar(_ destinos: [DestinoDoAlternador], em estado: AlternadorEstado) {
        let caixa = AlternadorController.caixaDaPrevia
        Task {
            guard let conteudo = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            else { return }
            // só janelas de verdade, do tamanho de alguma coisa
            let janelas = conteudo.windows.filter {
                $0.windowLayer == 0 && $0.frame.width > 60 && $0.frame.height > 60
            }
            var pares: [(id: String, janela: SCWindow)] = []
            for pid in Set(destinos.map(\.app.processIdentifier)) {
                let doApp = janelas.filter { $0.owningApplication?.processID == pid }
                let ds = destinos.filter { $0.app.processIdentifier == pid }
                if ds.contains(where: { $0.quadro != nil }) {
                    let comQuadro = ds.filter { $0.quadro != nil }
                    let ids = Alternador.casar(comQuadro.map { $0.quadro! },
                                               com: doApp.map { (id: $0.windowID, quadro: $0.frame) })
                    for (d, id) in zip(comQuadro, ids) {
                        if let id, let w = doApp.first(where: { $0.windowID == id }) { pares.append((d.id, w)) }
                    }
                } else if let d = ds.first,
                          let w = doApp.first(where: \.isOnScreen) ?? doApp.first {
                    // modo de apps: a janela da frente do app (a lista vem de frente para trás)
                    pares.append((d.id, w))
                }
            }
            for par in pares {
                let t = Alternador.miniatura(par.janela.frame.size, caixa: caixa)
                let cfg = SCStreamConfiguration()
                cfg.width = Int(t.width * 2)      // o dobro: nítida em tela Retina
                cfg.height = Int(t.height * 2)
                cfg.showsCursor = false
                guard let img = try? await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: par.janela), configuration: cfg)
                else { continue }
                await MainActor.run {
                    // fechou ou reabriu com outra lista no meio: descarta
                    guard estado.visivel, estado.destinos.contains(where: { $0.id == par.id }) else { return }
                    estado.previas[par.id] = img
                }
            }
        }
    }
}
