// Génère le fond de la fenêtre du DMG : swift tools/make-dmg-background.swift <dossier-sortie>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let W: CGFloat = 660, H: CGFloat = 400

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Fond : dégradé très clair, teinte de l'icône.
    NSGradient(colors: [
        NSColor(srgbRed: 0.96, green: 0.95, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 1.0, green: 0.95, blue: 0.93, alpha: 1),
    ])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -30)

    let center = NSMutableParagraphStyle(); center.alignment = .center
    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.25, green: 0.18, blue: 0.55, alpha: 1),
        .paragraphStyle: center,
    ]
    ("Installer Plume" as NSString).draw(in: NSRect(x: 0, y: H - 70, width: W, height: 36), withAttributes: title)

    let sub: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor(white: 0.35, alpha: 1),
        .paragraphStyle: center,
    ]
    ("Glisse Plume dans le dossier Applications" as NSString)
        .draw(in: NSRect(x: 0, y: 58, width: W, height: 22), withAttributes: sub)

    // Flèche entre l'icône (x 170) et le dossier Applications (x 490), à hauteur des icônes.
    let y: CGFloat = H - 200
    let color = NSColor(srgbRed: 0.55, green: 0.35, blue: 0.85, alpha: 0.85)
    color.setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: y))
    shaft.curve(to: NSPoint(x: 378, y: y + 4), controlPoint1: NSPoint(x: 300, y: y + 26), controlPoint2: NSPoint(x: 354, y: y + 26))
    shaft.lineWidth = 5; shaft.lineCapStyle = .round
    let dash: [CGFloat] = [0.1, 12]
    shaft.setLineDash(dash, count: 2, phase: 0)
    shaft.stroke()
    color.setFill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 404, y: y - 2))
    head.line(to: NSPoint(x: 384, y: y + 12))
    head.line(to: NSPoint(x: 386, y: y - 12))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
save(render(scale: 1), "\(out)/dmg-background.png")
save(render(scale: 2), "\(out)/dmg-background@2x.png")
print("ok")
