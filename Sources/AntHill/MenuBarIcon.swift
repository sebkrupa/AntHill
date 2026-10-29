import AppKit

extension NSImage {
    /// The menu bar icon: the app icon's ant, from Resources/MenuBarIcon.svg.
    /// A template image, so the menu bar tints it for light, dark, and highlighted states.
    @MainActor static let menuBarIcon: NSImage = {
        let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "ant.fill", accessibilityDescription: nil)!
        image.size = NSSize(width: 18, height: 18) // grid: ok menu bar icon size
        image.isTemplate = true
        image.accessibilityDescription = "AntHill"
        return image
    }()
}
