import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DockaCore

/// Mouse e teclado: foco que segue o mouse, filtro de clique duplo
/// acidental, repique de teclas, clique do meio com três dedos e a tecla
/// super. Cada um só cria o que precisa quando está ligado; os taps pedem
/// Acessibilidade.
final class MouseETecladoController {
    static let shared = MouseETecladoController()

    private var store: DockaStore { .shared }

    func sincronizar() {
        let ok = Colagem.permitido
        sincronizarFoco(store.focoSegueMouse && ok)
        sincronizarCliques((store.filtroDeClique || store.cliqueDoMeio) && ok)
        sincronizarTeclas((store.repiqueDeTeclas || store.teclaSuper) && ok)
        sincronizarDedos(store.cliqueDoMeio && ok)
        TeclaSuper.aplicar(store.teclaSuper && ok)
    }

    // MARK: foco segue o mouse

    private var relogioDoFoco: Timer?
    private var vigia = MouseETeclado.Vigia()

    private func sincronizarFoco(_ quer: Bool) {
        if quer, relogioDoFoco == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.olharFoco() }
            t.tolerance = 0.03
            RunLoop.main.add(t, forMode: .common)
            relogioDoFoco = t
        } else if !quer {
            relogioDoFoco?.invalidate(); relogioDoFoco = nil
            vigia = MouseETeclado.Vigia()
        }
    }

    private func olharFoco() {
        let loc = NSEvent.mouseLocation
        let alturaDaPrincipal = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: loc.x, y: alturaDaPrincipal - loc.y)
        let sob = Self.appSob(p)
        let frente = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let mods = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let pid = vigia.leu(sob: sob, frente: frente, em: Date(), atraso: store.focoAtraso,
                                  botaoApertado: NSEvent.pressedMouseButtons != 0, modificador: !mods.isEmpty),
              let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
              !store.focoIgnorados.contains(app.bundleIdentifier ?? "") else { return }
        // a janela sob o cursor sobe, e o app vem junto
        var el: AXUIElement?
        if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success, let el {
            var w: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &w) == .success, let w,
               CFGetTypeID(w) == AXUIElementGetTypeID() {
                AXUIElementPerformAction(w as! AXUIElement, kAXRaiseAction as CFString)
            }
        }
        app.activate()
    }

    /// O app dono da janela comum (camada 0) mais à frente sob o ponto —
    /// barra de menus, Dock e mesa ficam de fora, e as janelas do Docka também.
    private static func appSob(_ p: CGPoint) -> Int32? {
        guard let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for w in lista {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(p),
                  let pid = w[kCGWindowOwnerPID as String] as? Int32 else { continue }
            return pid == getpid() ? nil : pid
        }
        return nil
    }

    // MARK: cliques (filtro de repique e clique do meio)

    private var tapDeCliques: CFMachPort?
    private var fonteDeCliques: CFRunLoopSource?
    private var repiqueDeCliques = MouseETeclado.Repique()
    /// O "apertar" de três dedos virou botão do meio: o "soltar" também vira.
    private var meioApertado = false

    private func sincronizarCliques(_ quer: Bool) {
        if quer, tapDeCliques == nil {
            let tipos: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            let mascara = tipos.reduce(0) { $0 | (1 << $1.rawValue) }
            guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                            eventsOfInterest: CGEventMask(mascara),
                                            callback: { _, tipo, e, _ in MouseETecladoController.shared.tratarClique(tipo, e) },
                                            userInfo: nil) else { return }
            tapDeCliques = t
            fonteDeCliques = CFMachPortCreateRunLoopSource(nil, t, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), fonteDeCliques, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
        } else if !quer, let t = tapDeCliques {
            CGEvent.tapEnable(tap: t, enable: false)
            if let f = fonteDeCliques { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
            tapDeCliques = nil; fonteDeCliques = nil
        }
    }

    private func tratarClique(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let passa = Unmanaged.passUnretained(e)
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tapDeCliques { CGEvent.tapEnable(tap: t, enable: true) }
            return passa
        }
        guard e.getIntegerValueField(.eventSourceUserData) != MouseController.marca else { return passa }

        // três dedos no trackpad: o clique esquerdo vira o do meio
        if store.cliqueDoMeio {
            if tipo == .leftMouseDown, Dedos.agora >= 3 {
                meioApertado = true
                e.type = .otherMouseDown
                e.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                return passa
            }
            if tipo == .leftMouseUp, meioApertado {
                meioApertado = false
                e.type = .otherMouseUp
                e.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                return passa
            }
        }

        guard store.filtroDeClique else { return passa }
        let botao: Int64 = (tipo == .leftMouseDown || tipo == .leftMouseUp) ? 0 : 1
        let limiar = store.filtroDeCliqueMs / 1000
        switch tipo {
        case .leftMouseDown, .rightMouseDown:
            return repiqueDeCliques.apertou(botao, em: Date(), onde: e.location, limiar: limiar) ? nil : passa
        case .leftMouseUp, .rightMouseUp:
            return repiqueDeCliques.soltou(botao, em: Date(), onde: e.location) ? nil : passa
        default:
            return passa
        }
    }

    // MARK: teclas (repique e tecla super)

    private var tapDeTeclas: CFMachPort?
    private var fonteDeTeclas: CFRunLoopSource?
    private var repiqueDeTeclas = MouseETeclado.Repique()
    private var superApertada = false

    private func sincronizarTeclas(_ quer: Bool) {
        if quer, tapDeTeclas == nil {
            let mascara = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                            eventsOfInterest: CGEventMask(mascara),
                                            callback: { _, tipo, e, _ in MouseETecladoController.shared.tratarTecla(tipo, e) },
                                            userInfo: nil) else { return }
            tapDeTeclas = t
            fonteDeTeclas = CFMachPortCreateRunLoopSource(nil, t, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), fonteDeTeclas, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
        } else if !quer, let t = tapDeTeclas {
            CGEvent.tapEnable(tap: t, enable: false)
            if let f = fonteDeTeclas { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
            tapDeTeclas = nil; fonteDeTeclas = nil
            superApertada = false
        }
    }

    private func tratarTecla(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let passa = Unmanaged.passUnretained(e)
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tapDeTeclas { CGEvent.tapEnable(tap: t, enable: true) }
            return passa
        }
        guard e.getIntegerValueField(.eventSourceUserData) != MouseController.marca else { return passa }
        let codigo = e.getIntegerValueField(.keyboardEventKeycode)

        // a tecla super: o Caps Lock chega como F18 (remapeado); enquanto
        // ela está apertada, toda tecla ganha ⌃⌥⇧⌘
        if store.teclaSuper {
            if codigo == Int64(kVK_F18) {
                superApertada = tipo == .keyDown
                return nil
            }
            if superApertada {
                e.flags.formUnion([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            }
        }

        // repique: a repetição de quem segura a tecla não conta
        guard store.repiqueDeTeclas, e.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return passa }
        let limiar = store.repiqueMs / 1000
        if tipo == .keyDown { return repiqueDeTeclas.apertou(codigo, em: Date(), limiar: limiar) ? nil : passa }
        return repiqueDeTeclas.soltou(codigo, em: Date()) ? nil : passa
    }

    // MARK: dedos no trackpad

    private func sincronizarDedos(_ quer: Bool) {
        if quer { Dedos.ligar() } else { Dedos.desligar() }
    }

    /// Ao encerrar: a tecla super devolve o Caps Lock.
    func encerrar() { TeclaSuper.aplicar(false) }
}

