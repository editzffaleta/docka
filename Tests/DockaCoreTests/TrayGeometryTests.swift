import Testing
import CoreGraphics
@testable import DockaCore

// Tela de 1710×1074 com o Dock ocupando 70pt embaixo — o formato que a bandeja
// realmente encontra numa máquina com Dock visível na borda inferior.
private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1074)
private let visible = CGRect(x: 0, y: 70, width: 1710, height: 1004)
private let trayHeight: CGFloat = 170

@Suite("Geometria da bandeja")
struct TrayGeometryTests {

    // MARK: largura

    @Test("A largura em repouso segue size, gap e a contagem de apps")
    func larguraEmRepouso() {
        let tres = TrayGeometry.restingContentWidth(appCount: 3, size: 48)
        // o esperado vai num local tipado: dentro do #expect o literal seria
        // inferido como Int e a comparação não sobrevive à expansão do macro
        let esperado: CGFloat = 3 * 48 + 2 * TrayGeometry.gap(size: 48)
        #expect(tres == esperado)
        #expect(TrayGeometry.restingContentWidth(appCount: 4, size: 48) > tres)
        #expect(TrayGeometry.restingContentWidth(appCount: 3, size: 64) > tres)
    }

    @Test("A largura do painel reserva espaço para a ampliação")
    func larguraReservaAmpliacao() {
        // o painel tem frame fixo: sem essa folga, o ícone ampliado da ponta
        // seria cortado pela borda do NSPanel
        let comAmpliacao = TrayGeometry.magnifiedContentWidth(appCount: 6, size: 48,
                                                              maxScale: 1.75, maxRange: 200)
        let repouso = TrayGeometry.restingContentWidth(appCount: 6, size: 48)
        #expect(comAmpliacao > repouso)

        let maior = TrayGeometry.magnifiedContentWidth(appCount: 6, size: 48,
                                                       maxScale: 2.5, maxRange: 200)
        #expect(maior > comAmpliacao)
    }

