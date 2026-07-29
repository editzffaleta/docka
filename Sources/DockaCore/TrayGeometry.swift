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

    /// Vão entre ícones em repouso. O Dock da Apple é justo (o dockbar usa 5).
    public static let gap: CGFloat = 6
    /// Espessura do vidro em volta da faixa de ícones.
    public static let padding: CGFloat = 10
    /// Vidro acima e abaixo da faixa de ícones.
    public static let verticalPadding: CGFloat = 6
    /// Separador + engrenagem no fim da bandeja.
    public static let trailingWidth: CGFloat = 44

    /// Altura do vidro: o ícone no tamanho máximo mais o vidro em volta.
    public static func glassHeight(size: CGFloat, maxScale: CGFloat) -> CGFloat {
        size * max(1, maxScale) + iconSlotSlack + 2 * verticalPadding
    }

    /// Folga vertical dentro do slot do ícone (respiro para a bolinha de execução).
    public static let iconSlotSlack: CGFloat = 10

    /// Raio do canto proporcional à altura, como no Dock. Um raio fixo deixa a
    /// bandeja quadrada com ícones pequenos e arredondada demais com ícones grandes.
    public static func cornerRadius(size: CGFloat, maxScale: CGFloat) -> CGFloat {
        glassHeight(size: size, maxScale: maxScale) * 0.30
    }

    public static func restingContentWidth(appCount: Int, size: CGFloat) -> CGFloat {
        let n = max(1, appCount)
        return CGFloat(n) * size + CGFloat(n - 1) * gap
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
        let gaps = CGFloat(n - 1) * gap
        let span = restingContentWidth(appCount: n, size: size)
        guard maxScale > 1, maxRange > 0 else { return span }

        var maior = span
        var pointer = -maxRange
        while pointer <= span + maxRange {
            var soma: CGFloat = 0
            for i in 0..<n {
                let centro = Magnification.restingCenter(index: i, size: size,
                                                         gap: gap, padding: 0)
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
            + 2 * padding + trailingWidth
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
