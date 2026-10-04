import Foundation
import CoreGraphics

/// Uma marca feita sobre a captura. As coordenadas são em PIXELS da imagem,
/// com a origem no canto superior esquerdo — não na janela —, para a imagem
/// exportada sair na resolução real, e não do tamanho em que foi editada.
public struct Anotacao: Identifiable, Equatable, Sendable {
    public enum Forma: Equatable, Sendable {
        case seta(de: CGPoint, para: CGPoint)
        case retangulo(CGRect)
        case caneta([CGPoint])
        case destaque(CGRect)
        case texto(CGPoint, String)
        /// Pixeliza a área: esconde de verdade, não só cobre.
        case borrao(CGRect)
    }

    public var id: UUID
    public var forma: Forma
    /// Cor em RGB de 0 a 1 — fora do AppKit para o Core continuar testável.
    public var cor: CorDeAnotacao
    public var espessura: CGFloat

    public init(id: UUID = UUID(), forma: Forma, cor: CorDeAnotacao = .vermelho, espessura: CGFloat = 6) {
        self.id = id
        self.forma = forma
        self.cor = cor
        self.espessura = espessura
    }
}

public enum CorDeAnotacao: String, CaseIterable, Identifiable, Sendable {
    case vermelho, laranja, amarelo, verde, azul, preto, branco

    public var id: String { rawValue }

    public var rgb: (Double, Double, Double) {
        switch self {
        case .vermelho: return (1.00, 0.23, 0.19)
        case .laranja:  return (1.00, 0.58, 0.00)
        case .amarelo:  return (1.00, 0.80, 0.00)
        case .verde:    return (0.20, 0.78, 0.35)
        case .azul:     return (0.00, 0.48, 1.00)
        case .preto:    return (0.00, 0.00, 0.00)
        case .branco:   return (1.00, 1.00, 1.00)
        }
    }
}

/// As ferramentas da barra do editor.
public enum FerramentaDeAnotacao: String, CaseIterable, Identifiable, Sendable {
    case seta, retangulo, caneta, destaque, texto, borrao, recorte

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .seta:      return "Seta"
        case .retangulo: return "Retângulo"
        case .caneta:    return "Caneta"
        case .destaque:  return "Marca-texto"
        case .texto:     return "Texto"
        case .borrao:    return "Borrão"
        case .recorte:   return "Recortar"
        }
    }

    public var simbolo: String {
        switch self {
        case .seta:      return "arrow.up.right"
        case .retangulo: return "rectangle"
        case .caneta:    return "scribble"
        case .destaque:  return "highlighter"
        case .texto:     return "textformat"
        case .borrao:    return "eye.slash"
        case .recorte:   return "crop"
        }
    }

    /// Atalho de uma tecla, como nos editores de imagem.
    public var tecla: Character {
        switch self {
        case .seta: return "a"
        case .retangulo: return "r"
        case .caneta: return "p"
        case .destaque: return "h"
        case .texto: return "t"
        case .borrao: return "b"
        case .recorte: return "c"
        }
    }
}

public enum GeometriaDeAnotacao {

    /// O retângulo entre dois pontos, qualquer que seja a direção do arrasto.
    public static func retangulo(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// As duas pontas da cabeça da seta. A cabeça cresce com a espessura, mas
    /// nunca passa de metade do corpo — numa seta curta, viraria um triângulo.
    public static func cabeca(de a: CGPoint, para b: CGPoint, espessura: CGFloat) -> (CGPoint, CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y
        let comprimento = max(hypot(dx, dy), 0.001)
        let tamanho = min(espessura * 4 + 8, comprimento / 2)
        let angulo = atan2(dy, dx)
        let abertura = CGFloat.pi / 7
        func ponta(_ s: CGFloat) -> CGPoint {
            CGPoint(x: b.x - tamanho * cos(angulo + s * abertura),
                    y: b.y - tamanho * sin(angulo + s * abertura))
        }
        return (ponta(1), ponta(-1))
    }

    /// Escala e deslocamento para a imagem caber na área da janela sem
    /// distorcer e sem ampliar além de 1:1 em pontos.
    public static func encaixe(imagem: CGSize, area: CGSize, escalaDaTela: CGFloat) -> (escala: CGFloat, deslocamento: CGPoint) {
        guard imagem.width > 0, imagem.height > 0, area.width > 0, area.height > 0 else {
            return (1, .zero)
        }
        // 1 pixel da imagem = 1/escalaDaTela pontos: a captura Retina aparece
        // no tamanho em que estava na tela, não no dobro
        let natural = 1 / max(escalaDaTela, 1)
        let caber = min(area.width / imagem.width, area.height / imagem.height)
        let e = min(natural, caber)
        let desenho = CGSize(width: imagem.width * e, height: imagem.height * e)
        return (e, CGPoint(x: (area.width - desenho.width) / 2, y: (area.height - desenho.height) / 2))
    }

    /// Ponto da janela → pixel da imagem.
    public static func paraImagem(_ p: CGPoint, escala: CGFloat, deslocamento: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - deslocamento.x) / escala, y: (p.y - deslocamento.y) / escala)
    }

    /// O recorte preso aos limites da imagem e com pixels inteiros; `nil` se
    /// ficou pequeno demais para ser intencional (um clique sem arrasto).
    public static func recorte(_ r: CGRect, imagem: CGSize) -> CGRect? {
        let limitado = r.standardized.intersection(CGRect(origin: .zero, size: imagem)).integral
        guard !limitado.isNull, limitado.width >= 4, limitado.height >= 4 else { return nil }
        return limitado
    }

    /// Lado do bloco do borrão: proporcional à imagem, para pixelizar o
    /// bastante tanto numa captura pequena quanto numa tela 5K.
    public static func blocoDoBorrao(imagem: CGSize) -> CGFloat {
        max(12, (max(imagem.width, imagem.height) / 80).rounded())
    }
}
