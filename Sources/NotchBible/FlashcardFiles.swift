import AppKit
import UniformTypeIdentifiers

/// Save and open panels for flashcards. The lookup panel floats above normal
/// windows, so these panels are raised above it.
@MainActor
enum FlashcardFiles {
    private static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

    static func printPile(_ pile: FlashcardPile, model: FlashcardModel) {
        let cards = model.deck.cards(in: pile)
        guard !cards.isEmpty, let url = saveURL(name: "\(pile.name) Flashcards.pdf", type: .pdf) else { return }
        do {
            try FlashcardPDF.write(cards, to: url)
            NSWorkspace.shared.open(url)
        } catch { show(error) }
    }

    static func export(_ pile: FlashcardPile?, model: FlashcardModel) {
        let name = pile.map { "\($0.name) Flashcards" } ?? "NotchBible Flashcards"
        guard let url = saveURL(name: name + ".json", type: .json) else { return }
        do { try FlashcardStore.encoder.encode(model.exportSet(pile)).write(to: url, options: .atomic) }
        catch { show(error) }
    }

    static func importSet(model: FlashcardModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.level = panelLevel
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let set: FlashcardSet
        do { set = try FlashcardStore.decoder.decode(FlashcardSet.self, from: Data(contentsOf: url)) }
        catch {
            show(message: "This file isn't a NotchBible flashcard set.", detail: error.localizedDescription)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Import \(set.cards.count) \(set.cards.count == 1 ? "card" : "cards")?"
        alert.informativeText = "Merge adds cards you don't have yet. Replace discards your current \(model.deck.cards.count) cards and their progress."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = panelLevel
        switch alert.runModal() {
        case .alertFirstButtonReturn: model.merge(set)
        case .alertSecondButtonReturn: model.replace(with: set)
        default: break
        }
    }

    private static func saveURL(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.level = panelLevel
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func show(_ error: Error) {
        show(message: "Couldn't save the file.", detail: error.localizedDescription)
    }
    private static func show(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.window.level = panelLevel
        alert.runModal()
    }
}

/// One 5 × 3 inch index card per page: the reference, then the verse on the
/// following page, so duplex printing puts them back to back.
enum FlashcardPDF {
    static let pageSize = CGSize(width: 360, height: 216)

    static func write(_ cards: [Flashcard], to url: URL) throws {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for card in cards {
            page(context) {
                draw(card.reference, size: 26, weight: .semibold, centered: true)
                caption(card.translation)
            }
            page(context) {
                draw(card.text, size: 15, weight: .regular, centered: false, serif: true)
                caption("\(card.reference) · \(card.translation)")
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        context.closePDF()
    }

    private static func page(_ context: CGContext, _ body: () -> Void) {
        context.beginPDFPage(nil)
        body()
        context.endPDFPage()
    }

    private static let textArea = CGRect(x: 22, y: 32, width: pageSize.width - 44, height: pageSize.height - 54)

    /// Shrinks long verses until they fit on the card.
    private static func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, centered: Bool, serif: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .natural
        paragraph.lineBreakMode = .byWordWrapping
        var fontSize = size
        var string: NSAttributedString
        var bounds: CGRect
        repeat {
            var font = NSFont.systemFont(ofSize: fontSize, weight: weight)
            if serif, let descriptor = font.fontDescriptor.withDesign(.serif) { font = NSFont(descriptor: descriptor, size: fontSize) ?? font }
            string = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.black])
            bounds = string.boundingRect(with: textArea.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
            fontSize -= 0.5
        } while bounds.height > textArea.height && fontSize > 5
        let height = min(bounds.height, textArea.height)
        let rect = CGRect(x: textArea.minX, y: textArea.midY - height / 2, width: textArea.width, height: height)
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }

    private static func caption(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.gray, .paragraphStyle: paragraph
        ]).draw(in: CGRect(x: 22, y: 12, width: pageSize.width - 44, height: 12))
    }
}
