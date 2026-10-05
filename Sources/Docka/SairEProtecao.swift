import SwiftUI
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DockaCore

// MARK: - Sair ao fechar

/// Encerra os apps escolhidos quando a última janela deles fecha — como no
/// Windows, onde fechar a janela fecha o programa.
///
/// Olha a contagem de janelas pela Acessibilidade a cada ¾ de segundo, só
/// dos apps escolhidos e abertos. O encerramento é o pedido educado do Dock:
/// app com trabalho não salvo pergunta, e pode recusar.
final class SairAoFecharController {
    static let shared = SairAoFecharController()

    private var relogio: Timer?
    private var vigias: [pid_t: SairAoFechar.Vigia] = [:]
    private var store: DockaStore { .shared }

    func sincronizar() {
        let precisa = store.sairAoFecharControl && Colagem.permitido && !store.sairAoFecharApps.isEmpty
        if precisa, relogio == nil {
            let t = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.olhar() }
            t.tolerance = 0.25
            RunLoop.main.add(t, forMode: .common)
            relogio = t
        } else if !precisa {
            relogio?.invalidate()
            relogio = nil
            vigias = [:]
        }
    }

    private func olhar() {
        let escolhidos = Set(store.sairAoFecharApps).subtracting(SairAoFechar.nuncaEncerrar)
        let apps = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return escolhidos.contains(id) && !$0.isTerminated
        }
        var vivos: [pid_t: SairAoFechar.Vigia] = [:]
        for app in apps {
            var v = vigias[app.processIdentifier] ?? SairAoFechar.Vigia()
            if v.leu(Self.janelas(de: app.processIdentifier)) { app.terminate() }
            vivos[app.processIdentifier] = v
        }
        vigias = vivos   // app que fechou sai da conta
    }

    /// Janelas abertas do app — minimizadas contam: ainda estão abertas.
    static func janelas(de pid: pid_t) -> Int {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v) == .success,
              let lista = v as? [AXUIElement] else { return 0 }
        return SairAoFechar.contar(lista.map { w in
            var papel: CFTypeRef?, minimizada: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &papel)
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimizada)
            return (papel as? String, (minimizada as? Bool) ?? false)
        })
    }
}

// MARK: - Proteção do ⌘Q e ⌘W

/// Evita o ⌘Q e o ⌘W sem querer: segurar, apertar duas vezes ou usar ⌥.
///
/// Intercepta o teclado (um event tap ativo, que só existe com a
/// Acessibilidade) — mas só age sobre ⌘Q e ⌘W. Toda outra tecla passa direto,
/// sem ser guardada nem olhada além do código.
final class ProtecaoController {
    static let shared = ProtecaoController()

    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var protecoes: [CGKeyCode: ProtecaoDeAtalho] = [:]
    private var segurando: CGKeyCode?
    private var relogio: Timer?
    private var teclaQ = CGKeyCode(kVK_ANSI_Q)
    private var teclaW = CGKeyCode(kVK_ANSI_W)
    private var store: DockaStore { .shared }

    func sincronizar() {
        let precisa = (store.protecaoQ || store.protecaoW) && Colagem.permitido
        if precisa && tap == nil { ligar() }
        if !precisa && tap != nil { desligar() }
        let modo = ModoDeProtecao(persisted: store.protecaoModo)
        protecoes = [teclaQ: ProtecaoDeAtalho(modo: modo), teclaW: ProtecaoDeAtalho(modo: modo)]
    }

