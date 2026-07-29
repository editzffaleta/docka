import SwiftUI
import AppKit

/// Arrasto e clique que funcionam num painel NÃO-ATIVANTE.
///
/// **Por que não `DragGesture`.** Num `NSPanel` não-ativante que nunca vira
/// *key*, o gesto do SwiftUI não recebe evento nenhum — nem clique, nem arrasto.
/// Um `Button` funciona (o AppKit trata botão por outro caminho), mas gesto cru
/// fica mudo, sem erro e sem aviso. Verificado com clique e arrasto sintéticos:
/// tanto o botão do brilho quanto a alça da bandeja estavam inertes.
///
/// A saída é a mesma do cursor: uma `NSView` que declara `acceptsFirstMouse` e
/// trata os eventos ela mesma.
struct ArrastoAppKit: NSViewRepresentable {
    /// Deslocamento acumulado desde o início, na convenção do SwiftUI:
    /// y positivo para BAIXO, x positivo para a DIREITA.
    var aoArrastar: (CGSize) -> Void
    var aoSoltar: (CGSize) -> Void
    var cursor: NSCursor = .arrow
    /// Pinta a área com um alfa mínimo para que ela receba cliques.
    ///
    /// `NSVisualEffectView` com `.behindWindow` não desenha pixel nenhum: ele
    /// abre um buraco no buffer da janela para o desktop aparecer. Numa janela
    /// não-opaca, o servidor decide o clique pelo alfa do pixel — e alfa zero
    /// deixa o clique atravessar. Era por isso que o vidro da bandeja não
    /// respondia a nada enquanto os ícones, que têm pixels opacos, respondiam.
    var receberCliques = false

    final class V: NSView {
        var aoArrastar: ((CGSize) -> Void)?
        var aoSoltar: ((CGSize) -> Void)?
        var cursor: NSCursor = .arrow
        private var inicio: NSPoint = .zero

        /// A chave: sem isto o primeiro clique numa janela sem foco é engolido.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Uma única área, criada no início. `.inVisibleRect` faz o retângulo
        /// acompanhar os bounds sozinho: refazer a área a cada layout disparava
        /// uma tempestade de mouseEntered/mouseExited (centenas por segundo,
        /// medidas no log) enquanto a fileira respirava com a ampliação.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            guard trackingAreas.isEmpty else { return }
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                           owner: self))
        }
        override func cursorUpdate(with event: NSEvent) { cursor.set() }

        override func mouseDown(with e: NSEvent) { inicio = e.locationInWindow }
        override func mouseDragged(with e: NSEvent) { aoArrastar?(desloc(e)) }
        override func mouseUp(with e: NSEvent) { aoSoltar?(desloc(e)) }

        /// AppKit tem y crescendo para cima; o resto do código usa a convenção
        /// do SwiftUI, com y para baixo.
        private func desloc(_ e: NSEvent) -> CGSize {
            CGSize(width: e.locationInWindow.x - inicio.x,
                   height: inicio.y - e.locationInWindow.y)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let v = V()
        if receberCliques {
            v.wantsLayer = true
            // 2% de branco sobre a vibrância: imperceptível a olho, suficiente
            // para o pixel deixar de ser transparente
            v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.02).cgColor
        }
        v.aoArrastar = aoArrastar
        v.aoSoltar = aoSoltar
        v.cursor = cursor
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? V else { return }
        v.aoArrastar = aoArrastar
        v.aoSoltar = aoSoltar
        v.cursor = cursor
    }
}
