import Foundation
import IOKit.pwr_mgt
import DockaCore

/// Segura o Mac acordado com uma asserção de energia do IOKit.
///
/// É a mesma ferramenta do `caffeinate`: API pública e sem permissão. A
/// asserção morre junto com o processo, então um Docka encerrado (ou que
/// travou) nunca deixa o Mac preso acordado.
final class AcordadoBackend {
    static let shared = AcordadoBackend()

    private var assercao: IOPMAssertionID = 0
    private var ativa = false

    /// Liga (ou troca) a asserção.
    ///
    /// - `telaAcesa`: impede também a tela de apagar. Sem ele, só o sistema
    ///   fica acordado — downloads e builds continuam, mas a tela apaga.
    @discardableResult
    func ligar(telaAcesa: Bool) -> Bool {
        desligar()
        let tipo = telaAcesa ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                             : kIOPMAssertionTypePreventUserIdleSystemSleep
        // ASCII de propósito: o pmset e o Monitor de Atividade mostram o travessão como "?"
        let motivo = "Docka: Manter acordado" as CFString
        let r = IOPMAssertionCreateWithName(tipo as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            motivo, &assercao)
        ativa = (r == kIOReturnSuccess)
        return ativa
    }

    func desligar() {
        guard ativa else { return }
        IOPMAssertionRelease(assercao)
        ativa = false
        assercao = 0
    }

    /// Os tipos de asserção que ESTE processo segura agora, lidos do próprio
    /// sistema — é o que o autoteste confere, em vez de confiar no retorno.
    static func tiposAtivosDesteProcesso() -> Set<String> {
        var porProcesso: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&porProcesso) == kIOReturnSuccess,
              let mapa = porProcesso?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              let minhas = mapa[NSNumber(value: getpid())] else { return [] }
        return Set(minhas.compactMap { $0[kIOPMAssertionTypeKey] as? String })
    }

    static func autoteste(paraArquivo caminho: String? = nil) -> String {
        let r = autoteste()
        if let caminho { try? r.write(toFile: caminho, atomically: true, encoding: .utf8) }
        return r
    }

    static func autoteste() -> String {
        let b = AcordadoBackend()
        guard b.ligar(telaAcesa: true) else { return "FALHOU — o sistema recusou a asserção" }
        let comTela = tiposAtivosDesteProcesso()
        b.ligar(telaAcesa: false)
        let semTela = tiposAtivosDesteProcesso()
        b.desligar()
        let depois = tiposAtivosDesteProcesso()

        let tela = kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        let sistema = kIOPMAssertionTypePreventUserIdleSystemSleep as String
        guard comTela.contains(tela) else { return "FALHOU — tela acesa não apareceu: \(comTela)" }
        guard semTela.contains(sistema), !semTela.contains(tela) else {
            return "FALHOU — a troca não substituiu a asserção: \(semTela)"
        }
        guard depois.isEmpty else { return "FALHOU — sobrou asserção depois de desligar: \(depois)" }
        return "OK — tela acesa, só sistema e liberação conferidos no IOKit"
    }
}

/// O estado da sessão "manter acordado": quando acaba e o relógio que a encerra.
///
/// Fica fora do `DockaStore` de propósito: o tempo restante muda a cada minuto,
/// e publicar isso no store redesenharia a bandeja e os ajustes inteiros à toa.
final class AcordadoSessao: ObservableObject {
    static let shared = AcordadoSessao()

    /// `true` enquanto a asserção está de pé.
    @Published private(set) var ativo = false
    /// Fim da sessão; `nil` com ela ativa = sem limite.
    @Published private(set) var fim: Date?
    /// Rótulo do tempo restante, atualizado pelo relógio.
    @Published private(set) var restante = ""

    private var relogio: Timer?

    func ligar(_ duracao: DuracaoAcordado, telaAcesa: Bool) {
        guard AcordadoBackend.shared.ligar(telaAcesa: telaAcesa) else {
            desligar()
            return
        }
        fim = Acordado.fim(de: duracao, desde: Date())
        ativo = true
        atualizar()
        relogio?.invalidate()
        // a cada 15 s basta: o menu mostra minutos, e um relógio por segundo
        // acordaria a CPU à toa justo no recurso que lida com energia
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.atualizar() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        relogio = t
    }

    func desligar() {
        AcordadoBackend.shared.desligar()
        relogio?.invalidate()
        relogio = nil
        ativo = false
        fim = nil
        restante = ""
    }

    /// Troca a asserção sem mexer no fim — quando o ajuste da tela muda com a
    /// sessão rodando.
    func trocarTela(acesa: Bool) {
        guard ativo else { return }
        if !AcordadoBackend.shared.ligar(telaAcesa: acesa) { desligar() }
    }

    private func atualizar() {
        let agora = Date()
        if Acordado.expirou(ate: fim, agora: agora) {
            desligar()
            return
        }
        restante = Acordado.rotulo(restante: Acordado.restante(ate: fim, agora: agora))
    }
}
