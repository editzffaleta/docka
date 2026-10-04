import Foundation
import CoreGraphics

/// Onde mandar a janela da frente.
public enum LayoutDeJanela: String, CaseIterable, Identifiable, Codable, Sendable {
    case esquerda, direita, cima, baixo
    case superiorEsquerdo, superiorDireito, inferiorEsquerdo, inferiorDireito
    case tercoEsquerdo, tercoCentral, tercoDireito
    case maximizar, centralizar
    case proximaTela
    case restaurar

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .esquerda:         return "Metade esquerda"
        case .direita:          return "Metade direita"
        case .cima:             return "Metade de cima"
        case .baixo:            return "Metade de baixo"
        case .superiorEsquerdo: return "Quarto superior esquerdo"
        case .superiorDireito:  return "Quarto superior direito"
        case .inferiorEsquerdo: return "Quarto inferior esquerdo"
        case .inferiorDireito:  return "Quarto inferior direito"
        case .tercoEsquerdo:    return "Terço esquerdo"
        case .tercoCentral:     return "Terço do meio"
        case .tercoDireito:     return "Terço direito"
        case .maximizar:        return "Maximizar"
        case .centralizar:      return "Centralizar"
        case .proximaTela:      return "Mandar para a próxima tela"
        case .restaurar:        return "Voltar ao tamanho anterior"
        }
    }

    public var simbolo: String {
        switch self {
        case .esquerda:         return "rectangle.lefthalf.filled"
        case .direita:          return "rectangle.righthalf.filled"
        case .cima:             return "rectangle.tophalf.filled"
        case .baixo:            return "rectangle.bottomhalf.filled"
        case .superiorEsquerdo: return "rectangle.inset.topleft.filled"
        case .superiorDireito:  return "rectangle.inset.topright.filled"
        case .inferiorEsquerdo: return "rectangle.inset.bottomleft.filled"
        case .inferiorDireito:  return "rectangle.inset.bottomright.filled"
        case .tercoEsquerdo:    return "rectangle.leadingthird.inset.filled"
        case .tercoCentral:     return "rectangle.center.inset.filled"
        case .tercoDireito:     return "rectangle.trailingthird.inset.filled"
        case .maximizar:        return "rectangle.inset.filled"
        case .centralizar:      return "rectangle.center.inset.filled"
        case .proximaTela:      return "rectangle.on.rectangle"
        case .restaurar:        return "arrow.uturn.backward"
        }
    }

    /// Os que aparecem no menu, em grupos separados por um divisor.
    public static let grupos: [[LayoutDeJanela]] = [
        [.esquerda, .direita, .cima, .baixo],
        [.superiorEsquerdo, .superiorDireito, .inferiorEsquerdo, .inferiorDireito],
        [.tercoEsquerdo, .tercoCentral, .tercoDireito],
        [.maximizar, .centralizar, .proximaTela, .restaurar],
    ]
}

/// A geometria do encaixe, em coordenadas do AppKit (origem embaixo à
/// esquerda, y para cima) — a conversão para as da Acessibilidade fica num
/// passo à parte.
public enum Encaixe {

    /// Larguras por que um atalho de metade passa ao ser repetido.
    public static let ciclo: [CGFloat] = [1.0 / 2, 1.0 / 3, 2.0 / 3]

    /// O próximo passo do ciclo: repetir "metade esquerda" com a janela já na
    /// metade esquerda estreita para um terço, depois alarga para dois terços.
    public static func proximoPasso(depois anterior: Int?) -> Int {
        guard let anterior else { return 0 }
        return (anterior + 1) % ciclo.count
    }

    /// O quadro do layout dentro da área útil da tela (sem barra de menus nem
    /// Dock). `passo` escolhe a fração do ciclo nos layouts de metade.
    /// `atual` serve ao centralizar, que mantém o tamanho.
    public static func quadro(_ layout: LayoutDeJanela, em area: CGRect,
                              passo: Int = 0, atual: CGRect? = nil) -> CGRect? {
        let f = ciclo[min(max(passo, 0), ciclo.count - 1)]
        let w = area.width, h = area.height
        let x = area.minX, y = area.minY
        switch layout {
        case .esquerda: return CGRect(x: x, y: y, width: w * f, height: h)
        case .direita:  return CGRect(x: area.maxX - w * f, y: y, width: w * f, height: h)
        case .cima:     return CGRect(x: x, y: area.maxY - h * f, width: w, height: h * f)
        case .baixo:    return CGRect(x: x, y: y, width: w, height: h * f)
        case .superiorEsquerdo: return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
        case .superiorDireito:  return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
        case .inferiorEsquerdo: return CGRect(x: x, y: y, width: w / 2, height: h / 2)
        case .inferiorDireito:  return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
        case .tercoEsquerdo:    return CGRect(x: x, y: y, width: w / 3, height: h)
        case .tercoCentral:     return CGRect(x: x + w / 3, y: y, width: w / 3, height: h)
        case .tercoDireito:     return CGRect(x: x + 2 * w / 3, y: y, width: w / 3, height: h)
        case .maximizar:        return area
        case .centralizar:
            let a = atual ?? area.insetBy(dx: w * 0.15, dy: h * 0.15)
            let lw = min(a.width, w), lh = min(a.height, h)
            return CGRect(x: area.midX - lw / 2, y: area.midY - lh / 2, width: lw, height: lh)
        case .proximaTela, .restaurar:
            return nil   // dependem de outra tela ou da memória: a casca resolve
        }
    }

    /// Leva um quadro de uma tela para outra mantendo a proporção: a janela
    /// que ocupava a metade esquerda de uma ocupa a metade esquerda da outra.
    public static func levar(_ quadro: CGRect, de origem: CGRect, para destino: CGRect) -> CGRect {
        guard origem.width > 0, origem.height > 0 else { return quadro }
        let fx = (quadro.minX - origem.minX) / origem.width
        let fy = (quadro.minY - origem.minY) / origem.height
        let fw = quadro.width / origem.width
        let fh = quadro.height / origem.height
        return CGRect(x: destino.minX + fx * destino.width,
                      y: destino.minY + fy * destino.height,
                      width: min(fw, 1) * destino.width,
                      height: min(fh, 1) * destino.height)
    }

    /// AppKit (y para cima, origem na base da tela principal) → Acessibilidade
    /// (y para baixo, origem no topo da tela principal). A tela principal é a
    /// referência dos dois sistemas, por isso a altura dela é o que basta.
    public static func paraAcessibilidade(_ r: CGRect, alturaDaPrincipal: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: alturaDaPrincipal - r.maxY, width: r.width, height: r.height)
    }

    public static func doAcessibilidade(_ r: CGRect, alturaDaPrincipal: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: alturaDaPrincipal - r.maxY, width: r.width, height: r.height)
    }

    /// A janela já está (quase) neste quadro? Apps arredondam o tamanho pedido
    /// — um terminal só aceita larguras múltiplas da coluna —, então igualdade
    /// exata nunca acontece.
    public static func quaseIgual(_ a: CGRect, _ b: CGRect, folga: CGFloat = 12) -> Bool {
        abs(a.minX - b.minX) <= folga && abs(a.minY - b.minY) <= folga
            && abs(a.width - b.width) <= folga && abs(a.height - b.height) <= folga
    }
}
