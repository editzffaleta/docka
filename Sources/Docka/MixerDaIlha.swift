import SwiftUI
import AppKit
import CoreAudio
import AudioToolbox
import DockaCore

// MARK: - Core Audio: saídas e processos

/// As saídas de som e a escolhida no sistema.
enum SaidasDeAudio {
    struct Saida: Identifiable, Equatable {
        let id: AudioObjectID
        let uid: String
        let nome: String
    }

    static func lista() -> [Saida] {
        dispositivos().compactMap { d in
            guard canais(d, escopo: kAudioObjectPropertyScopeOutput) > 0,
                  let uid = texto(d, kAudioDevicePropertyDeviceUID),
                  let nome = texto(d, kAudioObjectPropertyName) else { return nil }
            // os agregados privados (inclusive os do próprio mixer) ficam de fora
            if uid.hasPrefix("docka.mixer.") { return nil }
            return Saida(id: d, uid: uid, nome: nome)
        }
    }

    static var padrao: AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var tam = UInt32(MemoryLayout<AudioObjectID>.size)
        var end = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &end, 0, nil, &tam, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func escolher(_ id: AudioObjectID) {
        var v = id
        var end = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &end, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &v)
    }

    static func uid(_ d: AudioObjectID) -> String? { texto(d, kAudioDevicePropertyDeviceUID) }

    private static func dispositivos() -> [AudioObjectID] {
        lista(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
    }

    static func lista(_ objeto: AudioObjectID, _ seletor: AudioObjectPropertySelector) -> [AudioObjectID] {
        var end = AudioObjectPropertyAddress(mSelector: seletor, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objeto, &end, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(tam) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(objeto, &end, 0, nil, &tam, &ids) == noErr else { return [] }
        return ids
    }

    private static func canais(_ d: AudioObjectID, escopo: AudioObjectPropertyScope) -> Int {
        var end = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: escopo,
                                             mElement: kAudioObjectPropertyElementMain)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(d, &end, 0, nil, &tam) == noErr, tam > 0 else { return 0 }
        let mem = UnsafeMutableRawPointer.allocate(byteCount: Int(tam), alignment: 16)
        defer { mem.deallocate() }
        guard AudioObjectGetPropertyData(d, &end, 0, nil, &tam, mem) == noErr else { return 0 }
        let lista = UnsafeMutableAudioBufferListPointer(mem.assumingMemoryBound(to: AudioBufferList.self))
        return lista.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func texto(_ objeto: AudioObjectID, _ seletor: AudioObjectPropertySelector) -> String? {
        var end = AudioObjectPropertyAddress(mSelector: seletor, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        var s: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objeto, &end, 0, nil, &tam, &s) == noErr, let s else { return nil }
        return s.takeRetainedValue() as String
    }
}

/// Os processos que o Core Audio conhece, com o pid, o identificador e se
/// estão tocando agora (macOS 14.2 em diante, API pública).
enum ProcessosDeAudio {
    struct Processo {
        let id: AudioObjectID
        let pid: pid_t
        let bundle: String
        let tocando: Bool
    }

    static func lista() -> [Processo] {
        SaidasDeAudio.lista(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).compactMap { p in
            let pid: pid_t = numero(p, kAudioProcessPropertyPID) ?? -1
            let tocando: UInt32 = numero(p, kAudioProcessPropertyIsRunningOutput) ?? 0
            guard pid > 0, pid != getpid(), let b = SaidasDeAudio.texto(p, kAudioProcessPropertyBundleID), !b.isEmpty
            else { return nil }
            return Processo(id: p, pid: pid, bundle: b, tocando: tocando != 0)
        }
    }

    private static func numero<T>(_ o: AudioObjectID, _ s: AudioObjectPropertySelector) -> T? {
        var end = AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        var tam = UInt32(MemoryLayout<T>.size)
        let mem = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { mem.deallocate() }
        guard AudioObjectGetPropertyData(o, &end, 0, nil, &tam, mem) == noErr else { return nil }
        return mem.pointee
    }
}

// MARK: - O desvio de um app

/// O som de um app passando pelo Docka com outro volume.
///
/// Um toque (`CATapDescription`) nos processos do app, que cala o som
/// original enquanto existe, e um dispositivo agregado privado — a saída de
/// som de verdade mais o toque — cujo IOProc copia o que entra para a saída,
/// multiplicado pelo ganho. Nada é gravado. Se o Docka fechar, o macOS
/// desfaz o toque e o app volta a soar normal.
protocol Desvio: AnyObject {
    var processos: Set<AudioObjectID> { get }
    func mudar(_ g: Float)
    func destruir()
}

@available(macOS 14.2, *)
final class DesvioDeApp: Desvio {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agregado = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private let canaisDoToque: Int
    /// Lido pela linha de áudio a cada bloco: um ponteiro, para a troca do
    /// ganho não precisar de trava.
    private let ganho = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let processos: Set<AudioObjectID>
    let saida: String

    init?(processos: [AudioObjectID], saidaUID: String, nome: String, ganho g: Float) {
        self.processos = Set(processos)
        self.saida = saidaUID
        ganho.pointee = g
        let desc = CATapDescription(stereoMixdownOfProcesses: processos)
        desc.uuid = UUID()
        desc.name = "Docka — \(nome)"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        canaisDoToque = 2
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr, tap != kAudioObjectUnknown else { ganho.deallocate(); return nil }

        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Docka — mixer",
            kAudioAggregateDeviceUIDKey: "docka.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: saidaUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: saidaUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &agregado) == noErr else {
            AudioHardwareDestroyProcessTap(tap); ganho.deallocate(); return nil
        }
        let g = ganho, nToque = canaisDoToque
        let r = AudioDeviceCreateIOProcIDWithBlock(&proc, agregado, nil) { _, entrada, _, saida, _ in
            Self.copiar(entrada, saida, ganho: g.pointee, canaisDoToque: nToque)
        }
        guard r == noErr, let proc, AudioDeviceStart(agregado, proc) == noErr else {
            destruir(); return nil
        }
    }

    func mudar(_ g: Float) { ganho.pointee = g }

    func destruir() {
        if let proc { AudioDeviceStop(agregado, proc); AudioDeviceDestroyIOProcID(agregado, proc) }
        proc = nil
        if agregado != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(agregado) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        agregado = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        destruir()
        ganho.deallocate()
    }

    /// Da entrada para a saída, canal a canal, com o ganho. Vale para
    /// buffers intercalados (um buffer, vários canais) e separados (um buffer
    /// por canal). Da entrada usa só os últimos canais — os do toque: se a
    /// saída também tiver microfone, os canais dele vêm antes e ficam de fora
    /// (senão o microfone iria parar nos alto-falantes).
    private static func copiar(_ entrada: UnsafePointer<AudioBufferList>, _ saida: UnsafeMutablePointer<AudioBufferList>,
                               ganho: Float, canaisDoToque: Int) {
        let ent = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: entrada))
        let sai = UnsafeMutableAudioBufferListPointer(saida)
        // (buffer, deslocamento, passo) de cada canal
        func mapa(_ l: UnsafeMutableAudioBufferListPointer) -> [(UnsafeMutablePointer<Float>, Int, Int, Int)] {
            var r: [(UnsafeMutablePointer<Float>, Int, Int, Int)] = []
            for b in l {
                guard let d = b.mData else { continue }
                let n = max(1, Int(b.mNumberChannels))
                let quadros = Int(b.mDataByteSize) / (MemoryLayout<Float>.size * n)
                for c in 0..<n { r.append((d.assumingMemoryBound(to: Float.self), c, n, quadros)) }
            }
            return r
        }
        let canaisSai = mapa(sai)
        let todosEnt = mapa(ent)
        let canaisEnt = Array(todosEnt.suffix(canaisDoToque))
        for (i, (dest, off, passo, quadros)) in canaisSai.enumerated() {
            guard !canaisEnt.isEmpty else {
                for f in 0..<quadros { dest[f * passo + off] = 0 }
                continue
            }
            let (orig, ooff, opasso, oquadros) = canaisEnt[min(i, canaisEnt.count - 1)]
            let n = min(quadros, oquadros)
            for f in 0..<n { dest[f * passo + off] = orig[f * opasso + ooff] * ganho }
            if quadros > n { for f in n..<quadros { dest[f * passo + off] = 0 } }
        }
    }
}

