import AppKit
import DockaCore

/// Escuta um botão extra do mouse no sistema inteiro.
///
/// **Por que isto não pede permissão.** `NSEvent.addGlobalMonitorForEvents`
/// exige Acessibilidade para eventos de TECLADO; para eventos de mouse, não. É
/// a diferença entre observar e interceptar: um monitor global só é avisado,
/// nunca consome o evento nem o modifica. Um `CGEventTap`, que consumiria,
/// exigiria Monitoramento de Entrada — e por isso não está aqui.
///
/// A consequência dessa escolha é honesta e precisa ser dita: **o clique
/// continua chegando no app que estiver embaixo**. Num navegador, o botão
/// lateral vai navegar para trás ao mesmo tempo em que abre a órbita. Escolha
/// um botão que você não use para outra coisa.
final class MonitorDeBotao {
    /// Número do botão vigiado.
    var botao: Int

    /// Chamados com o botão pressionado e solto.
    var aoApertar: (() -> Void)?
    var aoSoltar: ((TimeInterval) -> Void)?

    private var global: Any?
    private var local: Any?
    private var apertadoEm: Date?

    init(botao: Int) {
        self.botao = botao
        ligar()
    }

    deinit { desligar() }

    private func ligar() {
        let tipos: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]
        global = NSEvent.addGlobalMonitorForEvents(matching: tipos) { [weak self] e in
            self?.tratar(e)
        }
        // o global não enxerga eventos entregues ao PRÓPRIO app; sem este, o
        // botão morreria justamente com a janela de ajustes em foco
        local = NSEvent.addLocalMonitorForEvents(matching: tipos) { [weak self] e in
            self?.tratar(e)
            return e
        }
    }

    func desligar() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil
    }

    private func tratar(_ e: NSEvent) {
        guard BotaoDoMouse.valido(botao), e.buttonNumber == botao else { return }
        switch e.type {
        case .otherMouseDown:
            apertadoEm = Date()
            aoApertar?()
        case .otherMouseUp:
            let duracao = apertadoEm.map { Date().timeIntervalSince($0) } ?? 0
            apertadoEm = nil
            aoSoltar?(duracao)
        default:
            break
        }
    }
}

/// Captura qual botão o usuário apertou, para os ajustes.
///
/// O número de cada botão lateral muda de mouse para mouse; perguntar é mais
/// confiável do que oferecer uma lista adivinhada.
final class CapturaDeBotao {
    private var monitorGlobal: Any?
    private var monitorLocal: Any?

    func comecar(_ aoCapturar: @escaping (Int) -> Void) {
        parar()
        let tipos: NSEvent.EventTypeMask = [.otherMouseDown]
        monitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: tipos) { [weak self] e in
            self?.parar(); aoCapturar(e.buttonNumber)
        }
        monitorLocal = NSEvent.addLocalMonitorForEvents(matching: tipos) { [weak self] e in
            self?.parar(); aoCapturar(e.buttonNumber)
            return nil          // não deixa o clique vazar para a janela
        }
    }

    func parar() {
        if let monitorGlobal { NSEvent.removeMonitor(monitorGlobal) }
        if let monitorLocal { NSEvent.removeMonitor(monitorLocal) }
        monitorGlobal = nil; monitorLocal = nil
    }
}
