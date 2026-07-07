// Gera a logo do Docka (arte original, desenhada por código).
// Uso: swift scripts/make_logo.swift
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// fundo: quadrado arredondado com gradiente turquesa
let corner = size * 0.225
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: corner, yRadius: corner)
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.88, blue: 0.80, alpha: 1),   // turquesa claro
    NSColor(calibratedRed: 0.02, green: 0.47, blue: 0.52, alpha: 1),   // turquesa profundo
])!.draw(in: bgPath, angle: -70)

// brilho suave no topo (luz de vidro)
let glow = NSBezierPath(roundedRect: NSRect(x: size*0.06, y: size*0.52,
                                            width: size*0.88, height: size*0.42),
                        xRadius: size*0.2, yRadius: size*0.2)
NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.22),
    NSColor(calibratedWhite: 1, alpha: 0.0),
])!.draw(in: glow, angle: -90)

// sombra projetada dos elementos
func withShadow(_ blur: CGFloat, _ alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.current!.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowBlurRadius = blur
    sh.shadowOffset = NSSize(width: 0, height: -size*0.012)
    sh.shadowColor = NSColor.black.withAlphaComponent(alpha)
    sh.set()
    draw()
    NSGraphicsContext.current!.restoreGraphicsState()
}

// prateleira de vidro (a "bandeja")
let shelfH = size * 0.075
let shelfRect = NSRect(x: size*0.14, y: size*0.20, width: size*0.72, height: shelfH)
withShadow(size*0.03, 0.35) {
    NSColor(calibratedWhite: 1, alpha: 0.92)
        .setFill()
    NSBezierPath(roundedRect: shelfRect, xRadius: shelfH/2, yRadius: shelfH/2).fill()
}

// três "apps" sobre a prateleira — o do meio ampliado (motivo da magnificação)
let baseY = shelfRect.maxY + size*0.02
func appSquare(cx: CGFloat, side: CGFloat, alpha: CGFloat) {
    let r = NSRect(x: cx - side/2, y: baseY, width: side, height: side)
    withShadow(size*0.025, 0.30) {
        NSColor(calibratedWhite: 1, alpha: alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: side*0.24, yRadius: side*0.24).fill()
    }
}
appSquare(cx: size*0.285, side: size*0.155, alpha: 0.62)
appSquare(cx: size*0.500, side: size*0.240, alpha: 0.97)   // magnificado
appSquare(cx: size*0.715, side: size*0.155, alpha: 0.62)

// bolinha de "app aberto" sob o ícone central
NSColor(calibratedWhite: 1, alpha: 0.9).setFill()
let dotR = size * 0.016
NSBezierPath(ovalIn: NSRect(x: size*0.5 - dotR, y: shelfRect.minY - size*0.045,
                            width: dotR*2, height: dotR*2)).fill()

img.unlockFocus()

// salva PNG (1024 + 256 para o README)
func save(_ image: NSImage, px: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
try? fm.createDirectory(atPath: "Sources/Docka/Assets", withIntermediateDirectories: true)
save(img, px: 1024, to: "Sources/Docka/Assets/logo.png")
save(img, px: 256, to: "Sources/Docka/Assets/logo-256.png")
print("logo gerada em Sources/Docka/Assets/")
