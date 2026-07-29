import Foundation
import CoreGraphics

/// Onde a bandeja fica na tela e quando ela deve aparecer ou sumir.
///
/// Geometria pura, sem AppKit: o `TrayController` cuida do `NSPanel` e do polling
/// do cursor, mas as contas moram aqui, onde os testes conseguem alcançá-las.
public enum TrayGeometry {

    public enum Position: String, Sendable, CaseIterable {
        case left, center, right

        /// A preferência é persistida como string livre; qualquer valor
        /// desconhecido cai no padrão do app.
        public init(persisted: String) {
            self = Position(rawValue: persisted) ?? .right
        }
    }

    /// Folga lateral da zona que dispara a revelação.
    public static let revealSlackX: CGFloat = 8
    /// Folga ao redor da bandeja antes de considerar que o cursor saiu dela.
    public static let hideSlack: CGFloat = 30

    // Nomes iguais aos da especificação do dockbar, para a conta bater com o
    // desenho: `size` é o ícone, `gap` o vão entre eles, `padding` o vidro em volta.

    // As proporções abaixo saíram de medir uma captura do Dock real desta máquina
    // (tilesize 32) e são expressas como FRAÇÃO do ícone: no Dock a barra inteira
    // escala junto com o tile, e não só os ícones dentro de uma moldura fixa.

    /// Vão entre tiles: no Dock é ZERO.
    ///
    /// O respiro que se vê entre os ícones do Dock é a margem transparente da
    /// própria arte do ícone, não espaçamento de layout — medindo o passo entre
    /// tiles na captura, ele é exatamente o tamanho do tile. Como o Docka desenha
    /// a mesma arte (com a mesma margem) preenchendo `size`, o resultado visual
    /// bate sem precisar somar nada.
    public static func gap(size: CGFloat) -> CGFloat { size * 0.03 }
    /// Vidro à esquerda e à direita da faixa de ícones.
    public static func padding(size: CGFloat) -> CGFloat { size * 0.123 }
    /// Vidro acima do tile.
    public static func paddingTop(size: CGFloat) -> CGFloat { size * 0.108 }
    /// Vidro abaixo da bolinha de execução, que quase encosta na borda.
    public static func paddingBottom(size: CGFloat) -> CGFloat { size * 0.055 }
    /// Separador + engrenagem, como o HStack os monta de fato:
    /// [vão][traço com 2·(gap+3) de folga][vão][tile da engrenagem].
    /// Precisa ser exato — a posição do cursor no espaço do painel é convertida
    /// para o espaço da fileira usando esta largura.
    public static func trailingWidth(size: CGFloat) -> CGFloat {
        4 * gap(size: size) + 7 + size
    }

    /// Largura da fileira inteira em repouso, vidro incluído.
    public static func restingRowWidth(appCount: Int, size: CGFloat) -> CGFloat {
        2 * padding(size: size)
            + restingContentWidth(appCount: appCount, size: size)
            + trailingWidth(size: size)
    }

    /// Altura do vidro — calculada com o ícone **em repouso**, de propósito.
    ///
    /// No Dock o vidro não cresce quando um ícone é ampliado: o ícone é que sobe
    /// para fora dele. Dimensionar o vidro pelo tamanho máximo, como estava aqui,
    /// deixava a bandeja alta e vazia enquanto ninguém aponta nada.
    public static func glassHeight(size: CGFloat) -> CGFloat {
        paddingTop(size: size) + size + indicatorRow(size: size) + paddingBottom(size: size)
    }

    /// Diâmetro da bolinha de app em execução — proporcional ao ícone, como no Dock.
    public static func indicatorSize(size: CGFloat) -> CGFloat {
        max(2.5, size * 0.077)
    }

    /// Faixa abaixo do ícone reservada à bolinha.
    ///
    /// Substituiu uma folga fixa de 10 pt herdada do código original, que não
    /// tinha relação com nada e sobrava acima do ícone.
    public static func indicatorRow(size: CGFloat) -> CGFloat {
        indicatorSpacing(size: size) + indicatorSize(size: size)
    }

    /// Respiro entre o ícone e a bolinha.
    public static func indicatorSpacing(size: CGFloat) -> CGFloat { size * 0.068 }

    /// Raio do canto proporcional à altura, como no Dock. Um raio fixo deixa a
    /// bandeja quadrada com ícones pequenos e arredondada demais com ícones grandes.
    public static func cornerRadius(size: CGFloat) -> CGFloat {
        glassHeight(size: size) * 0.25
    }

    /// Novo tamanho do ícone ao arrastar o separador, como no Dock: arrastar
    /// para CIMA aumenta, para baixo diminui, 1 pt de cursor = 1 pt de ícone.
    /// A faixa é a mesma do slider de ajustes.
    public static let iconSizeRange: ClosedRange<CGFloat> = 32...64

