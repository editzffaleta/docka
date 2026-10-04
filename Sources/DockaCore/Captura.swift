import Foundation
import CoreGraphics

/// Formatos em que o conta-gotas copia a cor.
public enum FormatoDeCor: String, CaseIterable, Identifiable, Sendable {
    case hex, rgb, hsl, swiftUI

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .hex:     return "HEX — #1E90FF"
        case .rgb:     return "RGB — rgb(30, 144, 255)"
        case .hsl:     return "HSL — hsl(210, 100%, 56%)"
        case .swiftUI: return "SwiftUI — Color(red:green:blue:)"
        }
    }

    public init(persisted: String) { self = FormatoDeCor(rawValue: persisted) ?? .hex }
}

public enum Captura {

    // MARK: cor

    /// A cor no formato escolhido. Componentes de 0 a 1, em sRGB.
    public static func texto(r: Double, g: Double, b: Double, formato: FormatoDeCor) -> String {
        let c = [r, g, b].map { min(max($0, 0), 1) }
        let i = c.map { Int(($0 * 255).rounded()) }
        switch formato {
        case .hex:
            return String(format: "#%02X%02X%02X", i[0], i[1], i[2])
        case .rgb:
            return "rgb(\(i[0]), \(i[1]), \(i[2]))"
        case .hsl:
            let (h, s, l) = hsl(c[0], c[1], c[2])
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .swiftUI:
            func f(_ v: Double) -> String { String(format: "%.3f", v) }
            return "Color(red: \(f(c[0])), green: \(f(c[1])), blue: \(f(c[2])))"
        }
    }

    /// RGB → HSL, com matiz em graus.
    static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    // MARK: texto da tela

    /// Um trecho reconhecido e onde ele está, com a origem embaixo (como o
    /// Vision devolve).
    public struct Trecho: Equatable, Sendable {
        public var texto: String
        public var quadro: CGRect

        public init(texto: String, quadro: CGRect) {
            self.texto = texto
            self.quadro = quadro
        }
    }

    /// Junta os trechos na ordem de leitura: de cima para baixo e, na mesma
    /// linha, da esquerda para a direita.
    ///
    /// O Vision não promete ordem nenhuma. Dois trechos estão na mesma linha
    /// quando o centro de um cai dentro da altura do outro — comparar o y
    /// exato separaria palavras de uma mesma linha por um pixel de diferença.
    public static func juntar(_ trechos: [Trecho]) -> String {
        var linhas: [[Trecho]] = []
        for t in trechos.sorted(by: { $0.quadro.midY > $1.quadro.midY }) {
            if let i = linhas.firstIndex(where: { l in
                l.contains { abs($0.quadro.midY - t.quadro.midY) < max($0.quadro.height, t.quadro.height) / 2 }
            }) {
                linhas[i].append(t)
            } else {
                linhas.append([t])
            }
        }
        return linhas
            .map { $0.sorted { $0.quadro.minX < $1.quadro.minX }.map(\.texto).joined(separator: " ") }
            .joined(separator: "\n")
    }

    // MARK: arquivo

    /// "Captura 2026-10-03 às 22.15.07.png" — o padrão do macOS, com pontos
    /// na hora porque dois-pontos não pode em nome de arquivo no Finder.
    public static func nomeDoArquivo(em data: Date, fuso: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = fuso
        f.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
        return "Captura \(f.string(from: data)).png"
    }
}
