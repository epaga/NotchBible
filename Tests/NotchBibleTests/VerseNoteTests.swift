import AppKit
import BibleCore
import XCTest
@testable import NotchBible

final class VerseNoteTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testNewNotesRememberLastAnnotationChoicesAcrossLaunches() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "GEN 1:1 God created.\n".write(to: directory.appendingPathComponent("TestBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        let suite = "VerseNoteTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = NoteStore(url: directory.appendingPathComponent("Notes.json"))
        let model = LookupModel(library: library, preferences: preferences, noteStore: store)
        var note = model.makeNote(translation: "Test", segments: [])
        XCTAssertEqual(note.style, .underline)
        XCTAssertEqual(note.color, 0)
        note.style = .topBox
        note.color = 8
        model.rememberAnnotation(note)
        let nextLaunch = LookupModel(library: library, preferences: UserDefaults(suiteName: suite)!, noteStore: store)
        let nextNote = nextLaunch.makeNote(translation: "Other", segments: [])
        XCTAssertEqual(nextNote.style, .topBox)
        XCTAssertEqual(nextNote.color, 8)
        XCTAssertTrue(nextLaunch.notes.isEmpty)
        preferences.set("unknown", forKey: "noteAnnotationStyle")
        preferences.set(100, forKey: "noteAnnotationColor")
        let fallback = nextLaunch.makeNote(translation: "Test", segments: [])
        XCTAssertEqual(fallback.style, .underline)
        XCTAssertEqual(fallback.color, 0)
    }

    @MainActor
    func testEditorButtonsPreviewAnnotationsWithoutSavingOrChangingTextLayout() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "GEN 1:1 God created.\n".write(to: directory.appendingPathComponent("TestBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        let suite = "VerseNoteTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = NoteStore(url: directory.appendingPathComponent("Notes.json"))
        let model = LookupModel(library: library, preferences: preferences, noteStore: store)
        let verse = NoteVerse(model.bible.verses[0].address)
        let note = VerseNote(translation: "Test", segments: [NoteSegment(verse: verse, location: 0, length: 3, quote: "God")],
                             text: "Saved text", style: .box, color: 2)
        try model.saveNote(note)
        let storage = NSTextStorage(string: "1\tGod created.", attributes: [.font: NSFont.systemFont(ofSize: 20)])
        storage.addAttribute(.toolTip, value: "Show Genesis 1:1", range: NSRange(location: 0, length: 1))
        let layout = AnnotatedLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 300, height: 800))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let text = SelectablePassageTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 800), textContainer: container)
        let scroll = PassageScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 70))
        scroll.documentView = text
        let coordinator = PassageTextView.Coordinator(model: model)
        defer { coordinator.detach() }
        coordinator.translation = "Test"
        coordinator.verses = [DisplayedVerse(verse: verse, range: NSRange(location: 2, length: storage.length - 2), text: "God created.")]
        coordinator.attach(text: text, scroll: scroll)
        coordinator.updateAnnotations()
        var saved: VerseNote?
        let editor = NoteEditorViewController(note: note, onAnnotationChange: coordinator.previewAnnotation) {
            saved = $0
            return true
        }
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let controls = buttons(in: editor.view)
        XCTAssertEqual(model.makeNote(translation: "Test", segments: []).style, .underline, "Opening an old note must not change defaults")
        try XCTUnwrap(controls.first { $0.toolTip == AnnotationStyle.oval.name }).performClick(nil)
        XCTAssertEqual(layout.annotations.count, 1)
        XCTAssertEqual(layout.annotations.first?.note.style, .oval)
        let blue = try XCTUnwrap(AnnotationColors.names.firstIndex(of: "Blue"))
        try XCTUnwrap(controls.first { $0.toolTip == "Blue" }).performClick(nil)
        XCTAssertEqual(layout.annotations.first?.note.color, blue)
        XCTAssertEqual(model.notes, [note])
        XCTAssertEqual(NoteStore(url: store.url).notes, [note])
        XCTAssertEqual(storage.attribute(.toolTip, at: 2, effectiveRange: nil) as? String, "Saved text")
        XCTAssertEqual(storage.attribute(.toolTip, at: 0, effectiveRange: nil) as? String, "Show Genesis 1:1")
        XCTAssertEqual(storage.string, "1\tGod created.")
        let next = model.makeNote(translation: "Test", segments: [])
        XCTAssertEqual(next.style, .oval)
        XCTAssertEqual(next.color, blue)
        editor.text.string = "Updated text\nSecond line"
        XCTAssertTrue(editor.save())
        XCTAssertEqual(saved?.text, "Updated text\nSecond line")
        XCTAssertEqual(saved?.style, .oval)
        XCTAssertEqual(saved?.color, blue)
    }

    func testMultilineNotesPersistByTranslationAndEditingReplacesTheSameNote() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bible = try BibleStore(text: "GEN 1:1 God created.\nGEN 1:2 Water.\n", requiresCompleteBible: false)
        let segment = NoteSegment(verse: NoteVerse(bible.verses[0].address), location: 0, length: 3, quote: "God")
        let url = directory.appendingPathComponent("Notes.json")
        let store = NoteStore(url: url)
        var note = VerseNote(translation: "NET", segments: [segment], text: "First line\nSecond line",
                             style: .bottomBox, color: 8)
        try store.save(note)
        try store.save(VerseNote(translation: "Other", segments: [segment], text: "Other edition"))
        note.text += "\nThird line"
        note.style = .oval
        try store.save(note)
        let reopened = NoteStore(url: url)
        XCTAssertEqual(reopened.notes.count, 2)
        XCTAssertEqual(reopened.notes.first, note)
        XCTAssertEqual(reopened.notes.last?.translation, "Other")
    }

    func testCorruptNotesArePreservedWhenSavingFails() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Notes.json")
        let original = Data("damaged notes file".utf8)
        try original.write(to: url)
        let store = NoteStore(url: url)
        XCTAssertThrowsError(try store.save(VerseNote(translation: "NET", segments: [])))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testLoadingLegacyEmptyNotesFiltersThemAndTheNextSaveRemovesThemFromDisk() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Notes.json")
        var kept = VerseNote(translation: "NET", segments: [], text: "Keep this note")
        let empty = ["", " \t\r\n", "\u{00a0}\u{2003}\n"].map {
            VerseNote(translation: "NET", segments: [], text: $0)
        }
        let original = try JSONEncoder().encode(empty + [kept])
        try original.write(to: url)
        let store = NoteStore(url: url)
        XCTAssertEqual(store.notes, [kept])
        XCTAssertEqual(try Data(contentsOf: url), original, "Loading alone must not rewrite the notes file")
        kept.text += "\nUpdated"
        try store.save(kept)
        let saved = try JSONDecoder().decode([VerseNote].self, from: Data(contentsOf: url))
        XCTAssertEqual(saved, [kept])
        XCTAssertEqual(NoteStore(url: url).notes, [kept])
    }

    func testSavingEmptyOrWhitespaceTextRemovesOnlyThatNoteAndPersistsRemoval() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bible = try BibleStore(text: "GEN 1:1 God created.\n", requiresCompleteBible: false)
        let segment = NoteSegment(verse: NoteVerse(bible.verses[0].address), location: 0, length: 3, quote: "God")
        for (index, empty) in ["", " \t\r\n", "\u{00a0}\u{2003}\n"].enumerated() {
            let url = directory.appendingPathComponent("Notes-\(index).json")
            let store = NoteStore(url: url)
            var note = VerseNote(translation: "NET", segments: [segment], text: "Remove this note")
            let other = VerseNote(translation: "Other", segments: [segment], text: "Keep this note")
            try store.save(note)
            try store.save(other)
            note.text = empty
            try store.save(note)
            XCTAssertEqual(store.notes, [other])
            XCTAssertEqual(NoteStore(url: url).notes, [other])
        }
    }

    func testDismissingAnEmptyNewNoteDoesNotCreateAFile() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Notes.json")
        let store = NoteStore(url: url)
        try store.save(VerseNote(translation: "NET", segments: [], text: " \t\n"))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSelectionsAcrossVersesExcludeLabelsAndUseUTF16Offsets() throws {
        let bible = try BibleStore(text: "GEN 1:1 God 🌍 made.\nGEN 1:2 Water and light.\n", requiresCompleteBible: false)
        let first = bible.verses[0].text
        let second = bible.verses[1].text
        let document = "\t1\t" + first + "\n\t2\t" + second + "\n"
        let body = document as NSString
        let displayed = [
            DisplayedVerse(verse: NoteVerse(bible.verses[0].address), range: body.range(of: first), text: first),
            DisplayedVerse(verse: NoteVerse(bible.verses[1].address), range: body.range(of: second), text: second)
        ]
        let start = body.range(of: "🌍").location
        let end = NSMaxRange(body.range(of: "Water"))
        let segments = DisplayedVerse.segments(in: NSRange(location: start, length: end - start), verses: displayed)
        XCTAssertEqual(segments.map(\.quote), ["🌍 made.", "Water"])
        XCTAssertEqual(segments[0].location, 4)
        XCTAssertEqual(segments[0].length, 8)
        XCTAssertEqual(segments[0].range(in: first), NSRange(location: 4, length: 8))
        XCTAssertNil(segments[0].range(in: "Changed translation text."))
        XCTAssertTrue(DisplayedVerse.segments(in: NSRange(location: 0, length: 3), verses: displayed).isEmpty)
    }

    func testBadgesCountNotesOnceForOnlyVisibleVersesInOtherTranslations() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["Alpha", "Beta"] {
            try "GEN 1:1 God created.\nGEN 1:2 Water.\nGEN 1:3 Light.\n"
                .write(to: directory.appendingPathComponent(name + "Bible.txt"), atomically: true, encoding: .utf8)
        }
        let library = try BibleLibrary(directory: directory)
        try await MainActor.run {
            let suite = "VerseNoteTests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let model = LookupModel(library: library, preferences: preferences,
                                    noteStore: NoteStore(url: directory.appendingPathComponent("Notes.json")))
            model.query = "gen1"
            let verses = model.bible.verses.map { NoteVerse($0.address) }
            let spans = verses.map { NoteSegment(verse: $0, location: 0, length: 1, quote: "G") }
            try model.saveNote(VerseNote(translation: "Beta", segments: Array(spans[0...1]), text: "First two verses"))
            try model.saveNote(VerseNote(translation: "Beta", segments: [spans[2]], text: "Third verse"))
            var alphaNote = VerseNote(translation: "Alpha", segments: [spans[0]], text: "Alpha note")
            try model.saveNote(alphaNote)
            model.setVisibleVerses([verses[0], verses[1]])
            XCTAssertEqual(model.noteCount(for: "Beta"), 1)
            XCTAssertEqual(model.noteCount(for: "Alpha"), 0)
            model.setVisibleVerses([verses[2]])
            XCTAssertEqual(model.noteCount(for: "Beta"), 1)
            model.setVisibleVerses([])
            XCTAssertEqual(model.noteCount(for: "Beta"), 0)
            model.setVisibleVerses(Set(verses))
            XCTAssertEqual(model.noteCount(for: "Beta"), 2)
            model.query = "gen1:1"
            XCTAssertEqual(model.noteCount(for: "Beta"), 0)
            model.setVisibleVerses([verses[0]])
            model.selectTranslation("Beta")
            XCTAssertTrue(model.visibleVerses.isEmpty)
            model.setVisibleVerses([verses[0]])
            XCTAssertEqual(model.noteCount(for: "Alpha"), 1)
            XCTAssertEqual(model.noteCount(for: "Beta"), 0)
            alphaNote.text = " \t\n"
            try model.saveNote(alphaNote)
            XCTAssertEqual(model.noteCount(for: "Alpha"), 0)
            XCTAssertFalse(model.notes.contains { $0.id == alphaNote.id })
        }
    }

    func testAnnotationSlicesFollowWrappedLinesAndResize() async throws {
        try await MainActor.run {
            let storage = NSTextStorage(string: "Label\tA short beginning and a much longer middle with several words and a tiny end.\n",
                                        attributes: [.font: NSFont.systemFont(ofSize: 20)])
            let layout = AnnotatedLayoutManager()
            let container = NSTextContainer(size: NSSize(width: 260, height: 1000))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            let body = storage.string as NSString
            let range = body.range(of: "beginning and a much longer middle with several words and a tiny end.")
            let bible = try BibleStore(text: "GEN 1:1 God created.\n", requiresCompleteBible: false)
            let note = VerseNote(translation: "NET", segments: [NoteSegment(verse: NoteVerse(bible.verses[0].address),
                                                                         location: 0, length: 3, quote: "God")])
            let annotation = RenderedAnnotation(note: note, range: range)
            layout.ensureLayout(for: container)
            let wide = layout.slices(for: annotation, in: container)
            XCTAssertGreaterThan(wide.count, 1)
            XCTAssertGreaterThan(wide[0].minX, 0)
            XCTAssertTrue(zip(wide, wide.dropFirst()).allSatisfy { $0.maxY < $1.minY })
            XCTAssertTrue(wide.allSatisfy { $0.width > 0 && $0.width <= 264 })
            container.containerSize.width = 150
            layout.ensureLayout(for: container)
            let narrow = layout.slices(for: annotation, in: container)
            XCTAssertGreaterThan(narrow.count, wide.count, "wide: \(wide), narrow: \(narrow), used: \(layout.usedRect(for: container)), text: \(storage.length)")
            XCTAssertTrue(narrow.allSatisfy { $0.width <= 154 })
        }
    }

    @MainActor
    func testScrollingRemovesBadgesForVersesOutsideTheViewport() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = (1...20).map { "GEN 1:\($0) God made verse \($0) with several words." }.joined(separator: "\n")
        try records.write(to: directory.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        try records.write(to: directory.appendingPathComponent("BetaBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        let suite = "VerseNoteTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = LookupModel(library: library, preferences: preferences,
                                noteStore: NoteStore(url: directory.appendingPathComponent("Notes.json")))
        model.query = "gen1"
        let first = NoteVerse(model.bible.verses[0].address)
        let last = NoteVerse(model.bible.verses.last!.address)
        try model.saveNote(VerseNote(translation: "Beta", segments: [
            NoteSegment(verse: first, location: 0, length: 3, quote: "God")
        ], text: "Visible verse note"))

        let storage = NSTextStorage()
        let layout = AnnotatedLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 300, height: 2000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let text = SelectablePassageTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 2000), textContainer: container)
        text.textContainerInset = .zero
        container.widthTracksTextView = true
        let scroll = PassageScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 70))
        scroll.documentView = text
        let coordinator = PassageTextView.Coordinator(model: model)
        defer { coordinator.detach() }
        coordinator.translation = model.selectedTranslation
        for verse in model.bible.verses {
            coordinator.verses.append(DisplayedVerse(verse: NoteVerse(verse.address),
                                                     range: NSRange(location: storage.length, length: (verse.text as NSString).length),
                                                     text: verse.text))
            storage.append(NSAttributedString(string: verse.text + "\n", attributes: [.font: NSFont.systemFont(ofSize: 20)]))
        }
        coordinator.attach(text: text, scroll: scroll)
        scroll.layoutSubtreeIfNeeded()
        scroll.updateDocumentSize()
        coordinator.scheduleVisibleVerses()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertTrue(model.visibleVerses.contains(first))
        XCTAssertFalse(model.visibleVerses.contains(last))
        XCTAssertEqual(model.noteCount(for: "Beta"), 1)

        let lastGlyphs = layout.glyphRange(forCharacterRange: coordinator.verses.last!.range, actualCharacterRange: nil)
        let lastRect = layout.boundingRect(forGlyphRange: lastGlyphs, in: container)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: lastRect.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertFalse(model.visibleVerses.contains(first))
        XCTAssertTrue(model.visibleVerses.contains(last))
        XCTAssertEqual(model.noteCount(for: "Beta"), 0)
    }
}
