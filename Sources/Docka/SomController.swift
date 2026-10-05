import AppKit
import CoreAudio
import AudioToolbox
import DockaCore

/// Microfones e saídas pelo Core Audio: o que o macOS não oferece num lugar
/// só — a entrada preferida, o nível dela, silenciar todos os microfones,
/// trocar de saída num atalho e baixar o volume quando o fone sai.
///
/// Nenhuma permissão: é configuração de dispositivo, nada é gravado. (A
/// saída por app é outra história: passa o som pelo Docka, como o mixer.)
final class SomController {
    static let shared = SomController()

    private var store: DockaStore { .shared }
    private var mudo = Som.Mudo()
    /// Para os microfones sem "mudo" de hardware: o volume de antes.
    private var volumesAntes: [String: Float] = [:]
    private var eraFone = false
    private var saidaOuvida = AudioObjectID(kAudioObjectUnknown)
    private var ouvintes: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var saidaComOuvinte: (AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)?

    var microfonesMudos: Bool { mudo.ativo }

    func comecar() {
        let sistema = AudioObjectID(kAudioObjectSystemObject)
        for seletor in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
                        kAudioHardwarePropertyDefaultOutputDevice] {
            ouvir(sistema, seletor, escopo: kAudioObjectPropertyScopeGlobal) { [weak self] in self?.mudou() }
        }
        eraFone = foneAgora()
        ouvirFonteDaSaida()
        aplicarEntradaPreferida()
        MixerModelo.shared.sincronizarRegras()
    }

    /// Ao fechar o Docka: os microfones voltam como estavam.
    func encerrar() {
        if mudo.ativo { alternarMudo(aviso: false) }
    }

    private var assentando: DispatchWorkItem?

    private func mudou() {
        // espera a troca assentar: o sistema dispara várias notificações seguidas
        assentando?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.assentar() }
        assentando = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func assentar() {
        ouvirFonteDaSaida()
        conferirFone()
        aplicarEntradaPreferida()
        // microfone que chega com tudo silenciado também fica mudo
        if mudo.ativo { silenciarNovos() }
        NotificationCenter.default.post(name: .somMudou, object: nil)
    }

    // MARK: entradas

    struct Entrada: Identifiable, Equatable {
        let id: AudioObjectID
        let uid: String
        let nome: String
    }

    static func entradas() -> [Entrada] {
        SaidasDeAudio.dispositivos().compactMap { d in
            guard SaidasDeAudio.canais(d, escopo: kAudioObjectPropertyScopeInput) > 0,
                  let uid = SaidasDeAudio.texto(d, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix("docka."), !uid.hasPrefix("CADefaultDeviceAggregate"),
                  let nome = SaidasDeAudio.texto(d, kAudioObjectPropertyName) else { return nil }
            return Entrada(id: d, uid: uid, nome: nome)
        }
    }

    static var entradaPadrao: AudioObjectID? { padrao(kAudioHardwarePropertyDefaultInputDevice) }

    private static func padrao(_ seletor: AudioObjectPropertySelector) -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var tam = UInt32(MemoryLayout<AudioObjectID>.size)
        var end = AudioObjectPropertyAddress(mSelector: seletor, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &end, 0, nil, &tam, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func usarEntrada(_ id: AudioObjectID) {
        var v = id
        var end = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &end, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &v)
    }

    /// Os AirPods conectam e viram o microfone do sistema (com som de
    /// telefone); com uma preferida escolhida, o Docka devolve para ela.
    func aplicarEntradaPreferida() {
        let lista = Self.entradas()
        let atual = Self.entradaPadrao.flatMap(SaidasDeAudio.uid)
        guard let uid = Som.entradaParaUsar(preferida: store.entradaPreferida.isEmpty ? nil : store.entradaPreferida,
                                            conectadas: lista.map(\.uid), atual: atual),
              let e = lista.first(where: { $0.uid == uid }) else { return }
        Self.usarEntrada(e.id)
    }

    // MARK: nível e mudo das entradas

    private static func endereco(_ seletor: AudioObjectPropertySelector, _ elemento: UInt32 = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: seletor, mScope: kAudioDevicePropertyScopeInput, mElement: elemento)
    }

    /// Os elementos que têm volume: o principal, ou os canais um a um.
    private static func elementosDeVolume(_ d: AudioObjectID) -> [UInt32] {
        var e = endereco(kAudioDevicePropertyVolumeScalar)
        if AudioObjectHasProperty(d, &e) { return [kAudioObjectPropertyElementMain] }
        return (1...UInt32(max(1, SaidasDeAudio.canais(d, escopo: kAudioObjectPropertyScopeInput)))).filter {
            var c = endereco(kAudioDevicePropertyVolumeScalar, $0)
            return AudioObjectHasProperty(d, &c)
        }
    }

    static func nivelAjustavel(_ d: AudioObjectID) -> Bool {
        elementosDeVolume(d).contains { el in
            var e = endereco(kAudioDevicePropertyVolumeScalar, el)
            var pode: DarwinBoolean = false
            return AudioObjectIsPropertySettable(d, &e, &pode) == noErr && pode.boolValue
        }
    }

    static func nivel(_ d: AudioObjectID) -> Float? {
        guard let el = elementosDeVolume(d).first else { return nil }
        var e = endereco(kAudioDevicePropertyVolumeScalar, el)
        var v: Float32 = 0
        var tam = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(d, &e, 0, nil, &tam, &v) == noErr ? v : nil
    }

    static func definirNivel(_ d: AudioObjectID, _ nivel: Float) {
        for el in elementosDeVolume(d) {
            var e = endereco(kAudioDevicePropertyVolumeScalar, el)
            var v = Float32(min(1, max(0, nivel)))
            AudioObjectSetPropertyData(d, &e, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    static func temMudo(_ d: AudioObjectID) -> Bool {
        var e = endereco(kAudioDevicePropertyMute)
        var pode: DarwinBoolean = false
        return AudioObjectHasProperty(d, &e) && AudioObjectIsPropertySettable(d, &e, &pode) == noErr && pode.boolValue
    }

    static func estaMudo(_ d: AudioObjectID) -> Bool {
        var e = endereco(kAudioDevicePropertyMute)
        var m: UInt32 = 0
        var tam = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(d, &e, 0, nil, &tam, &m) == noErr else { return false }
        return m != 0
    }

    private static func definirMudo(_ d: AudioObjectID, _ sim: Bool) {
        var e = endereco(kAudioDevicePropertyMute)
        var m: UInt32 = sim ? 1 : 0
        AudioObjectSetPropertyData(d, &e, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }

    // MARK: silenciar todos

    func alternarMudo(aviso: Bool = true) {
        if mudo.ativo {
            let entradas = Self.entradas()
            for uid in mudo.religar() {
                guard let e = entradas.first(where: { $0.uid == uid }) else { continue }
                if let v = volumesAntes[uid] { Self.definirNivel(e.id, v) } else { Self.definirMudo(e.id, false) }
            }
            volumesAntes = [:]
            if aviso { DicaDeTecla.shared.mostrar("Microfones ligados", progresso: nil) }
        } else {
            silenciarNovos()
            if aviso { DicaDeTecla.shared.mostrar("Todos os microfones mudos", progresso: nil) }
        }
        store.playSound(mudo.ativo ? "Bottle" : "Pop", volume: 0.4)
        NotificationCenter.default.post(name: .somMudou, object: nil)
    }

    private func silenciarNovos() {
        let entradas = Self.entradas()
        // sem "mudo" de hardware, o microfone conta como "não estava mudo" e
        // é silenciado pelo volume
        let estados = Dictionary(entradas.map { ($0.uid, Self.temMudo($0.id) ? Self.estaMudo($0.id) : false) },
                                 uniquingKeysWith: { a, _ in a })
        for uid in mudo.silenciar(estados) {
            guard let e = entradas.first(where: { $0.uid == uid }) else { continue }
            if Self.temMudo(e.id) {
                Self.definirMudo(e.id, true)
            } else if Self.nivelAjustavel(e.id) {
                volumesAntes[uid] = Self.nivel(e.id) ?? 1
                Self.definirNivel(e.id, 0)
            }
        }
    }

    // MARK: saídas

    /// A próxima saída conectada, com o nome num aviso.
    func proximaSaida() {
        let lista = SaidasDeAudio.lista()
        let atual = SaidasDeAudio.padrao.flatMap(SaidasDeAudio.uid)
        guard let uid = Som.proxima(atual: atual, lista: lista.map(\.uid)),
              let s = lista.first(where: { $0.uid == uid }) else { NSSound.beep(); return }
        SaidasDeAudio.escolher(s.id)
        DicaDeTecla.shared.mostrar("Som em \(s.nome)", progresso: nil)
    }

    // MARK: fones

    private static func numero(_ d: AudioObjectID, _ seletor: AudioObjectPropertySelector,
                               escopo: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var e = AudioObjectPropertyAddress(mSelector: seletor, mScope: escopo, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(d, &e) else { return nil }
        var v: UInt32 = 0
        var tam = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(d, &e, 0, nil, &tam, &v) == noErr ? v : nil
    }

    private func foneAgora() -> Bool {
        guard let d = SaidasDeAudio.padrao else { return false }
        return Som.ehFone(transporte: Self.numero(d, kAudioDevicePropertyTransportType) ?? 0,
                          fonteDeDados: Self.numero(d, kAudioDevicePropertyDataSource, escopo: kAudioObjectPropertyScopeOutput))
    }

    private func conferirFone() {
        let agora = foneAgora()
        defer { eraFone = agora }
        guard store.baixarAoTirarFone, let volume = VolumeBackend.ler(),
              let novo = Som.volumeAoTirarFone(antes: eraFone, agora: agora, volume: Float(volume),
                                               limite: Float(store.volumeSemFone)) else { return }
        VolumeBackend.escrever(Double(novo))
        DicaDeTecla.shared.mostrar("Fone desconectado — volume em \(Som.porcentagem(novo))", progresso: nil)
    }

    /// O fone de fio troca só a "fonte" da saída embutida, sem trocar de
    /// dispositivo: é preciso ouvir essa propriedade na saída atual.
    private func ouvirFonteDaSaida() {
        guard let d = SaidasDeAudio.padrao, d != saidaOuvida else { return }
        if let (antiga, e, bloco) = saidaComOuvinte {
            var end = e
            AudioObjectRemovePropertyListenerBlock(antiga, &end, .main, bloco)
        }
        saidaOuvida = d
        var e = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource,
                                           mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(d, &e) else { saidaComOuvinte = nil; return }
        let bloco: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.mudou() }
        AudioObjectAddPropertyListenerBlock(d, &e, .main, bloco)
        saidaComOuvinte = (d, e, bloco)
    }

    private func ouvir(_ objeto: AudioObjectID, _ seletor: AudioObjectPropertySelector,
                       escopo: AudioObjectPropertyScope, _ acao: @escaping () -> Void) {
        var e = AudioObjectPropertyAddress(mSelector: seletor, mScope: escopo, mElement: kAudioObjectPropertyElementMain)
        let bloco: AudioObjectPropertyListenerBlock = { _, _ in acao() }
        AudioObjectAddPropertyListenerBlock(objeto, &e, .main, bloco)
        ouvintes.append((objeto, e, bloco))
    }
}

extension Notification.Name {
    /// Microfones, saídas ou o mudo mudaram: os ajustes relêem.
    static let somMudou = Notification.Name("docka.somMudou")
}

/// Uma linha no terminal quando `DOCKA_DIAGNOSTICO` está definido — para
/// acompanhar o que o som está fazendo sem um depurador.
func diagnostico(_ texto: String) {
    guard ProcessInfo.processInfo.environment["DOCKA_DIAGNOSTICO"] != nil else { return }
    print("[docka] \(texto)")
    fflush(stdout)
}

extension SomController {
    /// Autoteste no contexto real do app: lê os microfones, mexe no nível e
    /// no mudo de todos e devolve tudo como estava.
    static func autoteste() -> String {
        var r: [String] = []
        func conferir(_ nome: String, _ ok: Bool) { r.append("\(ok ? "OK" : "FALHOU") — \(nome)") }
        let entradas = entradas()
        r.append("entradas: " + entradas.map { "\($0.nome) (nível \(nivelAjustavel($0.id) ? "ajustável" : "fixo"), mudo \(temMudo($0.id) ? "sim" : "não"))" }.joined(separator: "; "))
        r.append("saídas: " + SaidasDeAudio.lista().map(\.nome).joined(separator: "; "))
        if let d = entradaPadrao, nivelAjustavel(d), let antes = nivel(d) {
            definirNivel(d, 0.42)
            let lido = nivel(d) ?? -1
            conferir("nível do microfone muda (0,42 → \(String(format: "%.2f", lido)))", abs(lido - 0.42) < 0.02)
            definirNivel(d, antes)
            conferir("nível volta ao de antes (\(String(format: "%.2f", antes)))", abs((nivel(d) ?? -1) - antes) < 0.02)
        }
        let antes = Dictionary(entradas.map { ($0.uid, (temMudo($0.id) ? estaMudo($0.id) : false, nivel($0.id))) },
                               uniquingKeysWith: { a, _ in a })
        shared.alternarMudo(aviso: false)
        let calados = entradas.filter { temMudo($0.id) ? estaMudo($0.id) : (nivel($0.id) ?? 1) == 0 }
        let silenciaveis = entradas.filter { temMudo($0.id) || nivelAjustavel($0.id) }
        conferir("silenciar todos: \(calados.count) de \(silenciaveis.count) silenciáveis mudos", calados.count == silenciaveis.count)
        shared.alternarMudo(aviso: false)
        let devolvidos = entradas.allSatisfy { e in
            guard let a = antes[e.uid] else { return true }
            let mudoOk = !temMudo(e.id) || estaMudo(e.id) == a.0
            let nivelOk = a.1.map { abs((nivel(e.id) ?? -1) - $0) < 0.02 } ?? true
            return mudoOk && nivelOk
        }
        conferir("religar devolve cada um como estava", devolvidos)
        return r.joined(separator: "\n")
    }
}
