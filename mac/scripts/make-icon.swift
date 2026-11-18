// 產生 app 圖示：柿橘色圓角方塊上一隻張嘴的九官鳥（黑色的鳥、黃色的喙與肉垂），嘴邊有聲波。
// 用法：swift scripts/make-icon.swift Resources/VoiceStudio.icns [預覽.png]
import AppKit

let output = CommandLine.arguments[1]
let preview = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoiceStudio.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: (cx - rx) * s, y: (cy - ry) * s, width: 2 * rx * s, height: 2 * ry * s))
    }

    // macOS 圖示格線：內容方塊約占 80%，四周留透明邊
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: color(0xFF9A56), ending: color(0xDE4433))!.draw(in: shape, angle: -90)
    shape.addClip()   // 鳥的身體從底邊切出去

    // 身體與頭：同一種黑，疊起來是一隻側身的鳥
    let black = color(0x1B1A1F)
    black.setFill()
    oval(0.33, 0.17, 0.33, 0.27).fill()
    oval(0.385, 0.535, 0.185, 0.185).fill()
    // 脖子：把頭和身體之間的凹處補起來
    let neck = NSBezierPath()
    neck.move(to: p(0.21, 0.50))
    neck.curve(to: p(0.10, 0.25), controlPoint1: p(0.17, 0.42), controlPoint2: p(0.11, 0.34))
    neck.line(to: p(0.60, 0.25))
    neck.curve(to: p(0.555, 0.47), controlPoint1: p(0.60, 0.34), controlPoint2: p(0.59, 0.41))
    neck.close()
    neck.fill()

    // 喙：張開的上下兩片
    let beak = color(0xFFC83A)
    beak.setFill()
    let upper = NSBezierPath()
    upper.move(to: p(0.545, 0.625))
    upper.curve(to: p(0.725, 0.565), controlPoint1: p(0.62, 0.635), controlPoint2: p(0.69, 0.61))
    upper.line(to: p(0.555, 0.535))
    upper.close()
    upper.fill()
    let lower = NSBezierPath()
    lower.move(to: p(0.555, 0.52))
    lower.line(to: p(0.69, 0.475))
    lower.curve(to: p(0.535, 0.455), controlPoint1: p(0.64, 0.455), controlPoint2: p(0.58, 0.45))
    lower.close()
    color(0xF5A623).setFill()
    lower.fill()

    // 眼睛，和九官鳥後腦那塊黃色的肉垂
    NSColor.white.setFill()
    oval(0.445, 0.60, 0.034, 0.034).fill()
    black.setFill()
    oval(0.452, 0.60, 0.017, 0.017).fill()
    beak.setFill()
    let wattle = NSBezierPath()
    wattle.move(to: p(0.375, 0.585))
    wattle.curve(to: p(0.265, 0.50), controlPoint1: p(0.33, 0.585), controlPoint2: p(0.285, 0.55))
    wattle.curve(to: p(0.375, 0.545), controlPoint1: p(0.305, 0.525), controlPoint2: p(0.34, 0.54))
    wattle.close()
    wattle.fill()

    // 聲波：從嘴邊往右擴散，越遠越淡
    let center = p(0.665, 0.52)
    for (radius, alpha) in [(0.115, 1.0), (0.185, 0.72)] as [(CGFloat, CGFloat)] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius * s, startAngle: -34, endAngle: 34)
        arc.lineWidth = s * 0.042
        arc.lineCapStyle = .round
        NSColor.white.withAlphaComponent(alpha).setStroke()
        arc.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512),
                   ("512x512@2x", 1024)] {
    try! render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
if let preview {
    try! render(1024).write(to: URL(fileURLWithPath: preview))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "圖示：\(output)" : "iconutil 失敗")
