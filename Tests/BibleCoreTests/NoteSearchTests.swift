import XCTest
@testable import BibleCore

final class NoteSearchTests: XCTestCase {
    private let bible = try! BibleStore(text: """
        GEN 1:1 Bla blub in verse text.
        GEN 1:2 Quiet waters.
        GEN 1:3 Light.
        GEN 1:4 Bla without phrase.
        GEN 1:5
        PSA 1:1 Rest.
        MAT 1:1 Hope.
        """.replacingOccurrences(of: "GEN 1:5\n", with: "GEN 1:5 \n"),
        translation: "Fixture", requiresCompleteBible: false)
    private let notes = [
        VerseSearchNote(text: "bla blub", verseIDs: [2, 1, 1, 4, -1, 999]),
        VerseSearchNote(text: "blub bla", verseIDs: [5]),
        VerseSearchNote(text: "BLA — BLUB.\nLÖWE heißt Straße.", verseIDs: [6]),
        VerseSearchNote(text: "blabla blubber", verseIDs: [3]),
        VerseSearchNote(text: "bla", verseIDs: [3]),
        VerseSearchNote(text: "blub", verseIDs: [3])
    ]

    func testOrdinarySearchIncludesNotesAndReturnsDistinctVersesInBibleOrder() {
        assertSearch("bla", [0, 1, 2, 3, 5, 6])
        assertSearch("bla blub", [0, 1, 2, 3, 5, 6])
        assertSearch("blabla", [3])
        assertSearch("waters note:bla", [1])
        let result = bible.search("bla", notes: notes)
        let text = bible.text(for: result.passages)
        XCTAssertTrue(text.contains("Genesis 1:2 (Fixture)\n1:2 Quiet waters."))
        XCTAssertFalse(text.contains("1:5"), "Omitted verses and invalid note IDs must not become matches")
    }

    func testNoteTagRestrictsWordsAndPhrasesToNotes() {
        assertSearch("note:bla", [1, 2, 3, 5, 6])
        assertSearch("NOTE:BLA", [1, 2, 3, 5, 6])
        assertSearch("\"bla blub\"", [0, 1, 2, 6])
        assertSearch("note:\"bla blub\"", [1, 2, 6])
        assertSearch("note:“BLA BLUB”", [1, 2, 6])
        assertSearch("note:blabla", [3])
        assertSearch("note:\"bla bla\"", [])
        assertSearch("note:löwe note:STRASSE", [6])
        assertSearch("note:lo\u{308}we", [6])
        XCTAssertTrue(bible.search("note:bla").passages.isEmpty)
    }

    func testNotesUseExistingWildcardsExclusionsAndBookFilters() {
        assertSearch("note:blab*", [3])
        assertSearch("note:*lab*", [3])
        assertSearch("note:\"b*a b*b\"", [1, 2, 6])
        assertSearch("note:bla book:gen", [1, 2, 3])
        assertSearch("note:bla book:gen book:ps", [1, 2, 3, 5])
        assertSearch("note:bla in:nt", [6])
        assertSearch("note:bla -book:gen", [5, 6])
        assertSearch("note:bla -note:\"bla blub\"", [3, 5])
        assertSearch("bla -note:\"bla blub\"", [0, 3, 5])
        assertSearch("bla -blub", [])
    }

    func testIncompleteNoteSyntaxAndReferenceRouting() {
        for query in ["note:", "note:\"bla blub", "bla note:"] {
            let result = BibleLookupEngine(bible: bible).lookup(query, notes: notes)
            XCTAssertTrue(result.isSearch, query)
            XCTAssertTrue(result.isIncomplete, query)
            XCTAssertNil(result.error, query)
            XCTAssertNotNil(result.hint, query)
            XCTAssertFalse(result.canCopy, query)
        }
        XCTAssertTrue(bible.search("note:", notes: notes).passages.isEmpty)
        let reference = BibleLookupEngine(bible: bible).lookup("gen1:1", notes: notes)
        XCTAssertFalse(reference.isSearch)
        XCTAssertEqual(reference.passages.map(\.range.lowerBound), [0])
    }

    private func assertSearch(_ query: String, _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        let result = BibleLookupEngine(bible: bible).lookup(query, notes: notes)
        XCTAssertTrue(result.isSearch, query, file: file, line: line)
        XCTAssertNil(result.error, query, file: file, line: line)
        XCTAssertEqual(result.passages.map(\.range.lowerBound), expected, query, file: file, line: line)
        XCTAssertEqual(result.canCopy, !expected.isEmpty, query, file: file, line: line)
    }
}
