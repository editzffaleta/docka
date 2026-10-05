import AppKit
import SwiftUI
import AVFoundation
import ScreenCaptureKit
import DockaCore

/// A gravação de tela: escolhe a área (ou a tela inteira), grava com o
/// ScreenCaptureKit direto num .mov — o som do sistema e o microfone em
/// faixas separadas — e mostra um controle pequeno com o tempo e o parar.
///
/// As janelas do próprio Docka ficam fora da imagem: o controle, o seletor e
/// o aviso nunca aparecem no vídeo. Pede a Gravação de Tela (e o microfone,
/// se ele for gravado); nada sai do Mac.
final class GravacaoController: NSObject {
    static let shared = GravacaoController()

    final class Estado: ObservableObject {
        @Published var gravando = false
        @Published var tempo = "0:00"
    }

    let estado = Estado()
    private var store: DockaStore { .shared }
    private var seletor: [NSPanel] = []
    private var controle: NSPanel?
    private var relogio: Timer?
    private var inicio: Date?
    private var arquivo: URL?
    /// `SCStream` e `SCRecordingOutput`, guardados sem o tipo para o resto
    /// do app compilar no macOS 14.
    private var stream: AnyObject?
    private var gravacao: AnyObject?

    var gravando: Bool { estado.gravando }

    func alternar() {
        if gravando { parar() } else { escolherArea() }
    }

    // MARK: escolher a área

    func escolherArea() {
        guard #available(macOS 15, *) else {
            DicaDeTecla.shared.mostrar("A gravação de tela pede o macOS 15 ou mais novo", progresso: nil)
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            DicaDeTecla.shared.mostrar("Conceda a Gravação de Tela e tente de novo", progresso: nil)
            return
        }
        guard seletor.isEmpty else { return }
        for tela in NSScreen.screens {
            let p = PainelDeNotas(contentRect: tela.frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.level = .screenSaver
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.aoEsc = { [weak self] in self?.fecharSeletor() }
            let v = SeletorDeArea(frame: NSRect(origin: .zero, size: tela.frame.size))
            v.tela = tela
            v.escolheu = { [weak self] tela, area in self?.fecharSeletor(); self?.comecar(tela: tela, area: area) }
            v.cancelou = { [weak self] in self?.fecharSeletor() }
            p.contentView = v
            p.setFrame(tela.frame, display: true)
            p.orderFrontRegardless()
            seletor.append(p)
        }
        // o da tela do cursor recebe o teclado (para o Esc)
        let loc = NSEvent.mouseLocation
        (seletor.first { NSMouseInRect(loc, $0.frame, false) } ?? seletor.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    private func fecharSeletor() {
        guard !seletor.isEmpty else { return }
        seletor.forEach { $0.orderOut(nil) }
        seletor = []
        NSCursor.pop()
    }

    // MARK: gravar

    private func comecar(tela: NSScreen, area: CGRect?) {
        guard #available(macOS 15, *) else { return }
        let microfone = store.gravacaoMicrofone
        Task { @MainActor in
            if microfone, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            do {
                try await self.iniciar(tela: tela, area: area)
            } catch {
                self.falhou("Não deu para gravar: \(error.localizedDescription)")
            }
        }
    }

    @available(macOS 15, *)
    @MainActor
    private func iniciar(tela: NSScreen, area: CGRect?) async throws {
        let conteudo = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let numero = (tela.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = conteudo.displays.first(where: { $0.displayID == numero }) ?? conteudo.displays.first else {
            throw NSError(domain: "Docka", code: 1, userInfo: [NSLocalizedDescriptionKey: "a tela não foi encontrada"])
        }
        // o Docka fora do vídeo: o controle e os avisos não aparecem
        let docka = conteudo.applications.filter { $0.processID == getpid() }
        let filtro = SCContentFilter(display: display, excludingApplications: docka, exceptingWindows: [])

        let cfg = SCStreamConfiguration()
        let escala = tela.backingScaleFactor
        // a área em pontos da tela, com a origem no topo (a convenção do SCK)
        let fonte = area.map { a in
            CGRect(x: a.minX - tela.frame.minX, y: tela.frame.maxY - a.maxY, width: a.width, height: a.height)
        } ?? CGRect(origin: .zero, size: tela.frame.size)
        cfg.sourceRect = fonte
        let (l, a) = Midia.tamanhoAlvo(largura: Int(fonte.width * escala), altura: Int(fonte.height * escala),
                                        maximo: 8192, par: true)
        cfg.width = l
        cfg.height = a
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(store.gravacaoQuadros))
        cfg.showsCursor = true
        cfg.showMouseClicks = store.gravacaoCliques
        cfg.capturesAudio = store.gravacaoSomDoSistema
        cfg.excludesCurrentProcessAudio = true
        cfg.captureMicrophone = store.gravacaoMicrofone
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        let url = Self.pasta().appendingPathComponent(Gravacao.nomeDoArquivo(em: Date()))
        let saida = SCRecordingOutputConfiguration()
        saida.outputURL = url
        saida.outputFileType = .mov
        saida.videoCodecType = .hevc

        let s = SCStream(filter: filtro, configuration: cfg, delegate: self)
        let r = SCRecordingOutput(configuration: saida, delegate: self)
        try s.addRecordingOutput(r)
        try await s.startCapture()
        stream = s
        gravacao = r
        arquivo = url
        inicio = Date()
        estado.gravando = true
        estado.tempo = "0:00"
        relogio = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let i = self.inicio else { return }
            self.estado.tempo = Gravacao.relogio(Date().timeIntervalSince(i))
        }
        mostrarControle(em: tela)
        store.playSound("Tink", volume: 0.3)
    }

    func parar() {
        guard #available(macOS 15, *), let s = stream as? SCStream else { return }
        relogio?.invalidate()
        relogio = nil
        controle?.orderOut(nil)
        Task { @MainActor in
            try? await s.stopCapture()
            // o arquivo termina de ser escrito no recordingOutputDidFinishRecording
        }
    }

    /// Onde o macOS grava as capturas (a escolhida no app Capturar Tela), ou a Mesa.
    static func pasta() -> URL {
        let gravada = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return URL(fileURLWithPath: ArquivosDaIlha.pastaDeCapturas(gravada: gravada, home: NSHomeDirectory()))
    }

    private func terminou() {
        let url = arquivo
        limpar()
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        store.playSound("Glass", volume: 0.4)
        DicaDeTecla.shared.mostrar("Gravação salva — \(url.deletingLastPathComponent().lastPathComponent)", progresso: nil)
        switch store.gravacaoDepois {
        case "abrir":  NSWorkspace.shared.open(url)
        case "finder": NSWorkspace.shared.activateFileViewerSelecting([url])
        default:       break
        }
    }

    private func falhou(_ texto: String) {
        limpar()
        DicaDeTecla.shared.mostrar(texto, progresso: nil)
    }

    private func limpar() {
        relogio?.invalidate()
        relogio = nil
        controle?.orderOut(nil)
        stream = nil
        gravacao = nil
        arquivo = nil
        inicio = nil
        estado.gravando = false
    }

    // MARK: o controle

    private func mostrarControle(em tela: NSScreen) {
        let tam = CGSize(width: 170, height: 40)
        let v = tela.visibleFrame
        let p = controle ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = NSHostingView(rootView: ControleDaGravacao { [weak self] in self?.parar() }
                .environmentObject(estado))
            return p
        }()
        controle = p
        p.setFrame(NSRect(x: v.midX - tam.width / 2, y: v.maxY - tam.height - 8, width: tam.width, height: tam.height),
                   display: true)
        p.orderFrontRegardless()
    }
}

