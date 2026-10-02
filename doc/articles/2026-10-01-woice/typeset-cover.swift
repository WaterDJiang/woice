import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let root = CommandLine.arguments[1]
let fontPath = "/Users/water/.wattter-skills/skills/wtt-nine-comic-imagegen/assets/fonts/FontQuSmile-Regular.ttf"
let title = "一段录音的成本，不只是转写费"
let lines = ["一段录音的成本，", "不只是转写费"]
precondition(lines.joined() == title)
guard let provider = CGDataProvider(filename: fontPath), let graphicFont = CGFont(provider) else { fatalError("Cannot load exact TTF") }
let probe = CTFontCreateWithGraphicsFont(graphicFont, 100, nil, nil)
let units = Array(title.utf16)
var glyphs = [CGGlyph](repeating: 0, count: units.count)
precondition(CTFontGetGlyphsForCharacters(probe, units, &glyphs, units.count), "Missing title glyphs")
func textLine(_ text: String, _ size: CGFloat) -> CTLine {
    let font = CTFontCreateWithGraphicsFont(graphicFont, size, nil, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.102, alpha: 1)
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}
let maxWidth: CGFloat = 714
var fontSize: CGFloat = 120
while lines.contains(where: { CTLineGetBoundsWithOptions(textLine($0, fontSize), [.useGlyphPathBounds]).width > maxWidth }) { fontSize -= 1 }
var layout: [String: Any] = ["title": title, "lines": lines, "font_path": fontPath, "font_postscript": CTFontCopyPostScriptName(probe), "font_size": fontSize, "glyph_check": "all title characters present", "master": [1920,1080], "wide_crop": [0,131,1920,817], "square_crop_from_wide": [551,0,817,817], "layout_id": "D-U1-adjusted-for-WeChat-crops", "title_box": [603,225,714,260], "scene_box": [633,583,653,249], "editor_crop_status": "not tested in WeChat editor"]
func save(_ cg: CGImage, _ path: String) {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath:path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot create PNG") }
    CGImageDestinationAddImage(dest,cg,nil)
    precondition(CGImageDestinationFinalize(dest), "Cannot finalize PNG")
}
var boundsRows: [[String:Any]] = []
for key in ["A","B","C","D"] {
    let basePath = root + "/cover-" + key + "-base.png"
    guard let src=CGImageSourceCreateWithURL(URL(fileURLWithPath:basePath) as CFURL,nil), let base=CGImageSourceCreateImageAtIndex(src,0,nil) else { fatalError("Cannot load base " + key) }
    guard let ctx=CGContext(data:nil,width:1920,height:1080,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot create context") }
    ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:1920,height:1080))
    ctx.interpolationQuality = .high
    ctx.draw(base,in:CGRect(x:288,y:122,width:1344,height:756))
    for (index,text) in lines.enumerated() {
        let line=textLine(text,fontSize)
        let bounds=CTLineGetBoundsWithOptions(line,[.useGlyphPathBounds])
        let top: CGFloat = CGFloat(index == 0 ? 248 : 377)
        let originX = 960 - bounds.width/2 - bounds.minX
        let baseline = 1080-top-bounds.maxY
        ctx.textPosition = CGPoint(x:originX,y:baseline)
        CTLineDraw(line,ctx)
        if key == "A" { boundsRows.append(["text":text,"x":originX+bounds.minX,"top":top,"width":bounds.width,"height":bounds.height]) }
    }
    guard let full=ctx.makeImage() else { fatalError("Cannot render title") }
    save(full,root+"/cover-"+key+".png")
    let wide=full.cropping(to:CGRect(x:0,y:131,width:1920,height:817))!
    save(wide,root+"/cover-"+key+"-wide.png")
    save(wide.cropping(to:CGRect(x:551,y:0,width:817,height:817))!,root+"/cover-"+key+"-square.png")
    print("cover-\(key): exact TTF, \(fontSize)pt, title complete")
}
layout["title_ink_bounds"] = boundsRows
let json=try JSONSerialization.data(withJSONObject:layout,options:[.prettyPrinted,.sortedKeys])
try json.write(to:URL(fileURLWithPath:root+"/cover-layout.json"))
