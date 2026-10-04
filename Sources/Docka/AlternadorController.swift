import SwiftUI
import AppKit
import ApplicationServices
import DockaCore

/// Um destino do alternador: um app, ou uma janela dele quando o modo de
/// janelas está ligado e permitido.
struct DestinoDoAlternador: Identifiable {
    let id: String
    let app: NSRunningApplication
    /// Título da janela; `nil` = o app inteiro.
    let janela: String?
    let elemento: AXUIElement?

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

    static let lado: CGFloat = 104
    static let colunas = 7

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
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let porPid = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let ordem = Alternador.porUso(apps.map(\.processIdentifier), historico: historico)
        let comJanelas = DockaStore.shared.alternadorJanelas && Colagem.permitido

        return ordem.compactMap { porPid[$0] }.flatMap { app -> [DestinoDoAlternador] in
            let base = "\(app.processIdentifier)"
            guard comJanelas else { return [DestinoDoAlternador(id: base, app: app, janela: nil, elemento: nil)] }
            let janelas = Self.janelas(de: app)
            if janelas.isEmpty { return [DestinoDoAlternador(id: base, app: app, janela: nil, elemento: nil)] }
            return janelas.enumerated().map { i, j in
                DestinoDoAlternador(id: "\(base):\(i)", app: app, janela: j.titulo, elemento: j.elemento)
            }
        }
    }

    /// As janelas de um app, pela Acessibilidade — o título vem junto, sem a
    /// Gravação de Tela que a lista de janelas do sistema exigiria.
    private static func janelas(de app: NSRunningApplication) -> [(titulo: String, elemento: AXUIElement)] {
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
            return (titulo, w)
        }
    }

    // MARK: abrir, mover, escolher

    func abrir() {
        let lista = destinos()
        guard !lista.isEmpty else { NSSound.beep(); return }
        estado.destinos = lista
        estado.selecao = Alternador.selecaoInicial(total: lista.count)
        gatilho = DockaStore.shared.atalho(de: .alternador)?.modifiers ?? []

        let p = panel ?? construir()
        panel = p
        let colunas = min(lista.count, Self.colunas)
        let linhas = Int((Double(lista.count) / Double(Self.colunas)).rounded(.up))
        let largura = CGFloat(colunas) * Self.lado + 40
        let altura = CGFloat(min(linhas, 4)) * (Self.lado + 18) + 70
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
                default: return e
                }
                return nil
            }
        }
    }

    /// Estado atual do teclado, lido sem permissão.
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
        p.aoEsc = { [weak self] in self?.fechar() }
        p.contentView = NSHostingView(
            rootView: AlternadorView(escolher: { [weak self] in self?.escolher($0) })
                .environmentObject(estado)
                .environmentObject(DockaStore.shared))
        return p
    }
}

final class AlternadorEstado: ObservableObject {
    @Published var visivel = false
    @Published var destinos: [DestinoDoAlternador] = []
    @Published var selecao = 0
}

struct AlternadorView: View {
    let escolher: (Int) -> Void
    @EnvironmentObject var estado: AlternadorEstado
    @EnvironmentObject var store: DockaStore

    private var grade: [GridItem] {
        Array(repeating: GridItem(.fixed(AlternadorController.lado), spacing: 0),
              count: min(max(estado.destinos.count, 1), AlternadorController.colunas))
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVGrid(columns: grade, spacing: 18) {
                    ForEach(Array(estado.destinos.enumerated()), id: \.element.id) { i, d in
                        Button { escolher(i) } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: d.app.icon ?? NSImage())
                                    .resizable()
                                    .frame(width: 64, height: 64)
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
