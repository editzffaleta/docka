import AppKit
import Carbon.HIToolbox
import DockaCore

/// Os atalhos globais do Docka.
///
/// Usa `RegisterEventHotKey` (Carbon): funciona sem permissão de Acessibilidade.
/// O handler é instalado uma única vez; só os registros trocam quando o usuário
/// muda alguma combinação.
///
/// Já foi um atalho só. Com mais de uma bandeja isso não dava conta — o atalho
/// servia a primeira e as outras ficavam sem —, então agora são vários, cada um
/// com sua ação. O handler descobre qual disparou pelo `EventHotKeyID` que vem
/// no próprio evento.
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

    private struct Registro {
        let acao: String
        let ref: EventHotKeyRef
    }

    /// Por número do Carbon — é ele que volta no evento.
    private var registros: [UInt32: Registro] = [:]
    private var handlerInstalled = false

    /// Recebe o id da ação que disparou.
    var onPress: ((String) -> Void)?

    /// Troca TODOS os registros de uma vez. Devolve as falhas por ação.
    ///
    /// Substituir o conjunto inteiro, em vez de mexer de um em um, evita o
    /// estado intermediário em que uma combinação recém-liberada ainda consta
    /// registrada e o novo dono é recusado por "já em uso".
    @discardableResult
    func aplicar(_ atalhos: [String: Shortcut]) -> [String: Falha] {
        installHandlerIfNeeded()
        desregistrarTudo()

        var falhas: [String: Falha] = [:]
        // numeração de 1 a N a cada aplicação, e não um contador que só cresce:
        // como tudo foi desregistrado logo acima, reaproveitar os números é
        // seguro e mantém o espaço pequeno e legível no diagnóstico
        for (numero, par) in atalhos.sorted(by: { $0.key < $1.key }).enumerated() {
            let (acao, atalho) = par
            guard atalho.isValid else { falhas[acao] = .invalido; continue }
            let numero = UInt32(numero + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(atalho.keyCode),
                carbonModifiers(atalho.modifiers),
                EventHotKeyID(signature: OSType(0x444F_4B41) /* "DOKA" */, id: numero),
                GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                // o ponteiro fica indefinido quando o registro falha
                falhas[acao] = status == OSStatus(eventHotKeyExistsErr)
                    ? .jaEmUso : .desconhecida(status)
                continue
            }
            registros[numero] = Registro(acao: acao, ref: ref)
        }
        return falhas
    }

    /// Sem isto os atalhos antigos continuariam registrados no sistema.
    func desregistrarTudo() {
        registros.values.forEach { UnregisterEventHotKey($0.ref) }
        registros.removeAll()
    }

    private func disparou(numero: UInt32) {
        guard let r = registros[numero] else { return }
        onPress?(r.acao)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, evento, _ -> OSStatus in
            // qual das combinações foi: o número vem no próprio evento
            var id = EventHotKeyID()
            let st = GetEventParameter(evento, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard st == noErr else { return noErr }
            let numero = id.id
            DispatchQueue.main.async { HotKeyManager.shared.disparou(numero: numero) }
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
