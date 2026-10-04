import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers
import DockaCore

// MARK: - Desenho (o mesmo na tela e na exportação)

/// Desenha a imagem e as marcas num contexto com origem no topo (y para
/// baixo), em pixels da imagem. A prévia e a exportação passam por aqui —
/// o que se vê é exatamente o que sai.
enum DesenhoDeAnotacao {

    static func desenhar(_ marcas: [Anotacao], imagem: CGImage, pixelada: CGImage?, em ctx: CGContext) {
        let tamanho = CGRect(x: 0, y: 0, width: imagem.width, height: imagem.height)
        desenharImagem(imagem, em: tamanho, ctx)
        for m in marcas { desenhar(m, pixelada: pixelada, tamanho: tamanho, em: ctx) }
    }

    static func desenhar(_ m: Anotacao, pixelada: CGImage?, tamanho: CGRect, em ctx: CGContext) {
        let (r, g, b) = m.cor.rgb
        let cor = CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(m.espessura)
        ctx.setStrokeColor(cor)
        ctx.setFillColor(cor)

        switch m.forma {
        case .retangulo(let rect):
            ctx.stroke(rect)

        case .destaque(let rect):
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 0.4))
            ctx.fill(rect)

        case .seta(let a, let p):
            let (e, d) = GeometriaDeAnotacao.cabeca(de: a, para: p, espessura: m.espessura)
            // o corpo termina na base da cabeça: com ponta redonda saindo
            // pela ponta da seta, ela pareceria rombuda
            let base = CGPoint(x: (e.x + d.x) / 2, y: (e.y + d.y) / 2)
            ctx.move(to: a); ctx.addLine(to: base); ctx.strokePath()
            ctx.move(to: p); ctx.addLine(to: e); ctx.addLine(to: d); ctx.closePath()
            ctx.fillPath()

        case .caneta(let pontos):
            guard let primeiro = pontos.first else { return }
            ctx.move(to: primeiro)
            pontos.dropFirst().forEach { ctx.addLine(to: $0) }
            ctx.strokePath()

        case .texto(let ponto, let texto):
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let fonte = NSFont.systemFont(ofSize: tamanhoDoTexto(m.espessura), weight: .bold)
            let atributos: [NSAttributedString.Key: Any] = [
                .font: fonte,
                .foregroundColor: NSColor(cgColor: cor) ?? .red,
                // contorno escuro (ou claro, para texto preto): legível sobre qualquer fundo
                .strokeColor: m.cor == .preto ? NSColor.white : NSColor.black.withAlphaComponent(0.6),
                .strokeWidth: -3,
            ]
            (texto as NSString).draw(at: ponto, withAttributes: atributos)
            NSGraphicsContext.restoreGraphicsState()

        case .borrao(let rect):
            guard let pixelada else { return }
            ctx.clip(to: rect)
            desenharImagem(pixelada, em: tamanho, ctx)
        }
    }

    static func tamanhoDoTexto(_ espessura: CGFloat) -> CGFloat { espessura * 5 + 14 }

    /// `CGContext.draw` desenha de cabeça para baixo num contexto y-para-baixo:
    /// desvira só para a imagem.
    private static func desenharImagem(_ img: CGImage, em r: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    /// A imagem toda pixelizada, calculada uma vez: o borrão só recorta dela.
    static func pixelar(_ img: CGImage) -> CGImage? {
        let bloco = GeometriaDeAnotacao.blocoDoBorrao(imagem: CGSize(width: img.width, height: img.height))
        let entrada = CIImage(cgImage: img)
        guard let f = CIFilter(name: "CIPixellate") else { return nil }
        f.setValue(entrada.clampedToExtent(), forKey: kCIInputImageKey)
        f.setValue(bloco, forKey: kCIInputScaleKey)
        f.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let saida = f.outputImage?.cropped(to: entrada.extent) else { return nil }
        return CIContext().createCGImage(saida, from: entrada.extent)
    }

    /// A imagem final, na resolução da captura, já recortada.
    static func exportar(_ marcas: [Anotacao], imagem: CGImage, pixelada: CGImage?, recorte: CGRect?) -> CGImage? {
        let w = imagem.width, h = imagem.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // contexto de bitmap tem y para cima: vira para o desenho comum
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        desenhar(marcas, imagem: imagem, pixelada: pixelada, em: ctx)
        guard let pronto = ctx.makeImage() else { return nil }
        guard let r = recorte else { return pronto }
        return pronto.cropping(to: r)   // `cropping` usa origem no topo, como as marcas
    }

    static func png(_ img: CGImage) -> Data? {
        let dados = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(dados, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destino, img, nil)
        return CGImageDestinationFinalize(destino) ? dados as Data : nil
    }
}

