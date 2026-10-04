import AppKit
import CoreGraphics
import DockaCore

/// As telas conectadas e o brilho de cada uma: o de hardware (DisplayServices)
/// onde a tela aceita, e o escurecimento por gama em qualquer uma.
///
/// A gama é do processo: se o Docka encerrar — ou travar —, o sistema devolve
/// as cores originais sozinho. Escurecer nunca deixa a tela presa escura.
final class TelasDeBrilho: ObservableObject {
    static let shared = TelasDeBrilho()

    struct Tela: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let nome: String
        let chave: String
        /// Aceita brilho de hardware pelo DisplayServices?
        let hardware: Bool
    }

    @Published private(set) var telas: [Tela] = []
    /// Escurecimento por chave de tela, gravado entre aberturas.
    @Published private(set) var escurecimentos: [String: Double] = [:]

    private let chaveGravada = "docka.dimming"

    private init() {
        escurecimentos = (UserDefaults.standard.dictionary(forKey: chaveGravada) as? [String: Double]) ?? [:]
        atualizarTelas()
    }

    /// Relê as telas e reaplica o escurecimento de cada uma. Chamado ao abrir
    /// e quando um monitor entra ou sai.
    func atualizarTelas() {
        telas = NSScreen.screens.compactMap { s in
            guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID else { return nil }
            let chave = Escurecimento.chave(fabricante: CGDisplayVendorNumber(id),
                                            modelo: CGDisplayModelNumber(id),
                                            serie: CGDisplaySerialNumber(id))
            return Tela(id: id, nome: s.localizedName, chave: chave,
                        hardware: BrightnessBackend.ler(id) != nil)
        }
        aplicarTodas()
    }

    func escurecimento(_ tela: Tela) -> Double { escurecimentos[tela.chave] ?? 0 }

    func definirEscurecimento(_ valor: Double, em tela: Tela) {
        let v = Escurecimento.limitar(valor)
        escurecimentos[tela.chave] = v < 0.005 ? nil : v
        UserDefaults.standard.set(escurecimentos, forKey: chaveGravada)
        aplicarTodas()
    }

    /// Aplica a gama de todas as telas de uma vez.
    ///
    /// Restaura primeiro e reaplica depois: `CGDisplayRestoreColorSyncSettings`
    /// é o único jeito de devolver a calibração original, e ele age em todas as
    /// telas juntas — restaurar só a que voltou a 0 não existe.
    private func aplicarTodas() {
        CGDisplayRestoreColorSyncSettings()
        for t in telas {
            let e = escurecimento(t)
            guard e > 0 else { continue }
            let teto = CGGammaValue(Escurecimento.teto(e))
            CGSetDisplayTransferByFormula(t.id, 0, teto, 1, 0, teto, 1, 0, teto, 1)
        }
    }

    // MARK: a régua da borda

    /// A tela sob o cursor — é nela que a régua age.
    private func telaSobOCursor() -> Tela? {
        let loc = NSEvent.mouseLocation
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }),
              let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return telas.first }
        return telas.first { $0.id == id }
    }

    /// Nível da régua: o brilho de hardware, ou — numa tela sem ele — o
    /// escurecimento ao contrário. Assim a mesma régua funciona em qualquer
    /// monitor, sem a pessoa precisar saber qual aceita o quê.
    func lerRegua() -> Double? {
        guard let t = telaSobOCursor() else { return BrightnessBackend.ler() }
        if t.hardware { return BrightnessBackend.ler(t.id) }
        return Escurecimento.nivelDaRegua(escurecimento: escurecimento(t))
    }

    func escreverRegua(_ nivel: Double) {
        guard let t = telaSobOCursor() else { BrightnessBackend.escrever(nivel); return }
        if t.hardware {
            BrightnessBackend.escrever(nivel, t.id)
        } else {
            definirEscurecimento(Escurecimento.escurecimento(nivelDaRegua: nivel), em: t)
        }
    }

    /// Confere a gama de verdade: escurece um pouco, lê de volta do sistema e
    /// desfaz. Pisca a tela por um instante, nada além disso.
    static func autoteste() -> String {
        let t = TelasDeBrilho.shared
        var linhas = t.telas.map { tela -> String in
            let hw = tela.hardware ? "hardware \(Int((BrightnessBackend.ler(tela.id) ?? 0) * 100))%" : "sem brilho de hardware"
            return "\(tela.nome) [\(tela.chave)]: \(hw), escurecimento \(Int(t.escurecimento(tela) * 100))%"
        }
        guard let tela = t.telas.first else { return "nenhuma tela" }
        let antes = t.escurecimento(tela)
        t.definirEscurecimento(0.15, em: tela)
        var minimo: CGGammaValue = 0, maximo: CGGammaValue = 0, gama: CGGammaValue = 0
        var g = (r: (minimo, maximo, gama), g: (minimo, maximo, gama), b: (minimo, maximo, gama))
        CGGetDisplayTransferByFormula(tela.id, &g.r.0, &g.r.1, &g.r.2,
                                      &g.g.0, &g.g.1, &g.g.2, &g.b.0, &g.b.1, &g.b.2)
        t.definirEscurecimento(antes, em: tela)
        let ok = abs(Double(g.r.1) - 0.85) < 0.01
        linhas.append(ok ? "gama: OK — teto lido \(String(format: "%.2f", g.r.1)) para 15% de escurecimento, desfeito"
                         : "gama: FALHOU — teto lido \(g.r.1), esperado 0,85")
        return linhas.joined(separator: "\n")
    }
}
