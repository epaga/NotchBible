import AppKit

enum AnnotationColors {
    static let names = ["Yellow", "Gold", "Coral", "Rose", "Pink", "Lavender", "Blue", "Cyan", "Mint", "Green"]
    static let values: [NSColor] = [
        NSColor(red: 0.98, green: 0.88, blue: 0.36, alpha: 1),
        NSColor(red: 1.00, green: 0.69, blue: 0.29, alpha: 1),
        NSColor(red: 1.00, green: 0.49, blue: 0.40, alpha: 1),
        NSColor(red: 0.98, green: 0.42, blue: 0.55, alpha: 1),
        NSColor(red: 0.96, green: 0.57, blue: 0.80, alpha: 1),
        NSColor(red: 0.72, green: 0.61, blue: 0.98, alpha: 1),
        NSColor(red: 0.48, green: 0.70, blue: 1.00, alpha: 1),
        NSColor(red: 0.36, green: 0.85, blue: 0.94, alpha: 1),
        NSColor(red: 0.42, green: 0.88, blue: 0.71, alpha: 1),
        NSColor(red: 0.64, green: 0.84, blue: 0.40, alpha: 1)
    ]
    static func color(_ index: Int) -> NSColor { values[values.indices.contains(index) ? index : 0] }
}

enum AnnotationDrawing {
    /// Each wrapped line gets its own fitted slice, including the short first
    /// and last lines. No shape crosses paragraph spacing or verse labels.
    static func draw(_ style: AnnotationStyle, in rect: NSRect, color: NSColor, flipped: Bool = true) {
        if style == .highlight {
            color.withAlphaComponent(0.27).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            return
        }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        let bottom = flipped ? rect.maxY : rect.minY
        let top = flipped ? rect.minY : rect.maxY
        switch style {
        case .underline, .dottedUnderline:
            path.move(to: NSPoint(x: rect.minX, y: bottom))
            path.line(to: NSPoint(x: rect.maxX, y: bottom))
            if style == .dottedUnderline { path.setLineDash([0.1, 3.4], count: 2, phase: 0) }
        case .box: path.appendRoundedRect(rect, xRadius: 2, yRadius: 2)
        case .oval: path.appendOval(in: rect)
        case .bottomBox, .topBox:
            let edge = style == .bottomBox ? bottom : top
            path.move(to: NSPoint(x: rect.minX, y: rect.midY))
            path.line(to: NSPoint(x: rect.minX, y: edge))
            path.line(to: NSPoint(x: rect.maxX, y: edge))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        case .highlight: break
        }
        path.stroke()
    }

    static func icon(_ style: AnnotationStyle, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 28), flipped: true) { _ in
            let rect = NSRect(x: 5, y: 3, width: 22, height: 21)
            if style == .highlight { draw(style, in: rect, color: color) }
            ("A" as NSString).draw(at: NSPoint(x: 9, y: 1), withAttributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white
            ])
            if style != .highlight { draw(style, in: rect, color: color) }
            return true
        }
    }
}

struct RenderedAnnotation {
    let note: VerseNote
    let range: NSRange
}

final class AnnotatedLayoutManager: NSLayoutManager {
    var annotations: [RenderedAnnotation] = []

    func slices(for annotation: RenderedAnnotation, in container: NSTextContainer) -> [NSRect] {
        let glyphs = glyphRange(forCharacterRange: annotation.range, actualCharacterRange: nil)
        var rects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
            let selected = NSIntersectionRange(glyphs, lineGlyphs)
            guard selected.length > 0 else { return }
            let ink = self.boundingRect(forGlyphRange: selected, in: container)
            guard ink.width > 0 else { return }
            let character = self.characterIndexForGlyph(at: selected.location)
            let font = self.textStorage?.attribute(.font, at: character, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: 20)
            let baseline = line.minY + self.location(forGlyphAt: selected.location).y
            let top = max(line.minY + 1, baseline - font.ascender - 1)
            let bottom = min(line.maxY - 1, baseline - font.descender + 1)
            rects.append(NSRect(x: ink.minX - 2, y: top, width: ink.width + 4, height: max(1, bottom - top)))
        }
        return rects
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawAnnotations(in: glyphsToShow, at: origin, background: true)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawAnnotations(in: glyphsToShow, at: origin, background: false)
    }

    private func drawAnnotations(in glyphs: NSRange, at origin: NSPoint, background: Bool) {
        guard let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        for annotation in annotations where (annotation.note.style == .highlight) == background {
            guard NSIntersectionRange(characters, annotation.range).length > 0 else { continue }
            for rect in slices(for: annotation, in: container) {
                AnnotationDrawing.draw(annotation.note.style, in: rect.offsetBy(dx: origin.x, dy: origin.y),
                                       color: AnnotationColors.color(annotation.note.color))
            }
        }
    }
}
