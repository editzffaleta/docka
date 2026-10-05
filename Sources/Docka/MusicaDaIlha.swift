import SwiftUI
import AppKit
import Accelerate
import ScreenCaptureKit
import DockaCore

// MARK: - O modelo

/// O que está tocando no Mac — em qualquer app ou aba do navegador que
/// anuncie o que toca (Spotify, Música, YouTube, SoundCloud…).
///
/// Quem lê é o /usr/bin/perl do sistema, carregando a libDockaTocando (ver
/// DockaTocando.h): desde o macOS 15.4, o serviço do "tocando agora" só
/// responde a processos da Apple. O perl fica rodando e escreve uma linha
/// JSON a cada mudança; se ele morrer, volta alguns segundos depois.
final class MusicaModelo: ObservableObject {
    static let shared = MusicaModelo()

    @Published private(set) var faixa = TocandoAgora()
    @Published private(set) var capa: NSImage?
    @Published private(set) var letra: [Letra.Linha] = []
    /// O ajudante não existe ou o macOS fechou o caminho.
    @Published private(set) var indisponivel = false

    let barras = BarrasDoEqualizador()

    private var processo: Process?
    private var entrada: Pipe?
    private var sobra = Data()
    private var ligado = false
    private var falhas = 0
    private var letraDe: String?

    /// O perl que carrega a biblioteca e chama a função pedida.
    private static let carregador = """
    use DynaLoader;
    my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $s = DynaLoader::dl_find_symbol($l, $ARGV[1]) or die "sem simbolo";
    DynaLoader::dl_install_xsub("main::f", $s);
    f();
    """

    /// No app empacotado, nos Recursos; rodando do `swift build`, ao lado do executável.
    static var biblioteca: URL? {
        let candidatos = [Bundle.main.resourceURL?.appendingPathComponent("libDockaTocando.dylib"),
                          Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("libDockaTocando.dylib")]
        return candidatos.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var app: NSRunningApplication? { faixa.pid > 0 ? NSRunningApplication(processIdentifier: faixa.pid) : nil }

    func ligar(_ quer: Bool) {
        ligado = quer
        if quer { iniciar() } else { parar() }
    }

    private func iniciar() {
        guard processo == nil, ligado else { return }
        guard let lib = Self.biblioteca else { indisponivel = true; return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.carregador, lib.path, "docka_ouvir"]
        let saida = Pipe(), entrada = Pipe()
        p.standardOutput = saida
        p.standardInput = entrada
        p.standardError = FileHandle.nullDevice
        saida.fileHandleForReading.readabilityHandler = { [weak self] h in
            let dados = h.availableData
            guard !dados.isEmpty else { return }
            DispatchQueue.main.async { self?.receber(dados) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.morreu() }
        }
        do {
            try p.run()
            processo = p
            self.entrada = entrada
        } catch {
            indisponivel = true
        }
    }

    private func parar() {
        // fechar a entrada é o sinal para o ajudante sair sozinho
        try? entrada?.fileHandleForWriting.close()
        processo?.terminationHandler = nil
        processo?.terminate()
        processo = nil
        entrada = nil
        barras.parar()
        faixa = TocandoAgora()
    }

    private func morreu() {
        processo = nil
        entrada = nil
        guard ligado else { return }
        falhas += 1
        // tenta de novo, cada vez esperando mais; depois de muitas, desiste
        guard falhas < 6 else { indisponivel = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(falhas * 3)) { [weak self] in self?.iniciar() }
    }

    private func receber(_ dados: Data) {
        sobra.append(dados)
        while let fim = sobra.firstIndex(of: 0x0A) {
            let linha = sobra[sobra.startIndex..<fim]
            sobra.removeSubrange(sobra.startIndex...fim)
            guard let obj = try? JSONSerialization.jsonObject(with: linha) as? [String: Any] else { continue }
            falhas = 0
            indisponivel = false
            aplicar(obj)
        }
    }

    private func aplicar(_ obj: [String: Any]) {
        let nova = TocandoAgora(json: obj)
        let trocou = !nova.mesmaFaixa(faixa)
        if let b64 = obj["capa"] as? String, let d = Data(base64Encoded: b64) {
            capa = NSImage(data: d)
        } else if nova.capaId == nil && trocou {
            capa = nil
        }
        faixa = nova
        if trocou { letra = []; buscarLetra() }
        if nova.tocando { barras.tocar() } else { barras.parar() }
    }

    // MARK: comandos

    enum Comando: Int { case tocarPausar = 2, proxima = 4, anterior = 5 }

    func enviar(_ c: Comando) { rodarComando(["DOCKA_COMANDO": "\(c.rawValue)"]) }

    func irPara(_ segundos: TimeInterval) { rodarComando(["DOCKA_POSICAO": String(format: "%.2f", segundos)]) }

    private func rodarComando(_ ambiente: [String: String]) {
        guard let lib = Self.biblioteca else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.carregador, lib.path, "docka_comando"]
        p.environment = ambiente
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        // sem esperar: o resultado chega pela escuta, como qualquer mudança
        try? p.run()
    }

