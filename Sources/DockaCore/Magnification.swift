import Foundation
import CoreGraphics

/// A curva de ampliação dos ícones, no modelo do `dockbar`
/// (github.com/CatsJuice/dockbar): uma onda de cosseno entre `1` e `maxScale`,
/// com suporte **limitado** por `maxRange`, avaliada como a inclinação média de
/// um seno ao longo da largura do ícone em repouso.
///
/// É mais fiel ao Dock da Apple que a gaussiana anterior em três pontos:
///
/// 1. fora de `maxRange` a escala é **exatamente** 1 — a gaussiana decai para
///    sempre e nunca chega lá, então ícones distantes ficavam com um resto de
///    ampliação e a bandeja inteira respirava junto com o cursor;
/// 2. sob o cursor a escala é **exatamente** `maxScale`;
/// 3. usa as duas bordas do ícone, e não só o centro, então a resposta não muda
///    quando um ícone tem largura diferente dos outros.
public enum Magnification {

    /// Ampliação máxima do ícone sob o cursor (1 = desativada).
    public static let defaultMaxScale: CGFloat = 1.75
    /// Até onde o cursor ainda mexe com um ícone, em pontos.
    ///
    /// O dockbar usa 200, mas com os ícones de 48 pt do Docka isso deixa o
    /// primeiro vizinho em 91% do pico — o topo da curva fica chato e o ícone
    /// apontado não se destaca. Com 140 o vizinho fica em 82%, o seguinte em
    /// 35% e o terceiro já em repouso, que é o relevo do Dock da Apple.
    public static let defaultMaxRange: CGFloat = 140

    /// O cursor está sobre **este** ícone?
    ///
    /// É o que decide o balão com o nome. Não dá para usar um limiar de escala:
    /// com a curva do Dock, um alcance de 200 pt ainda deixa um vizinho a 90 pt
    /// em 1,53× — vários balões apareceriam ao mesmo tempo. No Dock da Apple só
    /// o ícone apontado mostra o nome, então a conta é de posição, comparando
    /// contra a faixa que o ícone ocupa **em repouso**.
    public static func isHovered(pointer: CGFloat?,
                                 itemCenter: CGFloat,
                                 size: CGFloat,
                                 gap: CGFloat) -> Bool {
        guard let pointer else { return false }
        // faixa meio-aberta: na fronteira exata entre dois ícones, `<=` dos dois
        // lados acendia os dois balões ao mesmo tempo
        let delta = pointer - itemCenter
        let half = (size + gap) / 2
        return delta >= -half && delta < half
    }

    public static func scale(pointer: CGFloat,
                             itemCenter: CGFloat,
                             itemSize: CGFloat,
                             maxRange: CGFloat,
                             maxScale: CGFloat) -> CGFloat {
        let centerDistance = abs(pointer - itemCenter)
        guard centerDistance < maxRange, itemSize > 0, maxRange > 0, maxScale > 1 else { return 1 }

        let d1 = itemCenter - itemSize / 2 - pointer     // borda esquerda, relativa ao cursor
        let d2 = itemCenter + itemSize / 2 - pointer     // borda direita
        let angle = CGFloat.pi / (2 * maxRange)
        let normalization = 2 * sin(angle * itemSize / 2)
        guard abs(normalization) > .ulpOfOne else { return 1 }

        let maxSize = itemSize * maxScale
        let averageSineSlope = (sin(angle * d2) - sin(angle * d1)) / (d2 - d1)
        let scale = 1 + (maxSize - itemSize) / normalization * averageSineSlope
        return min(max(scale, 1), maxScale)
    }

    /// Centro do ícone `index` com a bandeja **em repouso**.
    ///
    /// A escala precisa sair daqui, e não da posição medida na tela. Medir o
    /// centro já ampliado realimenta a conta — o ícone cresce, o centro anda, a
    /// distância muda, a escala muda — e a ampliação fica trêmula e assimétrica.
    public static func restingCenter(index: Int,
                                     size: CGFloat,
                                     gap: CGFloat,
                                     padding: CGFloat) -> CGFloat {
        padding + CGFloat(index) * (size + gap) + size / 2
    }

}
