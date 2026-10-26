import AppKit

// MARK: - App Icon Generator (macOS Squircle with CoreGraphics)

enum AppIconGenerator {
    /// Small icon for header, banners and check-in. Drawn once instead of on every SwiftUI render.
    /// Main-actor isolated: before the macOS 26 SDK, NSImage is not Sendable, so a plain static let fails to compile.
    @MainActor static let small = makeIcon(size: 64)

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Menu bar glyph: the app icon's clock ring, interval arc and "S", drawn as a template image so macOS
    /// tints it for light and dark menu bars. `due` cuts a dot into the ring's top right (a check-in is waiting).
    static func statusBarIcon(due: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.6

            // Faint full ring, bold half arc from 12 to 6 o'clock: the check-in interval
            let ring = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 1.2
            NSColor.black.withAlphaComponent(0.35).setStroke()
            ring.stroke()

            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -90, clockwise: true)
            arc.lineWidth = 1.8
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()

            // The "S": two stacked bowls meeting at the clock's center, as in the app icon
            let bowl: CGFloat = 2.15
            let s = NSBezierPath()
            s.appendArc(withCenter: CGPoint(x: 0, y: bowl), radius: bowl, startAngle: 35, endAngle: 270, clockwise: false)
            s.appendArc(withCenter: CGPoint(x: 0, y: -bowl), radius: bowl, startAngle: 90, endAngle: -145, clockwise: true)
            s.transform(using: AffineTransform(m11: 1.3, m12: 0, m21: 0, m22: 1, tX: center.x, tY: center.y))
            s.lineWidth = 1.7
            s.lineCapStyle = .round
            s.lineJoinStyle = .round
            s.stroke()

