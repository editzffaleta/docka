import AppKit
import ApplicationServices
import DockaCore

/// Segurando as teclas escolhidas (⌃⌥ por padrão), o botão esquerdo move a
/// janela de qualquer ponto dela, e o direito a redimensiona pelo canto mais
/// perto do clique.
///
/// Um event tap ativo de clique (Acessibilidade). Sem as teclas, nenhum
/// clique é tocado. Com elas, o apertar, o arrastar e o soltar são engolidos
/// — o app de baixo não vê o clique — e a janela anda pela Acessibilidade.
final class ArrastoComTeclaController {
    static let shared = ArrastoComTeclaController()

    private struct Arrasto {
        let janela: AXUIElement
        let quadro: CGRect          // coordenadas da Acessibilidade
        let inicio: CGPoint
        let redimensionar: Bool
        let canto: ArrastoComTecla.Canto
    }

    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var arrasto: Arrasto?
    /// Botão apertado com as teclas mas sem janela embaixo (a mesa, o Dock):
    /// o soltar dele também é engolido.
    private var engolirSoltar = false
    private var pendente: CGRect?
    private var agendado = false
    private var store: DockaStore { .shared }

    func sincronizar() {
        let precisa = store.arrastarComTecla && Colagem.permitido
        if precisa && tap == nil { ligar() }
        if !precisa && tap != nil { desligar() }
    }

    private func ligar() {
        let tipos: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mascara = tipos.reduce(0) { $0 | (1 << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, e, _ in ArrastoComTeclaController.shared.tratar(tipo, e) },
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
        arrasto = nil; engolirSoltar = false; pendente = nil
    }

    private func tratar(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let passa = Unmanaged.passUnretained(e)
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return passa
        }
        guard e.getIntegerValueField(.eventSourceUserData) != MouseController.marca else { return passa }

        switch tipo {
        case .leftMouseDown, .rightMouseDown:
            let direito = tipo == .rightMouseDown
            let f = e.flags
            guard TeclasDoArrasto(persisted: store.arrastarTeclas)
                    .confere(comando: f.contains(.maskCommand), opcao: f.contains(.maskAlternate),
                             controle: f.contains(.maskControl)),
                  !direito || store.arrastarRedimensiona else { return passa }
            guard let janela = Self.janela(em: e.location), let quadro = Self.quadroAX(janela) else {
                engolirSoltar = true
                return nil
            }
            arrasto = Arrasto(janela: janela, quadro: quadro, inicio: e.location, redimensionar: direito,
                              canto: ArrastoComTecla.canto(clique: e.location, quadro: quadro))
            DispatchQueue.main.async { AXUIElementPerformAction(janela, kAXRaiseAction as CFString) }
            return nil

        case .leftMouseDragged, .rightMouseDragged:
            guard let a = arrasto else { return engolirSoltar ? nil : passa }
            let p = e.location
            let delta = CGPoint(x: p.x - a.inicio.x, y: p.y - a.inicio.y)
            aplicar(a.redimensionar
                    ? ArrastoComTecla.redimensionar(a.quadro, delta: delta, canto: a.canto)
                    : ArrastoComTecla.mover(a.quadro, delta: delta))
            return nil

        case .leftMouseUp, .rightMouseUp:
            if arrasto != nil || engolirSoltar {
                arrasto = nil
                engolirSoltar = false
                return nil
            }
            return passa

        default:
            return passa
        }
    }

    /// Fora do tap e um por vez: os arrastos chegam mais rápido do que um app
    /// lento aceita mudar de lugar, e o tap não pode esperar por ele.
    private func aplicar(_ r: CGRect) {
        pendente = r
        guard !agendado, let janela = arrasto?.janela else { return }
        let redimensionar = arrasto?.redimensionar ?? false
        agendado = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.agendado = false
            guard let r = self.pendente else { return }
            self.pendente = nil
            var ponto = r.origin, tamanho = r.size
            if redimensionar, let t = AXValueCreate(.cgSize, &tamanho) {
                AXUIElementSetAttributeValue(janela, kAXSizeAttribute as CFString, t)
            }
            if let p = AXValueCreate(.cgPoint, &ponto) {
                AXUIElementSetAttributeValue(janela, kAXPositionAttribute as CFString, p)
            }
        }
    }

    // MARK: Acessibilidade

    /// A janela de outro app sob o cursor — nunca as do próprio Docka, nem a
    /// mesa do Finder ou o Dock, que não são janelas.
    private static func janela(em p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success,
              let el else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        guard pid != getpid() else { return nil }
        var w: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &w) != .success { w = el }
        guard let w, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        let janela = w as! AXUIElement
        var papel: CFTypeRef?
        AXUIElementCopyAttributeValue(janela, kAXRoleAttribute as CFString, &papel)
        guard (papel as? String) == kAXWindowRole as String else { return nil }
        // tela cheia não se move
        var cheia: CFTypeRef?
        if AXUIElementCopyAttributeValue(janela, "AXFullScreen" as CFString, &cheia) == .success,
           (cheia as? Bool) == true { return nil }
        return janela
    }

    private static func quadroAX(_ el: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, tv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &tv) == .success,
              let pv, let tv else { return nil }
        var ponto = CGPoint.zero, tamanho = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &ponto)
        AXValueGetValue(tv as! AXValue, .cgSize, &tamanho)
        return CGRect(origin: ponto, size: tamanho)
    }
}
