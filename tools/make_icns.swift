// Draws Icon/AppIcon.icon's SVG layers on its background gradient and writes
// Resources/AppIcon.icns with iconutil. build.sh uses it when actool (Xcode) is missing.
// shortcut: flat icon, no Liquid Glass, dark or tinted looks; tools/make_icon.sh replaces it once Xcode is installed.
// Usage: swift tools/make_icns.swift [preview.png]
import AppKit

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = repo.appending(path: "Icon/AppIcon.icon/Assets")
let layers = ["back.svg", "front.svg"].map { name -> NSImage in
    guard let image = NSImage(contentsOf: assets.appending(path: name)) else { fatalError("cannot read \(name)") }
    return image
}

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    // Apple's macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
    let box = NSRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
    let shape = NSBezierPath(roundedRect: box, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.shadowBlurRadius = 20 * scale
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    shape.addClip()
    NSGradient(starting: NSColor(srgbRed: 0.55, green: 0.80, blue: 0.97, alpha: 1),
               ending: NSColor(srgbRed: 0.20, green: 0.50, blue: 0.84, alpha: 1))!.draw(in: box, angle: -90)
    for layer in layers { layer.draw(in: box) }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
if CommandLine.arguments.count > 1 { try render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
try FileManager.default.createDirectory(at: repo.appending(path: "Resources"), withIntermediateDirectories: true)
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", repo.appending(path: "Resources/AppIcon.icns").path]
try tool.run()
tool.waitUntilExit()
guard tool.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote Resources/AppIcon.icns")
