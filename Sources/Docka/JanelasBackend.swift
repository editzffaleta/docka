import AppKit
import ApplicationServices
import DockaCore

/// Encaixe da janela da frente, pela Acessibilidade.
///
/// Mover a janela de OUTRO app exige a permissão de Acessibilidade — a mesma
/// do "Colar sozinho". Por isso o encaixe é um módulo opcional: nasce
/// desligado e pede a permissão só quando ligado.
enum JanelasBackend {

    /// Quadro de antes do primeiro encaixe, por janela — o "voltar".
    fileprivate static var anteriores: [String: CGRect] = [:]
    /// O último encaixe: qual janela, que layout, em que passo do ciclo e o
    /// quadro aplicado. Repetir o atalho só avança o ciclo se a janela ainda
    /// estiver onde o Docka a deixou — mexeu nela à mão, recomeça da metade.
    private static var ultimo: (janela: String, layout: LayoutDeJanela, passo: Int, quadro: CGRect)?

    static func executar(_ layout: LayoutDeJanela) {
        guard DockaStore.shared.janelasControl else { return }
        guard Colagem.permitido else {
            Colagem.pedirPermissao()
            NSSound.beep()
            return
        }
        guard let janela = janelaDaFrente(), let atual = quadro(de: janela) else {
            NSSound.beep()
            return
        }
        let chave = identidade(janela)
        guard let tela = tela(de: atual) else { return }
        let area = tela.visibleFrame

        let destino: CGRect?
        switch layout {
        case .restaurar:
            destino = anteriores[chave]
            if destino != nil { anteriores[chave] = nil }
            ultimo = nil
        case .proximaTela:
            let telas = NSScreen.screens
            guard telas.count > 1, let i = telas.firstIndex(of: tela) else { NSSound.beep(); return }
            let outra = telas[(i + 1) % telas.count]
            destino = Encaixe.levar(atual, de: area, para: outra.visibleFrame)
            ultimo = nil
        default:
            var passo = 0
            if let u = ultimo, u.janela == chave, u.layout == layout, Encaixe.quaseIgual(u.quadro, atual) {
                passo = Encaixe.proximoPasso(depois: u.passo)
            }
            destino = Encaixe.quadro(layout, em: area, passo: passo, atual: atual)
            if let destino { ultimo = (chave, layout, passo, destino) }
        }
        guard let destino else { NSSound.beep(); return }
        // guarda o quadro de antes só no PRIMEIRO encaixe: encaixar de novo
        // não pode fazer o "voltar" voltar para outro encaixe
        if layout != .restaurar && anteriores[chave] == nil { anteriores[chave] = atual }
        definir(janela, destino)
    }

    // MARK: Acessibilidade

    private static func janelaDaFrente() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let elemento = AXUIElementCreateApplication(app.processIdentifier)
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXFocusedWindowAttribute as CFString, &valor) == .success,
              let valor, CFGetTypeID(valor) == AXUIElementGetTypeID() else { return nil }
        return (valor as! AXUIElement)
    }

    /// Chave estável da janela enquanto ela existe: o processo e o hash do
    /// elemento de Acessibilidade (o mesmo elemento devolve o mesmo hash).
    fileprivate static func identidade(_ janela: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(janela, &pid)
        return "\(pid):\(CFHash(janela))"
    }

    fileprivate static var alturaDaPrincipal: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// O quadro da janela em coordenadas do AppKit.
    fileprivate static func quadro(de janela: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, t: CFTypeRef?
        guard AXUIElementCopyAttributeValue(janela, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(janela, kAXSizeAttribute as CFString, &t) == .success,
              let p, let t else { return nil }
        var ponto = CGPoint.zero, tamanho = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &ponto)
        AXValueGetValue(t as! AXValue, .cgSize, &tamanho)
        return Encaixe.doAcessibilidade(CGRect(origin: ponto, size: tamanho),
                                        alturaDaPrincipal: alturaDaPrincipal)
    }

    /// Aplica tamanho, posição e tamanho de novo. A segunda vez não é
    /// descuido: ao mudar de tela, alguns apps recusam o tamanho que não
    /// cabia na tela de ANTES; repetido depois de mover, ele entra.
    fileprivate static func definir(_ janela: AXUIElement, _ r: CGRect) {
        let ax = Encaixe.paraAcessibilidade(r, alturaDaPrincipal: alturaDaPrincipal)
        var ponto = ax.origin, tamanho = ax.size
        guard let p = AXValueCreate(.cgPoint, &ponto), let t = AXValueCreate(.cgSize, &tamanho) else { return }
        AXUIElementSetAttributeValue(janela, kAXSizeAttribute as CFString, t)
        AXUIElementSetAttributeValue(janela, kAXPositionAttribute as CFString, p)
        AXUIElementSetAttributeValue(janela, kAXSizeAttribute as CFString, t)
    }

    /// A tela que contém o centro da janela (a da maior parte dela).
    private static func tela(de r: CGRect) -> NSScreen? {
        let centro = CGPoint(x: r.midX, y: r.midY)
        return NSScreen.screens.first { NSMouseInRect(centro, $0.frame, false) } ?? NSScreen.main
    }
}