// MARK: - Quantos dedos tocam o trackpad

/// Pela MultitouchSupport do sistema (a mesma que apps como o MiddleClick
/// usam): só a contagem de dedos, nada das posições.
enum Dedos {
    /// Escrito pela linha do trackpad, lido pelo tap: um inteiro só.
    nonisolated(unsafe) static var agora: Int32 = 0
    private static var dispositivos: [AnyObject] = []

    private typealias Lista = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Callback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias Registrar = @convention(c) (AnyObject, Callback) -> Void
    private typealias Iniciar = @convention(c) (AnyObject, Int32) -> Void
    private typealias Parar = @convention(c) (AnyObject) -> Void
    private static let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)

    static func ligar() {
        guard dispositivos.isEmpty, let l = dlsym(mt, "MTDeviceCreateList"), let r = dlsym(mt, "MTRegisterContactFrameCallback"),
              let i = dlsym(mt, "MTDeviceStart"),
              let lista = unsafeBitCast(l, to: Lista.self)()?.takeRetainedValue() as? [AnyObject] else { return }
        let cb: Callback = { _, _, n, _, _ in Dedos.agora = n; return 0 }
        for d in lista {
            unsafeBitCast(r, to: Registrar.self)(d, cb)
            unsafeBitCast(i, to: Iniciar.self)(d, 0)
        }
        dispositivos = lista
    }

    static func desligar() {
        guard !dispositivos.isEmpty, let p = dlsym(mt, "MTDeviceStop") else { return }
        for d in dispositivos { unsafeBitCast(p, to: Parar.self)(d) }
        dispositivos = []
        agora = 0
    }
}

// MARK: - A tecla super

/// O Caps Lock é remapeado para F18 no sistema de eventos (o mesmo que o
/// `hidutil` faz), e o tap transforma F18 apertado em ⌃⌥⇧⌘. O remapeamento
/// é desfeito ao desligar a opção e ao encerrar o Docka; os de outros apps
/// ficam como estavam.
enum TeclaSuper {
    private typealias Criar = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias Ler = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias Mudar = @convention(c) (AnyObject, CFString, CFTypeRef) -> Bool
    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let cliente: AnyObject? = dlsym(iokit, "IOHIDEventSystemClientCreateSimpleClient")
        .flatMap { unsafeBitCast($0, to: Criar.self)(kCFAllocatorDefault)?.takeRetainedValue() }
    private static let chave = "UserKeyMapping" as CFString

    static var mapeamentos: [[String: UInt64]] {
        guard let c = cliente, let f = dlsym(iokit, "IOHIDEventSystemClientCopyProperty"),
              let v = unsafeBitCast(f, to: Ler.self)(c, chave)?.takeRetainedValue() as? [[String: NSNumber]] else { return [] }
        return v.map { $0.mapValues { $0.uint64Value } }
    }

    static var ativa: Bool { mapeamentos.contains { $0["HIDKeyboardModifierMappingSrc"] == MouseETeclado.hidCapsLock } }

    static func aplicar(_ ligar: Bool) {
        // DOCKA_SEM_REMAPEAR: para testar o resto sem mexer no Caps Lock de verdade
        if ProcessInfo.processInfo.environment["DOCKA_SEM_REMAPEAR"] != nil { return }
        guard ligar != ativa, let c = cliente, let f = dlsym(iokit, "IOHIDEventSystemClientSetProperty") else { return }
        let novos = MouseETeclado.mapeamentos(mapeamentos, remover: !ligar)
        let valor = novos.map { $0.mapValues { NSNumber(value: $0) } } as CFArray
        _ = unsafeBitCast(f, to: Mudar.self)(c, chave, valor)
    }
}