    private func ligar() {
        // a tecla do Q e do W no layout em uso (no Dvorak elas moram noutro lugar)
        teclaQ = Colagem.codigoDaTecla(para: "q") ?? CGKeyCode(kVK_ANSI_Q)
        teclaW = Colagem.codigoDaTecla(para: "w") ?? CGKeyCode(kVK_ANSI_W)
        let mascara = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, e, _ in ProtecaoController.shared.tratar(tipo, e) },
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
        terminarSegurar()
        DicaDeTecla.shared.esconder()
    }

    private func tratar(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        let passa = Unmanaged.passUnretained(e)
        // o ⌘Q que o próprio Docka manda ao confirmar segue direto
        guard e.getIntegerValueField(.eventSourceUserData) != MouseController.marca else { return passa }
        let codigo = CGKeyCode(e.getIntegerValueField(.keyboardEventKeycode))
        guard codigo == teclaQ || codigo == teclaW,
              (codigo == teclaQ && store.protecaoQ) || (codigo == teclaW && store.protecaoW) else { return passa }
        let nome = codigo == teclaQ ? "⌘Q" : "⌘W"

        if tipo == .keyUp {
            guard segurando == codigo, var p = protecoes[codigo] else { return passa }
            let d = p.soltou()
            protecoes[codigo] = p
            aplicar(d, codigo: codigo, nome: nome)
            return nil
        }

        let f = e.flags
        // só ⌘ (com ⌥ opcional): ⌘⇧W, ⌃⌘Q e afins são outros atalhos
        guard f.contains(.maskCommand), !f.contains(.maskShift), !f.contains(.maskControl) else { return passa }
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           !store.protecaoApps.isEmpty, !store.protecaoApps.contains(id) { return passa }
        guard var p = protecoes[codigo] else { return passa }

        if e.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }   // o relógio cuida
        let d = p.apertou(em: Date(), comOpcao: f.contains(.maskAlternate), nome: nome)
        protecoes[codigo] = p
        aplicar(d, codigo: codigo, nome: nome)
        return nil
    }

    private func aplicar(_ d: ProtecaoDeAtalho.Decisao, codigo: CGKeyCode, nome: String) {
        switch d {
        case .deixar:
            break
        case .segurarComDica(let texto, let progresso):
            DicaDeTecla.shared.mostrar(texto, progresso: progresso)
            if progresso != nil, segurando == nil { comecarSegurar(codigo, nome: nome) }
        case .confirmar:
            terminarSegurar()
            DicaDeTecla.shared.esconder()
            // fora do tap: o atalho de verdade vai para o app da frente
            DispatchQueue.main.async {
                Colagem.enviarComando(codigo == self.teclaQ ? "q" : "w", reserva: codigo)
            }
        case .cancelar:
            terminarSegurar()
            DicaDeTecla.shared.esconder()
        }
    }

    /// No "segurar", o progresso anda pelo relógio — a repetição da tecla
    /// pode estar desligada nos Ajustes do Sistema.
    private func comecarSegurar(_ codigo: CGKeyCode, nome: String) {
        segurando = codigo
        relogio?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, var p = self.protecoes[codigo] else { return }
            let d = p.segurando(em: Date(), nome: nome)
            self.protecoes[codigo] = p
            if case .segurarComDica(_, nil) = d { return }
            self.aplicar(d, codigo: codigo, nome: nome)
        }
        RunLoop.main.add(t, forMode: .common)
        relogio = t
    }

    private func terminarSegurar() {
        segurando = nil
        relogio?.invalidate()
        relogio = nil
    }
}

/// A dica no meio da tela, embaixo: "Segure ⌘Q para confirmar", com a barra
/// enchendo. Some sozinha se ninguém confirmar.
final class DicaDeTecla {
    static let shared = DicaDeTecla()

    final class Estado: ObservableObject {
        @Published var texto = ""
        @Published var progresso: Double?
    }

    private let estado = Estado()
    private var panel: NSPanel?
    private var retirada: DispatchWorkItem?

    func mostrar(_ texto: String, progresso: Double?) {
        let p = panel ?? construir()
        panel = p
        estado.texto = texto
        estado.progresso = progresso
        if let v = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            p.setFrame(NSRect(x: v.midX - 160, y: v.minY + 120, width: 320, height: 64), display: true)
        }
        p.orderFrontRegardless()
        retirada?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.esconder() }
        retirada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    func esconder() {
        retirada?.cancel()
        panel?.orderOut(nil)
    }

    private func construir() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.level = .screenSaver
        p.contentView = NSHostingView(rootView: VistaDaDica().environmentObject(estado))
        return p
    }

    private struct VistaDaDica: View {
        @EnvironmentObject var estado: Estado
        var body: some View {
            VStack(spacing: 7) {
                Text(estado.texto).font(.system(size: 13, weight: .semibold))
                if let p = estado.progresso {
                    ProgressView(value: p).frame(width: 200)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .dockGlass(cornerRadius: 14, tint: DockaStore.shared.glassTint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
