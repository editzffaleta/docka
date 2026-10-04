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
    private static var anteriores: [String: CGRect] = [:]
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
    private static func identidade(_ janela: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(janela, &pid)
        return "\(pid):\(CFHash(janela))"
    }

    private static var alturaDaPrincipal: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// O quadro da janela em coordenadas do AppKit.
    private static func quadro(de janela: AXUIElement) -> CGRect? {
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
    private static func definir(_ janela: AXUIElement, _ r: CGRect) {
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
