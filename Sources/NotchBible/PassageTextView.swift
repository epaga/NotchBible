import AppKit
import BibleCore
import SwiftUI

/// Native text layout keeps long ranges fast and supports selection and
/// accessibility scrolling without SwiftUI's lazy-list scroll actions.
struct PassageTextView: NSViewRepresentable {
    let bible: BibleStore
    let passages: [BiblePassage]
    var showsReferences = false
    var onSelectReference: ((String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PassageScrollView()
        scroll.clipsToBounds = true
        scroll.contentView.clipsToBounds = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSTextView(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.delegate = context.coordinator
        text.linkTextAttributes = [
            .foregroundColor: NSColor(calibratedRed: 0.56, green: 0.55, blue: 0.52, alpha: 0.8),
            .underlineStyle: 0
        ]
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 25, height: 0)
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.selectedTextAttributes = [.backgroundColor: NSColor.white.withAlphaComponent(0.17)]
        text.setAccessibilityLabel("Passage")
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onSelectReference = onSelectReference
        let identity = bible.translation + ":\(showsReferences):" + passages.map(\.id).joined(separator: ";")
        guard identity != context.coordinator.identity, let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.identity = identity
        text.textStorage?.setAttributedString(attributedPassages())
        text.setSelectedRange(NSRange(location: 0, length: 0))
        (scroll as? PassageScrollView)?.updateDocumentSize()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var identity = ""
        var onSelectReference: ((String) -> Void)?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let reference = link as? String { onSelectReference?(reference) }
            return true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    private func attributedPassages() -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let ink = NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.87, alpha: 1)
        let muted = NSColor(calibratedRed: 0.56, green: 0.55, blue: 0.52, alpha: 1)
        let serif = NSFont.systemFont(ofSize: 20)
        let font = serif.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 20) } ?? serif
        let omittedFont = NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
        for passage in passages {
            if showsReferences || passages.count > 1 {
                let style = NSMutableParagraphStyle()
                style.paragraphSpacingBefore = 8
                style.paragraphSpacing = 12
                result.append(NSAttributedString(string: passage.reference + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor(calibratedRed: 0.88, green: 0.71, blue: 0.46, alpha: 1),
                    .paragraphStyle: style
                ]))
            }
            let showChapter = showsReferences || passages.count > 1 ||
                bible.verses[passage.range.lowerBound].address.chapter != bible.verses[passage.range.upperBound - 1].address.chapter
            let labelWidth: CGFloat = showChapter ? 33 : 14
            let style = NSMutableParagraphStyle()
            style.headIndent = labelWidth + 11
            style.tabStops = [NSTextTab(textAlignment: .right, location: labelWidth),
                              NSTextTab(textAlignment: .left, location: style.headIndent)]
            style.lineSpacing = 6
            style.paragraphSpacing = 12
            for verse in bible.verses[passage.range] {
                let number = showChapter ? "\(verse.address.chapter):\(verse.address.verse)" : "\(verse.address.verse)"
                let label = NSMutableAttributedString(string: "\t" + number + "\t", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: muted.withAlphaComponent(0.8), .paragraphStyle: style
                ])
                if showsReferences {
                    let chapterReference = "\(verse.book.name) \(verse.address.chapter)"
                    var chapterQuery = chapterReference
                    // A lone number means a verse in single-chapter books.
                    if verse.book.isSingleChapter,
                       let range = bible.chapterRange(book: verse.book, chapter: verse.address.chapter) {
                        chapterQuery += ":\(bible.verses[range.lowerBound].address.verse)–\(bible.verses[range.upperBound - 1].address.verse)"
                    }
                    let chapterLength = String(verse.address.chapter).utf16.count
                    label.addAttributes([.link: chapterQuery, .toolTip: "Show \(chapterReference)"],
                                        range: NSRange(location: 1, length: chapterLength))
                    let verseReference = chapterReference + ":\(verse.address.verse)"
                    label.addAttributes([.link: verseReference, .toolTip: "Show \(verseReference)"],
                                        range: NSRange(location: chapterLength + 2, length: String(verse.address.verse).utf16.count))
                }
                result.append(label)
                let body = verse.isOmitted ? "This verse number has no text in this \(bible.translation) edition." : verse.text
                result.append(NSAttributedString(string: body + "\n", attributes: [
                    .font: verse.isOmitted ? omittedFont : font,
                    .foregroundColor: verse.isOmitted ? muted : ink, .paragraphStyle: style
                ]))
            }
        }
        return result
    }
}

private final class PassageScrollView: NSScrollView {
    override func layout() {
        super.layout()
        updateDocumentSize()
    }

    func updateDocumentSize() {
        guard contentSize.width > 0, let text = documentView as? NSTextView,
              let container = text.textContainer, let layout = text.layoutManager else { return }
        let width = contentSize.width
        if text.frame.width != width {
            text.setFrameSize(NSSize(width: width, height: text.frame.height))
        }
        layout.ensureLayout(for: container)
        let height = max(contentSize.height, ceil(layout.usedRect(for: container).height) + 21)
        if text.frame.height != height {
            text.setFrameSize(NSSize(width: width, height: height))
        }
    }
}