    @Test("Sem ampliação, a largura é a de repouso")
    func semAmpliacaoNaoReservaNada() {
        #expect(TrayGeometry.magnifiedContentWidth(appCount: 6, size: 48,
                                                   maxScale: 1, maxRange: 200)
                == TrayGeometry.restingContentWidth(appCount: 6, size: 48))
    }

    @Test("Sem apps, a bandeja ainda tem a largura de um ícone")
    func larguraSemApps() {
        // o painel existe antes de o usuário escolher qualquer app; largura 0 o
        // deixaria com frame degenerado
        #expect(TrayGeometry.trayExtent(appCount: 0, size: 48, maxScale: 1.75, maxRange: 200)
                == TrayGeometry.trayExtent(appCount: 1, size: 48, maxScale: 1.75, maxRange: 200))
    }

    // MARK: proporções do vidro (calibradas contra o Dock real)

    @Test("O vidro tem 1,32× a altura do tile, como no Dock")
    func proporcaoDoVidro() {
        // medido numa captura do Dock desta máquina: vidro 86px sobre tile 65px.
        // A proporção vale para qualquer tamanho porque a barra escala junto.
        for tamanho in [CGFloat(32), 48, 64] {
            let razao = TrayGeometry.glassHeight(size: tamanho) / tamanho
            #expect(razao > 1.28 && razao < 1.36)
        }
    }

    @Test("O vidro é dimensionado pelo tile em repouso, não pelo ampliado")
    func vidroIgnoraAmpliacao() {
        // no Dock o ícone ampliado sobe para FORA do vidro. Se a altura levasse
        // maxScale em conta, a bandeja ficaria alta e vazia enquanto ninguém
        // aponta nada — por isso glassHeight nem recebe esse parâmetro.
        let tile: CGFloat = 48
        #expect(TrayGeometry.glassHeight(size: tile) < tile * 1.75)
    }

    @Test("Há mais vidro acima dos ícones que abaixo")
    func vidroAssimetrico() {
        // no Dock a bolinha quase encosta na borda de baixo
        #expect(TrayGeometry.paddingTop(size: 32) > TrayGeometry.paddingBottom(size: 32))
    }

    // MARK: arrastar o separador (redimensionar como no Dock)

    @Test("Arrastar o separador para cima aumenta o ícone, 1 pt por 1 pt")
    func arrastoParaCimaAumenta() {
        // translation.height é NEGATIVO ao arrastar para cima
        #expect(TrayGeometry.iconSizeDragged(from: 40, verticalTranslation: -10) == 50)
        // para baixo diminui — e 30 fica abaixo do mínimo, então trava no mínimo
        #expect(TrayGeometry.iconSizeDragged(from: 40, verticalTranslation: 10)
                == TrayGeometry.iconSizeRange.lowerBound)
    }

    @Test("O arrasto respeita a mesma faixa do slider de ajustes")
    func arrastoRespeitaFaixa() {
        #expect(TrayGeometry.iconSizeDragged(from: 60, verticalTranslation: -500)
                == TrayGeometry.iconSizeRange.upperBound)
        #expect(TrayGeometry.iconSizeDragged(from: 36, verticalTranslation: 500)
                == TrayGeometry.iconSizeRange.lowerBound)
    }

    // MARK: posição horizontal

    @Test("À direita, a bandeja encosta na borda direita menos o offset")
    func positionRight() {
        let f = frame(position: .end, offsetX: 24)
        #expect(f.maxX == screen.maxX - 24)
    }

    @Test("À esquerda, a bandeja começa na borda esquerda mais o offset")
    func positionLeft() {
        let f = frame(position: .start, offsetX: 24)
        #expect(f.minX == screen.minX + 24)
    }

    @Test("No centro, a bandeja fica centrada e o offset é ignorado")
    func positionCenter() {
        let f = frame(position: .center, offsetX: 24)
        #expect(f.midX == screen.midX)
        #expect(frame(position: .center, offsetX: 300).midX == screen.midX)
    }

    @Test("Uma posição persistida desconhecida cai na direita")
    func unknownPositionFallsBack() {
        // a preferência é gravada como string livre; versões antigas ou um plist
        // editado à mão não podem quebrar o layout
        #expect(TrayAlignment(persisted: "bottom") == .end)
        #expect(TrayAlignment(persisted: "") == .end)
        #expect(TrayAlignment(persisted: "left") == .start)
    }

    // MARK: seguir o Dock

    @Test("Com followDock, a bandeja assenta em cima do Dock")
    func followDockSitsAboveDock() {
        #expect(frame(followDock: true).minY == visible.minY)
        #expect(frame(followDock: true).minY == 70)
    }

    @Test("Sem followDock, a bandeja vai para a borda física da tela")
    func withoutFollowDockGoesToScreenEdge() {
        #expect(frame(followDock: false).minY == screen.minY)
    }

    @Test("Sem Dock embaixo, followDock não muda nada")
    func followDockIsNoOpWithoutBottomDock() {
        // Dock à esquerda ou escondido: visibleFrame e frame têm o mesmo minY
        let sideDock = CGRect(x: 80, y: 0, width: 1630, height: 1074)
        let comFollow = TrayGeometry.baseY(screenFrame: screen, visibleFrame: sideDock, followDock: true)
        let semFollow = TrayGeometry.baseY(screenFrame: screen, visibleFrame: sideDock, followDock: false)
        #expect(comFollow == semFollow)
    }

    // MARK: revelar

    @Test("Revela quando o cursor encosta na borda inferior dentro da faixa")
    func revealsAtBottomEdge() {
        let f = frame()
        #expect(TrayGeometry.shouldReveal(cursor: CGPoint(x: f.midX, y: 0),
                                          trayFrame: f, screenFrame: screen, edge: .bottom, pressureZone: false))
    }

    @Test("Não revela quando o cursor está longe da faixa horizontal")
    func doesNotRevealOutsideZone() {
        let f = frame(position: .end)
        // canto inferior ESQUERDO, com a bandeja à direita
        #expect(!TrayGeometry.shouldReveal(cursor: CGPoint(x: 5, y: 0),
                                           trayFrame: f, screenFrame: screen, edge: .bottom, pressureZone: false))
    }

    @Test("Pressure Zone é mais exigente que o modo normal")
    func pressureZoneIsStricter() {
        let f = frame()
        // 2pt acima da borda: o modo normal aceita, o Pressure Zone não
        let cursor = CGPoint(x: f.midX, y: 2)
        #expect(TrayGeometry.shouldReveal(cursor: cursor, trayFrame: f,
                                          screenFrame: screen, edge: .bottom, pressureZone: false))
        #expect(!TrayGeometry.shouldReveal(cursor: cursor, trayFrame: f,
                                          screenFrame: screen, edge: .bottom, pressureZone: true))
    }

    @Test("O gatilho é a borda da tela mesmo com a bandeja acima do Dock")
    func revealTriggerIgnoresTrayBase() {
        // bandeja assentada em y=70, mas o empurrão continua sendo contra o y=0
        let f = frame(followDock: true)
        #expect(f.minY == 70)
        #expect(TrayGeometry.shouldReveal(cursor: CGPoint(x: f.midX, y: 0),
                                          trayFrame: f, screenFrame: screen, edge: .bottom, pressureZone: false))
    }

    // MARK: esconder

    @Test("O cursor sobre a bandeja a mantém aberta")
    func staysOpenOverTray() {
        let f = frame(followDock: true)
        #expect(TrayGeometry.isInsideTray(cursor: CGPoint(x: f.midX, y: f.midY), trayFrame: f, edge: .bottom))
    }

    @Test("A região de permanência usa o topo do painel, não a borda da tela")
    func hideRegionFollowsPanelTop() {
        // Este é o ponto do conserto: com a bandeja assentada em 70, o topo dela
        // fica em 240. Medir a partir da borda da tela daria 200 e esconderia a
        // bandeja com o cursor ainda em cima dela.
        let f = frame(followDock: true)
        #expect(f.maxY == 70 + trayHeight)
        #expect(TrayGeometry.isInsideTray(cursor: CGPoint(x: f.midX, y: 235), trayFrame: f, edge: .bottom))
    }

    @Test("Esconde quando o cursor sobe acima da folga")
    func hidesWellAboveTray() {
        let f = frame()
        #expect(!TrayGeometry.isInsideTray(
            cursor: CGPoint(x: f.midX, y: f.maxY + TrayGeometry.hideSlack + 1), trayFrame: f, edge: .bottom))
    }

    @Test("Esconde quando o cursor sai pela lateral")
    func hidesToTheSide() {
        let f = frame()
        #expect(!TrayGeometry.isInsideTray(
            cursor: CGPoint(x: f.minX - TrayGeometry.hideSlack - 1, y: f.midY), trayFrame: f, edge: .bottom))
    }

    // MARK: helper

    private func frame(position: TrayAlignment = .end,
                       offsetX: CGFloat = 24,
                       followDock: Bool = false,
                       edge: TrayEdge = .bottom) -> CGRect {
        TrayGeometry.frame(screenFrame: screen, visibleFrame: visible,
                           edge: edge, alignment: position, offset: offsetX,
                           followDock: followDock,
                           extent: TrayGeometry.trayExtent(appCount: 5, size: 48,
                                                           maxScale: 1.75, maxRange: 200),
                           thickness: trayHeight)
    }
}
