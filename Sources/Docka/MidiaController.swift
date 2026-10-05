import AppKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import DockaCore

// MARK: - O trabalho em si

/// Converte e comprime, tudo no Mac: AVFoundation para vídeo, ImageIO para
/// imagem, Vision para texto. O resultado vai ao lado do original, com um
/// sufixo, e nunca o sobrescreve.
enum ProcessadorDeMidia {

    enum Qualidade: String, CaseIterable, Identifiable {
        case alta, media, pequena
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .alta:    return "Alta (1080p, HEVC)"
            case .media:   return "Média (720p)"
            case .pequena: return "Pequena (540p)"
            }
        }
        var preset: String {
            switch self {
            case .alta:    return AVAssetExportPresetHEVC1920x1080
            case .media:   return AVAssetExportPreset1280x720
            case .pequena: return AVAssetExportPreset960x540
            }
        }
    }

    enum FormatoDeImagem: String, CaseIterable, Identifiable {
        case jpeg, png, heic, tiff
        var id: String { rawValue }
        var titulo: String { rawValue.uppercased() }
        var tipo: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png:  return .png
            case .heic: return .heic
            case .tiff: return .tiff
            }
        }
        var extensao: String { self == .jpeg ? "jpg" : rawValue }
        var comPerda: Bool { self == .jpeg || self == .heic }
    }

    struct Falha: LocalizedError {
        let errorDescription: String?
        init(_ t: String) { errorDescription = t }
    }

    private static func saida(_ url: URL, _ sufixo: String, _ ext: String) -> URL {
        URL(fileURLWithPath: Midia.nomeDeSaida(original: url.path, sufixo: sufixo, extensao: ext) {
            FileManager.default.fileExists(atPath: $0)
        })
    }

    private static func exportar(_ url: URL, preset: String, tipo: AVFileType, para destino: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Falha("Este vídeo não aceita essa conversão")
        }
        s.shouldOptimizeForNetworkUse = true
        if #available(macOS 15, *) {
            try await s.export(to: destino, as: tipo)
        } else {
            s.outputURL = destino
            s.outputFileType = tipo
            await s.export()
            if let e = s.error { throw e }
        }
    }

    /// Se o resultado sair maior que o original (um vídeo que já era
    /// compacto), ele é apagado: comprimir nunca entrega um arquivo maior.
    static func comprimir(_ url: URL, _ q: Qualidade) async throws -> URL {
        let destino = saida(url, "comprimido", "mp4")
        try await exportar(url, preset: q.preset, tipo: .mp4, para: destino)
        if tamanho(destino) >= tamanho(url) {
            try? FileManager.default.removeItem(at: destino)
            throw Falha("Já estava pequeno — nada a ganhar nessa qualidade")
        }
        return destino
    }

    static func audio(_ url: URL) async throws -> URL {
        guard !(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)).isEmpty else {
            throw Falha("O vídeo não tem som")
        }
        let destino = saida(url, "audio", "m4a")
        try await exportar(url, preset: AVAssetExportPresetAppleM4A, tipo: .m4a, para: destino)
        return destino
    }

    /// Quadros do vídeo num GIF que repete, no máximo 300 quadros.
    static func gif(_ url: URL, largura: Int, fps: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duracao = try await asset.load(.duration).seconds
        let instantes = Midia.instantesDoGif(duracao: duracao, fps: fps, maxQuadros: 300)
        guard !instantes.isEmpty else { throw Falha("O vídeo não tem duração") }
        let gerador = AVAssetImageGenerator(asset: asset)
        gerador.appliesPreferredTrackTransform = true
        gerador.maximumSize = CGSize(width: largura, height: largura)
        let tolerancia = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        gerador.requestedTimeToleranceBefore = tolerancia
        gerador.requestedTimeToleranceAfter = tolerancia

        let destino = saida(url, "animado", "gif")
        guard let d = CGImageDestinationCreateWithURL(destino as CFURL, UTType.gif.identifier as CFString,
                                                      instantes.count, nil) else { throw Falha("Não deu para criar o GIF") }
        CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let atraso = Midia.atrasoDoGif(duracao: duracao, quadros: instantes.count)
        let quadro = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: atraso]] as CFDictionary
        for t in instantes {
            let (img, _) = try await gerador.image(at: CMTime(seconds: t, preferredTimescale: 600))
            CGImageDestinationAddImage(d, img, quadro)
        }
        guard CGImageDestinationFinalize(d) else { throw Falha("Não deu para gravar o GIF") }
        return destino
    }

    /// Lê aplicando a orientação da foto e já no tamanho pedido (0 = original).
    private static func imagem(_ url: URL, maximo: Int) throws -> CGImage {
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(fonte, 0, nil) as? [CFString: Any] else {
            throw Falha("Não é uma imagem que o macOS leia")
        }
        let l = props[kCGImagePropertyPixelWidth] as? Int ?? 0, a = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maior = max(l, a)
        let opcoes: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximo > 0 ? min(maximo, maior) : maior,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary) else {
            throw Falha("Não deu para ler a imagem")
        }
        return img
    }

    private static func comMarca(_ img: CGImage, texto: String, canto: Midia.Canto) -> CGImage {
        let w = img.width, h = img.height
        guard !texto.isEmpty,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let sombra = NSShadow()
        sombra.shadowColor = NSColor.black.withAlphaComponent(0.5)
        sombra.shadowBlurRadius = 3
        sombra.shadowOffset = NSSize(width: 0, height: -1)
        let fonte = NSFont.systemFont(ofSize: max(12, CGFloat(min(w, h)) * 0.045), weight: .semibold)
        let s = NSAttributedString(string: texto, attributes: [
            .font: fonte, .foregroundColor: NSColor.white.withAlphaComponent(0.85), .shadow: sombra])
        let q = Midia.quadroDaMarca(imagem: CGSize(width: w, height: h), marca: s.size(), canto: canto)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        s.draw(at: q.origin)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? img
    }

    static func converter(_ url: URL, formato: FormatoDeImagem, maximo: Int, qualidade: Double,
                          marca: String, canto: Midia.Canto) throws -> URL {
        let img = comMarca(try imagem(url, maximo: maximo), texto: marca, canto: canto)
        let destino = saida(url, "convertido", formato.extensao)
        guard let d = CGImageDestinationCreateWithURL(destino as CFURL, formato.tipo.identifier as CFString, 1, nil) else {
            throw Falha("O macOS não grava \(formato.titulo) aqui")
        }
        let props: [CFString: Any] = formato.comPerda ? [kCGImageDestinationLossyCompressionQuality: qualidade] : [:]
        CGImageDestinationAddImage(d, img, props as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw Falha("Não deu para gravar a imagem") }
        return destino
    }

    static func texto(_ url: URL) throws -> String {
        CapturaController.reconhecer(try imagem(url, maximo: 0)).texto
    }

    static func tamanho(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

// MARK: - O modelo da janela

final class MidiaModelo: ObservableObject {

    enum OperacaoDeVideo: String, CaseIterable, Identifiable {
        case comprimir, gif, audio
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .comprimir: return "Comprimir (MP4)"
            case .gif:       return "Fazer um GIF"
            case .audio:     return "Extrair o áudio"
            }
        }
    }

    enum OperacaoDeImagem: String, CaseIterable, Identifiable {
        case converter, texto
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .converter: return "Converter e redimensionar"
            case .texto:     return "Extrair o texto"
            }
        }
    }

    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var estado: String = ""
        var resultado: URL?
        var falhou = false
        var tipo: Midia.Tipo { Midia.tipo(url.path) }
    }

    @Published var itens: [Item] = []
    @Published var trabalhando = false
    @Published var opVideo: OperacaoDeVideo = .comprimir
    @Published var qualidade: ProcessadorDeMidia.Qualidade = .alta
    @Published var larguraDoGif = 640
    @Published var fpsDoGif: Double = 12
    @Published var opImagem: OperacaoDeImagem = .converter
    @Published var formato: ProcessadorDeMidia.FormatoDeImagem = .jpeg
    @Published var maximo = 0
    @Published var qualidadeDaImagem = 0.8
    @Published var marca = ""
    @Published var canto: Midia.Canto = .inferiorDireito
    @Published var aviso: String?

    var temVideo: Bool { itens.contains { $0.tipo == .video } }
    var temImagem: Bool { itens.contains { $0.tipo == .imagem } }

    func adicionar(_ urls: [URL]) {
        let novos = urls.filter { u in Midia.tipo(u.path) != .outro && !itens.contains { $0.url == u } }
        itens += novos.map { Item(url: $0) }
        if novos.count < urls.count { aviso = "Só vídeos e imagens entram." } else { aviso = nil }
    }

    func limpar() { if !trabalhando { itens = []; aviso = nil } }

    /// O que chega soltando arquivos na janela: cada um vem como um provedor
    /// que entrega a URL depois, fora da main thread.
    func receber(_ provedores: [NSItemProvider], pronto: (() -> Void)? = nil) {
        let grupo = DispatchGroup()
        var urls: [URL] = []
        let trava = NSLock()
        for p in provedores where p.canLoadObject(ofClass: URL.self) {
            grupo.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { trava.lock(); urls.append(url); trava.unlock() }
                grupo.leave()
            }
        }
        grupo.notify(queue: .main) { [weak self] in
            self?.adicionar(urls.sorted { $0.path < $1.path })
            pronto?()
        }
    }

    func comecar() {
        guard !trabalhando else { return }
        trabalhando = true
        aviso = nil
        Task { @MainActor in
            var textos: [String] = []
            for i in itens.indices {
                itens[i].estado = "Trabalhando…"
                itens[i].falhou = false
                let url = itens[i].url
                let antes = ProcessadorDeMidia.tamanho(url)
                do {
                    switch itens[i].tipo {
                    case .video:
                        let r: URL
                        switch opVideo {
                        case .comprimir: r = try await ProcessadorDeMidia.comprimir(url, qualidade)
                        case .gif:       r = try await ProcessadorDeMidia.gif(url, largura: larguraDoGif, fps: fpsDoGif)
                        case .audio:     r = try await ProcessadorDeMidia.audio(url)
                        }
                        itens[i].resultado = r
                        itens[i].estado = Midia.resumo(antes: antes, depois: ProcessadorDeMidia.tamanho(r))
                    case .imagem where opImagem == .texto:
                        let t = try ProcessadorDeMidia.texto(url)
                        textos.append(itens.count > 1 ? "— \(url.lastPathComponent) —\n\(t)" : t)
                        itens[i].estado = t.isEmpty ? "Nenhum texto" : "\(t.count) caracteres"
                    case .imagem:
                        let r = try ProcessadorDeMidia.converter(url, formato: formato, maximo: maximo,
                                                                 qualidade: qualidadeDaImagem, marca: marca, canto: canto)
                        itens[i].resultado = r
                        itens[i].estado = Midia.resumo(antes: antes, depois: ProcessadorDeMidia.tamanho(r))
                    case .outro:
                        itens[i].estado = "Ignorado"
                    }
                } catch {
                    itens[i].falhou = true
                    itens[i].estado = error.localizedDescription
                }
            }
            let texto = textos.filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !texto.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(texto, forType: .string)
                aviso = "O texto foi copiado."
            }
            trabalhando = false
            DockaStore.shared.playSound("Glass", volume: 0.3)
        }
    }

    func mostrarResultados() {
        let urls = itens.compactMap(\.resultado)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

// MARK: - A janela

final class MidiaController: NSObject, NSWindowDelegate {
    static let shared = MidiaController()
    let modelo = MidiaModelo()
    private var janela: NSWindow?

    /// Ao fechar: volta a viver só na barra de menus, se nenhuma outra janela
    /// comum do Docka (os ajustes) continua aberta.
    func windowWillClose(_ notification: Notification) {
        let outras = NSApp.windows.contains { $0 !== janela && $0.isVisible && $0.styleMask.contains(.titled) }
        if !outras { NSApp.setActivationPolicy(.accessory) }
    }

    func abrir(_ urls: [URL] = []) {
        if !urls.isEmpty { modelo.adicionar(urls) }
        let w = janela ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Ferramentas de mídia"
            w.isReleasedWhenClosed = false
            let hv = NSHostingView(rootView: MidiaView().environmentObject(modelo))
            hv.sizingOptions = []
            w.contentView = hv
            w.center()
            w.delegate = self
            return w
        }()
        janela = w
        // como os ajustes: um app só da barra de menus não consegue ficar na
        // frente — vira app normal enquanto a janela existe
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct MidiaView: View {
    @EnvironmentObject var m: MidiaModelo
    @State private var alvo = false

    var body: some View {
        VStack(spacing: 0) {
            soltar
            if !m.itens.isEmpty {
                lista
                Divider()
                Form { opcoes }.formStyle(.grouped).frame(maxHeight: 250)
                rodape
            }
        }
        .frame(minWidth: 520, minHeight: 300)
        .onDrop(of: [.fileURL], isTargeted: $alvo) { provedores in
            m.receber(provedores)
            return true
        }
    }

    private var soltar: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Solte vídeos e imagens aqui").font(.headline)
            Text("Comprimir e converter vídeo, fazer GIF, tirar o áudio; converter, redimensionar e marcar imagens, ou tirar o texto delas. Tudo no Mac.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Escolher arquivos…") { escolher() }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: m.itens.isEmpty ? 300 : 0)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(alvo ? Color.accentColor : Color.secondary.opacity(0.4)))
        .padding(12)
    }

    private var lista: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(m.itens) { i in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: i.url.path)).resizable().frame(width: 20, height: 20)
                        Text(i.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(i.estado).font(.caption).foregroundStyle(i.falhou ? Color.orange : Color.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 140)
    }

    @ViewBuilder
    private var opcoes: some View {
        if m.temVideo {
            Section("Vídeos") {
                Picker("Fazer", selection: $m.opVideo) {
                    ForEach(MidiaModelo.OperacaoDeVideo.allCases) { Text($0.titulo).tag($0) }
                }
                switch m.opVideo {
                case .comprimir:
                    Picker("Qualidade", selection: $m.qualidade) {
                        ForEach(ProcessadorDeMidia.Qualidade.allCases) { Text($0.titulo).tag($0) }
                    }
                case .gif:
                    Picker("Largura", selection: $m.larguraDoGif) {
                        ForEach([320, 480, 640, 800], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    Picker("Quadros por segundo", selection: $m.fpsDoGif) {
                        ForEach([8.0, 12.0, 15.0, 20.0], id: \.self) { Text("\(Int($0))").tag($0) }
                    }
                case .audio:
                    EmptyView()
                }
            }
        }
        if m.temImagem {
            Section("Imagens") {
                Picker("Fazer", selection: $m.opImagem) {
                    ForEach(MidiaModelo.OperacaoDeImagem.allCases) { Text($0.titulo).tag($0) }
                }
                if m.opImagem == .converter {
                    Picker("Formato", selection: $m.formato) {
                        ForEach(ProcessadorDeMidia.FormatoDeImagem.allCases) { Text($0.titulo).tag($0) }
                    }
                    Picker("Tamanho máximo", selection: $m.maximo) {
                        Text("Original").tag(0)
                        ForEach([3840, 2560, 1920, 1280, 800], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    if m.formato.comPerda {
                        LabeledContent("Qualidade") {
                            Slider(value: $m.qualidadeDaImagem, in: 0.3...1).frame(width: 180)
                            Text("\(Int(m.qualidadeDaImagem * 100))%").monospacedDigit().frame(width: 40)
                        }
                    }
                    TextField("Marca d'água (opcional)", text: $m.marca)
                    if !m.marca.isEmpty {
                        Picker("Posição", selection: $m.canto) {
                            ForEach(Midia.Canto.allCases) { Text($0.titulo).tag($0) }
                        }
                    }
                }
            }
        }
    }

    private var rodape: some View {
        HStack {
            if let a = m.aviso { Text(a).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("Limpar") { m.limpar() }.disabled(m.trabalhando)
            if m.itens.contains(where: { $0.resultado != nil }) {
                Button("Mostrar no Finder") { m.mostrarResultados() }
            }
            Button(m.trabalhando ? "Trabalhando…" : "Começar") { m.comecar() }
                .keyboardShortcut(.defaultAction)
                .disabled(m.trabalhando)
        }
        .padding(12)
    }

    private func escolher() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [.movie, .image]
        if p.runModal() == .OK { m.adicionar(p.urls) }
    }
}

// MARK: - Autoteste

extension ProcessadorDeMidia {
    /// Trabalha em cópias numa pasta temporária: um vídeo e um fundo de tela
    /// do sistema, e uma imagem com texto desenhada aqui.
    static func autoteste(pasta: String) async -> String {
        var r: [String] = []
        func conferir(_ nome: String, _ ok: Bool) { r.append("\(ok ? "OK" : "FALHOU") — \(nome)") }
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: pasta).appendingPathComponent("midia-autoteste")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let video = dir.appendingPathComponent("video.mov")
        let foto = dir.appendingPathComponent("foto.heic")
        try? fm.copyItem(at: URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app/Contents/Resources/BentoGalleryIntroduction.mov"), to: video)
        try? fm.copyItem(at: URL(fileURLWithPath: "/System/Library/Desktop Pictures/Mac Blue.heic"), to: foto)

        func arquivos() -> Int { (try? fm.contentsOfDirectory(atPath: dir.path))?.count ?? 0 }
        for q in Qualidade.allCases {
            let antes = arquivos()
            do {
                let c = try await comprimir(video, q)
                conferir("comprimir \(q.titulo): \(Midia.resumo(antes: tamanho(video), depois: tamanho(c)))", tamanho(c) < tamanho(video))
            } catch {
                // o vídeo de exemplo já é compacto: não ficar maior é o certo
                conferir("comprimir \(q.titulo): \(error.localizedDescription); nada ficou para trás", arquivos() == antes)
            }
        }
        do {
            let g = try await gif(video, largura: 320, fps: 8)
            let fonte = CGImageSourceCreateWithURL(g as CFURL, nil)
            let n = fonte.map(CGImageSourceGetCount) ?? 0
            let img = fonte.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            conferir("GIF: \(n) quadros, \(img?.width ?? 0)×\(img?.height ?? 0), \(Midia.resumo(antes: tamanho(video), depois: tamanho(g)))",
                     n > 1 && (img?.width ?? 999) <= 320)
        } catch { conferir("GIF: \(error.localizedDescription)", false) }
        do {
            let a = try await audio(video)
            conferir("áudio: \(a.lastPathComponent) \(tamanho(a)) bytes", tamanho(a) > 0)
        } catch { r.append("ℹ️ áudio: \(error.localizedDescription)") }
        do {
            let j = try converter(foto, formato: .jpeg, maximo: 800, qualidade: 0.7, marca: "Docka", canto: .inferiorDireito)
            let img = CGImageSourceCreateWithURL(j as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            conferir("imagem: HEIC → JPEG \(img?.width ?? 0)×\(img?.height ?? 0) com marca, \(Midia.resumo(antes: tamanho(foto), depois: tamanho(j)))",
                     max(img?.width ?? 0, img?.height ?? 0) == 800)
            try? fm.copyItem(at: j, to: URL(fileURLWithPath: pasta).appendingPathComponent("midia-marca.jpg"))
        } catch { conferir("imagem: \(error.localizedDescription)", false) }

        // uma imagem com texto, para o reconhecimento
        let texto = dir.appendingPathComponent("texto.png")
        if let ctx = CGContext(data: nil, width: 900, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 200))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: "Ferramentas de mídia do Docka", attributes: [.font: NSFont.systemFont(ofSize: 48)])
                .draw(at: NSPoint(x: 40, y: 70))
            NSGraphicsContext.restoreGraphicsState()
            if let img = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(texto as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(d, img, nil)
                CGImageDestinationFinalize(d)
            }
        }
        do {
            let t = try ProcessadorDeMidia.texto(texto)
            conferir("texto: \"\(t)\"", t.contains("Docka"))
        } catch { conferir("texto: \(error.localizedDescription)", false) }

        // soltar arquivos: o mesmo caminho que o arrasto do Finder usa (um
        // texto junto, que deve ficar de fora)
        try? "nota".write(to: dir.appendingPathComponent("nota.txt"), atomically: true, encoding: .utf8)
        let modelo = await MainActor.run { MidiaModelo() }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                modelo.receber([video, foto, dir.appendingPathComponent("nota.txt")].map { NSItemProvider(contentsOf: $0) ?? NSItemProvider() }) {
                    c.resume()
                }
            }
        }
        let (recebidos, aviso) = await MainActor.run { (modelo.itens.map { $0.url.lastPathComponent }, modelo.aviso ?? "") }
        conferir("soltar: \(recebidos) — \(aviso)", Set(recebidos) == ["video.mov", "foto.heic"])

        // nunca sobrescreve
        let primeiro = Midia.nomeDeSaida(original: video.path, sufixo: "comprimido", extensao: "mp4") { fm.fileExists(atPath: $0) }
        conferir("o próximo nome não sobrescreve (\((primeiro as NSString).lastPathComponent))", !fm.fileExists(atPath: primeiro))
        try? fm.removeItem(at: dir)
        return r.joined(separator: "\n")
    }
}
