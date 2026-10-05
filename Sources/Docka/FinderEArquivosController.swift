import SwiftUI
import AppKit
import ApplicationServices
import DockaCore

/// Finder e arquivos: recortar e colar no Finder, e o instalador de imagem
/// de disco.
final class FinderEArquivosController {
    static let shared = FinderEArquivosController()

    private var store: DockaStore { .shared }

    func comecar() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil,
                                                          queue: .main) { [weak self] n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            self?.montou(url)
        }
        sincronizar()
    }

    func sincronizar() {
        let quer = store.recorteNoFinder && Colagem.permitido
        if quer && tap == nil { ligar() }
        if !quer && tap != nil { desligar() }
    }

    // MARK: recortar e colar no Finder

    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var recorte = FinderEArquivos.Recorte()

    private func ligar() {
        let mascara = 1 << CGEventType.keyDown.rawValue
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, e, _ in FinderEArquivosController.shared.tratar(tipo, e) },
                                        userInfo: nil) else { return }
        tap = t
        fonte = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fonte, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func desligar() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let f = fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
        tap = nil; fonte = nil
        recorte.esquecer()
    }

    private func tratar(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let passa = Unmanaged.passUnretained(e)
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return passa
        }
        guard e.getIntegerValueField(.eventSourceUserData) != MouseController.marca,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return passa }
        // só ⌘X e ⌘V puros: ⇧⌘V, ⌥⌘V e companhia são outros atalhos
        let f = e.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard f == .maskCommand else { return passa }
        let codigo = CGKeyCode(e.getIntegerValueField(.keyboardEventKeycode))
        let x = Colagem.codigoDaTecla(para: "x") ?? 7
        let v = Colagem.codigoDaTecla(para: "v") ?? 9
        guard codigo == x || codigo == v else { return passa }
        let editando = Self.editandoTexto()

        if codigo == x {
            guard recorte.recortar(editandoTexto: editando) == .copiarELembrar else { return passa }
            DispatchQueue.main.async {
                Colagem.enviarComando("c", reserva: Colagem.codigoDaTecla(para: "c") ?? 8)
                // o Finder põe os arquivos na área de transferência num instante
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.recorte.copiou(numero: NSPasteboard.general.changeCount)
                    DicaDeTecla.shared.mostrar("Recortado — ⌘V em outra pasta move para lá", progresso: nil)
                }
            }
            return nil
        }
        // ⌘V
        guard recorte.colar(editandoTexto: editando, numeroAgora: NSPasteboard.general.changeCount) == .mover else { return passa }
        DispatchQueue.main.async { Self.enviarMover(v) }
        return nil
    }

    /// ⌥⌘V: o "mover para cá" do Finder.
    private static func enviarMover(_ v: CGKeyCode) {
        let fonte = CGEventSource(stateID: .combinedSessionState)
        for desce in [true, false] {
            guard let e = CGEvent(keyboardEventSource: fonte, virtualKey: v, keyDown: desce) else { continue }
            e.flags = [.maskCommand, .maskAlternate]
            e.setIntegerValueField(.eventSourceUserData, value: MouseController.marca)
            e.post(tap: .cghidEventTap)
        }
    }

    /// Renomeando um arquivo (ou num campo de busca): o foco do Finder está
    /// num campo de texto.
    private static func editandoTexto() -> Bool {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return false }
        var foco: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(finder.processIdentifier),
                                            kAXFocusedUIElementAttribute as CFString, &foco) == .success, let foco else { return false }
        var papel: CFTypeRef?
        AXUIElementCopyAttributeValue(foco as! AXUIElement, kAXRoleAttribute as CFString, &papel)
        return ["AXTextField", "AXTextArea", "AXComboBox"].contains(papel as? String ?? "")
    }

    // MARK: imagem de disco

    private func montou(_ volume: URL) {
        guard store.instaladorDeDmg else { return }
        let itens = (try? FileManager.default.contentsOfDirectory(atPath: volume.path)) ?? []
        guard !FinderEArquivos.apps(noVolume: itens).isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            p.arguments = ["info", "-plist"]
            let saida = Pipe()
            p.standardOutput = saida
            try? p.run()
            p.waitUntilExit()
            let dados = saida.fileHandleForReading.readDataToEndOfFile()
            let info = (try? PropertyListSerialization.propertyList(from: dados, format: nil)) as? [String: Any] ?? [:]
            let imagem = FinderEArquivos.imagem(doVolume: volume.path, info: info)
            guard let app = FinderEArquivos.oferecer(volume: volume.path, itens: itens, imagem: imagem) else { return }
            DispatchQueue.main.async {
                InstaladorPanel.shared.oferecer(app: volume.appendingPathComponent(app), volume: volume,
                                                imagem: imagem.map(URL.init(fileURLWithPath:)))
            }
        }
    }
}

// MARK: - A janelinha do instalador

final class InstaladorPanel {
    static let shared = InstaladorPanel()

