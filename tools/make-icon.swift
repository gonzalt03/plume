// Génère l'icône de Plume : swift tools/make-icon.swift <dossier-sortie>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"

// Plume dessinée dans un espace 1024 x 1024 (origine en bas à gauche).
func vanePath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 360, y: 300))
    p.curve(to: NSPoint(x: 790, y: 850), controlPoint1: NSPoint(x: 250, y: 560), controlPoint2: NSPoint(x: 470, y: 800))
    p.curve(to: NSPoint(x: 360, y: 300), controlPoint1: NSPoint(x: 820, y: 620), controlPoint2: NSPoint(x: 640, y: 360))
    p.close()
    return p
}

func shaftPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 250, y: 170))
    p.curve(to: NSPoint(x: 760, y: 810), controlPoint1: NSPoint(x: 420, y: 400), controlPoint2: NSPoint(x: 600, y: 620))
    return p
}

// Encoches sur les bords de la plume.
func notches() -> [(NSPoint, NSPoint)] {
    [
        (NSPoint(x: 300, y: 520), NSPoint(x: 430, y: 470)),
        (NSPoint(x: 400, y: 690), NSPoint(x: 530, y: 610)),
        (NSPoint(x: 770, y: 560), NSPoint(x: 640, y: 560)),
    ]
}

func drawFeather(color: NSColor, cutColor: NSColor?) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    color.setFill()
    vanePath().fill()
    // Tige et encoches découpées dans la plume.
    ctx.setBlendMode(.clear)
    let cut = shaftPath(); cut.lineWidth = 20; cut.lineCapStyle = .round; cut.stroke()
    for (a, b) in notches() {
        let n = NSBezierPath(); n.move(to: a); n.line(to: b); n.lineWidth = 18; n.lineCapStyle = .round; n.stroke()
    }
    ctx.setBlendMode(.normal)
    // Bas de la tige (hors plume), plein.
    color.setStroke()
    let quill = NSBezierPath()
    quill.move(to: NSPoint(x: 250, y: 170))
    quill.curve(to: NSPoint(x: 372, y: 318), controlPoint1: NSPoint(x: 290, y: 225), controlPoint2: NSPoint(x: 330, y: 270))
    quill.lineWidth = 26; quill.lineCapStyle = .round; quill.stroke()
    ctx.endTransparencyLayer()
}

func sparkle(center c: NSPoint, radius r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let k = r * 0.22
    p.move(to: NSPoint(x: c.x, y: c.y + r))
    p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + k, y: c.y + k), controlPoint2: NSPoint(x: c.x + k, y: c.y + k))
    p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + k, y: c.y - k), controlPoint2: NSPoint(x: c.x + k, y: c.y - k))
    p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - k, y: c.y - k), controlPoint2: NSPoint(x: c.x - k, y: c.y - k))
    p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - k, y: c.y + k), controlPoint2: NSPoint(x: c.x - k, y: c.y + k))
    p.close()
    return p
}

func render(pixels: Int, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: s, y: s)
    draw(s)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func appIcon(pixels: Int) -> NSBitmapImageRep {
    render(pixels: pixels) { _ in
        let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 28; shadow.set()
        NSColor.black.setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.35, green: 0.24, blue: 0.93, alpha: 1),
            NSColor(srgbRed: 0.62, green: 0.30, blue: 0.85, alpha: 1),
            NSColor(srgbRed: 0.93, green: 0.50, blue: 0.40, alpha: 1),
        ])!
        gradient.draw(in: shape, angle: 50)
        NSGraphicsContext.saveGraphicsState()
        let fs = NSShadow(); fs.shadowColor = NSColor.black.withAlphaComponent(0.22)
        fs.shadowOffset = NSSize(width: 0, height: -10); fs.shadowBlurRadius = 20; fs.set()
        drawFeather(color: .white, cutColor: nil)
        NSColor.white.setFill()
        sparkle(center: NSPoint(x: 300, y: 740), radius: 78).fill()
        sparkle(center: NSPoint(x: 410, y: 830), radius: 36).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func menuBarIcon(pixels: Int) -> NSBitmapImageRep {
    render(pixels: pixels) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Recadre la plume (zone ~230..810) sur toute l'image.
        ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: 1.4, y: 1.4); ctx.translateBy(x: -497, y: -512)
        drawFeather(color: .black, cutColor: nil)
        NSColor.black.setFill()
        sparkle(center: NSPoint(x: 290, y: 760), radius: 95).fill()
    }
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconset = "\(out)/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    save(appIcon(pixels: size), "\(iconset)/icon_\(size)x\(size).png")
    save(appIcon(pixels: size * 2), "\(iconset)/icon_\(size)x\(size)@2x.png")
}
save(appIcon(pixels: 1024), "\(out)/AppIcon-preview.png")
save(menuBarIcon(pixels: 18), "\(out)/MenuBarIcon.png")
save(menuBarIcon(pixels: 36), "\(out)/MenuBarIcon@2x.png")
save(menuBarIcon(pixels: 256), "\(out)/MenuBarIcon-preview.png")
print("ok")
