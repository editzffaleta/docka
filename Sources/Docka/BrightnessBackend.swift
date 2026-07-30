import AppKit
import Foundation
import CoreGraphics

/// Leitura e escrita do brilho da tela.
///
/// **Por que DisplayServices e não a tecla de mídia.** A tecla de mídia usa API
/// pública (`NSEvent.systemDefined` + `CGEvent.post`), mas exige permissão de
/// **Acessibilidade** — e a regra do projeto é clara: se a feature precisa de
/// permissão TCC, ela não entra. (O teste que me fez achar o contrário rodou
/// num processo que herdou a permissão do pai; dentro do Docka.app, sem
/// permissão, o post é silenciosamente ignorado.)
///
/// `DisplayServices` é framework do sistema, não pede permissão nenhuma e ainda
/// permite LER o brilho — o que elimina o modelo estimado e a recalibração.
/// O preço é ser API não documentada: pode sumir numa atualização do macOS. Por
/// isso tudo aqui é resolvido em tempo de execução e `disponivel` diz a verdade,
/// para a interface esconder o controle em vez de fingir que funciona.
enum BrightnessBackend {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let lib: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static let getFn: GetFn? = {
        guard let lib, let s = dlsym(lib, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(s, to: GetFn.self)
    }()

    private static let setFn: SetFn? = {
        guard let lib, let s = dlsym(lib, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(s, to: SetFn.self)
    }()

    /// O sistema desta máquina expõe o controle?
    static var disponivel: Bool { getFn != nil && setFn != nil }

    /// A tela sob o cursor — é nela que o brilho age.
    ///
    /// Antes tudo ia para `CGMainDisplayID()`: com dois monitores, a régua
    /// aberta no secundário ajustava o brilho do principal. O cursor está
    /// sempre na tela do painel que o usuário está usando (é ele que revela o
    /// painel), então "a tela sob o cursor" acerta nos dois mundos — e com um
    /// monitor só, é idêntico ao comportamento antigo.
    private static func telaSobOCursor() -> CGDirectDisplayID {
        let loc = NSEvent.mouseLocation
        let tela = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
        return (tela?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID) ?? CGMainDisplayID()
    }

    /// Brilho atual (0…1) da tela sob o cursor, ou nil se não der para ler.
    static func ler(_ display: CGDirectDisplayID? = nil) -> Double? {
        guard let getFn else { return nil }
        var v: Float = 0
        guard getFn(display ?? telaSobOCursor(), &v) == 0 else { return nil }
        return Double(v)
    }

    @discardableResult
    static func escrever(_ nivel: Double, _ display: CGDirectDisplayID? = nil) -> Bool {
        guard let setFn else { return false }
        return setFn(display ?? telaSobOCursor(), Float(max(0, min(1, nivel)))) == 0
    }

    /// Autoteste: lê, mexe, confere e devolve. Roda DENTRO do app, que é o único
    /// contexto que vale — foi testar fora dele que me levou ao caminho errado.
    /// O resultado também vai para um arquivo, porque lançado pelo Finder o app
    /// não tem stdout para onde falar.
    static func autoteste(paraArquivo caminho: String? = nil) -> String {
        let r = autoteste()
        if let caminho { try? r.write(toFile: caminho, atomically: true, encoding: .utf8) }
        return r
    }

    static func autoteste() -> String {
        guard disponivel else { return "indisponível: símbolos ausentes" }
        guard let antes = ler() else { return "indisponível: leitura falhou" }
        let alvo = antes > 0.5 ? antes - 0.12 : antes + 0.12
        guard escrever(alvo) else { return "escrita recusada" }
        usleep(250_000)
        let depois = ler() ?? -1
        escrever(antes)
        let ok = abs(depois - alvo) < 0.03
        return ok
            ? "OK — leu \(Int(antes * 100))%, escreveu \(Int(alvo * 100))%, confirmou \(Int(depois * 100))%"
            : "FALHOU — alvo \(Int(alvo * 100))%, resultado \(Int(depois * 100))%"
    }
}
