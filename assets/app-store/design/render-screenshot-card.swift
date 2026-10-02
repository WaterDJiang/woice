#!/usr/bin/swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 6 else {
    FileHandle.standardError.write(
        Data("用法：render-screenshot-card.swift <背景> <真实截图> <输出 PNG> <标题> <副标题>\n".utf8)
    )
    exit(64)
}

let backgroundURL = URL(fileURLWithPath: arguments[1])
let screenshotURL = URL(fileURLWithPath: arguments[2])
let outputURL = URL(fileURLWithPath: arguments[3])
let title = arguments[4]
let subtitle = arguments[5]

guard let background = NSImage(contentsOf: backgroundURL) else {
    fatalError("无法读取背景：\(backgroundURL.path)")
}
guard let screenshot = NSImage(contentsOf: screenshotURL) else {
    fatalError("无法读取真实截图：\(screenshotURL.path)")
}

let width = 1280
let height = 800
guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fatalError("无法创建 1280×800 RGBA 画布")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

func aspectFill(_ image: NSImage, in destination: NSRect) {
    let sourceSize = image.size
    let sourceRatio = sourceSize.width / sourceSize.height
    let destinationRatio = destination.width / destination.height
    var sourceRect = NSRect(origin: .zero, size: sourceSize)
    if sourceRatio > destinationRatio {
        let croppedWidth = sourceSize.height * destinationRatio
        sourceRect.origin.x = (sourceSize.width - croppedWidth) / 2
        sourceRect.size.width = croppedWidth
    } else {
        let croppedHeight = sourceSize.width / destinationRatio
        sourceRect.origin.y = (sourceSize.height - croppedHeight) / 2
        sourceRect.size.height = croppedHeight
    }
    image.draw(in: destination, from: sourceRect, operation: .copy, fraction: 1)
}

func aspectFit(_ sourceSize: NSSize, in destination: NSRect) -> NSRect {
    let scale = min(
        destination.width / sourceSize.width,
        destination.height / sourceSize.height)
    let fittedSize = NSSize(
        width: sourceSize.width * scale,
        height: sourceSize.height * scale)
    return NSRect(
        x: destination.midX - fittedSize.width / 2,
        y: destination.midY - fittedSize.height / 2,
        width: fittedSize.width,
        height: fittedSize.height)
}

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.14, alpha: 1).setFill()
canvas.fill()
aspectFill(background, in: canvas)

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 39, weight: .semibold),
    .foregroundColor: NSColor.white,
    .kern: -0.6,
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 19, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.82),
]

NSAttributedString(string: title, attributes: titleAttributes)
    .draw(at: NSPoint(x: 120, y: 737))
NSAttributedString(string: subtitle, attributes: subtitleAttributes)
    .draw(at: NSPoint(x: 122, y: 704))

let screenshotBounds = NSRect(x: 80, y: 24, width: 1120, height: 650)
let screenshotRect = aspectFit(screenshot.size, in: screenshotBounds)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -5)
shadow.set()

let rounded = NSBezierPath(roundedRect: screenshotRect, xRadius: 18, yRadius: 18)
NSGraphicsContext.saveGraphicsState()
rounded.addClip()
screenshot.draw(in: screenshotRect, from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.18).setStroke()
rounded.lineWidth = 1
rounded.stroke()

NSGraphicsContext.restoreGraphicsState()

let fileType: NSBitmapImageRep.FileType =
    ["jpg", "jpeg"].contains(outputURL.pathExtension.lowercased()) ? .jpeg : .png
let properties: [NSBitmapImageRep.PropertyKey: Any] =
    fileType == .jpeg ? [.compressionFactor: 1.0] : [:]
guard let encoded = bitmap.representation(using: fileType, properties: properties) else {
    fatalError("无法编码截图")
}
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true)
try encoded.write(to: outputURL, options: .atomic)
