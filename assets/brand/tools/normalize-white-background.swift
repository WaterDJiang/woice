import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("usage: normalize-white-background.swift <input.png> <output.png>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL
guard let source = CGImageSourceCreateWithURL(inputURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("unable to read input PNG\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: &pixels,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      ) else {
    fputs("unable to create RGB bitmap context\n", stderr)
    exit(1)
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * bytesPerPixel }
func isBackgroundLike(_ offset: Int) -> Bool {
    let r = Int(pixels[offset])
    let g = Int(pixels[offset + 1])
    let b = Int(pixels[offset + 2])
    let spread = max(r, g, b) - min(r, g, b)
    return (min(r, g, b) >= 240 && spread <= 8) || (max(r, g, b) <= 8 && spread <= 8)
}

var visited = [Bool](repeating: false, count: width * height)
var queue: [(Int, Int)] = []
func enqueue(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let cell = y * width + x
    guard !visited[cell], isBackgroundLike(index(x, y)) else { return }
    visited[cell] = true
    queue.append((x, y))
}
for x in 0..<width {
    enqueue(x, 0)
    enqueue(x, height - 1)
}
for y in 0..<height {
    enqueue(0, y)
    enqueue(width - 1, y)
}

var cursor = 0
while cursor < queue.count {
    let (x, y) = queue[cursor]
    cursor += 1
    let offset = index(x, y)
    pixels[offset] = 255
    pixels[offset + 1] = 255
    pixels[offset + 2] = 255
    enqueue(x - 1, y)
    enqueue(x + 1, y)
    enqueue(x, y - 1)
    enqueue(x, y + 1)
}

guard let outputImage = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL, "public.png" as CFString, 1, nil) else {
    fputs("unable to write output PNG\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("unable to finalize output PNG\n", stderr)
    exit(1)
}
print("normalized", queue.count, "background pixels to pure white")
