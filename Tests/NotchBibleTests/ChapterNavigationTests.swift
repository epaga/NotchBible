import AppKit
import BibleCore
import XCTest
@testable import NotchBible

final class ChapterNavigationTests: XCTestCase {
    @MainActor
    private func withModel(_ body: (LookupModel) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var records: [String] = []
        for (book, chapters) in [("GEN", [1, 2, 50]), ("EXO", [1]), ("3JO", [1]), ("JUD", [1]), ("REV", [1, 22])] {
            for chapter in chapters {
                for verse in 1...3 { records.append("\(book) \(chapter):\(verse) Water in this verse.") }
            }
        }
        try records.joined(separator: "\n").write(to: directory.appendingPathComponent("SampleBible.txt"),
                                                  atomically: true, encoding: .utf8)
        let suite = "ChapterNavigationTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = LookupModel(library: try BibleLibrary(directory: directory), preferences: preferences,
                                noteStore: NoteStore(url: directory.appendingPathComponent("Notes.json")))
        try body(model)
    }

    @MainActor
    func testMovesThroughChaptersAndBooksWithoutWrapping() throws {
        try withModel { model in
            model.query = "Genesis 1"
            XCTAssertTrue(model.moveChapter(-1))
            XCTAssertEqual(model.query, "Genesis 1")
            XCTAssertTrue(model.moveChapter(1))
            XCTAssertEqual(model.resultSummary, "Genesis 2")
            XCTAssertEqual(model.focusRequest, 0, "Navigation must keep focus outside the search field")
            XCTAssertTrue(model.moveChapter(-1))
            XCTAssertEqual(model.resultSummary, "Genesis 1")

            model.query = "Genesis 50"
            XCTAssertTrue(model.moveChapter(1))
            XCTAssertEqual(model.resultSummary, "Exodus 1")
            XCTAssertTrue(model.moveChapter(-1))
            XCTAssertEqual(model.resultSummary, "Genesis 50")

            model.query = "Revelation 22"
            XCTAssertTrue(model.moveChapter(1))
            XCTAssertEqual(model.query, "Revelation 22")
        }
    }

    @MainActor
    func testSingleChapterBooksRemainFullChaptersInBothDirections() throws {
        try withModel { model in
            model.query = "Revelation 1"
            XCTAssertTrue(model.moveChapter(-1))
            XCTAssertEqual(model.query, "Jude 1:1-3")
            XCTAssertEqual(model.result.verseCount, 3)
            XCTAssertTrue(model.moveChapter(-1))
            XCTAssertEqual(model.query, "3 John 1:1-3")
            XCTAssertEqual(model.result.verseCount, 3)
            XCTAssertTrue(model.moveChapter(1))
            XCTAssertEqual(model.query, "Jude 1:1-3")
            XCTAssertTrue(model.moveChapter(1))
            XCTAssertEqual(model.resultSummary, "Revelation 1")
        }
    }

    @MainActor
    func testRequiresOneCompleteChapterAndRespectsUnsavedNotes() throws {
        try withModel { model in
            for query in ["", "Genesis", "Genesis 1:2", "Genesis 1:1-2", "Genesis 1-2",
                          "Genesis 1; Genesis 2", "Genesis 1;", "Genesis 1:", "water", "Genesis 99"] {
                model.query = query
                XCTAssertFalse(model.moveChapter(1), query)
                XCTAssertFalse(model.moveChapter(-1), query)
                XCTAssertEqual(model.query, query)
            }
            model.query = "Genesis 1:1-3"
            XCTAssertTrue(model.moveChapter(1))
            XCTAssertEqual(model.resultSummary, "Genesis 2")
            model.finishNoteEditing = { false }
            XCTAssertTrue(model.moveChapter(-1))
            XCTAssertEqual(model.query, "Genesis 2", "A failed note save must block navigation")
        }
    }

    @MainActor
    func testOptionArrowsLeaveTheSearchFieldEditorAlone() throws {
        try withModel { model in
            model.query = "Genesis 1"
            let panel = LookupPanel(model: model)
            defer { panel.close() }
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            let field = NSTextField(frame: NSRect(x: 0, y: 150, width: 400, height: 30))
            field.stringValue = model.query
            content.addSubview(field)
            let passage = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 140))
            passage.isEditable = false
            content.addSubview(passage)
            panel.contentView = content
            var moves = 0
            panel.onMoveChapter = { delta in
                moves += 1
                return model.moveChapter(delta)
            }
            @MainActor func arrow(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [.option, .function, .numericPad]) -> NSEvent {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                 windowNumber: panel.windowNumber, context: nil, characters: "",
                                 charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)!
            }

            XCTAssertTrue(panel.makeFirstResponder(field))
            XCTAssertEqual((panel.firstResponder as? NSTextView)?.isFieldEditor, true)
            _ = panel.performKeyEquivalent(with: arrow(124))
            _ = panel.performKeyEquivalent(with: arrow(123))
            XCTAssertEqual(moves, 0)
            XCTAssertEqual(model.query, "Genesis 1")

            XCTAssertTrue(panel.makeFirstResponder(passage))
            XCTAssertTrue(panel.performKeyEquivalent(with: arrow(124)))
            XCTAssertEqual(model.resultSummary, "Genesis 2")
            XCTAssertTrue(panel.performKeyEquivalent(with: arrow(123)))
            XCTAssertEqual(model.resultSummary, "Genesis 1")
            XCTAssertEqual(moves, 2)
            _ = panel.performKeyEquivalent(with: arrow(124, modifiers: [.option, .shift]))
            XCTAssertEqual(moves, 2, "Only unshifted Option arrows navigate chapters")
        }
    }
}
