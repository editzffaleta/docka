import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DockaCore

/// Colar sozinho no app da frente — o primeiro módulo do Docka que pede
/// permissão.
///
/// Enviar um ⌘V sintético exige **Acessibilidade**: sem ela, o macOS descarta
/// o evento em silêncio. Por isso o módulo nasce desligado, só pede a
/// permissão quando a pessoa o liga, e sem ela tudo continua funcionando como
/// antes — o item fica na área de transferência, pronto para o ⌘V dela.
enum Colagem {

    /// O Docka tem Acessibilidade agora?
    static var permitido: Bool { AXIsProcessTrusted() }

    /// Mostra o pedido do sistema (só aparece se ainda não foi concedido).
    static func pedirPermissao() {
        let opcao = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([opcao: true] as CFDictionary)
    }

    static func abrirAjustesDePrivacidade() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Cola no app da frente, se o módulo estiver ligado e permitido.
    /// Devolve `false` quando não colou — aí o conteúdo segue só copiado.
    ///
    /// Espera um instante antes: o painel do Docka acabou de soltar o teclado,
    /// e o ⌘V tem de chegar ao app de baixo, não ao painel.
    static var podeColar: Bool { DockaStore.shared.colarSozinho && permitido }

    @discardableResult
    static func colarSePuder(depois espera: TimeInterval = 0.12) -> Bool {
        guard podeColar else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) { enviarComandoV() }
        return true
    }

    /// Posta ⌘V. A tecla é a que produz "v" no layout ATUAL: no Dvorak, por
    /// exemplo, o "v" mora noutra tecla, e o código fixo do QWERTY colaria
    /// com a letra errada (⌘. no lugar de ⌘V).
    private static func enviarComandoV() {
        enviarComando("v", reserva: CGKeyCode(kVK_ANSI_V))
    }

    /// Posta ⌘ + a tecla que produz `letra` no layout em uso — também o
    /// ⌘[ / ⌘] dos botões laterais do mouse.
    static func enviarComando(_ letra: Character, reserva: CGKeyCode) {
        let tecla = codigoDaTecla(para: letra) ?? reserva
        let fonte = CGEventSource(stateID: .combinedSessionState)
        let desce = CGEvent(keyboardEventSource: fonte, virtualKey: tecla, keyDown: true)
        let sobe = CGEvent(keyboardEventSource: fonte, virtualKey: tecla, keyDown: false)
        desce?.flags = .maskCommand
        sobe?.flags = .maskCommand
        // marcados: os taps do próprio Docka (gatilhos) não leem de volta
        desce?.setIntegerValueField(.eventSourceUserData, value: MouseController.marca)
        sobe?.setIntegerValueField(.eventSourceUserData, value: MouseController.marca)
        desce?.post(tap: .cghidEventTap)
        sobe?.post(tap: .cghidEventTap)
    }

    /// Procura, no layout de teclado em uso, a tecla que digita `letra`.
    static func codigoDaTecla(para letra: Character) -> CGKeyCode? {
        guard let fonte = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(fonte, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let dados = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return dados.withUnsafeBytes { bytes -> CGKeyCode? in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for codigo in 0..<128 {
                var estado: UInt32 = 0
                var tamanho = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let r = UCKeyTranslate(layout, UInt16(codigo), UInt16(kUCKeyActionDown), 0,
                                       UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                       &estado, chars.count, &tamanho, &chars)
                if r == noErr, tamanho == 1,
                   String(utf16CodeUnits: chars, count: 1).lowercased() == String(letra) {
                    return CGKeyCode(codigo)
                }
            }
            return nil
        }
    }

    // MARK: inserir texto sem perder o que estava copiado

    /// Põe o texto na área de transferência, cola e, um instante depois,
    /// devolve o que estava lá antes — inserir um snippet não pode apagar o
    /// que a pessoa tinha copiado.
    ///
    /// Sem permissão, só copia: aí a pessoa cola com ⌘V, e o que estava antes
    /// fica no histórico, se ele estiver ligado.
    /// `forcar`: cola mesmo com o "Colar sozinho" desligado — os gatilhos
    /// digitados não têm outro jeito de entregar o texto. Ainda exige a
    /// Acessibilidade.
    static func inserir(_ texto: String, forcar: Bool = false) {
        let pb = NSPasteboard.general
        guard forcar ? permitido : podeColar else {
            pb.clearContents()
            pb.setString(texto, forType: .string)
            return
        }
        let anterior = salvar(pb)
        pb.clearContents()
        // marcado como passageiro: o histórico (o do Docka e os de outros
        // apps) não guarda o que só passou pela área de transferência
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
        pb.setString(texto, forType: .string)
        if forcar {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { enviarComandoV() }
        } else {
            colarSePuder()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            restaurar(anterior, em: pb)
        }
    }

    /// Cópia rasa de tudo que está na área de transferência, tipo a tipo.
    static func salvar(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t, $0) } })
        }
    }

    static func restaurar(_ itens: [[NSPasteboard.PasteboardType: Data]], em pb: NSPasteboard) {
        guard !itens.isEmpty else { return }
        pb.clearContents()
        pb.writeObjects(itens.map { tipos in
            let item = NSPasteboardItem()
            for (t, d) in tipos { item.setData(d, forType: t) }
            return item
        })
    }

    /// Sem mandar tecla nenhuma: confere a permissão, a tecla do "v" no
    /// layout atual e o salvar/restaurar num pasteboard PRIVADO.
    static func autoteste() -> String {
        var r = ["acessibilidade: \(permitido ? "concedida" : "não concedida")"]
        r.append("tecla do v no layout atual: \(codigoDaTecla(para: "v").map(String.init) ?? "não achada") (QWERTY = \(kVK_ANSI_V))")

        let pb = NSPasteboard(name: NSPasteboard.Name("docka.autoteste.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let rico = NSAttributedString(string: "original", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
        pb.writeObjects([rico])
        let antes = salvar(pb)
        pb.clearContents()
        pb.setString("snippet", forType: .string)
        restaurar(antes, em: pb)
        let voltou = pb.string(forType: .string) == "original" && pb.data(forType: .rtf) != nil
        r.append("\(voltou ? "OK" : "FALHOU") — o copiado antes (com formatação) volta depois de inserir")
        return r.joined(separator: "\n")
    }
}
