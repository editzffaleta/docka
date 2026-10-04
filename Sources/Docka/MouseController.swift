import AppKit
import Carbon.HIToolbox
import DockaCore

/// O módulo do mouse: inverter, rolagem linear e suave, rolar de lado e os
/// botões laterais.
///
/// Mudar a rolagem e os cliques de OUTROS apps exige interceptar os eventos —
/// um event tap ativo, que só existe com a permissão de Acessibilidade. O tap
/// só é criado com o módulo ligado e permitido; desligado, nada intercepta.
final class MouseController {
    static let shared = MouseController()

    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var relogio: Timer?
    /// Passos de deslize pendentes, um par (x, y) por quadro, somados quando
    /// os dentes chegam mais rápido que o deslize termina.
    private var fila: [(x: Double, y: Double)] = []
    private var sobra: (x: Double, y: Double) = (0, 0)

    /// Assinatura dos eventos que o próprio Docka posta: o tap os deixa
    /// passar, senão a rolagem suave se realimentaria sem fim.
    static let marca: Int64 = 0x444F_434B   // "DOCK"

    private var store: DockaStore { .shared }

    private var ajustes: AjustesDeRolagem {
        AjustesDeRolagem(inverterVertical: store.mouseInverterVertical,
                         inverterHorizontal: store.mouseInverterHorizontal,
                         linhasPorDente: store.mouseLinhas > 0 ? store.mouseLinhas : nil,
                         deLado: store.mouseDeLado > 0 ? Shortcut.Modifiers(rawValue: UInt32(store.mouseDeLado)) : nil)
    }

    /// Cria ou desfaz o tap conforme os ajustes e a permissão.
    func sincronizar() {
        let precisa = store.mouseControl && Colagem.permitido
        if precisa && tap == nil { ligar() }
        if !precisa && tap != nil { desligar() }
    }

    private func ligar() {
        let mascara = (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: CGEventMask(mascara),
                                        callback: { _, tipo, evento, _ in
                                            MouseController.shared.tratar(tipo, evento)
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
        relogio?.invalidate()
        relogio = nil
        fila = []
    }

    // MARK: o tap

    private func tratar(_ tipo: CGEventType, _ evento: CGEvent) -> Unmanaged<CGEvent>? {
        // o sistema pausa o tap que demora a responder: religa na hora, senão
        // o mouse volta ao normal em silêncio até o Docka reabrir
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(evento)
        }
        return processar(tipo, evento).map { Unmanaged.passUnretained($0) }
    }

    /// A decisão sobre um evento: devolve o evento (talvez mudado) ou `nil`
    /// para engoli-lo. Separado do tap para o autoteste exercitar sem
    /// instalar tap nenhum.
    func processar(_ tipo: CGEventType, _ e: CGEvent) -> CGEvent? {
        if e.getIntegerValueField(.eventSourceUserData) == Self.marca { return e }

        switch tipo {
        case .scrollWheel:
            // contínuo = trackpad ou Magic Mouse: fica como o sistema mandou
            guard e.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return e }
            let antes = Rolada(linhasY: e.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                               linhasX: e.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                               pontosY: Double(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
                               pontosX: Double(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)))
            let depois = Rolagem.transformar(antes, com: ajustes, modificadores: modificadores(e.flags))
            if store.mouseSuave {
                deslizar(x: depois.pontosX, y: depois.pontosY)
                return nil
            }
            escrever(depois, em: e)
            return e

        case .otherMouseDown, .otherMouseUp:
            guard store.mouseBotoes,
                  let nav = Rolagem.navegacao(botao: Int(e.getIntegerValueField(.mouseEventButtonNumber)),
                                              botaoDaOrbita: store.orbitaControl ? store.orbitaBotao : BotaoDoMouse.nenhum)
            else { return e }
            // age no apertar; o soltar também é engolido, senão o app de
            // baixo receberia um "soltar" sem "apertar"
            if tipo == .otherMouseDown {
                Colagem.enviarComando(nav == .voltar ? "[" : "]",
                                      reserva: CGKeyCode(nav == .voltar ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket))
            }
            return nil

        default:
            return e
        }
    }

