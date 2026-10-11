import AppKit

@main
struct IconGenerator {
    static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let image = brandImage(size: CGFloat(pixels))
                guard let tiff = image.tiffRepresentation,
                      NSBitmapImageRep(data: tiff) != nil else {
                    throw NSError(domain: "mouNTFS", code: 1)
                }
                // Normalize Retina-backed rendering to exact iconset dimensions.
                guard let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                    let context = NSGraphicsContext(bitmapImageRep: output) else {
                    throw NSError(domain: "mouNTFS", code: 2)
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)),
                           from: .zero, operation: .copy, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
                guard let png = output.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "mouNTFS", code: 3)
                }
                let suffix = scale == 2 ? "@2x" : ""
                try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }
}
