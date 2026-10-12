import AppKit

/// MaKeep's icons: a yellow note with a folded bottom-right corner and a white checkmark or
/// checklist. Drawn in code so the menu bar glyph and the app icon (rendered into
/// AppIcon.icns at build time via `--render-iconset`) share one design and stay sharp.
enum MaKeepIcon {
    static let menuBar: NSImage = {
        let glyph = image(size: NSSize(width: 18, height: 18), draw: drawMenuBarGlyph)
        glyph.isTemplate = false  // Keep the colors instead of tinting to the menu bar style.
        glyph.accessibilityDescription = "MaKeep"
        return glyph
    }()

    nonisolated static func appIcon(size: NSSize) -> NSImage {
        image(size: size) { rect in drawAppIcon(in: rect, detailed: rect.width > 64) }
    }

    /// Writes the PNG sizes `iconutil -c icns` expects into `directory` (an .iconset folder).
    nonisolated static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                appIcon(size: rect.size).draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()

                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try rep.representation(using: .png, properties: [:])!.write(to: directory.appending(path: name))
            }
        }
    }

    // MARK: Drawing (y-down coordinates)

    nonisolated private static func image(size: NSSize, draw: @escaping @Sendable (NSRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            draw(rect)
            return true
        }
    }

    nonisolated private static let paperTop = NSColor(srgbRed: 1.000, green: 0.835, blue: 0.310, alpha: 1)  // #FFD54F
    nonisolated private static let paperBottom = NSColor(srgbRed: 0.984, green: 0.737, blue: 0.016, alpha: 1)  // #FBBC04
    nonisolated private static let flapLight = NSColor(srgbRed: 0.965, green: 0.639, blue: 0.000, alpha: 1)  // #F6A300
    nonisolated private static let flapDark = NSColor(srgbRed: 0.894, green: 0.533, blue: 0.000, alpha: 1)  // #E48800

    /// 24×24 design grid, scaled to `rect`.
    nonisolated private static func drawMenuBarGlyph(in rect: NSRect) {
        scale(to: rect, grid: 24)
        let note = NSRect(x: 3, y: 3, width: 18, height: 18)
        drawNote(note, radius: 4, fold: 6, shadow: nil)
        NSColor.white.setStroke()
        strokeCheck([NSPoint(x: 7.4, y: 11.6), NSPoint(x: 10.4, y: 14.6), NSPoint(x: 16.4, y: 8.4)], width: 2.6)
    }

    /// 1024×1024 design grid on Apple's icon template (824pt tile inset by 100).
    nonisolated private static func drawAppIcon(in rect: NSRect, detailed: Bool) {
        scale(to: rect, grid: 1024)
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        drawNote(tile, radius: 185, fold: 250, shadow: shadow)

        NSColor.white.setStroke()
        NSColor.white.setFill()
        if detailed {
            // Two checklist rows: a checked box and an empty one, each with a text line.
            let checked = NSBezierPath(roundedRect: NSRect(x: 250, y: 290, width: 160, height: 160), xRadius: 36, yRadius: 36)
            checked.fill()
            let empty = NSBezierPath(roundedRect: NSRect(x: 268, y: 528, width: 124, height: 124), xRadius: 26, yRadius: 26)
            empty.lineWidth = 30
            empty.stroke()
            NSBezierPath(roundedRect: NSRect(x: 470, y: 340, width: 300, height: 60), xRadius: 30, yRadius: 30).fill()
            NSBezierPath(roundedRect: NSRect(x: 470, y: 560, width: 210, height: 60), xRadius: 30, yRadius: 30).fill()
            paperBottom.setStroke()
            strokeCheck([NSPoint(x: 287, y: 372), NSPoint(x: 318, y: 403), NSPoint(x: 375, y: 340)], width: 30)
        } else {
            // Small sizes: the single checkmark reads better than the list.
            strokeCheck([NSPoint(x: 300, y: 500), NSPoint(x: 435, y: 635), NSPoint(x: 720, y: 345)], width: 110)
        }
    }

    /// A note with rounded corners except the folded bottom-right one.
    nonisolated private static func drawNote(_ r: NSRect, radius: CGFloat, fold: CGFloat, shadow: NSShadow?) {
        let paper = NSBezierPath()
        paper.move(to: NSPoint(x: r.minX + radius, y: r.minY))
        paper.appendArc(from: NSPoint(x: r.maxX, y: r.minY), to: NSPoint(x: r.maxX, y: r.maxY), radius: radius)
        paper.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
        paper.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
        paper.appendArc(from: NSPoint(x: r.minX, y: r.maxY), to: NSPoint(x: r.minX, y: r.minY), radius: radius)
        paper.appendArc(from: NSPoint(x: r.minX, y: r.minY), to: NSPoint(x: r.maxX, y: r.minY), radius: radius)
        paper.close()

        if let shadow {
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            paperBottom.setFill()
            paper.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGradient(starting: paperTop, ending: paperBottom)?.draw(in: paper, angle: 90)

        // The folded-over corner: the cut-off triangle mirrored across the fold line.
        let inner = fold * 0.12
        let flap = NSBezierPath()
        flap.move(to: NSPoint(x: r.maxX, y: r.maxY - fold))
        flap.appendArc(from: NSPoint(x: r.maxX - fold, y: r.maxY - fold), to: NSPoint(x: r.maxX - fold, y: r.maxY), radius: inner)
        flap.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
        flap.close()
        NSGradient(starting: flapLight, ending: flapDark)?.draw(in: flap, angle: 45)
    }

    nonisolated private static func strokeCheck(_ points: [NSPoint], width: CGFloat) {
        let check = NSBezierPath()
        check.move(to: points[0])
        points.dropFirst().forEach { check.line(to: $0) }
        check.lineWidth = width
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
    }

    nonisolated private static func scale(to rect: NSRect, grid: CGFloat) {
        let factor = min(rect.width, rect.height) / grid
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX - grid / 2 * factor, yBy: rect.midY - grid / 2 * factor)
        transform.scale(by: factor)
        transform.concat()
    }
}