// MARK: - O estado do editor

final class EditorModelo: ObservableObject {
    let imagem: CGImage
    let pixelada: CGImage?
    let escalaDaTela: CGFloat

    @Published var marcas: [Anotacao] = []
    @Published var recorte: CGRect?
    @Published var ferramenta: FerramentaDeAnotacao = .seta
    @Published var cor: CorDeAnotacao = .vermelho
    @Published var espessura: CGFloat = 6
    /// A marca sendo desenhada agora, antes de soltar o mouse.
    @Published var emAndamento: Anotacao?
    /// Recorte sendo arrastado agora.
    @Published var recorteEmAndamento: CGRect?
    /// Texto sendo digitado e onde (em pixels da imagem).
    @Published var textoEm: CGPoint?
    @Published var texto = ""

    /// Estados anteriores, para o ⌘Z.
    private var historico: [(marcas: [Anotacao], recorte: CGRect?)] = []

    var tamanho: CGSize { CGSize(width: imagem.width, height: imagem.height) }
    var podeDesfazer: Bool { !historico.isEmpty }

    init(imagem: CGImage, escalaDaTela: CGFloat) {
        self.imagem = imagem
        self.escalaDaTela = escalaDaTela
        pixelada = DesenhoDeAnotacao.pixelar(imagem)
    }

    private func guardar() { historico.append((marcas, recorte)) }

    func desfazer() {
        guard let anterior = historico.popLast() else { NSSound.beep(); return }
        marcas = anterior.marcas
        recorte = anterior.recorte
    }

    // MARK: gesto

    func arrastou(de a: CGPoint, ate b: CGPoint) {
        let rect = GeometriaDeAnotacao.retangulo(a, b)
        switch ferramenta {
        case .seta:      emAndamento = Anotacao(forma: .seta(de: a, para: b), cor: cor, espessura: espessura)
        case .retangulo: emAndamento = Anotacao(forma: .retangulo(rect), cor: cor, espessura: espessura)
        case .destaque:  emAndamento = Anotacao(forma: .destaque(rect), cor: cor, espessura: espessura)
        case .borrao:    emAndamento = Anotacao(forma: .borrao(rect), cor: cor, espessura: espessura)
        case .caneta:
            if case .caneta(let pontos)? = emAndamento?.forma {
                emAndamento?.forma = .caneta(pontos + [b])
            } else {
                emAndamento = Anotacao(forma: .caneta([a, b]), cor: cor, espessura: espessura)
            }
        case .recorte:   recorteEmAndamento = rect
        case .texto:     break
        }
    }

    func soltou(de a: CGPoint, ate b: CGPoint) {
        defer { emAndamento = nil; recorteEmAndamento = nil }
        switch ferramenta {
        case .texto:
            confirmarTexto()   // um clique em outro lugar fecha o texto aberto
            textoEm = b
        case .recorte:
            guard let r = GeometriaDeAnotacao.recorte(GeometriaDeAnotacao.retangulo(a, b), imagem: tamanho)
            else { return }
            guardar()
            recorte = r
        default:
            // clique sem arrasto não deixa marca solta
            guard var m = emAndamento, hypot(b.x - a.x, b.y - a.y) > 3 else { return }
            m.id = UUID()
            guardar()
            marcas.append(m)
        }
    }