// MARK: - O modelo

final class MixerModelo: ObservableObject {
    static let shared = MixerModelo()

    struct App: Identifiable, Equatable {
        let id: String          // bundle do app dono
        let nome: String
        let icone: NSImage?
        let tocando: Bool
        let processos: [AudioObjectID]
    }

    @Published private(set) var apps: [App] = []
    @Published private(set) var saidas: [SaidasDeAudio.Saida] = []
    @Published private(set) var saidaAtual: AudioObjectID?
    /// O controle de cada app (1 = 100%). Só na memória: ao reabrir o Docka,
    /// tudo volta a 100% e nenhum som passa pelo Docka sem você pedir.
    @Published private(set) var controles: [String: Double] = [:]
    @Published private(set) var falhou: String?
    private var desvios: [String: Desvio] = [:]
    /// Criar o toque pode esperar a pessoa responder ao pedido de permissão
    /// do macOS: numa fila própria, para a ilha não travar enquanto isso.
    private let fila = DispatchQueue(label: "docka.mixer")
    private var criando: Set<String> = []
    private var relogio: Timer?

    func olhar(_ ligar: Bool) {
        if ligar, relogio == nil {
            atualizar()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.atualizar() }
            RunLoop.main.add(t, forMode: .common)
            relogio = t
        } else if !ligar {
            relogio?.invalidate()
            relogio = nil
        }
    }

    /// Relê os processos e as saídas numa fila à parte: com um pedido de
    /// permissão de áudio na tela, o Core Audio segura quem pergunta até a
    /// resposta — e a linha principal (a ilha inteira) não pode esperar.
    private let leitura = DispatchQueue(label: "docka.mixer.leitura")
    private var lendo = false

    func atualizar() {
        guard !simulando, !lendo else { return }
        lendo = true
        leitura.async { [weak self] in
            let processos = ProcessosDeAudio.lista()
            let saidas = SaidasDeAudio.lista()
            let padrao = SaidasDeAudio.padrao
            DispatchQueue.main.async {
                self?.lendo = false
                self?.aplicar(processos, saidas, padrao)
            }
        }
    }

    private func aplicar(_ processos: [ProcessosDeAudio.Processo], _ s: [SaidasDeAudio.Saida], _ atual: AudioObjectID?) {
        let todos = NSWorkspace.shared.runningApplications
        let rodando = todos.filter { $0.activationPolicy == .regular }
        let bundles = rodando.compactMap(\.bundleIdentifier)
        var grupos: [String: [ProcessosDeAudio.Processo]] = [:]
        for p in processos {
            grupos[MixerDaIlha.dono(p.bundle, apps: bundles), default: []].append(p)
        }
        let novos = grupos.compactMap { dono, ps -> App? in
            let tocando = ps.contains { $0.tocando }
            // fica na lista quem toca agora ou tem um volume próprio
            guard tocando || controles[dono] != nil else { return nil }
            // o app do Dock; senão, qualquer app com esse identificador (os
            // que tocam sem ícone no Dock), ou o dono do próprio processo
            let app = rodando.first { $0.bundleIdentifier == dono }
                ?? todos.first { $0.bundleIdentifier == dono }
                ?? ps.lazy.compactMap { NSRunningApplication(processIdentifier: $0.pid) }.first
            return App(id: dono, nome: app?.localizedName ?? dono, icone: app?.icon, tocando: tocando,
                       processos: ps.map(\.id))
        }.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
        if novos != apps { apps = novos }
        if s != saidas { saidas = s }
        let trocouSaida = atual != saidaAtual
        saidaAtual = atual
        // um processo novo do app (outra aba tocando) ou outra saída de som:
        // o desvio é refeito para incluir tudo
        for (bundle, d) in desvios {
            guard let app = novos.first(where: { $0.id == bundle }) else { continue }
            if trocouSaida || Set(app.processos) != d.processos, let c = controles[bundle] { refazer(bundle, c) }
        }
    }

    func mudar(_ bundle: String, _ controle: Double) {
        controles[bundle] = controle
        if MixerDaIlha.precisaDesviar(controle) {
            if let d = desvios[bundle] { d.mudar(MixerDaIlha.ganho(controle)) }
            else if !criando.contains(bundle) { refazer(bundle, controle) }
        } else {
            desvios[bundle]?.destruir()
            desvios[bundle] = nil
            controles[bundle] = nil
        }
    }

    private func refazer(_ bundle: String, _ controle: Double) {
        desvios[bundle]?.destruir()
        desvios[bundle] = nil
        guard let app = apps.first(where: { $0.id == bundle }) else { return }
        guard #available(macOS 14.2, *) else {
            falhou = "O volume por app pede o macOS 14.2 ou mais novo."
            controles[bundle] = nil
            return
        }
        criando.insert(bundle)
        let processos = app.processos, nome = app.nome
        fila.async { [weak self] in
            let d = SaidasDeAudio.padrao.flatMap(SaidasDeAudio.uid).flatMap {
                DesvioDeApp(processos: processos, saidaUID: $0, nome: nome, ganho: MixerDaIlha.ganho(controle))
            }
            DispatchQueue.main.async {
                guard let self else { d?.destruir(); return }
                self.criando.remove(bundle)
                guard let d else {
                    self.falhou = "O macOS não deixou ajustar o som de \(nome). Confira a permissão de gravação de áudio do sistema."
                    self.controles[bundle] = nil
                    return
                }
                // enquanto esperava, o controle pode ter voltado a 100% ou mudado
                guard let atual = self.controles[bundle], MixerDaIlha.precisaDesviar(atual) else { d.destruir(); return }
                d.mudar(MixerDaIlha.ganho(atual))
                self.desvios[bundle] = d
                self.falhou = nil
            }
        }
    }

    /// Só para o autoteste de desenho.
    private var simulando = false
    func simular(_ lista: [App], controles c: [String: Double]) {
        simulando = true
        apps = lista
        controles = c
        saidas = SaidasDeAudio.lista()
        saidaAtual = SaidasDeAudio.padrao
    }

    /// Ao desligar a ilha: todo som volta direto, sem passar pelo Docka.
    func desfazerTudo() {
        desvios.values.forEach { $0.destruir() }
        desvios = [:]
        controles = [:]
    }
}

