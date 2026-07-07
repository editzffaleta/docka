import AppKit
import Carbon.HIToolbox

// Atalho global ⌘⇧D para mostrar/esconder a bandeja.
// Usa RegisterEventHotKey (Carbon): funciona sem permissão de Acessibilidade.
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    var onPress: (() -> Void)?

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x444F4B41) /* "DOKA" */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D),
                            UInt32(cmdKey | shiftKey),
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }
}