    func confirmarTexto() {
        defer { textoEm = nil; texto = "" }
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = textoEm, !t.isEmpty else { return }
        guardar()
        marcas.append(Anotacao(forma: .texto(p, t), cor: cor, espessura: espessura))
    }

    // MARK: saída

    func final() -> CGImage? {
        confirmarTexto()
        return DesenhoDeAnotacao.exportar(marcas, imagem: imagem, pixelada: pixelada, recorte: recorte)
    }
}

// MARK: - A janela

/// Uma janela por captura. Janela comum, e não painel: precisa de teclado
/// para o texto e de gestos, que num painel não-ativante não chegam.
final class EditorDeAnotacaoController: NSObject, NSWindowDelegate {
    private static var abertas: [EditorDeAnotacaoController] = []

    private let janela: NSWindow
    private let modelo: EditorModelo

    static func abrir(_ imagem: CGImage, escalaDaTela: CGFloat) {
        let c = EditorDeAnotacaoController(imagem: imagem, escalaDaTela: escalaDaTela)
        abertas.append(c)
        NSApp.activate(ignoringOtherApps: true)
        c.janela.makeKeyAndOrderFront(nil)
    }

    private init(imagem: CGImage, escalaDaTela: CGFloat) {
        modelo = EditorModelo(imagem: imagem, escalaDaTela: escalaDaTela)
        let visivel = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        // do tamanho da captura em pontos, sem passar de 85% da tela
        let natural = NSSize(width: CGFloat(imagem.width) / max(escalaDaTela, 1),
                             height: CGFloat(imagem.height) / max(escalaDaTela, 1) + 52)
        let tamanho = NSSize(width: min(max(natural.width + 40, 640), visivel.width * 0.85),
                             height: min(max(natural.height + 40, 420), visivel.height * 0.85))
        janela = NSWindow(contentRect: NSRect(origin: .zero, size: tamanho),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        janela.title = "Anotar captura"
        janela.isReleasedWhenClosed = false
        janela.delegate = self
        janela.center()
        janela.contentView = NSHostingView(
            rootView: EditorView(fechar: { [weak self] in self?.janela.close() })
                .environmentObject(modelo))
    }

    func windowWillClose(_ notification: Notification) {
        Self.abertas.removeAll { $0 === self }
    }
}

// MARK: - A vista

struct EditorView: View {
    let fechar: () -> Void
    @EnvironmentObject var m: EditorModelo
    @FocusState private var digitando: Bool

    var body: some View {
        VStack(spacing: 0) {
            barra
            Divider()
            GeometryReader { g in
                let e = GeometriaDeAnotacao.encaixe(imagem: m.tamanho, area: g.size, escalaDaTela: m.escalaDaTela)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        ctx.translateBy(x: e.deslocamento.x, y: e.deslocamento.y)
                        ctx.scaleBy(x: e.escala, y: e.escala)
                        ctx.withCGContext { cg in
                            DesenhoDeAnotacao.desenhar(m.marcas + [m.emAndamento].compactMap { $0 },
                                                       imagem: m.imagem, pixelada: m.pixelada, em: cg)
                            desenharRecorte(cg)
                        }
                    }
                    .gesture(arrasto(e))
                    if let p = m.textoEm {
                        campoDeTexto(em: p, e)
                    }
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 380)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { tecla in
            // uma letra troca de ferramenta — mas não enquanto se digita
            guard m.textoEm == nil, tecla.modifiers.isEmpty,
                  let c = tecla.characters.first,
                  let f = FerramentaDeAnotacao.allCases.first(where: { $0.tecla == c }) else { return .ignored }
            m.ferramenta = f
            return .handled
        }
    }

    // MARK: barra