    final class Estado: ObservableObject {
        @Published var app: URL?
        @Published var volume: URL?
        @Published var imagem: URL?
        @Published var instalado: String?    // versão já em Aplicativos
        @Published var fase: Fase = .oferta
        enum Fase: Equatable { case oferta, instalando, pronto, erro(String) }
    }

    private let estado = Estado()
    private var panel: NSPanel?

    func oferecer(app: URL, volume: URL, imagem: URL?) {
        estado.app = app
        estado.volume = volume
        estado.imagem = imagem
        estado.fase = .oferta
        estado.instalado = Self.versao(Self.destino(app))
        let p = panel ?? construir()
        panel = p
        if let v = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            p.setFrame(NSRect(x: v.maxX - 380, y: v.maxY - 170, width: 360, height: 150), display: true)
        }
        p.orderFrontRegardless()
    }

    static func destino(_ app: URL) -> URL { URL(fileURLWithPath: "/Applications").appendingPathComponent(app.lastPathComponent) }

    static func versao(_ app: URL) -> String? {
        guard FileManager.default.fileExists(atPath: app.path) else { return nil }
        return Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    func fechar() { panel?.orderOut(nil) }

    /// Copia para Aplicativos (a versão antiga vai para o Lixo, de onde dá
    /// para recuperar), ejeta a imagem e, se escolhido, manda o .dmg para o Lixo.
    func instalar(abrirDepois: Bool) {
        guard let app = estado.app else { return }
        estado.fase = .instalando
        let destino = Self.destino(app)
        let volume = estado.volume, imagem = estado.imagem
        let apagarImagem = DockaStore.shared.dmgParaOLixo
        DispatchQueue.global(qos: .userInitiated).async {
            var erro: String?
            do {
                if FileManager.default.fileExists(atPath: destino.path) {
                    try FileManager.default.trashItem(at: destino, resultingItemURL: nil)
                }
                try FileManager.default.copyItem(at: app, to: destino)
            } catch {
                erro = "Não deu para copiar para Aplicativos: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                if let erro { self.estado.fase = .erro(erro); return }
                if let volume { try? NSWorkspace.shared.unmountAndEjectDevice(at: volume) }
                if apagarImagem, let imagem { try? FileManager.default.trashItem(at: imagem, resultingItemURL: nil) }
                self.estado.fase = .pronto
                if abrirDepois { NSWorkspace.shared.open(destino) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.fechar() }
            }
        }
    }

    private func construir() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hv = NSHostingView(rootView: VistaDoInstalador().environmentObject(estado).environmentObject(DockaStore.shared))
        hv.sizingOptions = []
        p.contentView = hv
        return p
    }
}

private struct VistaDoInstalador: View {
    @EnvironmentObject var e: InstaladorPanel.Estado
    @EnvironmentObject var store: DockaStore
    @State private var abrir = true

    var body: some View {
        // o nome que o Finder mostra ("Calculadora", e não "Calculator.app")
        let nome = e.app.map { (FileManager.default.displayName(atPath: $0.path) as NSString).deletingPathExtension } ?? ""
        let nova = e.app.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(nsImage: e.app.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                    .resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nome + (nova.map { " \($0)" } ?? "")).font(.system(size: 13, weight: .semibold))
                    switch e.fase {
                    case .oferta:
                        Text(e.instalado.map { "Substitui a versão \($0) em Aplicativos" } ?? "Instalar em Aplicativos?")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    case .instalando: Text("Instalando…").font(.system(size: 11)).foregroundStyle(.secondary)
                    case .pronto: Label("Instalado", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
                    case .erro(let m): Text(m).font(.system(size: 10.5)).foregroundStyle(.orange).lineLimit(3)
                    }
                }
                Spacer()
            }
            if e.fase == .oferta {
                Toggle("Abrir depois de instalar", isOn: $abrir).toggleStyle(.checkbox).font(.system(size: 11))
                HStack {
                    Spacer()
                    Button("Agora não") { InstaladorPanel.shared.fechar() }
                    Button(e.instalado == nil ? "Instalar" : "Atualizar") { InstaladorPanel.shared.instalar(abrirDepois: abrir) }
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 360, height: 150, alignment: .topLeading)
        .dockGlass(cornerRadius: 16, tint: store.glassTint)
    }
}

// MARK: - Autoteste de desenho

extension InstaladorPanel {
    /// Desenha a janelinha fora da tela, com um app de exemplo.
    static func desenhar(pasta: String) -> String {
        let e = Estado()
        e.app = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        e.instalado = "11.0"
        let hv = NSHostingView(rootView: VistaDoInstalador().environmentObject(e).environmentObject(DockaStore.shared)
            .background(Color.gray))
        let w = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 360, height: 150), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.contentView = hv
        for _ in 0..<8 { hv.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds) else { return "FALHOU — instalador" }
        hv.cacheDisplay(in: hv.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(pasta)/instalador.png"))
        return "OK — instalador.png"
    }
}
