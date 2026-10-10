import AppKit

// Reuses the website's italic m + upright N mark and its blue-to-charcoal colors.
// Template rendering lets macOS adapt the menu bar mark to light/dark appearance.
func brandImage(size: CGFloat, template: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let font = NSFont(name: "Arial-BoldMT", size: size * 0.6) ?? NSFont.boldSystemFont(ofSize: size * 0.6)
    let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    let mark = NSMutableAttributedString(string: "m", attributes: [.font: italic, .foregroundColor: NSColor.black])
    mark.append(NSAttributedString(string: "N", attributes: [.font: font, .foregroundColor: NSColor.black]))
    let bounds = mark.size()
    mark.draw(at: NSPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2))
    if !template, let context = NSGraphicsContext.current {
        context.saveGraphicsState()
        context.compositingOperation = .sourceIn
        NSGradient(starting: NSColor(srgbRed: 107/255, green: 124/255, blue: 235/255, alpha: 1),
                   ending: NSColor(srgbRed: 36/255, green: 41/255, blue: 47/255, alpha: 1))?
            .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -45)
        context.restoreGraphicsState()
    }
    image.unlockFocus()
    image.isTemplate = template
    return image
}
