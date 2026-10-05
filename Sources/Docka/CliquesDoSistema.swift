import AppKit
import ApplicationServices
import DockaCore

/// Cliques que o Docka assume: o botão verde das janelas e os ícones do Dock
/// da Apple.
///
/// Um event tap ativo de clique (Acessibilidade). Em cada clique, pergunta à
/// Acessibilidade o que está sob o cursor; se não for o botão verde nem um
/// ícone de app no Dock, o clique segue como veio. Assumido, o "apertar" e o
/// "soltar" são engolidos juntos — o app de baixo não pode receber um soltar
/// sem apertar.
final class CliquesDoSistema {
    static let shared = CliquesDoSistema()

    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var engolirProximoSoltar = false
    private var store: DockaStore { .shared }

    func sincronizar() {
        let precisa = (store.botaoVerdeMaximiza || store.cliquesNoDock) && Colagem.permitido
        if precisa && tap == nil { ligar() }
        if !precisa && tap != nil { desligar() }
    }

    private func ligar() {
        let mascara = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, e, _ in CliquesDoSistema.shared.tratar(tipo, e) },
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
        engolirProximoSoltar = false
    }

    private func tratar(_ tipo: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        if tipo == .leftMouseUp {
            if engolirProximoSoltar { engolirProximoSoltar = false; return nil }
            return Unmanaged.passUnretained(e)
        }
        // clique duplo, triplo: só o primeiro interessa
        guard e.getIntegerValueField(.mouseEventClickState) == 1,
              let alvo = Self.elemento(em: e.location) else { return Unmanaged.passUnretained(e) }
        let comOpcao = e.flags.contains(.maskAlternate)

        if store.botaoVerdeMaximiza, let janela = Self.janelaDoBotaoVerde(sob: alvo, em: e.location) {
            if botaoVerde(janela, comOpcao: comOpcao) { engolirProximoSoltar = true; return nil }
        }
        if store.cliquesNoDock, let app = Self.appDoIconeDoDock(alvo) {
            if cliqueNoDock(app) { engolirProximoSoltar = true; return nil }
        }
        return Unmanaged.passUnretained(e)
    }

    // MARK: botão verde

    /// Maximiza na área útil, sem criar outro Espaço; na janela já
    /// maximizada, volta ao tamanho de antes. Devolve se assumiu o clique.
    private func botaoVerde(_ janela: AXUIElement, comOpcao: Bool) -> Bool {
        guard let quadro = JanelasBackend.quadro(de: janela),
              let tela = NSScreen.screens.first(where: { NSMouseInRect(CGPoint(x: quadro.midX, y: quadro.midY), $0.frame, false) })
        else { return false }
        let chave = JanelasBackend.identidade(janela)
        let anterior = JanelasBackend.anteriores[chave]
        switch BotaoVerde.acao(comOpcao: comOpcao, quadro: quadro, areaUtil: tela.visibleFrame,
                               temAnterior: anterior != nil) {
        case .deixar:
            return false
        case .maximizar:
            JanelasBackend.anteriores[chave] = quadro
            DispatchQueue.main.async { JanelasBackend.definir(janela, tela.visibleFrame) }
            return true
        case .restaurar:
            JanelasBackend.anteriores[chave] = nil
            if let anterior { DispatchQueue.main.async { JanelasBackend.definir(janela, anterior) } }
            return true
        }
    }

    // MARK: Dock

    /// O app já está na frente com janela à vista: o clique vira a ação
    /// escolhida. Fora disso, o Dock faz o de sempre.
    private func cliqueNoDock(_ app: NSRunningApplication) -> Bool {
        let janelas = Self.janelasVisiveis(de: app.processIdentifier)
        guard CliqueNoDock.assumir(appNaFrente: app.isActive, janelasVisiveis: janelas.count) else { return false }
        DispatchQueue.main.async {
            switch AcaoNoCliqueDoDock(persisted: self.store.acaoNoCliqueDoDock) {
            case .minimizar:
                for w in janelas { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            case .ocultar:
                app.hide()
            case .alternar:
                // a lista vem da frente para trás: a próxima é a segunda
                guard janelas.count > 1 else { return }
                let w = janelas[CliqueNoDock.proxima(atual: 0, total: janelas.count)]
                AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        }
        return true
    }

    // MARK: Acessibilidade

    /// O elemento sob o cursor. `location` do evento já vem com a origem no
    /// topo, como a Acessibilidade usa.
    private static func elemento(em p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success
        else { return nil }
        return el
    }

    private static func atributo(_ el: AXUIElement, _ nome: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, nome as CFString, &v) == .success ? v : nil
    }

    /// O botão verde: "tela cheia" na maioria dos apps, "zoom" nos que não
    /// têm tela cheia.
    private static func ehBotaoVerde(_ el: AXUIElement) -> Bool {
        let sub = atributo(el, kAXSubroleAttribute) as? String
        return sub == kAXFullScreenButtonSubrole as String || sub == kAXZoomButtonSubrole as String
    }

    /// A janela cujo botão verde está sob o cursor.
    ///
    /// Com o cursor parado sobre o botão, o macOS abre o menu de organizar
    /// janelas, e a Acessibilidade passa a devolver um item desse menu em vez
    /// do botão. Nesse caso, confere o botão verde da janela da frente pela
    /// posição dele.
    private static func janelaDoBotaoVerde(sob alvo: AXUIElement, em p: CGPoint) -> AXUIElement? {
        if ehBotaoVerde(alvo) { return janela(de: alvo) }
        guard (atributo(alvo, kAXRoleAttribute) as? String) == kAXMenuItemRole as String,
              let app = NSWorkspace.shared.frontmostApplication,
              let w = atributo(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        let janela = w as! AXUIElement
        guard let b = atributo(janela, kAXFullScreenButtonAttribute), CFGetTypeID(b) == AXUIElementGetTypeID(),
              let quadro = quadroAX(b as! AXUIElement), quadro.insetBy(dx: -2, dy: -2).contains(p) else { return nil }
        return janela
    }

    /// Quadro de um elemento em coordenadas da Acessibilidade (origem no topo).
    private static func quadroAX(_ el: AXUIElement) -> CGRect? {
        guard let pv = atributo(el, kAXPositionAttribute), let tv = atributo(el, kAXSizeAttribute) else { return nil }
        var ponto = CGPoint.zero, tamanho = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &ponto)
        AXValueGetValue(tv as! AXValue, .cgSize, &tamanho)
        return CGRect(origin: ponto, size: tamanho)
    }

    private static func janela(de el: AXUIElement) -> AXUIElement? {
        guard let w = atributo(el, kAXWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }

    /// O app de um ícone do Dock — só ícones de app, e só do processo do Dock.
    static func appDoIconeDoDock(_ el: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock",
              (atributo(el, kAXSubroleAttribute) as? String) == "AXApplicationDockItem",
              let url = atributo(el, kAXURLAttribute) as? URL else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
    }

    private static func janelasVisiveis(de pid: pid_t) -> [AXUIElement] {
        guard let lista = atributo(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return lista.filter { w in
            (atributo(w, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole as String
                && (atributo(w, kAXMinimizedAttribute) as? Bool) != true
        }
    }
}

// MARK: - Autoteste

extension CliquesDoSistema {
    /// Liga os taps de clique e de teclado por um instante e confere, na
    /// lista de taps do sistema, se eles existem — depois desliga tudo.
    static func autoteste() -> String {
        let s = DockaStore.shared
        var r = ["acessibilidade: \(Colagem.permitido ? "concedida" : "não concedida")",
                 "ajustes lidos: botão verde=\(s.botaoVerdeMaximiza) dock=\(s.cliquesNoDock) ⌘W=\(s.protecaoW)"]
        func meusTaps() -> Int {
            var n: UInt32 = 0
            CGGetEventTapList(0, nil, &n)
            var lista = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n))
            CGGetEventTapList(n, &lista, &n)
            return lista.filter { $0.tappingProcess == getpid() }.count
        }
        r.append("taps antes: \(meusTaps())")
        CliquesDoSistema.shared.sincronizar()
        ProtecaoController.shared.sincronizar()
        r.append("taps depois de sincronizar: \(meusTaps()) (esperado 2 se os ajustes estão ligados)")
        return r.joined(separator: "\n")
    }
}
