import AppKit

// Renderiza a logo nova do Docka em 1024×1024.
// Uso: swift logo-nova.swift <saida.png> <variante A|B>

let saida = CommandLine.arguments[1]
let variante = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "A"

let lado: CGFloat = 1024
let img = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // ---- squircle do macOS: 824×824 centrado, com sombra de apoio
    let q = CGRect(x: 100, y: 100, width: 824, height: 824)
    let raio: CGFloat = 185
    let squircle = NSBezierPath(roundedRect: q, xRadius: raio, yRadius: raio)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    squircle.fill()
    ctx.restoreGState()

    // ---- fundo: gradiente profundo
    squircle.addClip()
    let cores: [NSColor]
    if variante == "B" {
        // noturno: o vidro do app sobre fundo escuro, com o teal de marca no fundo
        cores = [NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.28, alpha: 1),
                 NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.15, alpha: 1)]
    } else {
        // teal de marca, mais fundo e com mais alcance que o atual
        cores = [NSColor(calibratedRed: 0.24, green: 0.82, blue: 0.76, alpha: 1),
                 NSColor(calibratedRed: 0.02, green: 0.36, blue: 0.47, alpha: 1)]
    }
    NSGradient(colors: cores)!.draw(in: q, angle: -90)

    // luz radial no topo — a curvatura do vidro
    let luz = NSGradient(colors: [NSColor.white.withAlphaComponent(0.30),
                                  NSColor.white.withAlphaComponent(0.0)])!
    luz.draw(fromCenter: CGPoint(x: q.midX, y: q.maxY + 80), radius: 0,
             toCenter: CGPoint(x: q.midX, y: q.maxY + 80), radius: 700,
             options: [])

    // ---- a prateleira de vidro (a bandeja)
    let shelf = CGRect(x: q.minX + 92, y: q.minY + 266, width: q.width - 184, height: 84)
    let shelfPath = NSBezierPath(roundedRect: shelf, xRadius: 42, yRadius: 42)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26,
                  color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.92),
                        NSColor.white.withAlphaComponent(0.68)])!
        .draw(in: shelfPath, angle: -90)
    ctx.restoreGState()
    // fio especular no topo da prateleira
    let fio = NSBezierPath(roundedRect: CGRect(x: shelf.minX + 8, y: shelf.maxY - 6,
                                               width: shelf.width - 16, height: 3),
                           xRadius: 1.5, yRadius: 1.5)
    NSColor.white.setFill(); fio.fill()

    // ---- os tiles: vizinhos menores, o do meio AMPLIADO passando da prateleira
    func tile(_ r: CGRect, raio: CGFloat, brilho: CGFloat, sombra: CGFloat) {
        let p = NSBezierPath(roundedRect: r, xRadius: raio, yRadius: raio)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: sombra,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
        NSGradient(colors: [NSColor.white.withAlphaComponent(brilho),
                            NSColor.white.withAlphaComponent(brilho - 0.22)])!
            .draw(in: p, angle: -90)
        ctx.restoreGState()
        // aro de luz
        let aro = NSBezierPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5),
                               xRadius: raio - 1.5, yRadius: raio - 1.5)
        aro.lineWidth = 3
        NSColor.white.withAlphaComponent(0.55).setStroke()
        aro.stroke()
    }

    let base = shelf.maxY - 8          // os tiles assentam na prateleira
    // vizinhos: translúcidos, dentro da prateleira — a rampa da ampliação
    tile(CGRect(x: q.midX - 122 - 42 - 152, y: base, width: 152, height: 152),
         raio: 38, brilho: 0.55, sombra: 18)
    tile(CGRect(x: q.midX + 122 + 42, y: base, width: 152, height: 152),
         raio: 38, brilho: 0.55, sombra: 18)
    // o apontado: opaco, subindo acima dos demais — a assinatura do app
    tile(CGRect(x: q.midX - 122, y: base, width: 244, height: 244),
         raio: 58, brilho: 1.0, sombra: 34)

    // ---- a bolinha de execução, abaixo da prateleira
    let dot = NSBezierPath(ovalIn: CGRect(x: q.midX - 13, y: shelf.minY - 52,
                                          width: 26, height: 26))
    NSColor.white.withAlphaComponent(0.95).setFill()
    dot.fill()

    return true
}

// grava PNG
if let tiff = img.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: saida))
    print("gravado: \(saida)")
}
