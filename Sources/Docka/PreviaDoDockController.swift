import SwiftUI
import AppKit
import ApplicationServices
import ScreenCaptureKit
import DockaCore

/// Parar o cursor num ícone de app no Dock da Apple mostra as janelas dele,
/// com miniatura e título; clicar numa traz ela para a frente (e tira do
/// Dock, se estava minimizada), e o × fecha.
///
/// Olha o cursor dez vezes por segundo, mas só pergunta à Acessibilidade o
/// que está embaixo dele quando ele está perto da borda da tela — no resto
/// do tempo, a conta é só comparar números.
final class PreviaDoDockController {
    static let shared = PreviaDoDockController()

    struct Janela: Identifiable {
        let id: Int
        let titulo: String
        let elemento: AXUIElement
        let quadro: CGRect?        // coordenadas da Acessibilidade
        let minimizada: Bool
    }

    final class Estado: ObservableObject {
        @Published var app: NSRunningApplication?
        @Published var janelas: [Janela] = []
        @Published var miniaturas: [Int: CGImage] = [:]
    }

    static let caixa = CGSize(width: 200, height: 125)
    static let largura: CGFloat = 220
    static let porLinha = 5
    /// Em volta do vidro: sem ela, a borda arredondada encosta na do painel
    /// e o canto sai quadrado.
    static let margem: CGFloat = 8

    private let estado = Estado()
    private var vigia = PreviaDoDock.Vigia()
    private var relogio: Timer?
    private var monitorDeClique: Any?
    private var panel: NSPanel?
    private var icones: [String: (app: NSRunningApplication, quadro: CGRect)] = [:]
    private var store: DockaStore { .shared }

    static var comMiniaturas: Bool { DockaStore.shared.previaDoDockMiniaturas && CapturaController.permitido }

