import AppKit
import BibleCore
import SwiftUI

/// Native text layout keeps long ranges fast and supports selection and
/// accessibility scrolling without SwiftUI's lazy-list scroll actions.
@MainActor
struct PassageTextView: NSViewRepresentable {
    let model: LookupModel
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
        let storage = NSTextStorage()
        let layout = AnnotatedLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let text = SelectablePassageTextView(frame: .zero, textContainer: container)
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
        context.coordinator.attach(text: text, scroll: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onSelectReference = onSelectReference
        let identity = bible.translation + ":\(showsReferences):" + passages.map(\.id).joined(separator: ";")
        guard let text = scroll.documentView as? NSTextView else { return }
        if identity != context.coordinator.identity {
            guard context.coordinator.finishEditing() else { return }
            let anchor = context.coordinator.translation != bible.translation && context.coordinator.query == model.query
                ? context.coordinator.topVisibleVerse() : nil
            context.coordinator.identity = identity
            let rendered = attributedPassages()
            context.coordinator.verses = rendered.verses
            context.coordinator.translation = bible.translation
            context.coordinator.invalidateAnnotations()
            text.textStorage?.setAttributedString(rendered.text)
            text.setSelectedRange(NSRange(location: 0, length: 0))
            (scroll as? PassageScrollView)?.updateDocumentSize()
            // NSTextView can shift its frame origin while resizing. Clip-view
            // coordinates must use the document's actual top, not zero.
            var position = text.frame.origin
            if let anchor, let offset = context.coordinator.verticalOffset(for: anchor) { position.y += offset }
            scroll.contentView.scroll(to: position)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        context.coordinator.query = model.query
        context.coordinator.updateAnnotations()
        context.coordinator.scheduleVisibleVerses()
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        _ = coordinator.finishEditing()
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var identity = ""
        var translation = ""
        var query = ""
        var verses: [DisplayedVerse] = []
        var onSelectReference: ((String) -> Void)?
        private weak var model: LookupModel?
        private weak var text: SelectablePassageTextView?
        private weak var scroll: PassageScrollView?
        private var editor: NoteEditorPanel?
        private var clickMonitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var visibleUpdateScheduled = false
        private var isSaving = false
        private var renderedNotes: [VerseNote]?
        private var previewNote: VerseNote?

        init(model: LookupModel) { self.model = model }

        func attach(text: SelectablePassageTextView, scroll: PassageScrollView) {
            self.text = text
            self.scroll = scroll
            text.onSelection = { [weak self] point in self?.editSelection(at: point) }
            scroll.onLayout = { [weak self] in self?.scheduleVisibleVerses() }
            scroll.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = self?.finishEditing()
                    self?.scheduleVisibleVerses()
                }
            })
            model?.finishNoteEditing = { [weak self] in self?.finishEditing() ?? true }
        }

        func detach() {
            text = nil
            scroll = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            model?.finishNoteEditing = nil
            let model = model
            DispatchQueue.main.async { model?.setVisibleVerses([]) }
        }

        func updateAnnotations() {
            guard let text, let layout = text.layoutManager as? AnnotatedLayoutManager else { return }
            let notes = (model?.notes ?? []).filter { $0.translation == translation }
            guard notes != renderedNotes else { return }
            renderedNotes = notes
            renderAnnotations()
            for displayed in verses {
                text.textStorage?.removeAttribute(.toolTip, range: displayed.range)
            }
            for annotation in layout.annotations where !annotation.note.text.isEmpty {
                text.textStorage?.addAttribute(.toolTip, value: annotation.note.text, range: annotation.range)
            }
        }

        func previewAnnotation(_ note: VerseNote) {
            previewNote = note
            model?.rememberAnnotation(note)
            renderAnnotations()
        }

        private func renderAnnotations() {
            guard let text, let layout = text.layoutManager as? AnnotatedLayoutManager else { return }
            var notes = (model?.notes ?? []).filter { $0.translation == translation }
            if let previewNote {
                notes.removeAll { $0.id == previewNote.id }
                notes.append(previewNote)
            }
            layout.annotations = notes.flatMap { note in
                verses.filter(\.allowsNotes).flatMap { displayed in
                    note.segments.compactMap { segment in
                        guard segment.verse == displayed.verse, let range = segment.range(in: displayed.text) else { return nil }
                        return RenderedAnnotation(note: note, range: NSRange(location: displayed.range.location + range.location,
                                                                            length: range.length))
                    }
                }
            }
            text.needsDisplay = true
        }

        func invalidateAnnotations() { renderedNotes = nil }

        func topVisibleVerse() -> NoteVerse? { visibleVerseAddresses().first }

        func verticalOffset(for anchor: NoteVerse) -> CGFloat? {
            guard let text, let layout = text.layoutManager, let container = text.textContainer else { return nil }
            let chapter = verses.filter { $0.verse.book == anchor.book && $0.verse.chapter == anchor.chapter }
                .sorted { $0.verse.verse < $1.verse.verse }
            // Editions can omit an address. Prefer the next displayed verse,
            // or the last one in the chapter if there is no following verse.
            guard let displayed = chapter.first(where: { $0.verse.verse >= anchor.verse }) ?? chapter.last else { return nil }
            layout.ensureLayout(for: container)
            let glyph = layout.glyphIndexForCharacter(at: displayed.range.location)
            return text.textContainerOrigin.y + layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        }

        private func visibleVerseAddresses() -> [NoteVerse] {
            guard let text, let scroll, let layout = text.layoutManager, let container = text.textContainer else { return [] }
            let origin = text.textContainerOrigin
            let viewport = scroll.documentVisibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
            let glyphs = layout.glyphRange(forBoundingRect: viewport, in: container)
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            return verses.compactMap { displayed in
                let intersection = NSIntersectionRange(characters, displayed.range)
                guard intersection.length > 0 else { return nil }
                let glyphRange = layout.glyphRange(forCharacterRange: intersection, actualCharacterRange: nil)
                return layout.boundingRect(forGlyphRange: glyphRange, in: container).intersects(viewport) ? displayed.verse : nil
            }
        }

        func scheduleVisibleVerses() {
            guard !visibleUpdateScheduled else { return }
            visibleUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.visibleUpdateScheduled = false
                self.model?.setVisibleVerses(Set(self.visibleVerseAddresses()))
            }
        }

        private func editSelection(at point: NSPoint) {
            guard let text, let parent = text.window,
                  let layout = text.layoutManager as? AnnotatedLayoutManager,
                  let container = text.textContainer, finishEditing() else { return }
            let selection = text.selectedRange()
            let existing: RenderedAnnotation?
            if selection.length == 0 {
                existing = layout.annotations.last { annotation in
                    layout.slices(for: annotation, in: container).contains {
                        $0.offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y).contains(point)
                    }
                }
            } else {
                let segments = DisplayedVerse.segments(in: selection, verses: verses)
                existing = layout.annotations.last { $0.note.segments == segments }
            }
            let segments = DisplayedVerse.segments(in: selection, verses: verses)
            guard existing != nil || !segments.isEmpty else { return }
            guard let note = existing?.note ?? model?.makeNote(translation: translation, segments: segments) else { return }
            let anchorRange: NSRange
            if let existing { anchorRange = existing.range }
            else {
                let ranges = verses.compactMap { displayed -> NSRange? in
                    let range = NSIntersectionRange(selection, displayed.range)
                    return range.length > 0 ? range : nil
                }
                guard let last = ranges.last else { return }
                anchorRange = last
            }
            let annotation = RenderedAnnotation(note: note, range: anchorRange)
            guard let lastRect = layout.slices(for: annotation, in: container).last else { return }
            let viewRect = lastRect.offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
            let anchor = parent.convertToScreen(text.convert(viewRect, to: nil))
            let editor = NoteEditorPanel(note: note, onAnnotationChange: { [weak self] note in
                self?.previewAnnotation(note)
            }) { [weak self] note in self?.save(note) ?? false }
            self.editor = editor
            let screen = parent.screen ?? NSScreen.main
            let available = screen?.visibleFrame ?? parent.frame
            let x = min(max(anchor.midX - 161, available.minX + 8), available.maxX - 330)
            // Reserve space for the color row too, so choosing a style keeps the
            // editor on screen. Prefer directly below the selected final line.
            let y = max(available.minY + 40, anchor.minY - 6 - 158)
            editor.setFrame(NSRect(x: x, y: y, width: 322, height: 158), display: false)
            parent.addChildWindow(editor, ordered: .above)
            editor.makeKeyAndOrderFront(nil)
            editor.makeFirstResponder(editor.editor.text)
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let blocked = MainActor.assumeIsolated {
                    guard let self, let editor = self.editor else { return false }
                    return event.window != editor && !self.finishEditing()
                }
                return blocked ? nil : event
            }
        }

        @discardableResult
        func finishEditing() -> Bool { isSaving ? true : (editor?.editor.save() ?? true) }

        private func save(_ note: VerseNote) -> Bool {
            guard !isSaving else { return true }
            isSaving = true
            defer { isSaving = false }
            do { try model?.saveNote(note) }
            catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Your note couldn’t be saved"
                alert.runModal()
                return false
            }
            if let editor {
                editor.parent?.removeChildWindow(editor)
                editor.orderOut(nil)
            }
            editor = nil
            previewNote = nil
            invalidateAnnotations()
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            updateAnnotations()
            return true
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let reference = link as? String { onSelectReference?(reference) }
            return true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    private func attributedPassages() -> (text: NSAttributedString, verses: [DisplayedVerse]) {
        let result = NSMutableAttributedString(string: "")
        var displayed: [DisplayedVerse] = []
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
                    let chapterReference = "\(bible.books[verse.address.book].name) \(verse.address.chapter)"
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
                displayed.append(DisplayedVerse(verse: NoteVerse(verse.address),
                                                range: NSRange(location: result.length, length: (body as NSString).length),
                                                text: body, allowsNotes: !verse.isOmitted))
                result.append(NSAttributedString(string: body + "\n", attributes: [
                    .font: verse.isOmitted ? omittedFont : font,
                    .foregroundColor: verse.isOmitted ? muted : ink, .paragraphStyle: style
                ]))
            }
        }
        return (result, displayed)
    }
}

final class SelectablePassageTextView: NSTextView {
    var onSelection: ((NSPoint) -> Void)?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        // NSTextView tracks the entire drag here and returns on mouse release.
        onSelection?(point)
    }
}

final class PassageScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        updateDocumentSize()
        onLayout?()
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
