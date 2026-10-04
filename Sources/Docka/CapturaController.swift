import AppKit
import Vision
import CoreImage
import DockaCore

/// Conta-gotas, texto da tela (OCR e QR) e captura de área.
///
/// A seleção da área é a do próprio macOS (`screencapture -i`, a mesma do
/// ⇧⌘4): uma interface que a pessoa já conhece, com lupa e janela por
/// espaço. O reconhecimento de texto roda no próprio Mac, pelo Vision —
/// nenhuma imagem sai daqui.
enum CapturaController {

    // MARK: permissão

    /// Capturar a tela com as janelas dos outros apps exige Gravação de Tela.
    /// Sem ela, a captura sai só com o fundo da mesa.
    static var permitido: Bool { CGPreflightScreenCaptureAccess() }

    static func pedirPermissao() { _ = CGRequestScreenCaptureAccess() }

    static func abrirAjustesDePrivacidade() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: conta-gotas

    /// O seletor de cor do sistema — lupa e tudo —, sem permissão nenhuma.
    static func contaGotas() {
        NSColorSampler().show { cor in
            guard let c = cor?.usingColorSpace(.sRGB) else { return }   // Esc: nada
            let texto = Captura.texto(r: Double(c.redComponent), g: Double(c.greenComponent),
                                      b: Double(c.blueComponent),
                                      formato: FormatoDeCor(persisted: DockaStore.shared.formatoDeCor))
            copiar(texto)
            avisar("Cor copiada", texto)
        }
    }

    // MARK: texto da tela

    static func textoDaTela() {
        guard exigirPermissao() else { return }
        let arquivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("docka-ocr-\(UUID().uuidString).png")
        // -s: só seleção de área; -x: sem o som do obturador
        rodarScreencapture(["-i", "-s", "-x", arquivo.path]) {
            defer { try? FileManager.default.removeItem(at: arquivo) }
            guard let img = NSImage(contentsOf: arquivo)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }   // cancelou
            let r = reconhecer(img)
            if let qr = r.qr {
                copiar(qr)
                avisar("QR code lido", qr)
            } else if !r.texto.isEmpty {
                copiar(r.texto)
                avisar("Texto copiado", r.texto)
            } else {
                avisar("Nenhum texto encontrado", "Tente uma área maior ou com mais contraste.")
            }
        }
    }

    /// Texto e QR de uma imagem, pelo Vision, no próprio Mac.
    static func reconhecer(_ img: CGImage) -> (texto: String, qr: String?) {
        let texto = VNRecognizeTextRequest()
        texto.recognitionLevel = .accurate
        texto.recognitionLanguages = ["pt-BR", "en-US"]
        texto.usesLanguageCorrection = true
        let codigo = VNDetectBarcodesRequest()
        codigo.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: img).perform([texto, codigo])

        let trechos = (texto.results ?? []).compactMap { o -> Captura.Trecho? in
            guard let t = o.topCandidates(1).first?.string else { return nil }
            return Captura.Trecho(texto: t, quadro: o.boundingBox)
        }
        let qr = codigo.results?.first?.payloadStringValue
        return (Captura.juntar(trechos), qr)
    }

    // MARK: captura de área

    static func capturarArea() {
        guard exigirPermissao() else { return }
        if DockaStore.shared.capturaEditar {
            // captura para um arquivo temporário e abre no editor; copiar ou
            // salvar fica para os botões dele
            let arquivo = FileManager.default.temporaryDirectory
                .appendingPathComponent("docka-captura-\(UUID().uuidString).png")
            rodarScreencapture(["-i", arquivo.path]) {
                defer { try? FileManager.default.removeItem(at: arquivo) }
                guard let img = NSImage(contentsOf: arquivo)?
                        .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }   // cancelou
                let escala = NSScreen.screens.first {
                    NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
                }?.backingScaleFactor ?? 2
                EditorDeAnotacaoController.abrir(img, escalaDaTela: escala)
            }
            return
        }
        if DockaStore.shared.capturaNaMesa {
            let mesa = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let arquivo = mesa.appendingPathComponent(Captura.nomeDoArquivo(em: Date()))
            rodarScreencapture(["-i", arquivo.path]) {
                guard FileManager.default.fileExists(atPath: arquivo.path) else { return }
                avisar("Captura salva na Mesa", arquivo.lastPathComponent)
            }
        } else {
            // -c: direto para a área de transferência
            rodarScreencapture(["-i", "-c"]) {}
        }
    }

    // MARK: utilidades

    private static func exigirPermissao() -> Bool {
        guard permitido else {
            pedirPermissao()
            avisar("Falta a Gravação de Tela",
                   "Conceda em Ajustes do Sistema › Privacidade › Gravação de Tela e tente de novo.")
            return false
        }
        return true
    }

    /// Roda o `screencapture` sem esperar por ele: a seleção pode levar o
    /// tempo que a pessoa quiser, e esperar travaria o Docka (e girar o run
    /// loop esperando já derrubou o app uma vez). O fim chega pelo
    /// `terminationHandler`, devolvido à main.
    private static func rodarScreencapture(_ argumentos: [String], depois: @escaping () -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = argumentos
        p.terminationHandler = { _ in DispatchQueue.main.async(execute: depois) }
        do { try p.run() } catch { NSSound.beep() }
    }

    private static func copiar(_ texto: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texto, forType: .string)
    }

    private static func avisar(_ titulo: String, _ mensagem: String) {
        AvisoController.shared.mostrar(Alerta(tipo: .captura, titulo: titulo,
                                              mensagem: HistoricoDeCopias.encurtar(mensagem, ate: 140)))
    }

    // MARK: autoteste

    /// Vision de verdade numa imagem desenhada aqui (texto e um QR gerado),
    /// sem capturar a tela.
    static func autoteste() -> String {
        var r: [String] = []
        let frase = "Docka lê a tela"
        let imagem = NSImage(size: NSSize(width: 900, height: 220), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            (frase as NSString).draw(at: NSPoint(x: 40, y: 80),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 64, weight: .semibold),
                                                      .foregroundColor: NSColor.black])
            return true
        }
        if let cg = imagem.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let lido = reconhecer(cg).texto
            r.append("\(lido == frase ? "OK" : "FALHOU") — OCR: \"\(lido)\"")
        }
        let filtro = CIFilter(name: "CIQRCodeGenerator")!
        filtro.setValue(Data("https://github.com/editzffaleta/docka".utf8), forKey: "inputMessage")
        if let qr = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
           let cg = CIContext().createCGImage(qr, from: qr.extent) {
            let lido = reconhecer(cg).qr
            r.append("\(lido == "https://github.com/editzffaleta/docka" ? "OK" : "FALHOU") — QR: \(lido ?? "nada")")
        }
        r.append("cor: \(Captura.texto(r: 30.0 / 255, g: 144.0 / 255, b: 1, formato: .hex))")
        r.append("gravação de tela: \(permitido ? "concedida" : "não concedida")")
        return r.joined(separator: "\n")
    }
}