    private var barra: some View {
        HStack(spacing: 10) {
            ForEach(FerramentaDeAnotacao.allCases) { f in
                Button { m.confirmarTexto(); m.ferramenta = f } label: {
                    Image(systemName: f.simbolo)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(m.ferramenta == f ? Color.accentColor.opacity(0.25) : .clear))
                }
                .buttonStyle(.plain)
                .help("\(f.titulo) (\(String(f.tecla).uppercased()))")
            }
            Divider().frame(height: 18)
            Menu {
                ForEach(CorDeAnotacao.allCases) { c in
                    Button { m.cor = c } label: { Label(c.rawValue.capitalized, systemImage: m.cor == c ? "checkmark.circle.fill" : "circle.fill") }
                }
            } label: {
                Circle().fill(Color(red: m.cor.rgb.0, green: m.cor.rgb.1, blue: m.cor.rgb.2))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.secondary, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Cor")
            Slider(value: $m.espessura, in: 2...20).frame(width: 80).help("Espessura")
            Button { m.desfazer() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!m.podeDesfazer)
                .help("Desfazer (⌘Z)")
            Spacer()
            // sem ⌘C de propósito: enquanto se digita um texto na imagem, o
            // ⌘C tem de copiar o texto selecionado, não exportar a captura
            Button("Copiar") { copiar() }
            Button("Salvar na Mesa") { salvar(em: nil) }
            Button("Salvar como…") { salvarComo() }.keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: gesto e texto

    private func arrasto(_ e: (escala: CGFloat, deslocamento: CGPoint)) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                m.arrastou(de: GeometriaDeAnotacao.paraImagem(v.startLocation, escala: e.escala, deslocamento: e.deslocamento),
                           ate: GeometriaDeAnotacao.paraImagem(v.location, escala: e.escala, deslocamento: e.deslocamento))
            }
            .onEnded { v in
                m.soltou(de: GeometriaDeAnotacao.paraImagem(v.startLocation, escala: e.escala, deslocamento: e.deslocamento),
                         ate: GeometriaDeAnotacao.paraImagem(v.location, escala: e.escala, deslocamento: e.deslocamento))
                if m.textoEm != nil { digitando = true }
            }
    }

    private func campoDeTexto(em p: CGPoint, _ e: (escala: CGFloat, deslocamento: CGPoint)) -> some View {
        TextField("Texto", text: $m.texto)
            .textFieldStyle(.plain)
            .font(.system(size: DesenhoDeAnotacao.tamanhoDoTexto(m.espessura) * e.escala, weight: .bold))
            .foregroundStyle(Color(red: m.cor.rgb.0, green: m.cor.rgb.1, blue: m.cor.rgb.2))
            .frame(minWidth: 160, alignment: .leading)
            .fixedSize()
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3])))
            .offset(x: e.deslocamento.x + p.x * e.escala, y: e.deslocamento.y + p.y * e.escala)
            .focused($digitando)
            .onSubmit { m.confirmarTexto() }
    }

    /// Fora do recorte fica escurecido; o recorte tem borda tracejada.
    private func desenharRecorte(_ cg: CGContext) {
        guard let r = m.recorteEmAndamento ?? m.recorte else { return }
        cg.saveGState()
        cg.setFillColor(CGColor(gray: 0, alpha: 0.5))
        cg.addRect(CGRect(origin: .zero, size: m.tamanho))
        cg.addRect(r)
        cg.fillPath(using: .evenOdd)
        cg.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        cg.setLineWidth(2 / max(m.escalaDaTela, 1) * 2)
        cg.setLineDash(phase: 0, lengths: [8, 6])
        cg.stroke(r)
        cg.restoreGState()
    }

    // MARK: saída

    private func copiar() {
        guard let img = m.final(), let png = DesenhoDeAnotacao.png(img) else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        AvisoController.shared.mostrar(Alerta(tipo: .captura, titulo: "Captura copiada",
                                              mensagem: "\(img.width) × \(img.height) pixels, com as anotações."))
        fechar()
    }

    private func salvar(em url: URL?) {
        guard let img = m.final(), let png = DesenhoDeAnotacao.png(img) else { NSSound.beep(); return }
        let destino = url ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Captura.nomeDoArquivo(em: Date()))
        do {
            try png.write(to: destino, options: .atomic)
            AvisoController.shared.mostrar(Alerta(tipo: .captura, titulo: "Captura salva",
                                                  mensagem: destino.lastPathComponent))
            fechar()
        } catch {
            NSSound.beep()
        }
    }

    private func salvarComo() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = Captura.nomeDoArquivo(em: Date())
        guard p.runModal() == .OK, let url = p.url else { return }
        salvar(em: url)
    }
}