    func sincronizar() {
        let precisa = store.previaDoDock && Colagem.permitido
        if precisa, relogio == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.olhar() }
            t.tolerance = 0.03
            RunLoop.main.add(t, forMode: .common)
            relogio = t
            monitorDeClique = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.cliqueFora()
            }
        } else if !precisa, relogio != nil {
            relogio?.invalidate()
            relogio = nil
            if let m = monitorDeClique { NSEvent.removeMonitor(m) }
            monitorDeClique = nil
            esconder()
            vigia = PreviaDoDock.Vigia()
        }
    }

    // MARK: o vigia

    private func olhar() {
        let loc = NSEvent.mouseLocation
        let aberta = panel?.isVisible == true
        let sobreOPainel = aberta && (panel?.frame.insetBy(dx: -4, dy: -4).contains(loc) ?? false)
        let icone = sobreOPainel ? nil : iconeSobOCursor(loc)
        switch vigia.leu(icone: icone, sobreOPainel: sobreOPainel, em: Date(),
                         atraso: store.previaDoDockAtraso) {
        case .nada: break
        case .mostrar(let chave): if let i = icones[chave] { mostrar(i.app, icone: i.quadro) }
        case .esconder: esconder()
        }
    }

    /// O ícone de app do Dock sob o cursor, como chave (o pid). Só pergunta
    /// perto das bordas de baixo e dos lados, onde o Dock pode estar.
    private func iconeSobOCursor(_ loc: CGPoint) -> String? {
        guard let tela = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) else { return nil }
        let f = tela.frame
        let perto: CGFloat = 160
        guard loc.y - f.minY < perto || loc.x - f.minX < perto || f.maxX - loc.x < perto else { return nil }
        let alturaDaPrincipal = NSScreen.screens.first?.frame.height ?? 0
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(loc.x),
                                               Float(alturaDaPrincipal - loc.y), &el) == .success,
              let el, let app = CliquesDoSistema.appDoIconeDoDock(el),
              let ax = Self.quadroAX(el) else { return nil }
        let chave = "\(app.processIdentifier)"
        icones = [chave: (app, Encaixe.doAcessibilidade(ax, alturaDaPrincipal: alturaDaPrincipal))]
        return chave
    }

    /// Clique em qualquer lugar fora da prévia — no próprio ícone, o Dock vai
    /// abrir o app: a prévia sai do caminho.
    private func cliqueFora() {
        guard panel?.isVisible == true || vigia.mostrando != nil else { return }
        if panel?.frame.contains(NSEvent.mouseLocation) == true { return }
        if vigia.clicou(icone: iconeSobOCursor(NSEvent.mouseLocation)) == .esconder { esconder() }
    }

    // MARK: o painel

    private func mostrar(_ app: NSRunningApplication, icone: CGRect) {
        let janelas = Self.janelas(de: app)
        guard !janelas.isEmpty,
              let tela = NSScreen.screens.first(where: { $0.frame.intersects(icone) }) ?? NSScreen.main else {
            panel?.orderOut(nil)
            return
        }
        estado.app = app
        estado.janelas = janelas
        estado.miniaturas = [:]
        let comMiniaturas = Self.comMiniaturas
        if comMiniaturas { carregarMiniaturas(app, janelas) }

        let colunas = min(janelas.count, Self.porLinha)
        let linhas = min(Int((Double(janelas.count) / Double(Self.porLinha)).rounded(.up)), 2)
        let altoDoCartao = (comMiniaturas ? Self.caixa.height : 64) + 44
        let tamanho = CGSize(width: CGFloat(colunas) * Self.largura + 28 + 2 * Self.margem,
                             height: CGFloat(linhas) * altoDoCartao + 58 + 2 * Self.margem)
        let p = panel ?? construir()
        panel = p
        p.setFrame(PreviaDoDock.quadro(tamanho: tamanho, icone: icone, tela: tela.frame), display: true)
        p.orderFrontRegardless()
    }

    private func esconder() {
        panel?.orderOut(nil)
        estado.miniaturas = [:]
    }

    private func construir() -> NSPanel {
        // nasce com tamanho de verdade: janela zerada hospedando SwiftUI
        // entra em laço de recálculo (ver o OrbitaController)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.level = .popUpMenu
        p.contentView = NSHostingView(
            rootView: VistaDaPreviaDoDock(escolher: { [weak self] in self?.escolher($0) },
                                          fechar: { [weak self] in self?.fecharJanela($0) })
                .environmentObject(estado)
                .environmentObject(DockaStore.shared))
        return p
    }

    // MARK: ações

    private func escolher(_ j: Janela) {
        let app = estado.app
        esconder()
        _ = vigia.clicou(icone: app.map { "\($0.processIdentifier)" })
        if j.minimizada {
            AXUIElementSetAttributeValue(j.elemento, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(j.elemento, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(j.elemento, kAXRaiseAction as CFString)
        // pelo LaunchServices, como o Dock: o activate() de um app em segundo
        // plano pode ser recusado pela ativação cooperativa
        if let url = app?.bundleURL {
            let c = NSWorkspace.OpenConfiguration()
            c.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: c, completionHandler: nil)
        }
    }

    /// O × da miniatura: aperta o botão vermelho da janela — o app pergunta
    /// se houver algo por salvar.
    private func fecharJanela(_ j: Janela) {
        var b: CFTypeRef?
        guard AXUIElementCopyAttributeValue(j.elemento, kAXCloseButtonAttribute as CFString, &b) == .success,
              let b, CFGetTypeID(b) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let app = self.estado.app, self.panel?.isVisible == true else { return }
            let restantes = Self.janelas(de: app)
            if restantes.isEmpty { self.esconder(); return }
            self.estado.janelas = restantes
        }
    }

    // MARK: Acessibilidade e captura

    /// As janelas de verdade do app, minimizadas incluídas (elas viram
    /// AXDialog ao minimizar — por isso o AXMinimized conta).
    static func janelas(de app: NSRunningApplication) -> [Janela] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                            kAXWindowsAttribute as CFString, &v) == .success,
              let lista = v as? [AXUIElement] else { return [] }
        var r: [Janela] = []
        for w in lista {
            var papel: CFTypeRef?, minimizada: CFTypeRef?, titulo: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &papel)
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimizada)
            let min = (minimizada as? Bool) ?? false
            guard min || (papel as? String) == kAXStandardWindowSubrole as String else { continue }
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titulo)
            let t = (titulo as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (app.localizedName ?? "Janela")
            r.append(Janela(id: r.count, titulo: t, elemento: w, quadro: quadroAX(w), minimizada: min))
        }
        return Array(r.prefix(porLinha * 2))
    }

    static func quadroAX(_ el: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, tv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &tv) == .success,
              let pv, let tv else { return nil }
        var ponto = CGPoint.zero, tamanho = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &ponto)
        AXValueGetValue(tv as! AXValue, .cgSize, &tamanho)
        return CGRect(origin: ponto, size: tamanho)
    }

    /// Miniaturas pela ScreenCaptureKit, casando cada janela da
    /// Acessibilidade com a da captura pelo quadro. Nada é gravado: as
    /// imagens ficam na memória e somem quando a prévia fecha.
    private func carregarMiniaturas(_ app: NSRunningApplication, _ janelas: [Janela]) {
        let pid = app.processIdentifier
        let caixa = Self.caixa
        Task {
            guard let conteudo = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            else { return }
            let doApp = conteudo.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0
                    && $0.frame.width > 60 && $0.frame.height > 60
            }
            let comQuadro = janelas.filter { $0.quadro != nil }
            let ids = Alternador.casar(comQuadro.map { $0.quadro! },
                                       com: doApp.map { (id: $0.windowID, quadro: $0.frame) })
            for (j, id) in zip(comQuadro, ids) {
                guard let id, let w = doApp.first(where: { $0.windowID == id }) else { continue }
                let t = Alternador.miniatura(w.frame.size, caixa: caixa)
                let cfg = SCStreamConfiguration()
                cfg.width = Int(t.width * 2)      // o dobro: nítida em tela Retina
                cfg.height = Int(t.height * 2)
                cfg.showsCursor = false
                guard let img = try? await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
                else { continue }
                await MainActor.run {
                    // fechou ou trocou de app no meio: descarta
                    guard self.panel?.isVisible == true, self.estado.app?.processIdentifier == pid,
                          self.estado.janelas.indices.contains(j.id) else { return }
                    self.estado.miniaturas[j.id] = img
                }
            }
        }
    }
}

