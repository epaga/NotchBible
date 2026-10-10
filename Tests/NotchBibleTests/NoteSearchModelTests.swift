import BibleCore
import XCTest
@testable import NotchBible

final class NoteSearchModelTests: XCTestCase {
    @MainActor
    func testAllNotesSearchShowsTotalNoteCountsForEveryTranslation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["Alpha", "Beta", "Gamma"] {
            try "GEN 1:1 Water.\nGEN 1:2 Light.\n"
                .write(to: directory.appendingPathComponent(name + "Bible.txt"), atomically: true, encoding: .utf8)
        }
        let library = try BibleLibrary(directory: directory)
        let suite = "NoteSearchModelTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("Gamma", forKey: "selectedTranslation")
        let model = LookupModel(library: library, preferences: preferences,
                                noteStore: NoteStore(url: directory.appendingPathComponent("Notes.json")))
        let segments = model.bible.verses.map {
            NoteSegment(verse: NoteVerse($0.address), location: 0, length: $0.text.count, quote: $0.text)
        }
        try model.saveNote(VerseNote(translation: "Alpha", segments: [segments[0]], text: "First note"))
        try model.saveNote(VerseNote(translation: "Alpha", segments: [segments[0]], text: "Second note"))
        var beta = VerseNote(translation: "Beta", segments: segments, text: "Spanning two verses")
        try model.saveNote(beta)
        for query in ["note:*", "  NOTE:*\n"] {
            model.query = query
            XCTAssertTrue(model.result.passages.isEmpty, "The current translation has no notes")
            XCTAssertTrue(model.isAllNotesSearch)
            XCTAssertEqual(model.noteCount(for: "Alpha"), 2, "Count notes, even when they share a verse")
            XCTAssertEqual(model.noteCount(for: "Beta"), 1, "A note spanning multiple verses counts once")
            XCTAssertEqual(model.noteCount(for: "Gamma"), 0)
        }
        model.selectTranslation("Alpha")
        XCTAssertEqual(model.result.verseCount, 1)
        XCTAssertEqual(model.noteCount(for: "Alpha"), 2, "The selected tab also gets its total count")
        model.setVisibleVerses([])
        XCTAssertEqual(model.noteCount(for: "Alpha"), 2)
        XCTAssertEqual(model.noteCount(for: "Beta"), 1)
        beta.text = ""
        try model.saveNote(beta)
        XCTAssertEqual(model.noteCount(for: "Beta"), 0)
        model.query = "gen1:1"
        XCTAssertFalse(model.isAllNotesSearch)
        model.setVisibleVerses([segments[0].verse])
        XCTAssertEqual(model.noteCount(for: "Alpha"), 0, "Ordinary lookups retain their visible-verse badge rules")
        model.selectTranslation("Gamma")
        model.setVisibleVerses([segments[0].verse])
        XCTAssertEqual(model.noteCount(for: "Alpha"), 2)
    }

    @MainActor
    func testSearchUsesOnlyCurrentTranslationAndRefreshesWhenNotesChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["Alpha", "Beta"] {
            try "GEN 1:1 Water.\nGEN 1:2 Light.\n"
                .write(to: directory.appendingPathComponent(name + "Bible.txt"), atomically: true, encoding: .utf8)
        }
        let library = try BibleLibrary(directory: directory)
        let suite = "NoteSearchModelTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("Alpha", forKey: "selectedTranslation")
        let store = NoteStore(url: directory.appendingPathComponent("Notes.json"))
        let model = LookupModel(library: library, preferences: preferences, noteStore: store)
        let segments = model.bible.verses.map {
            NoteSegment(verse: NoteVerse($0.address), location: 0, length: $0.text.count, quote: $0.text)
        }
        var alpha = VerseNote(translation: "Alpha", segments: segments, text: "Bla blub")
        let beta = VerseNote(translation: "Beta", segments: [segments[1]], text: "Bla blub")
        try model.saveNote(beta)
        model.query = "bla"
        XCTAssertTrue(model.result.passages.isEmpty, "Other translations' notes must not leak into results")
        try model.saveNote(alpha)
        XCTAssertEqual(model.result.passages.map(\.range.lowerBound), [0, 1])
        model.query = "note:\"bla blub\""
        XCTAssertEqual(model.result.passages.map(\.range.lowerBound), [0, 1])
        model.selectTranslation("Beta")
        XCTAssertEqual(model.query, "note:\"bla blub\"")
        XCTAssertEqual(model.result.passages.map(\.range.lowerBound), [1])
        model.selectTranslation("Alpha")
        alpha.text = "Changed note"
        try model.saveNote(alpha)
        XCTAssertTrue(model.result.passages.isEmpty, "Editing a matching note must refresh the current search")
        model.query = "note:changed"
        XCTAssertEqual(model.result.passages.map(\.range.lowerBound), [0, 1])
        alpha.text = ""
        try model.saveNote(alpha)
        XCTAssertTrue(model.result.passages.isEmpty, "Deleting a note must remove its search matches")
        XCTAssertEqual(NoteStore(url: store.url).notes, [beta])
        let nextLaunch = LookupModel(library: library, preferences: preferences, noteStore: NoteStore(url: store.url))
        nextLaunch.selectTranslation("Beta")
        nextLaunch.query = "note:bla"
        XCTAssertEqual(nextLaunch.result.passages.map(\.range.lowerBound), [1])
    }
}
