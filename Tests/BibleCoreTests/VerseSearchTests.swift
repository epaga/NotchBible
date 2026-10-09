import Foundation
import XCTest
@testable import BibleCore

final class VerseSearchTests: XCTestCase {
    private static let bible = try! BibleStore(text: """
        GEN 1:1 In the beginning God created the heavens and the earth.
        GEN 1:2 For God so loved the world. Love loves loving beloved.
        GEN 1:3 God made light for all. He created it.
        GEN 1:4 Godly creation is lovely; the world loves darkness.
        GEN 1:5 God, for ever. Love is kind.
        GEN 1:6 God for God.
        GEN 1:7
        GEN 1:8 GOD — created. LÖWE heißt Straße.
        PSA 1:1 God created a clean heart.
        PSA 1:2 For the love of God.
        MAT 1:1 For God created hope and love.
        MAT 1:2 The world hated love.
        JOH 1:1 God created love.
        1JO 1:1 God is love.
        """.replacingOccurrences(of: "GEN 1:7\n", with: "GEN 1:7 \n"),
        translation: "Fixture", requiresCompleteBible: false)
    private let bible = VerseSearchTests.bible

    func testWordsAreCaseInsensitiveWholeWordsAndedWithinAVerse() {
        assertSearch("created God", ["GEN1:1", "GEN1:3", "GEN1:8", "PSA1:1", "MAT1:1", "JOH1:1"])
        assertSearch("CREATED gOd created", ["GEN1:1", "GEN1:3", "GEN1:8", "PSA1:1", "MAT1:1", "JOH1:1"])
        assertSearch("God world", ["GEN1:2"])
        assertSearch("love", ["GEN1:2", "GEN1:5", "PSA1:2", "MAT1:1", "MAT1:2", "JOH1:1", "1JO1:1"])
        assertSearch("doesnotexist", [])
        assertSearch("löwe STRASSE", ["GEN1:8"])
        assertSearch("lo\u{308}we", ["GEN1:8"])
        assertSearch("ＧＯＤ created", ["GEN1:1", "GEN1:3", "GEN1:8", "PSA1:1", "MAT1:1", "JOH1:1"])
    }

    func testPhrasesRequireConsecutiveWordsInOrder() {
        assertSearch("\"for God\"", ["GEN1:2", "GEN1:6", "MAT1:1"])
        assertSearch("“FOR GOD”", ["GEN1:2", "GEN1:6", "MAT1:1"])
        assertSearch("\"God created\"", ["GEN1:1", "GEN1:8", "PSA1:1", "MAT1:1", "JOH1:1"])
        assertSearch("\"God God\"", [])
        assertSearch("\"God for God\"", ["GEN1:6"])
        assertSearch("\"for God\" created", ["MAT1:1"])
    }

    func testExclusionsAndWildcardWords() {
        assertSearch("love -world", ["GEN1:5", "PSA1:2", "MAT1:1", "JOH1:1", "1JO1:1"])
        assertSearch("God -\"for God\" -created", ["GEN1:5", "PSA1:2", "1JO1:1"])
        assertSearch("love*", ["GEN1:2", "GEN1:4", "GEN1:5", "PSA1:2", "MAT1:1", "MAT1:2", "JOH1:1", "1JO1:1"])
        assertSearch("*love*", ["GEN1:2", "GEN1:4", "GEN1:5", "PSA1:2", "MAT1:1", "MAT1:2", "JOH1:1", "1JO1:1"])
        assertSearch("l*ing", ["GEN1:2"])
        assertSearch("l*v*", ["GEN1:2", "GEN1:4", "GEN1:5", "PSA1:2", "MAT1:1", "MAT1:2", "JOH1:1", "1JO1:1"])
        assertSearch("\"for G*\"", ["GEN1:2", "GEN1:6", "MAT1:1"])
        assertSearch("love* -lovel*", ["GEN1:2", "GEN1:5", "PSA1:2", "MAT1:1", "MAT1:2", "JOH1:1", "1JO1:1"])
        assertSearch("*notaword*", [])
        assertSearch("-God", ["GEN1:4", "MAT1:2"])
        XCTAssertEqual(bible.search("*").verseCount, bible.verses.count - 1)
        XCTAssertEqual(bible.search("**").verseCount, bible.verses.count - 1)
        XCTAssertFalse(bible.search("*").passages.contains { bible.verses[$0.range.lowerBound].isOmitted })
    }

    func testRepeatedTagsAreOrGroupsAndDifferentTagsAreAnded() {
        assertSearch("book:gen book:ps created God", ["GEN1:1", "GEN1:3", "GEN1:8", "PSA1:1"])
        assertSearch("BOOK:Genesis book:PSALMS in:OT God created", ["GEN1:1", "GEN1:3", "GEN1:8", "PSA1:1"])
        assertSearch("book:gen book:ps in:nt God", [])
        assertSearch("book:gen book:john in:nt created God", ["JOH1:1"])
        assertSearch("in:ot in:nt created God", ["GEN1:1", "GEN1:3", "GEN1:8", "PSA1:1", "MAT1:1", "JOH1:1"])
        assertSearch("in:nt in:nt love", ["MAT1:1", "MAT1:2", "JOH1:1", "1JO1:1"])
        assertSearch("book:\"1 John\" love", ["1JO1:1"])
        assertSearch("in:\"New Testament\" -book:mat created", ["JOH1:1"])
        assertSearch("created -in:ot", ["MAT1:1", "JOH1:1"])
        assertSearch("love -book:gen -book:ps", ["MAT1:1", "MAT1:2", "JOH1:1", "1JO1:1"])
        assertSearch("in:ot -in:ot", [])
        assertSearch("book:gen book:gen created", ["GEN1:1", "GEN1:3", "GEN1:8"])
        XCTAssertEqual(bible.search("book:gen").verseCount, 7)
    }

