// Monta o demo.gif a partir dos frames capturados com screencapture.
// Uso: swift scripts/make_gif.swift <pasta-dos-frames> <saida.gif> [largura]
import AppKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("uso: swift make_gif.swift <pasta> <saida.gif> [largura]")
    exit(1)
}
let dir = args[1]
let out = URL(fileURLWithPath: args[2])
let targetW = args.count > 3 ? CGFloat(Double(args[3])!) : 780

let fm = FileManager.default
let frames = try! fm.contentsOfDirectory(atPath: dir)
    .filter { $0.hasPrefix("frame") && $0.hasSuffix(".png") }
    .sorted()
guard !frames.isEmpty else { print("nenhum frame em \(dir)"); exit(1) }

func scaled(_ img: NSImage, to width: CGFloat) -> CGImage {
    let ratio = width / img.size.width
    let size = NSSize(width: width, height: img.size.height * ratio)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString,
                                           frames.count, nil)!
// loop infinito
CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)

let frameProps = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.07]
] as CFDictionary

for f in frames {
    guard let img = NSImage(contentsOfFile: dir + "/" + f) else { continue }
    CGImageDestinationAddImage(dest, scaled(img, to: targetW), frameProps)
}
CGImageDestinationFinalize(dest)

let kb = (try! fm.attributesOfItem(atPath: out.path)[.size] as! Int) / 1024
print("\(out.path): \(frames.count) frames, \(kb) KB")