    // MARK: letra

    /// Busca a letra sincronizada no lrclib.net (base aberta e gratuita),
    /// só com a opção ligada. Vai: título, artista, álbum e duração.
    private func buscarLetra() {
        guard DockaStore.shared.ilhaLetra, let titulo = faixa.titulo, let artista = faixa.artista else { return }
        let chave = "\(titulo)|\(artista)"
        guard chave != letraDe else { return }
        letraDe = chave
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [URLQueryItem(name: "track_name", value: titulo),
                        URLQueryItem(name: "artist_name", value: artista)]
        if let a = faixa.album { c.queryItems?.append(URLQueryItem(name: "album_name", value: a)) }
        if let d = faixa.duracao { c.queryItems?.append(URLQueryItem(name: "duration", value: "\(Int(d.rounded()))")) }
        guard let url = c.url else { return }
        var pedido = URLRequest(url: url, timeoutInterval: 10)
        pedido.setValue("Docka (https://github.com/editzffaleta/docka)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: pedido) { [weak self] dados, _, _ in
            guard let dados, let obj = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
                  let lrc = obj["syncedLyrics"] as? String else { return }
            let linhas = Letra.ler(lrc)
            DispatchQueue.main.async {
                guard self?.letraDe == chave else { return }
                self?.letra = linhas
            }
        }.resume()
    }

    var atividade: Ilha.Atividade? {
        guard faixa.temFaixa, faixa.tocando else { return nil }
        return Ilha.Atividade(id: "musica", tipo: .musica, simbolo: "music.note", valor: "", prioridade: 40)
    }
}

// MARK: - Equalizador

/// As barras, publicadas à parte: mudam quinze vezes por segundo, e só quem
/// desenha barras precisa saber.
final class BarrasDoEqualizador: ObservableObject {
    static let quantas = 5
    @Published private(set) var valores: [Float] = Array(repeating: 0.15, count: quantas)

    private var relogio: Timer?
    private var aoVivo: AudioAoVivo?
    private var medidas: [Float]?

    func tocar() {
        guard relogio == nil else { return }
        let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.passo() }
        RunLoop.main.add(t, forMode: .common)
        relogio = t
        if DockaStore.shared.ilhaEqualizadorAoVivo && CapturaController.permitido {
            let a = AudioAoVivo { [weak self] f in DispatchQueue.main.async { self?.medidas = f } }
            aoVivo = a
            Task { await a.ligar() }
        }
    }

    func parar() {
        relogio?.invalidate(); relogio = nil
        let a = aoVivo
        aoVivo = nil
        medidas = nil
        Task { await a?.desligar() }
        valores = Array(repeating: 0.15, count: Self.quantas)
    }

    private func passo() {
        let alvo = medidas ?? Equalizador.enfeite(quantas: Self.quantas, em: Date().timeIntervalSinceReferenceDate)
        valores = Equalizador.suavizar(valores, alvo)
    }
}

/// O áudio que o Mac está tocando, pela ScreenCaptureKit, só para medir as
/// faixas do equalizador. Nada é gravado: cada pedaço é medido e descartado.
/// Pede Gravação de Tela — e o macOS mostra o aviso de gravação enquanto mede.
final class AudioAoVivo: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let aoMedir: ([Float]) -> Void
    private let fila = DispatchQueue(label: "docka.equalizador")
    private let fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)
    private var janela = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 1024, isHalfWindow: false)
    private var acumulado: [Float] = []
    private var maior: Float = 0.35

    init(aoMedir: @escaping ([Float]) -> Void) { self.aoMedir = aoMedir }

    func ligar() async {
        guard let conteudo = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let tela = conteudo.displays.first else { return }
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48_000
        cfg.channelCount = 1
        // a imagem é obrigatória na ScreenCaptureKit; a menor possível, uma por segundo
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let s = SCStream(filter: SCContentFilter(display: tela, excludingApplications: [], exceptingWindows: []),
                         configuration: cfg, delegate: nil)
        do {
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: fila)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: fila)
            try await s.startCapture()
            stream = s
        } catch {}
    }

    func desligar() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let fft else { return }
        var lista = AudioBufferList()
        var bloco: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: nil, bufferListOut: &lista, bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &bloco) == noErr,
              let dados = lista.mBuffers.mData else { return }
        let n = Int(lista.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        acumulado.append(contentsOf: UnsafeBufferPointer(start: dados.assumingMemoryBound(to: Float.self), count: n))
        guard acumulado.count >= 1024 else { return }
        let amostras = vDSP.multiply(Array(acumulado.suffix(1024)), janela)
        acumulado.removeAll(keepingCapacity: true)

        var real = [Float](repeating: 0, count: 512), imag = [Float](repeating: 0, count: 512)
        var magnitudes = [Float](repeating: 0, count: 512)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                amostras.withUnsafeBufferPointer { a in
                    a.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: 512) { vDSP_ctoz($0, 2, &split, 1, 512) }
                }
                fft.forward(input: split, output: &split)
                vDSP_zvabs(&split, 1, &magnitudes, 1, 512)
            }
        }
        var escala: Float = 1.0 / 512
        vDSP_vsmul(magnitudes, 1, &escala, &magnitudes, 1, 512)
        // até ~8 kHz (cada posição vale 48 000 / 1024 ≈ 47 Hz): acima disso a
        // música quase não tem nada, e a última barra ficaria parada
        let ate = Array(magnitudes.prefix(171))
        let g = Equalizador.ganho(Equalizador.faixas(ate, quantas: BarrasDoEqualizador.quantas), maior: maior)
        maior = g.maior
        aoMedir(g.faixas)
    }
}

