import CoreGraphics
import ImageIO
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let exportRoot = root.appendingPathComponent("assets/brand/exports", isDirectory: true)
let iconsetRoot = exportRoot.appendingPathComponent("Woice.iconset", isDirectory: true)
let assetCatalogRoot = exportRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconsetRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetCatalogRoot, withIntermediateDirectories: true)

let ink = CGColor(red: 0x17 / 255.0, green: 0x20 / 255.0, blue: 0x33 / 255.0, alpha: 1)
let deepFold = CGColor(red: 0x0C / 255.0, green: 0x14 / 255.0, blue: 0x22 / 255.0, alpha: 1)
let cobalt = CGColor(red: 0x2D / 255.0, green: 0x63 / 255.0, blue: 0xD7 / 255.0, alpha: 1)

func drawWWaveform(in context: CGContext, size: CGFloat, background: Bool, monochrome: Bool = false) {
    let scale = size / 1024
    context.saveGState()
    context.scaleBy(x: scale, y: scale)

    if background {
        context.setFillColor(ink)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }

    let path = CGMutablePath()
    path.move(to: CGPoint(x: 110, y: 510))
    path.addCurve(to: CGPoint(x: 310, y: 704), control1: CGPoint(x: 184, y: 510), control2: CGPoint(x: 224, y: 704))
    path.addCurve(to: CGPoint(x: 512, y: 310), control1: CGPoint(x: 398, y: 704), control2: CGPoint(x: 446, y: 310))
    path.addCurve(to: CGPoint(x: 714, y: 704), control1: CGPoint(x: 578, y: 310), control2: CGPoint(x: 626, y: 704))
    path.addCurve(to: CGPoint(x: 914, y: 510), control1: CGPoint(x: 800, y: 704), control2: CGPoint(x: 840, y: 510))

    context.setLineCap(.round)
    context.setLineJoin(.round)
    if monochrome {
        context.setStrokeColor(ink)
        context.setLineWidth(146)
        context.addPath(path)
        context.strokePath()
    } else {
        context.setStrokeColor(deepFold)
        context.setLineWidth(190)
        context.addPath(path)
        context.strokePath()
        context.setStrokeColor(cobalt)
        context.setLineWidth(146)
        context.addPath(path)
        context.strokePath()
        context.setStrokeColor(ink)
        context.setLineWidth(24)
        context.addPath(path)
        context.strokePath()
    }
    context.restoreGState()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "WoiceBrandExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建 PNG 输出：\(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "WoiceBrandExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法写入 PNG：\(url.path)"])
    }
}

func render(size: Int, background: Bool, monochrome: Bool = false) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "WoiceBrandExport", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法创建位图上下文"])
    }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    drawWWaveform(in: context, size: CGFloat(size), background: background, monochrome: monochrome)
    guard let image = context.makeImage() else {
        throw NSError(domain: "WoiceBrandExport", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法生成图像"])
    }
    return image
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let icon = try render(size: size, background: true)
    let iconURL = exportRoot.appendingPathComponent("woice-app-icon-\(size).png")
    try writePNG(icon, to: iconURL)
}

let transparentMark = try render(size: 1024, background: false)
try writePNG(transparentMark, to: exportRoot.appendingPathComponent("woice-mark-transparent-1024.png"))

let monochromeMark = try render(size: 1024, background: false, monochrome: true)
try writePNG(monochromeMark, to: exportRoot.appendingPathComponent("woice-mark-monochrome-1024.png"))

let iconsetNames: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in iconsetNames {
    let source = exportRoot.appendingPathComponent("woice-app-icon-\(size).png")
    let iconsetDestination = iconsetRoot.appendingPathComponent(name)
    let assetCatalogDestination = assetCatalogRoot.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: iconsetDestination)
    try? FileManager.default.removeItem(at: assetCatalogDestination)
    try FileManager.default.copyItem(at: source, to: iconsetDestination)
    try FileManager.default.copyItem(at: source, to: assetCatalogDestination)
}

print("Woice brand assets rendered to \(exportRoot.path)")
