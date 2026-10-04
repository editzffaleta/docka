import AppKit
import Carbon.HIToolbox
import DockaCore

/// Expande gatilhos digitados em qualquer app: ";email" vira o snippet.
///
/// O módulo mais sensível do Docka, e por isso o mais contido:
/// - o tap é **só de escuta** (Monitoramento de Entrada): vê as teclas, não
///   as altera nem as engole;
/// - guarda só os últimos caracteres, **na memória**, o bastante para o maior
///   gatilho — nada vai para disco, log ou rede;
/// - campos de senha ficam de fora sozinhos: com a "entrada segura" ligada,
///   o macOS não entrega as teclas a tap nenhum;
/// - apagar o gatilho e colar o texto usa a Acessibilidade, como o "Colar
///   sozinho".
final class GatilhosController {
    static let shared = GatilhosController()

    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var detector = DetectorDeGatilho()
    private var store: DockaStore { .shared }

    // MARK: permissões

    static var podeEscutar: Bool { CGPreflightListenEventAccess() }
    static func pedirEscuta() { _ = CGRequestListenEventAccess() }

    static func abrirAjustesDeEscuta() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Escutar e agir: as duas permissões juntas.
    static var permitido: Bool { podeEscutar && Colagem.permitido }

    // MARK: o tap

    func sincronizar() {
        let precisa = store.gatilhosControl && Self.permitido
            && SnippetsModelo.shared.lista.contains { !$0.gatilho.isEmpty }
        if precisa && tap == nil { ligar() }
        if !precisa && tap != nil { desligar() }
    }

    private func ligar() {
        let mascara = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                        options: .listenOnly, eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, evento, _ in
                                            GatilhosController.shared.ouvir(tipo, evento)
                                            return Unmanaged.passUnretained(evento)
                                        }, userInfo: nil) else { return }
        tap = t
        fonte = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fonte, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func desligar() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let f = fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), f, .commonModes) }
        tap = nil
        fonte = nil
        detector.zerar()
    }

    /// Teclas que tiram o cursor do lugar: o que vem depois já não continua
    /// o que estava antes.
    private static let quebram: Set<Int64> = [
        Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter), Int64(kVK_Tab), Int64(kVK_Escape),
        Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow), Int64(kVK_DownArrow),
        Int64(kVK_Home), Int64(kVK_End), Int64(kVK_PageUp), Int64(kVK_PageDown), Int64(kVK_ForwardDelete),
    ]

    private func ouvir(_ tipo: CGEventType, _ e: CGEvent) {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        // as teclas que o próprio Docka posta (apagar, colar) não contam
        guard e.getIntegerValueField(.eventSourceUserData) != MouseController.marca else { return }
        guard tipo == .keyDown else { detector.zerar(); return }   // clique muda o cursor de lugar

        let codigo = e.getIntegerValueField(.keyboardEventKeycode)
        if e.flags.contains(.maskCommand) || e.flags.contains(.maskControl) || Self.quebram.contains(codigo) {
            detector.zerar()
            return
        }
        if codigo == Int64(kVK_Delete) { detector.apagou(); return }

        var tamanho = 0
        var chars = [UniChar](repeating: 0, count: 8)
        e.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &tamanho, unicodeString: &chars)
        guard tamanho > 0 else { return }   // tecla morta (acento): o caractere vem na próxima
        detector.digitou(String(utf16CodeUnits: chars, count: tamanho))

        guard let s = detector.procurar(em: SnippetsModelo.shared.lista) else { return }
        // fora do tap: o caractere que completou o gatilho ainda está a
        // caminho do app, e o apagar tem de vir depois dele
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Self.expandir(s)
        }
    }

    private static func expandir(_ s: Snippet) {
        let texto = SnippetsModelo.expandido(s)
        apagar(s.gatilho.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Colagem.inserir(texto, forcar: true)
        }
    }

    /// Apaga `n` caracteres com ⌫ sintético, marcado para o próprio tap
    /// ignorar.
    private static func apagar(_ n: Int) {
        let fonte = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<n {
            for desce in [true, false] {
                let e = CGEvent(keyboardEventSource: fonte, virtualKey: CGKeyCode(kVK_Delete), keyDown: desce)
                e?.setIntegerValueField(.eventSourceUserData, value: MouseController.marca)
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: autoteste

    /// Passa teclas fabricadas pelo mesmo caminho do tap, sem tap e sem
    /// postar nada — confere a leitura dos caracteres e o detector.
    static func autoteste() -> String {
        var r: [String] = []
        let lista = [Snippet(nome: "teste", texto: "ok", gatilho: ";tt")]
        var d = DetectorDeGatilho()
        func tecla(_ c: Character) -> CGEvent {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            var u = Array(String(c).utf16)
            e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
            return e
        }
        var achou: Snippet?
        for c in "oi ;tt" {
            var tamanho = 0
            var chars = [UniChar](repeating: 0, count: 8)
            tecla(c).keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &tamanho, unicodeString: &chars)
            d.digitou(String(utf16CodeUnits: chars, count: tamanho))
            achou = d.procurar(em: lista) ?? achou
        }
        r.append("\(achou?.nome == "teste" ? "OK" : "FALHOU") — \"oi ;tt\" lido do evento dispara o gatilho")
        r.append("monitoramento de entrada: \(podeEscutar ? "concedido" : "não concedido")")
        r.append("acessibilidade: \(Colagem.permitido ? "concedida" : "não concedida")")
        return r.joined(separator: "\n")
    }
}
