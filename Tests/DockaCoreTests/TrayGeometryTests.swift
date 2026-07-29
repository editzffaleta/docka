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

    @Test("A largura cresce com a quantidade de apps e o tamanho do ícone")
    func widthGrows() {
        let small = TrayGeometry.trayWidth(appCount: 3, iconSize: 48)
        // o esperado vai num local tipado: dentro do #expect o literal seria
        // inferido como Int e a comparação não sobrevive à expansão do macro
        let esperado: CGFloat = 3 * (48 + 14) + 150
        #expect(small == esperado)
        #expect(TrayGeometry.trayWidth(appCount: 4, iconSize: 48) > small)
        #expect(TrayGeometry.trayWidth(appCount: 3, iconSize: 64) > small)
    }

    @Test("Sem apps, a bandeja ainda tem a largura de um ícone")
    func widthWithNoApps() {
        // o painel existe antes de o usuário escolher qualquer app; largura 0 o
        // deixaria com frame degenerado
        #expect(TrayGeometry.trayWidth(appCount: 0, iconSize: 48)
                == TrayGeometry.trayWidth(appCount: 1, iconSize: 48))
    }

    // MARK: posição horizontal

    @Test("À direita, a bandeja encosta na borda direita menos o offset")
    func positionRight() {
        let f = frame(position: .right, offsetX: 24)
        #expect(f.maxX == screen.maxX - 24)
    }

    @Test("À esquerda, a bandeja começa na borda esquerda mais o offset")
    func positionLeft() {
        let f = frame(position: .left, offsetX: 24)
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
        #expect(TrayGeometry.Position(persisted: "bottom") == .right)
        #expect(TrayGeometry.Position(persisted: "") == .right)
        #expect(TrayGeometry.Position(persisted: "left") == .left)
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
                                          trayFrame: f, screenBottomY: 0, pressureZone: false))
    }

    @Test("Não revela quando o cursor está longe da faixa horizontal")
    func doesNotRevealOutsideZone() {
        let f = frame(position: .right)
        // canto inferior ESQUERDO, com a bandeja à direita
        #expect(!TrayGeometry.shouldReveal(cursor: CGPoint(x: 5, y: 0),
                                           trayFrame: f, screenBottomY: 0, pressureZone: false))
    }

    @Test("Pressure Zone é mais exigente que o modo normal")
    func pressureZoneIsStricter() {
        let f = frame()
        // 2pt acima da borda: o modo normal aceita, o Pressure Zone não
        let cursor = CGPoint(x: f.midX, y: 2)
        #expect(TrayGeometry.shouldReveal(cursor: cursor, trayFrame: f,
                                          screenBottomY: 0, pressureZone: false))
        #expect(!TrayGeometry.shouldReveal(cursor: cursor, trayFrame: f,
                                           screenBottomY: 0, pressureZone: true))
    }

    @Test("O gatilho é a borda da tela mesmo com a bandeja acima do Dock")
    func revealTriggerIgnoresTrayBase() {
        // bandeja assentada em y=70, mas o empurrão continua sendo contra o y=0
        let f = frame(followDock: true)
        #expect(f.minY == 70)
        #expect(TrayGeometry.shouldReveal(cursor: CGPoint(x: f.midX, y: 0),
                                          trayFrame: f, screenBottomY: 0, pressureZone: false))
    }

    // MARK: esconder

    @Test("O cursor sobre a bandeja a mantém aberta")
    func staysOpenOverTray() {
        let f = frame(followDock: true)
        #expect(TrayGeometry.isInsideTray(cursor: CGPoint(x: f.midX, y: f.midY), trayFrame: f))
    }

    @Test("A região de permanência usa o topo do painel, não a borda da tela")
    func hideRegionFollowsPanelTop() {
        // Este é o ponto do conserto: com a bandeja assentada em 70, o topo dela
        // fica em 240. Medir a partir da borda da tela daria 200 e esconderia a
        // bandeja com o cursor ainda em cima dela.
        let f = frame(followDock: true)
        #expect(f.maxY == 70 + trayHeight)
        #expect(TrayGeometry.isInsideTray(cursor: CGPoint(x: f.midX, y: 235), trayFrame: f))
    }

    @Test("Esconde quando o cursor sobe acima da folga")
    func hidesWellAboveTray() {
        let f = frame()
        #expect(!TrayGeometry.isInsideTray(
            cursor: CGPoint(x: f.midX, y: f.maxY + TrayGeometry.hideSlack + 1), trayFrame: f))
    }

    @Test("Esconde quando o cursor sai pela lateral")
    func hidesToTheSide() {
        let f = frame()
        #expect(!TrayGeometry.isInsideTray(
            cursor: CGPoint(x: f.minX - TrayGeometry.hideSlack - 1, y: f.midY), trayFrame: f))
    }

    // MARK: helper

    private func frame(position: TrayGeometry.Position = .right,
                       offsetX: CGFloat = 24,
                       followDock: Bool = false) -> CGRect {
        TrayGeometry.frame(screenFrame: screen, visibleFrame: visible,
                           appCount: 5, iconSize: 48, position: position,
                           offsetX: offsetX, followDock: followDock, height: trayHeight)
    }
}