            if due {
                // Knock a gap into the ring, then the dot, so it reads as a badge at 18 pt
                let dotCenter = CGPoint(x: rect.maxX - 2.8, y: rect.maxY - 2.8)
                let gap = NSBezierPath(ovalIn: CGRect(x: dotCenter.x - 3.3, y: dotCenter.y - 3.3, width: 6.6, height: 6.6))
                NSGraphicsContext.current?.compositingOperation = .clear
                gap.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: CGRect(x: dotCenter.x - 2.3, y: dotCenter.y - 2.3, width: 4.6, height: 4.6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func makeIcon(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let context = NSGraphicsContext.current?.cgContext

        // macOS Squircle proportions: Inset 10%, cornerRadius = 22.5% of width
        let inset = size * 0.10
        let squircleRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let cornerRadius = squircleRect.width * 0.225

        // Outer drop shadow
        context?.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.022)
        shadow.shadowBlurRadius = size * 0.04
        shadow.set()

        let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.withAlphaComponent(0.05).setFill()
        squirclePath.fill()
        context?.restoreGState()

        // Vertical gradient fill (#318866 top -> #164431 bottom)
        context?.saveGState()
        squirclePath.addClip()
        let topGreen = NSColor(srgbRed: 0x31/255.0, green: 0x88/255.0, blue: 0x66/255.0, alpha: 1.0)
        let bottomGreen = NSColor(srgbRed: 0x16/255.0, green: 0x44/255.0, blue: 0x31/255.0, alpha: 1.0)
        let gradient = NSGradient(starting: bottomGreen, ending: topGreen)
        gradient?.draw(in: squircleRect, angle: 90)

        // Subtle radial glow in upper center
        if let cg = context {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [NSColor.white.withAlphaComponent(0.14).cgColor, NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray
            if let radial = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                let glowCenter = CGPoint(x: squircleRect.midX, y: squircleRect.midY + squircleRect.height * 0.18)
                cg.drawRadialGradient(radial, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: squircleRect.width * 0.65, options: [])
            }
        }

        // Subtle inner highlight stroke
        let innerRect = squircleRect.insetBy(dx: max(0.5, size * 0.003), dy: max(0.5, size * 0.003))
        let innerStroke = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius - 1.0, yRadius: cornerRadius - 1.0)
        NSColor.white.withAlphaComponent(0.24).setStroke()
        innerStroke.lineWidth = max(1.0, size * 0.006)
        innerStroke.stroke()

        // Combined "S + clock" design:
        // 1. Crisp Clock Dial Ring in the center
        let center = CGPoint(x: squircleRect.midX, y: squircleRect.midY)
        let dialRadius = squircleRect.width * 0.34

        // Subtle dark translucent backing inside the clock dial for depth
        let dialRect = CGRect(x: center.x - dialRadius, y: center.y - dialRadius, width: dialRadius * 2, height: dialRadius * 2)
        let dialBgPath = NSBezierPath(ovalIn: dialRect)
        NSColor.black.withAlphaComponent(0.14).setFill()
        dialBgPath.fill()

        // Clock outer ring with a 30-minute active progress arc highlight
        let ringWidth = max(1.5, size * 0.022)
        let baseRing = NSBezierPath(ovalIn: dialRect)
        NSColor.white.withAlphaComponent(0.26).setStroke()
        baseRing.lineWidth = ringWidth
        baseRing.stroke()

        // Bright mint/white arc from 12 o'clock to 6 o'clock (representing the 30-min interval!)
        let arcPath = NSBezierPath()
        arcPath.appendArc(withCenter: center, radius: dialRadius, startAngle: 90, endAngle: -90, clockwise: true)
        arcPath.lineWidth = ringWidth
        arcPath.lineCapStyle = .round
        NSColor(srgbRed: 0.68, green: 0.96, blue: 0.82, alpha: 0.92).setStroke()
        arcPath.stroke()

        // 12 hour tick marks around the inside of the ring
        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi / 6.0)
            let isQuarter = (i % 3 == 0)
            let outerR = dialRadius - ringWidth * 0.95
            let innerR = outerR - (isQuarter ? size * 0.028 : size * 0.015)
            let p1 = CGPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR)
            let p2 = CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR)
            let tick = NSBezierPath()
            tick.move(to: p1)
            tick.line(to: p2)
            tick.lineWidth = isQuarter ? max(1.2, size * 0.011) : max(0.8, size * 0.006)
            tick.lineCapStyle = .round
            NSColor.white.withAlphaComponent(isQuarter ? 0.85 : 0.42).setStroke()
            tick.stroke()
        }

        // 2. Bold "S" monogram in the clock center: two stacked bowls whose meeting point is the clock pivot
        let bowlRadius = dialRadius * 0.22
        let sPath = NSBezierPath()
        // Upper bowl: from the top-right terminal counterclockwise over the top down to the center
        sPath.appendArc(withCenter: CGPoint(x: 0, y: bowlRadius), radius: bowlRadius, startAngle: 35, endAngle: 270, clockwise: false)
        // Lower bowl: from the center clockwise over the bottom up to the bottom-left terminal
        sPath.appendArc(withCenter: CGPoint(x: 0, y: -bowlRadius), radius: bowlRadius, startAngle: 90, endAngle: -145, clockwise: true)
        // Widen the bowls horizontally to fill the dial, then move the S onto the clock center
        sPath.transform(using: AffineTransform(m11: 1.45, m12: 0, m21: 0, m22: 1, tX: center.x, tY: center.y))
        sPath.lineWidth = max(2.0, size * 0.056)
        sPath.lineCapStyle = .round
        sPath.lineJoinStyle = .round

        // Subtle shadow behind the S
        context?.saveGState()
        let sShadow = NSShadow()
        sShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        sShadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
        sShadow.shadowBlurRadius = size * 0.02
        sShadow.set()
        NSColor.white.setStroke()
        sPath.stroke()
        context?.restoreGState()

        // Center watch pivot dot where the two bowls of the S meet (unifying S and Clock!)
        let pivotOuter = max(2.5, size * 0.036)
        let pivotRect = CGRect(x: center.x - pivotOuter, y: center.y - pivotOuter, width: pivotOuter * 2, height: pivotOuter * 2)
        let pivotPath = NSBezierPath(ovalIn: pivotRect)
        topGreen.setFill()
        pivotPath.fill()
        NSColor.white.setStroke()
        pivotPath.lineWidth = max(1.2, size * 0.014)
        pivotPath.stroke()

        context?.restoreGState()

        image.unlockFocus()
        return image
    }

    static func generateIconSet(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for (filename, ptSize) in sizes {
            guard let png = pngData(makeIcon(size: ptSize)) else {
                throw SchichtaError("Konnte PNG für \(filename) nicht erzeugen", en: "Could not create PNG for \(filename)")
            }
            try png.write(to: directory.appendingPathComponent(filename))
        }
    }
}
