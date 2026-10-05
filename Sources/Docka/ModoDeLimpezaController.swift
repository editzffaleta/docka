import AppKit
import SwiftUI
import DockaCore

/// O modo de limpeza: o teclado para de responder por um tempo — dá para
/// passar um pano nas teclas sem digitar nada em lugar nenhum.
///
/// Termina sozinho no fim do prazo, ou segurando o botão na tela. O prazo é
/// conferido a cada tecla, dentro do próprio tap: mesmo que a interface
/// travasse, o teclado voltaria no fim. E se o Docka fechar, o tap vai junto.
final class ModoDeLimpezaController {
    static let shared = ModoDeLimpezaController()

    final class Estado: ObservableObject {
        @Published var restante = ""
        @Published var visual: ModoDeLimpeza.Visual = .telaPreta
    }

    let estado = Estado()
    private var modo: ModoDeLimpeza?
    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var janelas: [NSPanel] = []
    private var relogio: Timer?

    /// Lido pelo tap, que é uma função C.
    private static var fim: Date?

    var ativo: Bool { modo != nil }

    func alternar() { ativo ? terminar() : comecar() }

    func comecar() {
        guard !ativo else { return }
        guard Colagem.permitido else {
            Colagem.pedirPermissao()
            DicaDeTecla.shared.mostrar("O modo de limpeza precisa da Acessibilidade", progresso: nil)
            return
        }
        let store = DockaStore.shared
        let m = ModoDeLimpeza(inicio: Date(), duracao: store.limpezaDuracao)
        guard ligarTap() else {
            DicaDeTecla.shared.mostrar("Não deu para travar o teclado", progresso: nil)
            return
        }
        modo = m
        Self.fim = m.fim
        estado.visual = ModoDeLimpeza.Visual(rawValue: store.limpezaVisual) ?? .telaPreta
        atualizar()
        mostrarJanelas()
        relogio = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.atualizar() }
    }

    func terminar() {
        guard ativo else { return }
        modo = nil
        Self.fim = nil
        relogio?.invalidate()
        relogio = nil
        desligarTap()
        janelas.forEach { $0.orderOut(nil) }
        janelas = []
        DockaStore.shared.playSound("Pop", volume: 0.4)
        DicaDeTecla.shared.mostrar("Teclado de volta", progresso: nil)
    }

    private func atualizar() {
        guard let m = modo else { return }
        let agora = Date()
        guard m.ativo(em: agora) else { terminar(); return }
        estado.restante = ModoDeLimpeza.relogio(m.restante(em: agora))
    }

    // MARK: o tap

    private func ligarTap() -> Bool {
        let mascara = [CGEventType.keyDown, .keyUp, .flagsChanged]
            .reduce(CGEventMask(1 << 14)) { $0 | (1 << $1.rawValue) }   // 14: teclas especiais
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mascara,
                                        callback: { _, tipo, e, _ in ModoDeLimpezaController.tratar(tipo, e) },
                                        userInfo: nil) else { return false }
        tap = t
        fonte = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fonte, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func desligarTap() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let f = fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
        tap = nil
        fonte = nil
    }

    private static func tratar(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = shared.tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        guard let fim, Date() < fim, ModoDeLimpeza.engole(tipo: tipo.rawValue) else {
            return Unmanaged.passUnretained(e)
        }
        return nil
    }

    // MARK: as janelas

    private func mostrarJanelas() {
        let loc = NSEvent.mouseLocation
        let telaDoCursor = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        switch estado.visual {
        case .telaPreta:
            // todas as telas pretas: a sujeira aparece, e os cliques não
            // chegam aos apps embaixo
            for tela in NSScreen.screens {
                let p = painel(tela.frame)
                p.backgroundColor = .black
                if tela == telaDoCursor {
                    p.contentView = NSHostingView(rootView: AvisoDeLimpeza(grande: true) { [weak self] in self?.terminar() }
                        .environmentObject(estado))
                }
                janelas.append(p)
            }
        case .indicador:
            guard let v = telaDoCursor?.visibleFrame else { return }
            let tam = CGSize(width: 330, height: 64)
            let p = painel(NSRect(x: v.midX - tam.width / 2, y: v.maxY - tam.height - 12,
                                  width: tam.width, height: tam.height))
            p.backgroundColor = .clear
            p.contentView = NSHostingView(rootView: AvisoDeLimpeza(grande: false) { [weak self] in self?.terminar() }
                .environmentObject(estado))
            janelas.append(p)
        }
        janelas.forEach { $0.orderFrontRegardless() }
    }

    private func painel(_ quadro: NSRect) -> NSPanel {
        let p = NSPanel(contentRect: quadro, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.level = .screenSaver
        p.setFrame(quadro, display: true)
        return p
    }
}

private struct AvisoDeLimpeza: View {
    let grande: Bool
    let terminar: () -> Void
    @EnvironmentObject var estado: ModoDeLimpezaController.Estado

    var body: some View {
        if grande {
            VStack(spacing: 14) {
                Image(systemName: "keyboard").font(.system(size: 44, weight: .light))
                Text("Teclado travado para limpeza").font(.system(size: 22, weight: .semibold))
                Text("Volta sozinho em \(estado.restante)")
                    .font(.system(size: 14)).monospacedDigit().opacity(0.6)
                BotaoDeSegurar(titulo: "Segure para terminar", aoCompletar: terminar)
                    .frame(width: 220, height: 40)
                    .padding(.top, 10)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "keyboard").font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Teclado travado").font(.system(size: 12, weight: .semibold))
                    Text("volta em \(estado.restante)").font(.system(size: 10.5)).monospacedDigit().opacity(0.6)
                }
                Spacer()
                BotaoDeSegurar(titulo: "Segure", aoCompletar: terminar).frame(width: 90, height: 28)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(width: 314, height: 52)
            // escuro nos dois modos: o botão é desenhado em branco
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.8)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Um botão que só dispara depois de segurado — num painel que não ativa o
/// Docka, gesto do SwiftUI não chega; por isso é AppKit.
private struct BotaoDeSegurar: NSViewRepresentable {
    let titulo: String
    let aoCompletar: () -> Void

    func makeNSView(context: Context) -> Vista {
        let v = Vista()
        v.titulo = titulo
        v.aoCompletar = aoCompletar
        return v
    }
    func updateNSView(_ v: Vista, context: Context) {
        v.titulo = titulo
        v.aoCompletar = aoCompletar
    }

    final class Vista: NSView {
        var titulo = ""
        var aoCompletar: (() -> Void)?
        private var desde: Date?
        private var progresso: Double = 0 { didSet { needsDisplay = true } }
        private var relogio: Timer?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            desde = Date()
            relogio?.invalidate()
            relogio = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.progresso = ModoDeLimpeza.progressoDeSaida(desde: self.desde, agora: Date())
                if self.progresso >= 1 { self.soltar(); self.aoCompletar?() }
            }
        }

        override func mouseUp(with event: NSEvent) { soltar() }

        private func soltar() {
            relogio?.invalidate()
            relogio = nil
            desde = nil
            progresso = 0
        }

        override func draw(_ dirtyRect: NSRect) {
            let raio = bounds.height / 2
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: raio, yRadius: raio).fill()
            if progresso > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: bounds, xRadius: raio, yRadius: raio).addClip()
                NSColor.white.withAlphaComponent(0.35).setFill()
                NSRect(x: 0, y: 0, width: bounds.width * progresso, height: bounds.height).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            let atributos: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: bounds.height > 32 ? 13 : 11, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let t = NSAttributedString(string: titulo, attributes: atributos)
            let s = t.size()
            t.draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2))
        }
    }
}
