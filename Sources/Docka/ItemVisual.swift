import AppKit
import SwiftUI
import DockaCore

/// Ícone, nome e lançamento de um item da órbita — a parte que toca o sistema.
///
/// O modelo (`ItemDaOrbita`) fica no Core, testável; aqui mora o que depende
/// de AppKit e do disco.
enum ItemVisual {

    private static let cache = NSCache<NSString, NSImage>()

    /// Ícone do item. Apps, arquivos e pastas usam o ícone real do Finder;
    /// site usa a logo baixada do PRÓPRIO site — a única exceção à regra de
    /// zero rede, pedida pelo usuário — e o globo desenhado enquanto (ou se)
    /// ela não chega.
    static func icone(_ item: ItemDaOrbita) -> NSImage {
        if item.tipo == .site {
            // sem NSCache aqui, de propósito: a logo chega DEPOIS que o anel já
            // desenhou o globo, e um cache por chave congelaria o globo
            if let logo = FaviconStore.shared.icone(para: item.valor) {
                return ladrilho(com: logo)
            }
            FaviconStore.shared.buscarSePreciso(item.valor)
            return ladrilhoDoGlobo()
        }
        let chave = "\(item.tipo.rawValue):\(item.valor)" as NSString
        if let pronto = cache.object(forKey: chave) { return pronto }
        let imagem = NSWorkspace.shared.icon(forFile: item.valor)
        cache.setObject(imagem, forKey: chave)
        return imagem
    }

    /// A logo do site num ladrilho branco arredondado, do feitio de um ícone
    /// de app — favicons vêm em formatos variados, e soltos no anel destoam.
    private static func ladrilho(com logo: NSImage) -> NSImage {
        let lado: CGFloat = 128
        return NSImage(size: NSSize(width: lado, height: lado), flipped: false) { rect in
            let forma = NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10),
                                     xRadius: 26, yRadius: 26)
            NSColor.white.setFill()
            forma.fill()
            forma.addClip()
            logo.draw(in: rect.insetBy(dx: 26, dy: 26))
            return true
        }
    }

    /// Nome de exibição: apps e arquivos usam o nome do Finder (localizado);
    /// o resto sai do próprio valor.
    static func nome(_ item: ItemDaOrbita) -> String {
        switch item.tipo {
        case .app:
            return PinnedApp(path: item.valor).name
        case .arquivo, .pasta:
            return FileManager.default.displayName(atPath: item.valor)
        case .site:
            return item.nomeDerivado
        }
    }

    /// O item ainda existe? Sites sempre existem; o resto depende do disco.
    static func existe(_ item: ItemDaOrbita) -> Bool {
        item.tipo == .site || FileManager.default.fileExists(atPath: item.valor)
    }

    /// Abre o item do jeito próprio de cada tipo.
    static func lancar(_ item: ItemDaOrbita) {
        switch item.tipo {
        case .app:
            PinnedApp(path: item.valor).launch()
        case .site:
            if let url = URL(string: item.valor) { NSWorkspace.shared.open(url) }
        case .arquivo, .pasta:
            // pasta abre no Finder; arquivo abre no app padrão dele
            NSWorkspace.shared.open(URL(fileURLWithPath: item.valor))
        }
    }

    /// O globo num ladrilho arredondado — o provisório enquanto a logo não
    /// chega, e o definitivo para site sem favicon (ou sem rede).
    private static func ladrilhoDoGlobo() -> NSImage {
        let lado: CGFloat = 128
        return NSImage(size: NSSize(width: lado, height: lado), flipped: false) { rect in
            let forma = NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10),
                                     xRadius: 26, yRadius: 26)
            NSColor.systemBlue.withAlphaComponent(0.85).setFill()
            forma.fill()
            let simbolo = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 58, weight: .medium))
            if let simbolo {
                let branca = NSImage(size: simbolo.size, flipped: false) { r in
                    NSColor.white.set()
                    simbolo.draw(in: r)
                    r.fill(using: .sourceAtop)
                    return true
                }
                let s = branca.size
                branca.draw(in: NSRect(x: rect.midX - s.width / 2,
                                       y: rect.midY - s.height / 2,
                                       width: s.width, height: s.height))
            }
            return true
        }
    }
}
