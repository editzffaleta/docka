import Foundation
import CoreGraphics

/// Onde a bandeja fica na tela e quando ela deve aparecer ou sumir.
///
/// Geometria pura, sem AppKit: o `TrayController` cuida do `NSPanel` e do polling
/// do cursor, mas as contas moram aqui, onde os testes conseguem alcançá-las.
public enum TrayGeometry {


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
    /// Espaço extra no fim da fileira.
    ///
    /// Zero: a bandeja não tem mais separador nem engrenagem — as configurações
    /// abrem pela barra de menus ou pelo clique-direito na própria bandeja.
    /// A conversão do cursor para o espaço da fileira depende deste valor.
    public static func trailingWidth(size: CGFloat) -> CGFloat { 0 }

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
        glassHeight(size: size) * 0.32
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

    /// Espessura do painel: o vidro mais o espaço que o ícone ampliado e o
    /// balão de nome ocupam para fora dele.
    ///
    /// Era um 170 fixo herdado do código original — apertado para ícones de 64
    /// com ampliação alta, e desperdiçado com ícones pequenos.
    public static func panelThickness(size: CGFloat, maxScale: CGFloat,
                                      edge: TrayEdge = .bottom) -> CGFloat {
        let margemDaBorda: CGFloat = 8
        let estouroDoIcone = size * max(0, maxScale - 1)
        // O balão sai na direção perpendicular à borda: embaixo ele é uma faixa
        // baixa, mas numa lateral ele sai deitado e precisa da LARGURA do nome —
        // sem isso o rótulo aparece cortado na borda do painel.
        let balao: CGFloat = edge.isVertical ? 240 : 46
        return margemDaBorda + glassHeight(size: size) + estouroDoIcone + balao
    }

    /// Extensão do painel AO LONGO da borda.
    ///
    /// A fileira cresce com o pico cheio e a ancoragem a desloca para os lados:
    /// o painel reserva o extra dos DOIS lados, calculado já com o alcance
    /// limitado pela fileira.
    public static func trayExtent(appCount: Int,
                                  size: CGFloat,
                                  maxScale: CGFloat,
                                  maxRange: CGFloat) -> CGFloat {
        let alcance = Magnification.cappedRange(count: appCount, size: size,
                                                gap: gap(size: size), maxRange: maxRange)
        let repouso = restingContentWidth(appCount: appCount, size: size)
        let ampliada = magnifiedContentWidth(appCount: appCount, size: size,
                                             maxScale: maxScale, maxRange: alcance)
        return repouso + 2 * (ampliada - repouso)
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

    /// Frame do painel para uma borda qualquer.
    ///
    /// `extent` corre ao longo da borda e `thickness` é perpendicular a ela —
    /// numa lateral os dois trocam de eixo, e é só isso que muda.
    public static func frame(screenFrame: CGRect,
                             visibleFrame: CGRect,
                             edge: TrayEdge,
                             alignment: TrayAlignment,
                             offset: CGFloat,
                             followDock: Bool,
                             extent: CGFloat,
                             thickness: CGFloat) -> CGRect {
        switch edge {
        case .bottom:
            let base = followDock ? visibleFrame.minY : screenFrame.minY
            let x: CGFloat
            switch alignment {
            case .start:  x = screenFrame.minX + offset
            case .center: x = screenFrame.midX - extent / 2
            case .end:    x = screenFrame.maxX - extent - offset
            }
            return CGRect(x: x, y: base, width: extent, height: thickness)

        case .left, .right:
            // AppKit: y cresce para cima, então `start` (topo) é o maior y
            let y: CGFloat
            switch alignment {
            case .start:  y = screenFrame.maxY - extent - offset
            case .center: y = screenFrame.midY - extent / 2
            case .end:    y = screenFrame.minY + offset
            }
            let x = edge == .left
                ? (followDock ? visibleFrame.minX : screenFrame.minX)
                : (followDock ? visibleFrame.maxX : screenFrame.maxX) - thickness
            return CGRect(x: x, y: y, width: thickness, height: extent)
        }
    }

    /// O cursor está encostado na borda inferior, dentro da faixa horizontal da bandeja?
    ///
    /// O gatilho é sempre a borda **física** da tela, mesmo quando a bandeja está
    /// assentada acima do Dock. Pressure Zone exige o cursor cravado na borda;
    /// o modo normal aceita um ponto a mais.
    public static func shouldReveal(cursor: CGPoint,
                                    trayFrame: CGRect,
                                    screenFrame: CGRect,
                                    edge: TrayEdge,
                                    pressureZone: Bool) -> Bool {
        let reach: CGFloat = pressureZone ? 1 : 2
        switch edge {
        case .bottom:
            let naFaixa = cursor.x >= trayFrame.minX - revealSlackX
                       && cursor.x <= trayFrame.maxX + revealSlackX
            return naFaixa && cursor.y <= screenFrame.minY + reach
        case .left:
            let naFaixa = cursor.y >= trayFrame.minY - revealSlackX
                       && cursor.y <= trayFrame.maxY + revealSlackX
            return naFaixa && cursor.x <= screenFrame.minX + reach
        case .right:
            let naFaixa = cursor.y >= trayFrame.minY - revealSlackX
                       && cursor.y <= trayFrame.maxY + revealSlackX
            return naFaixa && cursor.x >= screenFrame.maxX - reach
        }
    }

    /// O cursor ainda está sobre a bandeja (ou perto o bastante para não escondê-la)?
    ///
    /// Usa o topo do painel, e não a borda da tela: a bandeja pode estar assentada
    /// em cima do Dock, e aí as duas alturas não coincidem.
    public static func isInsideTray(cursor: CGPoint, trayFrame: CGRect,
                                    edge: TrayEdge) -> Bool {
        switch edge {
        case .bottom:
            return cursor.x >= trayFrame.minX - hideSlack
                && cursor.x <= trayFrame.maxX + hideSlack
                && cursor.y <= trayFrame.maxY + hideSlack
        case .left:
            return cursor.y >= trayFrame.minY - hideSlack
                && cursor.y <= trayFrame.maxY + hideSlack
                && cursor.x <= trayFrame.maxX + hideSlack
        case .right:
            return cursor.y >= trayFrame.minY - hideSlack
                && cursor.y <= trayFrame.maxY + hideSlack
                && cursor.x >= trayFrame.minX - hideSlack
        }
    }
}
