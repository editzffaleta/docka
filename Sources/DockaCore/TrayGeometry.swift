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

    /// Ícones + espaçamentos + padding do vidro + margem para a magnificação.
    public static func trayWidth(appCount: Int, iconSize: CGFloat) -> CGFloat {
        CGFloat(max(1, appCount)) * (iconSize + 14) + 150
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
                             iconSize: CGFloat,
                             position: Position,
                             offsetX: CGFloat,
                             followDock: Bool,
                             height: CGFloat) -> CGRect {
        let width = trayWidth(appCount: appCount, iconSize: iconSize)
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