    private func escrever(_ r: Rolada, em e: CGEvent) {
        e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: r.linhasY)
        e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: r.linhasX)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(r.pontosY))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(r.pontosX))
        // há apps que leem a versão em ponto fixo: as três têm de concordar
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(r.linhasY))
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(r.linhasX))
    }

    private func modificadores(_ f: CGEventFlags) -> Shortcut.Modifiers {
        var m: Shortcut.Modifiers = []
        if f.contains(.maskCommand) { m.insert(.command) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        if f.contains(.maskControl) { m.insert(.control) }
        if f.contains(.maskShift) { m.insert(.shift) }
        return m
    }

    // MARK: rolagem suave

    /// Reparte o dente em quadros e soma à fila — dentes seguidos se somam e
    /// a página acelera, como na roda de verdade.
    private func deslizar(x: Double, y: Double) {
        let quadros = Int(Rolagem.duracaoSuave * Rolagem.quadrosPorSegundo)
        let px = Rolagem.passosSuaves(distancia: x, quadros: quadros)
        let py = Rolagem.passosSuaves(distancia: y, quadros: quadros)
        for i in 0..<quadros {
            if i < fila.count { fila[i].x += px[i]; fila[i].y += py[i] }
            else { fila.append((px[i], py[i])) }
        }
        guard relogio == nil else { return }
        let t = Timer(timeInterval: 1 / Rolagem.quadrosPorSegundo, repeats: true) { [weak self] _ in self?.quadro() }
        RunLoop.main.add(t, forMode: .common)
        relogio = t
    }

    private func quadro() {
        guard !fila.isEmpty else {
            relogio?.invalidate(); relogio = nil; sobra = (0, 0); return
        }
        let p = fila.removeFirst()
        // a fração que não cabe num pixel fica para o próximo quadro
        let x = p.x + sobra.x, y = p.y + sobra.y
        let ix = x.rounded(.towardZero), iy = y.rounded(.towardZero)
        sobra = (x - ix, y - iy)
        guard ix != 0 || iy != 0,
              let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: Self.marca)
        e.post(tap: .cgSessionEventTap)
    }

    // MARK: autoteste

    /// Passa eventos de rolagem fabricados pela mesma decisão do tap, sem
    /// instalar tap e sem postar nada.
    static func autoteste() -> String {
        let m = MouseController.shared
        let s = DockaStore.shared
        let guardados = (s.mouseInverterVertical, s.mouseLinhas, s.mouseSuave)
        defer { (s.mouseInverterVertical, s.mouseLinhas, s.mouseSuave) = guardados }
        s.mouseSuave = false

        func roda(_ linhas: Int32, continuo: Bool = false) -> CGEvent {
            let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                            wheel1: linhas, wheel2: 0, wheel3: 0)!
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuo ? 1 : 0)
            return e
        }
        var r: [String] = []
        func conferir(_ nome: String, _ ok: Bool) { r.append("\(ok ? "OK" : "FALHOU") — \(nome)") }

        s.mouseInverterVertical = true; s.mouseLinhas = 0
        let inv = m.processar(.scrollWheel, roda(2))
        conferir("roda invertida (2 → \(inv?.getIntegerValueField(.scrollWheelEventDeltaAxis1) ?? 99))",
                 inv?.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -2)

        let tp = m.processar(.scrollWheel, roda(2, continuo: true))
        conferir("trackpad intocado", tp?.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 2)

        s.mouseInverterVertical = false; s.mouseLinhas = 3
        let lin = m.processar(.scrollWheel, roda(7))
        conferir("linear: 7 linhas viram 3", lin?.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3)

        let proprio = roda(5)
        proprio.setIntegerValueField(.eventSourceUserData, value: marca)
        conferir("evento do próprio Docka passa direto",
                 m.processar(.scrollWheel, proprio)?.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 5)

        r.append("acessibilidade: \(Colagem.permitido ? "concedida" : "não concedida") — sem ela o tap não é criado")
        return r.joined(separator: "\n")
    }
}
