// Génère l'icône de Copiste (PNG 1024×1024) : un presse-papier et une plume de copiste.
// Usage : swift scripts/make_icon.swift sortie.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint, in path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 1. Fond : carré arrondi (grille d'icône macOS : 824 px centrés), dégradé indigo.
let base = CGRect(x: 100, y: 100, width: 824, height: 824)
let basePath = rounded(base, 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(basePath)
ctx.setFillColor(color(0x4B44E0))
ctx.fillPath()
ctx.restoreGState()
linear([color(0x7B78FF), color(0x4A3FD6), color(0x2E2494)],
       from: CGPoint(x: 300, y: 924), to: CGPoint(x: 724, y: 100), in: basePath)
// reflet doux en haut
linear([color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)],
       from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 600), in: basePath)

// 2. Carte en arrière-plan (l'historique), inclinée.
ctx.saveGState()
ctx.translateBy(x: 470, y: 530)
ctx.rotate(by: 9 * .pi / 180)
ctx.addPath(rounded(CGRect(x: -215, y: -270, width: 400, height: 500), 44))
ctx.setFillColor(color(0xFFFFFF, 0.28))
ctx.fillPath()
ctx.restoreGState()

// 3. Presse-papier principal.
let board = CGRect(x: 312, y: 200, width: 410, height: 520)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x140F50, 0.45))
ctx.addPath(rounded(board, 48))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()
linear([color(0xFFFFFF), color(0xECEBFF)], from: CGPoint(x: 512, y: 720), to: CGPoint(x: 512, y: 200),
       in: rounded(board, 48))

// Pince en haut.
let clip = CGRect(x: 422, y: 670, width: 190, height: 96)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x140F50, 0.35))
ctx.addPath(rounded(clip, 30))
ctx.setFillColor(color(0x2E2494))
ctx.fillPath()
ctx.restoreGState()
linear([color(0x5C55F0), color(0x2E2494)], from: CGPoint(x: 512, y: 766), to: CGPoint(x: 512, y: 670),
       in: rounded(clip, 30))
ctx.addPath(rounded(CGRect(x: 482, y: 728, width: 70, height: 22), 11))
ctx.setFillColor(color(0xFFFFFF, 0.9))
ctx.fillPath()

// Lignes de texte.
let lines: [(CGFloat, CGFloat)] = [(600, 300), (530, 250), (460, 280), (390, 170)]
for (y, width) in lines {
    ctx.addPath(rounded(CGRect(x: 368, y: y, width: width, height: 30), 15))
    ctx.setFillColor(color(0xBDB9F7))
    ctx.fillPath()
}

// 4. Plume de copiste (dorée), pointe posée sur la dernière ligne.
ctx.saveGState()
ctx.translateBy(x: 548, y: 396)
ctx.rotate(by: -40 * .pi / 180)
let nib = CGMutablePath()
nib.move(to: CGPoint(x: 0, y: 0))
nib.addQuadCurve(to: CGPoint(x: 70, y: 170), control: CGPoint(x: 62, y: 60))
nib.addLine(to: CGPoint(x: 70, y: 300))
nib.addLine(to: CGPoint(x: -70, y: 300))
nib.addLine(to: CGPoint(x: -70, y: 170))
nib.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -62, y: 60))
nib.closeSubpath()
ctx.setShadow(offset: CGSize(width: 6, height: -10), blur: 20, color: color(0x140F50, 0.5))
ctx.addPath(nib)
ctx.setFillColor(color(0xF5A623))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
linear([color(0xFFE08A), color(0xF7B731), color(0xE08E0B)],
       from: CGPoint(x: -70, y: 150), to: CGPoint(x: 70, y: 150), in: nib)
// bague de la plume
ctx.addPath(rounded(CGRect(x: -78, y: 250, width: 156, height: 50), 14))
ctx.setFillColor(color(0x2E2494))
ctx.fillPath()
// fente + trou
ctx.setStrokeColor(color(0x7A4A00))
ctx.setLineWidth(8)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 0, y: 14))
ctx.addLine(to: CGPoint(x: 0, y: 140))
ctx.strokePath()
ctx.addEllipse(in: CGRect(x: -17, y: 135, width: 34, height: 34))
ctx.setFillColor(color(0x7A4A00))
ctx.fillPath()
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icône : \(out)")