/// As barrinhas, do tamanho que couber.
struct VistaDasBarras: View {
    @ObservedObject var barras: BarrasDoEqualizador
    var cor: Color = .white
    var espaco: CGFloat = 2

    var body: some View {
        GeometryReader { g in
            HStack(alignment: .center, spacing: espaco) {
                ForEach(Array(barras.valores.enumerated()), id: \.offset) { _, v in
                    Capsule().fill(cor)
                        .frame(height: max(2, g.size.height * CGFloat(v)))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - A seção "Tocando agora"

struct TocandoAgoraView: View {
    @ObservedObject private var m = MusicaModelo.shared
    @EnvironmentObject var e: IlhaEstado
    @EnvironmentObject var store: DockaStore
    @State private var agora = Date()
    private let relogio = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if m.indisponivel {
                aviso("Não deu para ler o que está tocando", "O macOS pode ter fechado o caminho nesta versão.")
            } else if !m.faixa.temFaixa {
                aviso("Nada tocando agora", "Toque algo no Spotify, no Música ou no navegador.")
            } else {
                tocando
            }
        }
        .padding(.horizontal, 18).padding(.top, 6)
        .foregroundStyle(.white)
        .onReceive(relogio) { agora = $0 }
    }

    private func aviso(_ titulo: String, _ detalhe: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.pink)
            Text(titulo).font(.system(size: 13, weight: .semibold))
            Text(detalhe).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tocando: some View {
        let f = m.faixa
        let pos = f.posicao(em: agora)
        let atual = Letra.atual(m.letra, em: pos)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let c = m.capa { Image(nsImage: c).resizable().aspectRatio(contentMode: .fill) }
                    else { Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.pink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.08)) }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.titulo ?? "").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text([f.artista, f.album].compactMap { $0 }.joined(separator: " — "))
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    if let app = m.app {
                        HStack(spacing: 4) {
                            if let i = app.icon { Image(nsImage: i).resizable().frame(width: 12, height: 12) }
                            Text(app.localizedName ?? "").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                Spacer(minLength: 8)
                botao("backward.fill", "Anterior", 30) { m.enviar(.anterior) }
                botao(f.tocando ? "pause.fill" : "play.fill", f.tocando ? "Pausar" : "Tocar", 40, destaque: true) {
                    m.enviar(.tocarPausar)
                }
                botao("forward.fill", "Próxima", 30) { m.enviar(.proxima) }
                VistaDasBarras(barras: m.barras, cor: .pink).frame(width: 26, height: 22).padding(.leading, 4)
            }
            if let d = f.duracao {
                HStack(spacing: 8) {
                    Text(TimerDaIlha.relogio(pos)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15)).frame(height: 4)
                            Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(pos / max(d, 1)), height: 4)
                        }
                        .frame(maxHeight: .infinity)
                        .overlay(ToqueAbsolutoAppKit { x in m.irPara(Double(x / max(1, g.size.width)) * d) })
                    }
                    .frame(height: 14)
                    Text("-" + TimerDaIlha.relogio(max(0, d - pos))).font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            if store.ilhaLetra, !m.letra.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(atual.map { m.letra[$0].texto } ?? "♪").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let i = atual, i + 1 < m.letra.count {
                        Text(m.letra[i + 1].texto).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: atual)
            }
        }
    }

    private func botao(_ simbolo: String, _ rotulo: String, _ lado: CGFloat, destaque: Bool = false,
                       _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo).font(.system(size: lado * 0.38, weight: .bold))
                .foregroundStyle(destaque ? Color.black : Color.white)
                .frame(width: lado, height: lado)
                .background(Circle().fill(destaque ? Color.white : Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }
}

/// A asa da ilha fechada com música: a capa de um lado, as barras do outro.
struct AsaDaMusica: View {
    let esquerda: Bool
    var compacta = false
    @ObservedObject private var m = MusicaModelo.shared

    var body: some View {
        if esquerda {
            Group {
                if let c = m.capa { Image(nsImage: c).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "music.note").foregroundStyle(.pink) }
            }
            .frame(width: compacta ? 18 : 22, height: compacta ? 18 : 22)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            VistaDasBarras(barras: m.barras, cor: .pink).frame(width: compacta ? 16 : 22, height: compacta ? 12 : 14)
        }
    }
}
