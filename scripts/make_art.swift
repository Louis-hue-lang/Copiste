// Génère les visuels d'installation à partir de l'icône.
// Usage : swift scripts/make_art.swift <icon-1024.png> <dossier de sortie>
//   - installer-background.png : fond de l'installeur .pkg (logo en bas à gauche)
//   - dmg-background.png / dmg-background@2x.png : fenêtre du .dmg (660×440)
import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let outDir = URL(fileURLWithPath: args[2])

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(width: Int, height: Int, scale: CGFloat, to name: String, draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(width) * scale),
                               pixelsHigh: Int(CGFloat(height) * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height) // points → 144 dpi en @2x
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print(name)
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color c: NSColor,
          at point: NSPoint, center: Bool = false, width: CGFloat = 0) {
    let para = NSMutableParagraphStyle()
    para.alignment = center ? .center : .left
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: c,
        .paragraphStyle: para,
    ]
    let s = NSAttributedString(string: string, attributes: attrs)
    if center {
        s.draw(in: NSRect(x: point.x - width / 2, y: point.y, width: width, height: size * 1.6))
    } else {
        s.draw(at: point)
    }
}

// MARK: Fond de l'installeur .pkg

render(width: 620, height: 418, scale: 2, to: "installer-background.png") {
    icon.draw(in: NSRect(x: 18, y: 14, width: 150, height: 150), from: .zero, operation: .sourceOver, fraction: 0.9)
}

// MARK: Fond du .dmg (coordonnées : origine en bas à gauche, fenêtre 660×440)

func dmg() {
    let W: CGFloat = 660, H: CGFloat = 440
    NSGradient(starting: color(0xFBFAFF), ending: color(0xE9E7FD))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    text("Installer Copiste", size: 26, weight: .bold, color: color(0x2E2494),
         at: NSPoint(x: W / 2, y: H - 62), center: true, width: W)
    text("Glissez l'icône de Copiste sur le dossier Applications", size: 14, weight: .regular,
         color: color(0x55557A), at: NSPoint(x: W / 2, y: H - 88), center: true, width: W)

    // Flèche entre l'app (x 165) et Applications (x 495), à hauteur des icônes (y 190 depuis le haut).
    let y = H - 190
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 250, y: y))
    arrow.curve(to: NSPoint(x: 405, y: y), controlPoint1: NSPoint(x: 300, y: y + 34),
                controlPoint2: NSPoint(x: 355, y: y + 34))
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 11], count: 2, phase: 0)
    color(0x5B52EE).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 392, y: y + 15))
    head.line(to: NSPoint(x: 412, y: y - 2))
    head.line(to: NSPoint(x: 389, y: y - 9))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Bandeau des étapes.
    let band = NSBezierPath(roundedRect: NSRect(x: 24, y: 20, width: W - 48, height: 128), xRadius: 14, yRadius: 14)
    color(0xFFFFFF, 0.75).setFill()
    band.fill()
    color(0x5B52EE, 0.18).setStroke()
    band.lineWidth = 1
    band.stroke()

    let steps = [
        "Glissez Copiste dans Applications",
        "Ouvrez-le depuis Applications (voir le guide si macOS bloque)",
        "Autorisez « Contrôle de l'appareil », puis faites ⌥ + clic droit",
    ]
    for (i, step) in steps.enumerated() {
        let rowY = CGFloat(112 - i * 34)
        let bubble = NSBezierPath(ovalIn: NSRect(x: 44, y: rowY - 2, width: 22, height: 22))
        color(0x5B52EE).setFill()
        bubble.fill()
        text("\(i + 1)", size: 13, weight: .bold, color: .white, at: NSPoint(x: 55, y: rowY - 1), center: true, width: 22)
        text(step, size: 13, weight: .medium, color: color(0x2B2B45), at: NSPoint(x: 78, y: rowY))
    }
}

render(width: 660, height: 440, scale: 1, to: "dmg-background.png", draw: dmg)
render(width: 660, height: 440, scale: 2, to: "dmg-background@2x.png", draw: dmg)
