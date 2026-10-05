import Foundation
import CoreGraphics

/// As contas das ferramentas de mídia: nomes de saída que nunca sobrescrevem,
/// tamanhos que mantêm a proporção, os quadros de um GIF e onde vai a marca
/// d'água. Quem lê e grava os arquivos é o app.
public enum Midia {

    public enum Tipo: Equatable, Sendable { case video, imagem, outro }

    public static let extensoesDeVideo: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm", "3gp"]
    public static let extensoesDeImagem: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif",
                                                        "gif", "bmp", "webp"]

    public static func tipo(_ caminho: String) -> Tipo {
        let e = (caminho as NSString).pathExtension.lowercased()
        if extensoesDeVideo.contains(e) { return .video }
        if extensoesDeImagem.contains(e) { return .imagem }
        return .outro
    }

    /// Ao lado do original, com um sufixo, e sem nunca sobrescrever:
    /// "praia-comprimido.mp4", "praia-comprimido 2.mp4"…
    public static func nomeDeSaida(original: String, sufixo: String, extensao: String,
                                   existe: (String) -> Bool) -> String {
        let pasta = (original as NSString).deletingLastPathComponent
        let base = ((original as NSString).lastPathComponent as NSString).deletingPathExtension
        var n = 1
        while true {
            let nome = "\(base)-\(sufixo)\(n == 1 ? "" : " \(n)").\(extensao)"
            let caminho = (pasta as NSString).appendingPathComponent(nome)
            if !existe(caminho) { return caminho }
            n += 1
        }
    }

    /// Cabe em `maximo` no lado maior, sem aumentar; com `par`, os dois lados
    /// ficam pares (os codificadores de vídeo exigem).
    public static func tamanhoAlvo(largura: Int, altura: Int, maximo: Int, par: Bool = false) -> (Int, Int) {
        guard largura > 0, altura > 0 else { return (0, 0) }
        let escala = min(1, Double(maximo) / Double(max(largura, altura)))
        var l = Int((Double(largura) * escala).rounded()), a = Int((Double(altura) * escala).rounded())
        if par { l -= l % 2; a -= a % 2 }
        return (max(par ? 2 : 1, l), max(par ? 2 : 1, a))
    }

    /// Os instantes (em segundos) dos quadros de um GIF: `fps` por segundo,
    /// sem passar de `maxQuadros` — um vídeo longo vira um GIF com menos
    /// quadros por segundo, não um arquivo enorme.
    public static func instantesDoGif(duracao: Double, fps: Double, maxQuadros: Int) -> [Double] {
        guard duracao > 0, fps > 0, maxQuadros > 0 else { return [] }
        let n = min(maxQuadros, max(1, Int((duracao * fps).rounded(.down))))
        let passo = duracao / Double(n)
        return (0..<n).map { Double($0) * passo }
    }

    /// O atraso de cada quadro do GIF, em segundos.
    public static func atrasoDoGif(duracao: Double, quadros: Int) -> Double {
        guard quadros > 0 else { return 0.1 }
        return max(0.02, duracao / Double(quadros))
    }

    public enum Canto: String, CaseIterable, Identifiable, Sendable {
        case inferiorDireito, inferiorEsquerdo, superiorDireito, superiorEsquerdo, centro
        public var id: String { rawValue }
        public var titulo: String {
            switch self {
            case .inferiorDireito:  return "Embaixo à direita"
            case .inferiorEsquerdo: return "Embaixo à esquerda"
            case .superiorDireito:  return "Em cima à direita"
            case .superiorEsquerdo: return "Em cima à esquerda"
            case .centro:           return "No centro"
            }
        }
    }

    /// Onde desenhar a marca d'água, em coordenadas com a origem embaixo (as
    /// do Core Graphics). A margem é proporcional à imagem.
    public static func quadroDaMarca(imagem: CGSize, marca: CGSize, canto: Canto) -> CGRect {
        let m = (min(imagem.width, imagem.height) * 0.03).rounded()
        let x: CGFloat, y: CGFloat
        switch canto {
        case .inferiorDireito:  x = imagem.width - marca.width - m; y = m
        case .inferiorEsquerdo: x = m; y = m
        case .superiorDireito:  x = imagem.width - marca.width - m; y = imagem.height - marca.height - m
        case .superiorEsquerdo: x = m; y = imagem.height - marca.height - m
        case .centro:           x = (imagem.width - marca.width) / 2; y = (imagem.height - marca.height) / 2
        }
        return CGRect(x: x, y: y, width: marca.width, height: marca.height)
    }

    /// "2,4 MB → 840 KB (−65%)".
    public static func resumo(antes: Int64, depois: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        let a = f.string(fromByteCount: antes), d = f.string(fromByteCount: depois)
        guard antes > 0 else { return d }
        let p = Int(((Double(depois) / Double(antes) - 1) * 100).rounded())
        return "\(a) → \(d) (\(p > 0 ? "+" : p < 0 ? "−" : "")\(abs(p))%)"
    }
}

/// A gravação de tela: o nome do arquivo, a área escolhida e o relógio.
public enum Gravacao {

    public static func nomeDoArquivo(em data: Date, fuso: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = fuso
        f.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
        return "Gravação \(f.string(from: data)).mov"
    }

    /// O retângulo entre dois pontos do arrasto, dentro da tela e com lados
    /// pares; `nil` se pequeno demais (um clique sem arrastar).
    public static func area(de a: CGPoint, ate b: CGPoint, tela: CGRect, minimo: CGFloat = 40) -> CGRect? {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            .intersection(tela)
        guard !r.isNull, r.width >= minimo, r.height >= minimo else { return nil }
        let l = CGFloat(Int(r.width) - Int(r.width) % 2), h = CGFloat(Int(r.height) - Int(r.height) % 2)
        return CGRect(x: r.minX.rounded(.down), y: r.minY.rounded(.down), width: l, height: h)
    }

    /// "0:07", "12:30", "1:02:03".
    public static func relogio(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
