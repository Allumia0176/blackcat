// Fabrique Resources/AppIcon.icns : le chat noir centré sur un fond gris,
// dans la forme des icônes macOS (grille 1024 : forme de 824, coins de 185).
// Lancé par scripts/make-icon.sh.
import AppKit

let gray = NSColor(hex: 0xd4d4d9)

func icon(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)  // on dessine toujours sur la grille de 1024
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let shape = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    gray.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Corps et tête au milieu de la forme ; la queue dépasse à droite.
    // Sur la grille du chat, le corps est centré sur x = 10, dans une image qui va de 3 à 22,3.
    let cat = MainActor.assumeIsolated { CatIcon.image(pupil: .zero, blinking: false, height: 540) }
    let bodyCenter = (10 - 3) / 19.3 * cat.size.width
    let origin = NSPoint(x: 512 - bodyCenter, y: 512 - cat.size.height / 2)
    cat.draw(in: NSRect(origin: origin, size: cat.size))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try! icon(points * scale).write(to: iconset.appendingPathComponent(name))
    }
}
