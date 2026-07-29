import AppKit
import Carbon.HIToolbox
import DockaCore

/// Atalho global para mostrar/esconder a bandeja.
///
/// Usa `RegisterEventHotKey` (Carbon): funciona sem permissão de Acessibilidade.
/// O handler de evento é instalado uma única vez; só o registro do atalho troca
/// quando o usuário escolhe outra combinação.
final class HotKeyManager {
    static let shared = HotKeyManager()

    enum Falha: Equatable {
        case invalido            // faltou ⌘/⌥/⌃
        case jaEmUso             // outro app já registrou essa combinação
        case desconhecida(OSStatus)

        var mensagem: String {
            switch self {
            case .invalido:  return "Use pelo menos ⌘, ⌥ ou ⌃ na combinação."
            case .jaEmUso:   return "Esse atalho já está em uso por outro app."
            case .desconhecida(let s): return "O macOS recusou o atalho (código \(s))."
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false
    var onPress: (() -> Void)?

    /// Troca o atalho ativo. Devolve `nil` em caso de sucesso.
    @discardableResult
    func apply(_ shortcut: Shortcut) -> Falha? {
        installHandlerIfNeeded()
        unregister()

        guard shortcut.isValid else { return .invalido }

        let id = EventHotKeyID(signature: OSType(0x444F_4B41) /* "DOKA" */, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         carbonModifiers(shortcut.modifiers),
                                         id,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        guard status == noErr else {
            // o ponteiro fica indefinido quando o registro falha
            hotKeyRef = nil
            return status == OSStatus(eventHotKeyExistsErr) ? .jaEmUso : .desconhecida(status)
        }
        return nil
    }

    /// Sem isto o atalho antigo continuava registrado no sistema para sempre.
    func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
            return noErr
        }, 1, &eventType, nil, nil)
        handlerInstalled = (status == noErr)
    }

    private func carbonModifiers(_ m: Shortcut.Modifiers) -> UInt32 {
        var out: Int = 0
        if m.contains(.command) { out |= cmdKey }
        if m.contains(.shift)   { out |= shiftKey }
        if m.contains(.option)  { out |= optionKey }
        if m.contains(.control) { out |= controlKey }
        return UInt32(out)
    }
}

extension Shortcut {
    /// Constrói o atalho a partir de um `NSEvent` de tecla capturado pelo gravador.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        var mods: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift)   { mods.insert(.shift) }
        if flags.contains(.option)  { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        self.init(keyCode: event.keyCode, modifiers: mods)
    }
}
