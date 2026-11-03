// 產生選單列圖示 icon.tiff（template：黑色字、系統自動配合深淺色）。用法：swift make_icon.swift <輸出路徑>
import Cocoa

func rep(_ px: Int) -> NSBitmapImageRep {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
    r.size = NSSize(width: 16, height: 16)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    let s = NSAttributedString(string: "倉", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium),
                                                          .foregroundColor: NSColor.black])
    let sz = s.size()
    s.draw(at: NSPoint(x: (16 - sz.width) / 2, y: (16 - sz.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return r
}
let img = NSImage(size: NSSize(width: 16, height: 16))
img.addRepresentation(rep(16))
img.addRepresentation(rep(32))
try! img.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