// MARK: - A vista

private struct VistaDaPreviaDoDock: View {
    let escolher: (PreviaDoDockController.Janela) -> Void
    let fechar: (PreviaDoDockController.Janela) -> Void
    @EnvironmentObject var estado: PreviaDoDockController.Estado
    @EnvironmentObject var store: DockaStore

    private var grade: [GridItem] {
        Array(repeating: GridItem(.fixed(PreviaDoDockController.largura), spacing: 0),
              count: min(max(estado.janelas.count, 1), PreviaDoDockController.porLinha))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icone = estado.app?.icon {
                    Image(nsImage: icone).resizable().frame(width: 18, height: 18)
                }
                Text(estado.app?.localizedName ?? "").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(estado.janelas.count == 1 ? "1 janela" : "\(estado.janelas.count) janelas")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            LazyVGrid(columns: grade, spacing: 4) {
                ForEach(estado.janelas) { j in cartao(j) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dockGlass(cornerRadius: 18, tint: store.glassTint)
        .modifier(EsquemaEscolhido(appearance: TrayAppearance(persisted: store.appearance)))
        .padding(PreviaDoDockController.margem)
        .ignoresSafeArea()
    }

    /// A miniatura e o título trazem a janela; o × ao lado do título fecha.
    private func cartao(_ j: PreviaDoDockController.Janela) -> some View {
        let caixa = PreviaDoDockController.comMiniaturas ? PreviaDoDockController.caixa : CGSize(width: 200, height: 64)
        return VStack(spacing: 4) {
            Button { escolher(j) } label: {
                Group {
                    if let img = estado.miniaturas[j.id] {
                        let t = Alternador.miniatura(CGSize(width: img.width, height: img.height), caixa: caixa)
                        Image(decorative: img, scale: 1).resizable()
                            .frame(width: t.width, height: t.height)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    } else {
                        Image(nsImage: estado.app?.icon ?? NSImage()).resizable()
                            .frame(width: 48, height: 48)
                    }
                }
                .frame(width: caixa.width, height: caixa.height)
                .opacity(j.minimizada ? 0.55 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(j.minimizada ? "\(j.titulo), minimizada" : j.titulo)

            HStack(spacing: 4) {
                Button { escolher(j) } label: {
                    HStack(spacing: 4) {
                        if j.minimizada {
                            Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Text(j.titulo).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)   // o mesmo da miniatura

                Button { fechar(j) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Fechar a janela")
                .accessibilityLabel("Fechar \(j.titulo)")
            }
            .frame(width: caixa.width)
        }
        .padding(6)
        .frame(width: PreviaDoDockController.largura)
    }
}

