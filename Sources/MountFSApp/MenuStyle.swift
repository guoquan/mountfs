import AppKit

func menuSymbol(_ name: String, description: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: description)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
}

// Native menu items below this header retain macOS keyboard navigation and
// accessibility. Semantic colors follow the system's light/dark appearance.
final class MenuHeaderView: NSView {
    init(status: String, version: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 310, height: 70))
        let icon = NSImageView(frame: NSRect(x: 16, y: 22, width: 34, height: 34))
        icon.image = brandImage(size: 34)
        addSubview(icon)
        let name = NSTextField(labelWithString: "mouNTFS")
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.frame = NSRect(x: 60, y: 37, width: 155, height: 22)
        addSubview(name)
        let release = NSTextField(labelWithString: version)
        release.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        release.textColor = .secondaryLabelColor
        release.alignment = .right
        release.frame = NSRect(x: 222, y: 39, width: 70, height: 18)
        addSubview(release)
        let subtitle = NSTextField(labelWithString: status)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.frame = NSRect(x: 60, y: 17, width: 232, height: 18)
        subtitle.toolTip = status
        addSubview(subtitle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
