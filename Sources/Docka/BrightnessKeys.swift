import Cocoa
import DockaCore

/// Ajusta o brilho da tela pela tecla de mídia do sistema.
///
/// Caminho **público**: `NSEvent.otherEvent` do tipo `.systemDefined` com o
/// subtipo 8, postado como `CGEvent`. Não pede permissão nenhuma — verificado
/// nesta máquina, o brilho responde de imediato.
///
/// As alternativas seriam `DisplayServices` ou `CoreDisplay`, ambas privadas:
/// leem e escrevem valores absolutos, mas somem sem aviso em atualizações do
/// macOS e quebrariam a regra de só usar API pública. Por isso o Docka fala com
/// o sistema em PASSOS e guarda o nível por conta própria.
enum BrightnessKeys {
    private static let up: Int32 = 2      // NX_KEYTYPE_BRIGHTNESS_UP
    private static let down: Int32 = 3    // NX_KEYTYPE_BRIGHTNESS_DOWN

    /// Manda `abs(n)` toques na direção do sinal.
    static func nudge(_ n: Int) {
        guard n != 0 else { return }
        let tecla = n > 0 ? up : down
        for _ in 0..<min(abs(n), Brightness.steps) {
            envia(tecla, pressionada: true)
            envia(tecla, pressionada: false)
        }
    }

    private static func envia(_ tecla: Int32, pressionada: Bool) {
        // o data1 empacota a tecla e o estado, como o teclado faz
        let estado: Int32 = pressionada ? 0xa : 0xb
        let flags = NSEvent.ModifierFlags(rawValue: UInt(estado) << 8)
        let data1 = Int((tecla << 16) | (estado << 8))
        NSEvent.otherEvent(with: .systemDefined, location: .zero,
                           modifierFlags: flags, timestamp: 0,
                           windowNumber: 0, context: nil,
                           subtype: 8, data1: data1, data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
}
