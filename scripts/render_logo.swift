import AppKit

// A logo do Docka, renderizada em 1024.
// Uso: swift scripts/render_logo.swift <saida.png>
//
// O desenho é a ÓRBITA: um anel de vidro com quatro itens em volta e o
// apontado ampliado no topo. É o que o Docka tem de mais seu — nenhum outro
// app do Mac tem essa forma —, e é a única composição testada que continua
// reconhecível a 32 px, que é onde o ícone vive de verdade (Dock, barra de
// menus, Finder). As tentativas com a bandeja e os ladrilhos viravam borrão
// naquele tamanho e se pareciam com meia dúzia de utilitários.

let saida = CommandLine.arguments[1]

let lado: CGFloat = 1024

func squircle(_ ctx: CGContext, _ q: CGRect, cores: [NSColor]) {
    let raio: CGFloat = 225
    let p = NSBezierPath(roundedRect: q, xRadius: raio, yRadius: raio)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 48,
                  color: NSColor.black.withAlphaComponent(0.38).cgColor)
    NSColor.black.setFill(); p.fill()
    ctx.restoreGState()
    p.addClip()
    NSGradient(colors: cores)!.draw(in: q, angle: -90)
    // luz no topo
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: q.midX, y: q.maxY + 60), radius: 0,
              toCenter: CGPoint(x: q.midX, y: q.maxY + 60), radius: 720, options: [])
}

/// Ladrilho de vidro com aro de luz.
func ladrilho(_ ctx: CGContext, _ r: CGRect, alfa: CGFloat) {
    let raio = r.width * 0.26
    let p = NSBezierPath(roundedRect: r, xRadius: raio, yRadius: raio)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -r.width * 0.08), blur: r.width * 0.22,
                  color: NSColor.black.withAlphaComponent(0.34).cgColor)
    NSGradient(colors: [NSColor.white.withAlphaComponent(alfa),
                        NSColor.white.withAlphaComponent(max(0.05, alfa - 0.30))])!
        .draw(in: p, angle: -90)
    ctx.restoreGState()
    let aro = NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2),
                           xRadius: raio - 2, yRadius: raio - 2)
    aro.lineWidth = 4
    NSColor.white.withAlphaComponent(min(0.75, alfa + 0.15)).setStroke()
    aro.stroke()
}

let img = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    let q = CGRect(x: 96, y: 96, width: 832, height: 832)
    let teal = [NSColor(calibratedRed: 0.26, green: 0.85, blue: 0.79, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.34, blue: 0.46, alpha: 1)]

        squircle(ctx, q, cores: teal)
        let centro = CGPoint(x: q.midX, y: q.midY)
        let rExterno: CGFloat = 280, rInterno: CGFloat = 138
        let anel = NSBezierPath()
        anel.appendOval(in: CGRect(x: centro.x - rExterno, y: centro.y - rExterno,
                                   width: rExterno * 2, height: rExterno * 2))
        anel.appendOval(in: CGRect(x: centro.x - rInterno, y: centro.y - rInterno,
                                   width: rInterno * 2, height: rInterno * 2))
        anel.windingRule = .evenOdd
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 34,
                      color: NSColor.black.withAlphaComponent(0.32).cgColor)
        NSColor.white.withAlphaComponent(0.30).setFill()
        anel.fill()
        ctx.restoreGState()
        anel.lineWidth = 5
        NSColor.white.withAlphaComponent(0.5).setStroke(); anel.stroke()
        // seis ladrilhos em volta, o do topo ampliado (o apontado)
        let raioItens = (rExterno + rInterno) / 2
        for i in 0..<4 {
            let ang = -Double.pi / 2 + Double(i) * (2 * Double.pi / 4)
            let apontado = i == 0
            let t: CGFloat = apontado ? 232 : 150
            let cx = centro.x + CGFloat(cos(ang)) * raioItens
            let cy = centro.y - CGFloat(sin(ang)) * raioItens
            ladrilho(ctx, CGRect(x: cx - t/2, y: cy - t/2, width: t, height: t),
                     alfa: apontado ? 1.0 : 0.5)
        }

    return true
}

if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: saida))
    print("gravado: \(saida)")
}