// MARK: - A vista

struct MixerDaIlhaView: View {
    @ObservedObject private var m = MixerModelo.shared
    @State private var volume: Double = VolumeBackend.ler() ?? 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 22)
                ReguaDaIlha(valor: volume, cor: .white) { v in volume = v; _ = VolumeBackend.escrever(v) }
                    .frame(height: 20)
                Text("\(Int((volume * 100).rounded()))%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
                Menu {
                    ForEach(m.saidas) { s in
                        Button { SaidasDeAudio.escolher(s.id); m.atualizar() } label: {
                            if s.id == m.saidaAtual { Label(s.nome, systemImage: "checkmark") } else { Text(s.nome) }
                        }
                    }
                } label: {
                    Text(m.saidas.first { $0.id == m.saidaAtual }?.nome ?? "Saída").font(.system(size: 11)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            if m.apps.isEmpty {
                Text("Nenhum app tocando som agora").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 14)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) { ForEach(m.apps) { linha($0) } }
                }
            }
            if let f = m.falhou {
                Text(f).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.horizontal, 18).padding(.top, 6)
        .foregroundStyle(.white)
        .onAppear { m.olhar(true) }
        .onDisappear { m.olhar(false) }
    }

    private func linha(_ a: MixerModelo.App) -> some View {
        let c = m.controles[a.id] ?? 1
        return HStack(spacing: 10) {
            Group {
                if let i = a.icone { Image(nsImage: i).resizable() } else { Image(systemName: "app.dashed") }
            }
            .frame(width: 22, height: 22)
            .opacity(a.tocando ? 1 : 0.5)
            Text(a.nome).font(.system(size: 11.5)).lineLimit(1).frame(width: 110, alignment: .leading)
            Button { m.mudar(a.id, c > 0 ? 0 : 1) } label: {
                Image(systemName: c > 0 ? "speaker.wave.2" : "speaker.slash.fill").font(.system(size: 11))
                    .foregroundStyle(c > 0 ? Color.white : Color.orange)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(c > 0 ? "Silenciar \(a.nome)" : "Voltar o som de \(a.nome)")
            // a régua vai de 0 a 150%; a marquinha mostra onde fica o 100%
            ZStack(alignment: .leading) {
                ReguaDaIlha(valor: c / 1.5, cor: c > 1 ? .orange : .white) { v in m.mudar(a.id, v * 1.5) }
                GeometryReader { g in
                    Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 10)
                        .offset(x: g.size.width * (1 / 1.5), y: g.size.height / 2 - 5)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 20)
            Text(MixerDaIlha.rotulo(c)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(c == 1 ? Color.white.opacity(0.6) : Color.white)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume de \(a.nome)")
    }
}
