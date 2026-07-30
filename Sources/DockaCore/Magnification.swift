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
    ///
    /// 1,5 medido num print do Dock real do usuário (Terminal ampliado vs
    /// vizinho em repouso). Com o pico cheio, 1,75 ficava grande demais.
    public static let defaultMaxScale: CGFloat = 1.5
    /// Até onde o cursor ainda mexe com um ícone, em pontos.
    ///
    /// O dockbar usa 200, mas com os ícones de 48 pt do Docka isso deixa o
    /// primeiro vizinho em 91% do pico — o topo da curva fica chato e o ícone
    /// apontado não se destaca. Com 140 o vizinho fica em 82%, o seguinte em
    /// 35% e o terceiro já em repouso, que é o relevo do Dock da Apple.
    public static let defaultMaxRange: CGFloat = 140

    /// Alcance efetivo numa fileira curta: limitado a ~metade da fileira.
    /// Sem isso, um alcance grande cobre TODOS os ícones, tudo incha junto e o
    /// vidro muda de largura — o Dock real só mexe nos vizinhos do cursor.
    public static func cappedRange(count: Int, size: CGFloat, gap: CGFloat,
                                   maxRange: CGFloat) -> CGFloat {
        let fileira = CGFloat(count) * size + CGFloat(max(0, count - 1)) * gap
        return min(maxRange, max(size * 1.4, fileira * 0.45))
    }

    /// Deslocamento horizontal que mantém PARADO o ponto sob o cursor quando a
    /// fileira (um HStack centralizado no painel) muda de largura com a ampliação.
    ///
    /// Sem isto, o crescimento centralizado move a origem da fileira sob um
    /// cursor parado: o ícone cresce, a fileira alarga, a coordenada do cursor
    /// na fileira muda, a escala muda — realimentação, e a ampliação treme.
    /// O Dock real ancora o ponto sob o cursor e empurra os vizinhos para fora.
    ///
    /// `pointer` vem no espaço do vidro (0 = borda esquerda do vidro).
    public static func centeredRowShift(pointer: CGFloat?,
                                        count: Int,
                                        size: CGFloat,
                                        gap: CGFloat,
                                        padding: CGFloat,
                                        maxScale: CGFloat,
                                        maxRange: CGFloat) -> CGFloat {
        guard let pointer, count > 0, maxScale > 1, size > 0 else { return 0 }
        let p = pointer - padding            // coords da fileira: 0 = borda do 1º ícone
        var restingX: CGFloat = 0
        var scaledX: CGFloat = 0
        var scaledP: CGFloat? = p < 0 ? p : nil
        var extraTotal: CGFloat = 0

        for i in 0..<count {
            let centro = restingCenter(index: i, size: size, gap: gap, padding: 0)
            let w = size * scale(pointer: p, itemCenter: centro, itemSize: size,
                                 maxRange: maxRange, maxScale: maxScale)
            extraTotal += w - size
            // o mesmo ponto material do ícone, na fileira já ampliada
            if scaledP == nil, p <= restingX + size {
                scaledP = scaledX + (p - restingX) / size * w
            }
            restingX += size; scaledX += w
            if i < count - 1 {
                if scaledP == nil, p <= restingX + gap {
                    scaledP = scaledX + (p - restingX)   // vãos não mudam de largura
                }
                restingX += gap; scaledX += gap
            }
        }
        let sp = scaledP ?? (scaledX + (p - restingX))   // além da ponta direita

        // (p - sp) ancora o ponto material; extraTotal/2 desfaz a centralização
        return (p - sp) + extraTotal / 2
    }

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