// MARK: - Autoteste

extension DesenhoDeAnotacao {
    /// Exporta marcas sobre uma imagem desenhada aqui e confere pixel a pixel
    /// — e, pelo OCR, que o texto sob o borrão não pode mais ser lido.
    static func autoteste() -> String {
        let base = NSImage(size: NSSize(width: 400, height: 200), flipped: true) { r in
            NSColor.white.setFill(); r.fill()
            ("SEGREDO 1234" as NSString).draw(at: NSPoint(x: 20, y: 60),
                                              withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .bold),
                                                               .foregroundColor: NSColor.black])
            return true
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return "FALHOU — sem bitmap" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        base.draw(in: NSRect(x: 0, y: 0, width: 400, height: 200))
        NSGraphicsContext.restoreGraphicsState()
        guard let img = rep.cgImage else { return "FALHOU — sem imagem" }

        var r: [String] = []
        func conferir(_ nome: String, _ ok: Bool) { r.append("\(ok ? "OK" : "FALHOU") — \(nome)") }
        conferir("OCR lê o texto ANTES do borrão",
                 CapturaController.reconhecer(img).texto.contains("SEGREDO"))

        let marcas = [
            Anotacao(forma: .retangulo(CGRect(x: 300, y: 20, width: 80, height: 60)), cor: .vermelho, espessura: 6),
            Anotacao(forma: .seta(de: CGPoint(x: 20, y: 180), para: CGPoint(x: 220, y: 180)), cor: .vermelho, espessura: 6),
            Anotacao(forma: .borrao(CGRect(x: 10, y: 40, width: 285, height: 80))),
        ]
        guard let saida = exportar(marcas, imagem: img, pixelada: pixelar(img),
                                   recorte: CGRect(x: 0, y: 0, width: 390, height: 200)) else {
            return "FALHOU — exportação"
        }
        conferir("recorte aplicado (\(saida.width)×\(saida.height))", saida.width == 390 && saida.height == 200)

        let px = Pixels(saida)
        conferir("borda do retângulo vermelha", px.vermelho(340, 20))
        conferir("miolo do retângulo continua branco", px.branco(340, 50))
        conferir("corpo da seta vermelho", px.vermelho(110, 180))
        let lido = CapturaController.reconhecer(saida).texto
        conferir("OCR NÃO lê o texto depois do borrão (leu: \"\(lido)\")", !lido.contains("SEGREDO") && !lido.contains("1234"))
        return r.joined(separator: "\n")
    }

    /// Leitura de pixels com origem no topo, em RGBA de 8 bits.
    private struct Pixels {
        let dados: [UInt8]
        let largura: Int

        init(_ img: CGImage) {
            largura = img.width
            var d = [UInt8](repeating: 0, count: img.width * img.height * 4)
            let ctx = CGContext(data: &d, width: img.width, height: img.height, bitsPerComponent: 8,
                                bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            dados = d
        }

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * largura + x) * 4
            return (Int(dados[i]), Int(dados[i + 1]), Int(dados[i + 2]))
        }
        func vermelho(_ x: Int, _ y: Int) -> Bool { let c = rgb(x, y); return c.0 > 200 && c.1 < 110 && c.2 < 110 }
        func branco(_ x: Int, _ y: Int) -> Bool { let c = rgb(x, y); return c.0 > 240 && c.1 > 240 && c.2 > 240 }
    }
}