// MARK: - Arrastar até a borda

/// Encaixe arrastando a janela até a borda, com a prévia de onde ela vai
/// parar.
///
/// Perceber o arrasto não pede permissão: monitores globais de MOUSE só
/// observam. Saber qual janela está sendo arrastada e encaixá-la ao soltar
/// usa a mesma Acessibilidade do encaixe por atalho.
final class ArrastoDeJanelas {
    static let shared = ArrastoDeJanelas()

    private var monitores: [Any] = []
    private var janela: AXUIElement?
    private var posicaoInicial: CGPoint?
    private var arrastando = false
    private var zona: LayoutDeJanela?
    private var previa: NSPanel?

    func sincronizar() {
        let s = DockaStore.shared
        let precisa = s.janelasControl && s.janelasArrastar && Colagem.permitido
        if precisa && monitores.isEmpty {
            monitores = [
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.apertou() },
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.arrastou() },
                NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.soltou() },
            ].compactMap { $0 }
        } else if !precisa && !monitores.isEmpty {
            monitores.forEach(NSEvent.removeMonitor)
            monitores = []
            zerar()
        }
    }

    /// A janela sob o cursor, e onde ela estava — se ela mudar de lugar no
    /// arrasto, é uma janela sendo movida (e não texto sendo selecionado).
    private func apertou() {
        zerar()
        let loc = NSEvent.mouseLocation
        let ax = CGPoint(x: loc.x, y: JanelasBackend.alturaDaPrincipal - loc.y)
        var elemento: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(ax.x), Float(ax.y),
                                               &elemento) == .success, let elemento else { return }
        var w: CFTypeRef?
        // o próprio elemento pode já ser a janela; senão, a janela dele
        if AXUIElementCopyAttributeValue(elemento, kAXWindowAttribute as CFString, &w) != .success {
            w = elemento
        }
        guard let w, CFGetTypeID(w) == AXUIElementGetTypeID() else { return }
        let alvo = w as! AXUIElement
        janela = alvo
        posicaoInicial = JanelasBackend.quadro(de: alvo)?.origin
    }

    private func arrastou() {
        guard let janela, let inicio = posicaoInicial else { return }
        if !arrastando {
            // só confirma o arrasto quando a janela de fato andou
            guard let agora = JanelasBackend.quadro(de: janela)?.origin,
                  hypot(agora.x - inicio.x, agora.y - inicio.y) > 2 else { return }
            arrastando = true
        }
        let loc = NSEvent.mouseLocation
        guard let tela = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) else { return }
        let nova = Encaixe.zona(cursor: loc, tela: tela.frame)
        guard nova != zona else { return }
        zona = nova
        if let nova, let destino = Encaixe.quadro(nova, em: tela.visibleFrame) {
            mostrarPrevia(destino)
        } else {
            previa?.orderOut(nil)
        }
    }

    private func soltou() {
        defer { zerar() }
        guard arrastando, let janela, let zona else { return }
        let loc = NSEvent.mouseLocation
        guard let tela = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }),
              let destino = Encaixe.quadro(zona, em: tela.visibleFrame) else { return }
        let chave = JanelasBackend.identidade(janela)
        // "voltar" devolve ao tamanho de antes do arrasto
        if JanelasBackend.anteriores[chave] == nil, let atual = JanelasBackend.quadro(de: janela) {
            JanelasBackend.anteriores[chave] = atual
        }
        // um instante depois: o app ainda está terminando o próprio arrasto
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            JanelasBackend.definir(janela, destino)
        }
    }

    private func zerar() {
        janela = nil
        posicaoInicial = nil
        arrastando = false
        zona = nil
        previa?.orderOut(nil)
    }

    private func mostrarPrevia(_ quadro: CGRect) {
        let p = previa ?? {
            let p = NSPanel(contentRect: quadro, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.level = .floating
            let v = NSView()
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
            v.layer?.borderWidth = 2
            v.layer?.cornerRadius = 12
            p.contentView = v
            previa = p
            return p
        }()
        p.setFrame(quadro.insetBy(dx: 6, dy: 6), display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        p.orderFrontRegardless()
    }
}
