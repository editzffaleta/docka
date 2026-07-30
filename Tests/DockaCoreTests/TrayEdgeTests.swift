import Testing
import CoreGraphics
@testable import DockaCore

private let tela = CGRect(x: 0, y: 0, width: 1710, height: 1074)
private let visivel = CGRect(x: 0, y: 70, width: 1710, height: 1004)

private func frame(_ edge: TrayEdge, _ alinhamento: TrayAlignment = .center,
                   offset: CGFloat = 24, followDock: Bool = false) -> CGRect {
    TrayGeometry.frame(screenFrame: tela, visibleFrame: visivel,
                       edge: edge, alignment: alinhamento, offset: offset,
                       followDock: followDock, extent: 400, thickness: 170)
}

@Suite("Bandeja nas laterais")
struct TrayEdgeTests {

    @Test("Numa lateral, extensão e espessura trocam de eixo")
    func eixosTrocam() {
        let baixo = frame(.bottom)
        #expect(baixo.width == 400 && baixo.height == 170)
        let lado = frame(.left)
        #expect(lado.width == 170 && lado.height == 400)
    }

    @Test("Cada borda encosta na sua")
    func encostaNaBorda() {
        #expect(frame(.bottom).minY == tela.minY)
        #expect(frame(.left).minX == tela.minX)
        #expect(frame(.right).maxX == tela.maxX)
    }

    @Test("Seguir o Dock desconta a área dele na borda certa")
    func seguirODock() {
        // visibleFrame recuado embaixo: só a bandeja inferior sente
        #expect(frame(.bottom, followDock: true).minY == visivel.minY)
        #expect(frame(.left, followDock: true).minX == visivel.minX)
    }

    @Test("Nas laterais, 'início' é o TOPO da tela")
    func inicioEOTopo() {
        // AppKit: y cresce para cima, então o topo é o maior y
        let topo = frame(.left, .start, offset: 24)
        let base = frame(.left, .end, offset: 24)
        #expect(topo.maxY == tela.maxY - 24)
        #expect(base.minY == tela.minY + 24)
        #expect(topo.minY > base.minY)
    }

    @Test("Centralizado, o offset é ignorado em qualquer borda")
    func centroIgnoraOffset() {
        for e in TrayEdge.allCases {
            let a = frame(e, .center, offset: 0)
            let b = frame(e, .center, offset: 300)
            #expect(a == b)
        }
    }

    @Test("Revelar exige o cursor na borda daquela bandeja")
    func revelarPorBorda() {
        let esq = frame(.left, .center)
        // cursor cravado na lateral esquerda, na faixa da bandeja
        #expect(TrayGeometry.shouldReveal(cursor: CGPoint(x: 0, y: esq.midY),
                                          trayFrame: esq, screenFrame: tela,
                                          edge: .left, pressureZone: false))
        // mesma altura, mas na borda de baixo: não é a borda dela
        #expect(!TrayGeometry.shouldReveal(cursor: CGPoint(x: esq.midX, y: 0),
                                           trayFrame: esq, screenFrame: tela,
                                           edge: .left, pressureZone: false))
    }

    @Test("A região de permanência acompanha o eixo da borda")
    func permanenciaPorBorda() {
        let dir = frame(.right, .center)
        #expect(TrayGeometry.isInsideTray(cursor: CGPoint(x: dir.midX, y: dir.midY),
                                          trayFrame: dir, edge: .right))
        // afastar para DENTRO da tela (x menor) tira o cursor da bandeja direita
        #expect(!TrayGeometry.isInsideTray(
            cursor: CGPoint(x: dir.minX - TrayGeometry.hideSlack - 1, y: dir.midY),
            trayFrame: dir, edge: .right))
    }

    @Test("Uma bandeja nova nasce numa borda livre")
    func bordaLivre() {
        let so_inferior = [DockConfig(edge: .bottom)]
        #expect(DockConfig.proximaBordaLivre(so_inferior) != .bottom)
        let todas = TrayEdge.allCases.map { DockConfig(edge: $0) }
        #expect(DockConfig.proximaBordaLivre(todas) == .bottom)   // volta ao padrão
    }

    @Test("O rótulo da posição muda de nome conforme a borda")
    func rotuloContextual() {
        #expect(TrayAlignment.start.titulo(for: .bottom) == "Esquerda")
        #expect(TrayAlignment.start.titulo(for: .left) == "Topo")
        #expect(TrayAlignment.end.titulo(for: .right) == "Base")
    }

    @Test("As preferências antigas de posição continuam válidas")
    func migracaoDoAlinhamento() {
        // gravávamos "left"/"center"/"right" quando só existia a borda inferior
        #expect(TrayAlignment(persisted: "left") == .start)
        #expect(TrayAlignment(persisted: "right") == .end)
        #expect(TrayAlignment(persisted: "xxx") == .end)
        #expect(TrayEdge(persisted: "xxx") == .bottom)
    }

    @Test("A espessura do painel cabe o ícone ampliado e o balão")
    func espessura() {
        let e = TrayGeometry.panelThickness(size: 48, maxScale: 1.5)
        #expect(e > TrayGeometry.glassHeight(size: 48) + 48 * 0.5)
        // e cresce com o ícone — era um 170 fixo, apertado nos ícones grandes
        #expect(TrayGeometry.panelThickness(size: 64, maxScale: 1.5) > e)
    }

    @Test("Numa lateral o painel reserva a LARGURA do balão")
    func espessuraNaLateral() {
        // deitado, o rótulo sai na horizontal e precisa de bem mais espaço —
        // com a reserva da borda inferior ele aparecia cortado
        let baixo = TrayGeometry.panelThickness(size: 48, maxScale: 1.5, edge: .bottom)
        let lado = TrayGeometry.panelThickness(size: 48, maxScale: 1.5, edge: .left)
        #expect(lado > baixo + 150)
    }
}
