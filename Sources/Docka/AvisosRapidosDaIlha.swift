import AppKit
import CoreAudio
import DockaCore

/// Os avisos rápidos da ilha: carregador, bateria baixa, fones, volume,
/// brilho e "copiado". Uma leitura leve quatro vezes por segundo, numa fila
/// à parte — o Core Audio pode segurar quem pergunta (ver o mixer), e a ilha
/// não pode esperar. A primeira leitura só marca o ponto de partida: nada é
/// avisado ao abrir.
final class AvisosRapidosModelo {
    static let shared = AvisosRapidosModelo()

    private(set) var lista: [AvisosDaIlha.Temporaria] = []
    /// A ilha refaz as asas na hora em que chega um aviso.
    var aoAvisar: (() -> Void)?

    private let fila = DispatchQueue(label: "docka.avisos", qos: .utility)
    private var relogio: Timer?
    private var lendo = false
    private var leituras = 0
    // só usados na fila
    private var bateria: (fracao: Double, naTomada: Bool)?
    private var volume: Double?
    private var brilho: Double?
    private var saida: AudioObjectID?
    private var copias: Int?

    private var store: DockaStore { .shared }

    func ligar(_ quer: Bool) {
        if quer, relogio == nil {
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.ler() }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            relogio = t
        } else if !quer {
            relogio?.invalidate(); relogio = nil
            lista = []
        }
    }

    private struct Quer { let bateria, fones, volume, brilho, copiado: Bool }

    private func ler() {
        guard !lendo else { return }
        lendo = true
        leituras += 1
        let quer = Quer(bateria: store.ilhaAvisoBateria, fones: store.ilhaAvisoFones, volume: store.ilhaAvisoVolume,
                        brilho: store.ilhaAvisoBrilho, copiado: store.ilhaAvisoCopiado)
        let n = leituras
        let copiasAgora = NSPasteboard.general.changeCount
        fila.async { [weak self] in
            guard let self else { return }
            var novos: [(Ilha.Atividade, TimeInterval)] = []
            // a bateria muda devagar: uma vez por segundo basta
            if n % 4 == 1, let b = LeitorDoSistema.bateria() {
                let agora = (fracao: b.fracao, naTomada: b.naTomada)
                if quer.bateria, let e = AvisosDaIlha.bateria(antes: self.bateria, agora: agora) {
                    novos.append(Self.atividade(e, carregando: b.carregando))
                }
                self.bateria = agora
            }
            if let s = SaidasDeAudio.padrao {
                if quer.fones, let antes = self.saida, antes != s, let nome = SaidasDeAudio.texto(s, kAudioObjectPropertyName),
                   AvisosDaIlha.ehFone(nome: nome, bluetooth: Self.bluetooth(s)) {
                    let curto = nome.count > 18 ? String(nome.prefix(17)) + "…" : nome
                    novos.append((Ilha.Atividade(id: "fones", tipo: .nivel, simbolo: AvisosDaIlha.simboloDoFone(nome),
                                                 valor: curto, prioridade: 90), 4))
                }
                self.saida = s
            }
            if let v = VolumeBackend.ler() {
                if quer.volume, AvisosDaIlha.mudou(self.volume, v) {
                    novos.append((Ilha.Atividade(id: "volume", tipo: .nivel,
                                                 simbolo: v < 0.005 ? "speaker.slash.fill" : (v < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
                                                 valor: AvisosDaIlha.porcentagem(v), prioridade: 95, progresso: v), 1.6))
                }
                self.volume = v
            }
            if let b = BrightnessBackend.ler(Self.telaDoMac) {
                if quer.brilho, AvisosDaIlha.mudou(self.brilho, b) {
                    novos.append((Ilha.Atividade(id: "brilho", tipo: .nivel, simbolo: "sun.max.fill",
                                                 valor: AvisosDaIlha.porcentagem(b), prioridade: 95, progresso: b), 1.6))
                }
                self.brilho = b
            }
            if quer.copiado, let antes = self.copias, antes != copiasAgora {
                novos.append((Ilha.Atividade(id: "copiado", tipo: .nivel, simbolo: "doc.on.clipboard.fill",
                                             valor: "Copiado", prioridade: 85), 1.4))
            }
            self.copias = copiasAgora
            DispatchQueue.main.async {
                self.lendo = false
                guard !novos.isEmpty else { return }
                let agora = Date()
                for (a, d) in novos {
                    self.lista = AvisosDaIlha.juntar(.init(a, ate: agora.addingTimeInterval(d)), a: self.lista, agora: agora)
                }
                self.aoAvisar?()
            }
        }
    }

    func vivas() -> [Ilha.Atividade] { AvisosDaIlha.vivas(lista, agora: Date()) }

    private static func atividade(_ e: AvisosDaIlha.EventoDaBateria, carregando: Bool) -> (Ilha.Atividade, TimeInterval) {
        switch e {
        case .conectou(let f):
            return (.init(id: "bateria", tipo: .bateria, simbolo: "bolt.fill", valor: AvisosDaIlha.porcentagem(f),
                          prioridade: 90, progresso: f), 3.5)
        case .desconectou(let f):
            return (.init(id: "bateria", tipo: .nivel, simbolo: AvisosDaIlha.simboloDaBateria(f, carregando: false),
                          valor: AvisosDaIlha.porcentagem(f), prioridade: 90, progresso: f), 3)
        case .baixa(let f):
            return (.init(id: "bateria", tipo: .aviso, simbolo: AvisosDaIlha.simboloDaBateria(f, carregando: false),
                          valor: "Bateria \(AvisosDaIlha.porcentagem(f))", prioridade: 99, progresso: f), 6)
        }
    }

    /// A tela do próprio Mac (o brilho dos externos muda por outro caminho).
    private static var telaDoMac: CGDirectDisplayID? {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetActiveDisplayList(n, &ids, &n)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func bluetooth(_ d: AudioObjectID) -> Bool {
        var t: UInt32 = 0
        var tam = UInt32(MemoryLayout<UInt32>.size)
        var e = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(d, &e, 0, nil, &tam, &t) == noErr else { return false }
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }
}