    public static func iconSizeDragged(from start: CGFloat,
                                       verticalTranslation: CGFloat) -> CGFloat {
        min(max(start - verticalTranslation, iconSizeRange.lowerBound),
            iconSizeRange.upperBound)
    }

    public static func restingContentWidth(appCount: Int, size: CGFloat) -> CGFloat {
        let n = max(1, appCount)
        return CGFloat(n) * size + CGFloat(n - 1) * gap(size: size)
    }

    /// Largura da faixa de ícones no pior caso de ampliação.
    ///
    /// Varre a posição do cursor e fica com a soma de larguras mais alta. O
    /// painel tem frame fixo: se ele for menor que isso, o ícone ampliado da
    /// ponta é cortado. Roda no layout, não a cada quadro.
    public static func magnifiedContentWidth(appCount: Int,
                                             size: CGFloat,
                                             maxScale: CGFloat,
                                             maxRange: CGFloat) -> CGFloat {
        let n = max(1, appCount)
        let gaps = CGFloat(n - 1) * gap(size: size)
        let span = restingContentWidth(appCount: n, size: size)
        guard maxScale > 1, maxRange > 0 else { return span }

        var maior = span
        var pointer = -maxRange
        while pointer <= span + maxRange {
            var soma: CGFloat = 0
            for i in 0..<n {
                let centro = Magnification.restingCenter(index: i, size: size,
                                                         gap: gap(size: size), padding: 0)
                soma += size * Magnification.scale(pointer: pointer, itemCenter: centro,
                                                   itemSize: size, maxRange: maxRange,
                                                   maxScale: maxScale)
            }
            maior = max(maior, soma + gaps)
            pointer += 4
        }
        return maior
    }

    /// Largura total do painel: faixa de ícones ampliada + vidro + engrenagem.
    public static func trayWidth(appCount: Int,
                                 size: CGFloat,
                                 maxScale: CGFloat,
                                 maxRange: CGFloat) -> CGFloat {
        magnifiedContentWidth(appCount: appCount, size: size,
                              maxScale: maxScale, maxRange: maxRange)
            + 2 * padding(size: size) + trailingWidth(size: size)
    }

    /// Linha de base da bandeja.
    ///
    /// Com `followDock`, usamos `visibleFrame` — que já desconta o Dock — para a
    /// bandeja assentar em cima dele em vez de ficar por baixo.
    public static func baseY(screenFrame: CGRect,
                             visibleFrame: CGRect,
                             followDock: Bool) -> CGFloat {
        followDock ? visibleFrame.minY : screenFrame.minY
    }

    public static func frame(screenFrame: CGRect,
                             visibleFrame: CGRect,
                             appCount: Int,
                             size: CGFloat,
                             maxScale: CGFloat,
                             maxRange: CGFloat,
                             position: Position,
                             offsetX: CGFloat,
                             followDock: Bool,
                             height: CGFloat) -> CGRect {
        let width = trayWidth(appCount: appCount, size: size,
                              maxScale: maxScale, maxRange: maxRange)
        let x: CGFloat
        switch position {
        case .left:   x = screenFrame.minX + offsetX
        case .center: x = screenFrame.midX - width / 2
        case .right:  x = screenFrame.maxX - width - offsetX
        }
        let y = baseY(screenFrame: screenFrame, visibleFrame: visibleFrame, followDock: followDock)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// O cursor está encostado na borda inferior, dentro da faixa horizontal da bandeja?
    ///
    /// O gatilho é sempre a borda **física** da tela, mesmo quando a bandeja está
    /// assentada acima do Dock. Pressure Zone exige o cursor cravado na borda;
    /// o modo normal aceita um ponto a mais.
    public static func shouldReveal(cursor: CGPoint,
                                    trayFrame: CGRect,
                                    screenBottomY: CGFloat,
                                    pressureZone: Bool) -> Bool {
        let inZoneX = cursor.x >= trayFrame.minX - revealSlackX
                   && cursor.x <= trayFrame.maxX + revealSlackX
        let reach: CGFloat = pressureZone ? 1 : 2
        return inZoneX && cursor.y <= screenBottomY + reach
    }

    /// O cursor ainda está sobre a bandeja (ou perto o bastante para não escondê-la)?
    ///
    /// Usa o topo do painel, e não a borda da tela: a bandeja pode estar assentada
    /// em cima do Dock, e aí as duas alturas não coincidem.
    public static func isInsideTray(cursor: CGPoint, trayFrame: CGRect) -> Bool {
        cursor.x >= trayFrame.minX - hideSlack
            && cursor.x <= trayFrame.maxX + hideSlack
            && cursor.y <= trayFrame.maxY + hideSlack
    }
}