    func testIncompleteAndInvalidSearchSyntax() {
        for query in ["\"for God", "love -", "love book:", "love in:"] {
            let result = bible.search(query)
            XCTAssertTrue(result.isIncomplete, query)
            XCTAssertNil(result.error, query)
            XCTAssertNotNil(result.hint, query)
            XCTAssertFalse(result.canCopy, query)
            XCTAssertFalse(result.passages.isEmpty, query)
        }
        for query in ["book:notabook love", "book:ph love", "in:maybe", "other:value", String(repeating: "x", count: 2_049)] {
            let result = bible.search(query)
            XCTAssertNotNil(result.error, query)
            XCTAssertFalse(result.canCopy, query)
            XCTAssertTrue(result.passages.isEmpty, query)
        }
        for query in ["", "   ", "-", "book:", "\""] {
            XCTAssertTrue(bible.search(query).passages.isEmpty, query)
        }
        XCTAssertNotNil(bible.search("notaword").hint)
    }

    func testFallbackPreservesReferencesButDoesNotTurnSearchWordsIntoTypos() {
        let lookup = BibleLookupEngine(bible: bible)
        for query in ["gen1,1", "Genesis 1:1", "genisis1:1", "gen1:1;ps1:1"] {
            let result = lookup.lookup(query)
            XCTAssertFalse(result.isSearch, query)
            XCTAssertTrue(result.canCopy, query)
        }
        for query in ["gen1:", "gen1:1-"] {
            XCTAssertTrue(lookup.lookup(query).isIncomplete, query)
            XCTAssertFalse(lookup.lookup(query).isSearch, query)
        }
        for query in ["gen999", "gen1:1 nonsense"] {
            XCTAssertNotNil(lookup.lookup(query).error, query)
            XCTAssertFalse(lookup.lookup(query).isSearch, query)
        }
        XCTAssertFalse(lookup.lookup("ph1:1").suggestions.isEmpty)
        XCTAssertFalse(lookup.lookup("gen").suggestions.isEmpty)
        for query in ["created God", "sons", "\"John\"", "love*", "book:gen love", "in:nt"] {
            XCTAssertTrue(lookup.lookup(query).isSearch, query)
            XCTAssertTrue(lookup.lookup(query).suggestions.isEmpty, query)
        }
        let copy = bible.text(for: lookup.lookup("book:gen created God").passages)
        XCTAssertTrue(copy.contains("Genesis 1:1 (Fixture)"))
        XCTAssertTrue(copy.contains("Genesis 1:3 (Fixture)"))
        XCTAssertTrue(copy.contains("Genesis 1:8 (Fixture)"))
        XCTAssertFalse(copy.contains("Psalms"))
    }

    func testEveryBundledTranslationAgreesWithIndependentTextScan() throws {
        let library = try BibleLibrary.bundled()
        let created = try NSRegularExpression(pattern: #"\bcreated\b"#, options: .caseInsensitive)
        let god = try NSRegularExpression(pattern: #"\bgod\b"#, options: .caseInsensitive)
        let phrase = try NSRegularExpression(pattern: #"\bfor\W+god\b"#, options: .caseInsensitive)
        for bible in library.translations {
            func contains(_ expression: NSRegularExpression, _ verse: BibleVerse) -> Bool {
                expression.firstMatch(in: verse.text, range: NSRange(verse.text.startIndex..., in: verse.text)) != nil
            }
            let expected = bible.verses.filter {
                [0, 18].contains($0.address.book) && contains(created, $0) && contains(god, $0)
            }.map(\.id)
            XCTAssertEqual(bible.search("book:gen book:ps created God").passages.map { $0.range.lowerBound }, expected, bible.translation)
            let phrases = bible.verses.filter { contains(phrase, $0) }.map(\.id)
            XCTAssertEqual(bible.search("\"for God\"").passages.map { $0.range.lowerBound }, phrases, bible.translation)
        }
    }

    private func assertSearch(_ query: String, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let result = BibleLookupEngine(bible: bible).lookup(query)
        XCTAssertTrue(result.isSearch, query, file: file, line: line)
        XCTAssertNil(result.error, query, file: file, line: line)
        let addresses = result.passages.map { passage in
            let verse = bible.verses[passage.range.lowerBound]
            return "\(verse.book.code)\(verse.address.chapter):\(verse.address.verse)"
        }
        XCTAssertEqual(addresses, expected, query, file: file, line: line)
        XCTAssertEqual(result.canCopy, !expected.isEmpty, query, file: file, line: line)
    }
}