@available(macOS 15, *)
extension GravacaoController: SCStreamDelegate, SCRecordingOutputDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.falhou("A gravação parou: \(error.localizedDescription)") }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { self.terminou() }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async { self.falhou("A gravação falhou: \(error.localizedDescription)") }
    }
}

private struct ControleDaGravacao: View {
    let parar: () -> Void
    @EnvironmentObject var estado: GravacaoController.Estado

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 9, height: 9)
            Text(estado.tempo).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Spacer(minLength: 4)
            Button(action: parar) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill").font(.system(size: 10))
                    Text("Parar").font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.18)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(width: 162, height: 34)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// O seletor: escurece a tela, o arrasto desenha a área, um clique sem
/// arrastar escolhe a tela inteira. AppKit, porque num painel que não ativa
/// o Docka os gestos do SwiftUI não chegam.
final class SeletorDeArea: NSView {
    var tela: NSScreen?
    var escolheu: ((NSScreen, CGRect?) -> Void)?
    var cancelou: (() -> Void)?
    private var inicio: NSPoint?
    private var atual: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        inicio = convert(event.locationInWindow, from: nil)
        atual = inicio
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        atual = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let tela, let a = inicio else { return }
        let b = convert(event.locationInWindow, from: nil)
        let o = tela.frame.origin
        // em coordenadas globais
        let area = Gravacao.area(de: CGPoint(x: a.x + o.x, y: a.y + o.y), ate: CGPoint(x: b.x + o.x, y: b.y + o.y),
                                 tela: tela.frame)
        inicio = nil
        atual = nil
        escolheu?(tela, area)
    }

    override func rightMouseDown(with event: NSEvent) { cancelou?() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if let a = inicio, let b = atual {
            let r = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            NSColor.clear.setFill()
            r.fill(using: .copy)
            NSColor.white.setStroke()
            let borda = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            borda.lineWidth = 1
            borda.stroke()
            let medida = NSAttributedString(string: "\(Int(r.width)) × \(Int(r.height))", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            medida.draw(at: NSPoint(x: r.minX, y: max(4, r.minY - 18)))
        } else {
            let dica = NSAttributedString(
                string: "Arraste para gravar uma área · clique para gravar a tela inteira · Esc cancela",
                attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
            let s = dica.size()
            let caixa = NSRect(x: (bounds.width - s.width) / 2 - 14, y: bounds.midY - s.height / 2 - 9,
                               width: s.width + 28, height: s.height + 18)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: caixa, xRadius: 10, yRadius: 10).fill()
            dica.draw(at: NSPoint(x: caixa.minX + 14, y: caixa.minY + 9))
        }
    }
}
