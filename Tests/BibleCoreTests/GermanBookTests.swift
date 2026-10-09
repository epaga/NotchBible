import XCTest
@testable import BibleCore

final class GermanBookTests: XCTestCase {
    private static let bible = try! BibleStore(text: BibleBook.all.map {
        "\($0.code) 1:1 Gott steht in diesem Testvers.\n\($0.code) 1:2 Ein weiterer Testvers."
    }.joined(separator: "\n"), translation: "GermanFixture", requiresCompleteBible: false)

    func testLanguageDetectionUsesTheWholeWordRegardlessOfCaseOrTranslationName() throws {
        for text in ["Gott", "GOTT", "gott", "Gott, hier."] {
            let bible = try BibleStore(text: "GEN 1:1 \(text)", translation: "Sample", requiresCompleteBible: false)
            XCTAssertEqual(bible.books[0].name, "1. Mose", text)
        }
        for text in ["God", "Gottfried", "Gottes", "Ein Testvers."] {
            let bible = try BibleStore(text: "GEN 1:1 \(text)", translation: "German", requiresCompleteBible: false)
            XCTAssertEqual(bible.books[0].name, "Genesis", text)
        }
    }

    func testEveryGermanBookNameAndEnglishNameResolveToTheSameAddress() {
        let bible = Self.bible
        let lookup = BibleLookupEngine(bible: bible)
        XCTAssertEqual(bible.books.map(\.code), BibleBook.all.map(\.code))
        for book in bible.books {
            for name in [book.name, BibleBook.all[book.id].name] {
                let result = lookup.lookup("\(name) 1:1")
                XCTAssertFalse(result.isSearch, name)
                XCTAssertNil(result.error, name)
                XCTAssertTrue(result.canCopy, name)
                XCTAssertEqual(result.passages.map(\.range), [(book.id * 2)..<(book.id * 2 + 1)], name)
                XCTAssertEqual(result.passages.map(\.reference), ["\(book.name) 1:1"], name)
            }
        }
    }

    func testMosesAbbreviationsPunctuationListsAndSuggestions() {
        let lookup = BibleLookupEngine(bible: Self.bible)
        for ordinal in 1...5 {
            for name in ["\(ordinal)Mo", "\(ordinal).Mo", "\(ordinal). Mo", "\(ordinal). Mose", "\(ordinal) Mose"] {
                let result = lookup.lookup("\(name)1:1")
                XCTAssertFalse(result.isSearch, name)
                XCTAssertNil(result.error, name)
                XCTAssertEqual(result.passages.map(\.reference), ["\(ordinal). Mose 1:1"], name)
            }
            let suggestion = lookup.lookup("\(ordinal)Mo").suggestions.first
            XCTAssertEqual(suggestion?.book.name, "\(ordinal). Mose")
            XCTAssertEqual(suggestion?.query, "\(ordinal). Mose 1:1")
            XCTAssertTrue(lookup.lookup(String(ordinal)).suggestions.contains { $0.book.name == "\(ordinal). Mose" })
        }
        let list = lookup.lookup("1.Mo1:1-2;4. Mose1:2 + 5Mo1:1")
        XCTAssertNil(list.error)
        XCTAssertEqual(list.passages.map(\.reference), ["1. Mose 1:1–2", "4. Mose 1:2", "5. Mose 1:1"])
        XCTAssertEqual(list.verseCount, 4)
        XCTAssertTrue(Self.bible.text(for: list.passages).hasPrefix("1. Mose 1:1–2 (GermanFixture)"))
        XCTAssertTrue(lookup.lookup("5Mo99:1").error?.contains("5. Mose") == true)
    }

    func testCommonAbbreviationsUmlautsAndAsciiSpellings() {
        let lookup = BibleLookupEngine(bible: Self.bible)
        let examples = [
            ("Ri", "Richter"), ("Hi", "Hiob"), ("Spr", "Sprüche"), ("Sprueche", "Sprüche"),
            ("Pred", "Prediger"), ("Hld", "Hohelied"), ("Jes", "Jesaja"), ("Hes", "Hesekiel"),
            ("Klgl", "Klagelieder"), ("Sach", "Sacharja"), ("Mt", "Matthäus"), ("Matthaeus", "Matthäus"),
            ("Mk", "Markus"), ("Lk", "Lukas"), ("Joh", "Johannes"), ("Apg", "Apostelgeschichte"),
            ("Röm", "Römer"), ("Roem", "Römer"), ("Roemer", "Römer"), ("1.Kön", "1. Könige"),
            ("1. Koenige", "1. Könige"), ("2Kor", "2. Korinther"), ("Kol", "Kolosser"),
            ("Hebr", "Hebräer"), ("Jak", "Jakobus"), ("1Petr", "1. Petrus"), ("Offb", "Offenbarung")
        ]
        for (name, expected) in examples {
            let result = lookup.lookup("\(name) 1:1")
            XCTAssertFalse(result.isSearch, name)
            XCTAssertNil(result.error, name)
            XCTAssertEqual(result.passages.map(\.reference), ["\(expected) 1:1"], name)
        }
    }

    func testSearchFiltersResultsAndCopyUseGermanBookNames() {
        let bible = Self.bible
        for query in ["book:1Mo Gott", "book:1.Mo Gott", "book:\"1. Mose\" Gott", "book:gen Gott"] {
            let result = BibleLookupEngine(bible: bible).lookup(query)
            XCTAssertTrue(result.isSearch, query)
            XCTAssertNil(result.error, query)
            XCTAssertEqual(result.passages.map(\.reference), ["1. Mose 1:1"], query)
            XCTAssertTrue(bible.text(for: result.passages).hasPrefix("1. Mose 1:1 (GermanFixture)"), query)
        }
        XCTAssertEqual(bible.search("book:5.Mo Gott").passages.map(\.reference), ["5. Mose 1:1"])
        XCTAssertEqual(bible.search("book:Röm Gott").passages.map(\.reference), ["Römer 1:1"])
        XCTAssertEqual(bible.search("Gott -book:1Mo").verseCount, 65)
    }
}
