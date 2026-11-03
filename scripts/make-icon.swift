import AppKit

// Shoji のアプリアイコン。後ろから光が差す障子の引き戸 2 枚を、すりガラスの質感で重ねる。
// 背景はライトモードで白、ダークモードで黒になる（Icon Composer 形式。build.sh が actool でコンパイルする）
// 使い方: swift scripts/make-icon.swift Resources
let root = URL(fileURLWithPath: CommandLine.arguments[1])

func render(size: Int, dark: Bool, foregroundOnly: Bool = false) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    // 背景：ライトは白、ダークは黒。わずかに縦のグラデーションを付ける
    let body = r(100, 100, 824, 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    let background = dark ? [color(0x26262B), color(0x0A0A0C)] : [color(0xFFFFFF), color(0xE9E9EE)]
    if !foregroundOnly { NSGradient(colors: background)!.draw(in: bodyPath, angle: -90) }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    // 障子の向こうから差す暖かい光
    NSGradient(colors: [color(0xFFB36B, dark ? 0.75 : 0.55), color(0xFF7A8A, 0.22), color(0xFF7A8A, 0)])!
        .draw(in: NSBezierPath(ovalIn: r(250, 220, 560, 560)), relativeCenterPosition: .zero)

    // 引き戸 2 枚。奥の 1 枚は少しずらして重ね、すりガラスのように透かす
    func panel(_ rect: NSRect, alpha: CGFloat, lattice: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 44 * s, yRadius: 44 * s)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.28 * alpha)
        sh.shadowBlurRadius = 30 * s
        sh.shadowOffset = NSSize(width: 0, height: -12 * s)
        sh.set()
        NSGradient(colors: [color(0xFFFBF5, alpha), color(0xFFE6CC, alpha)])!.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        // 組子：細い線で縦 1 本・横 3 本
        color(0x8A5A3C, lattice).setFill()
        let w: CGFloat = 9 * s
        NSBezierPath(rect: NSRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: rect.height)).fill()
        for i in 1...3 {
            let y = rect.minY + rect.height * CGFloat(i) / 4 - w / 2
            NSBezierPath(rect: NSRect(x: rect.minX, y: y, width: rect.width, height: w)).fill()
        }
        // 上側のつや
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.45 * alpha), NSColor.white.withAlphaComponent(0)])!
            .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        (dark ? NSColor.white.withAlphaComponent(0.7 * alpha) : color(0xC9A27E, 0.6)).setStroke()
        path.lineWidth = 4 * s
        path.stroke()
    }
    // 白い背景では紙が背景に溶けないよう、奥の戸を濃いめにして縁を付ける
    panel(r(440, 236, 330, 560), alpha: dark ? 0.42 : 0.7, lattice: dark ? 0.35 : 0.45)
    panel(r(256, 206, 330, 590), alpha: 0.96, lattice: 0.55)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Icon Composer 形式（macOS 26 以降）。背景色だけを外観ごとに切り替え、前景の障子は共通にする。
// この形式ならダークモードで背景が黒になり、システムの Liquid Glass の質感も付く
let iconBundle = root.appendingPathComponent("AppIcon.icon")
try? FileManager.default.removeItem(at: iconBundle)
try FileManager.default.createDirectory(at: iconBundle.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try render(size: 1024, dark: false, foregroundOnly: true).write(to: iconBundle.appendingPathComponent("Assets/shoji.png"))
try Data("""
{
  "fill-specializations" : [
    { "value" : { "solid" : "extended-gray:1.00000,1.00000" } },
    { "appearance" : "dark", "value" : { "solid" : "extended-gray:0.04000,1.00000" } }
  ],
  "groups" : [
    {
      "layers" : [ { "image-name" : "shoji.png", "name" : "shoji" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : "shared" }
}
""".utf8).write(to: iconBundle.appendingPathComponent("icon.json"))
