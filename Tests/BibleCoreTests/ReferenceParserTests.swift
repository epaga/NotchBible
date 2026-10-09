import XCTest
@testable import BibleCore

final class ReferenceParserTests: XCTestCase {
    private static let bible = try! BibleStore.bundled()
    private let parser = ReferenceParser(bible: bible)

    func testRequestedExamples() {
        for input in ["gen1,1", "Genesis 1:1", "Gen1.1", "Gen 1:1", "Gen. 1:1"] {
            assertPassage(input, reference: "Genesis 1:1", count: 1)
        }
        for input in ["genes 1:1-2:3", "gen1.1-2.3", "gen1:1-2:3"] {
            assertPassage(input, reference: "Genesis 1:1–2:3", count: 34)
        }
        let result = parser.lookup("gen1.1;4:4-5")
        XCTAssertNil(result.error)
        XCTAssertEqual(result.passages.map(\.reference), ["Genesis 1:1", "Genesis 4:4–5"])
        XCTAssertEqual(result.verseCount, 3)
    }

    func testPunctuationAndNaturalShorthand() {
        for input in ["GEN1:1", "ge 1.1", "gn1/1", "Genesis 1 1", "Gen.1,1", "gen 1 : 1",
                      "gen chapter 1 verse 1", "gen ch.1 v.1", "gen c1v1", "gen1v1",
                      "(Genesis 1:1)", "[Gen 1:1]", "Genesis 1:1 (NET)", "see Gen 1:1",
                      "cf. Gen 1:1", "Ｇｅｎ１：１", "Gen 1∶1", "gen1·1", "book of Genesis 1:1"] {
            assertPassage(input, reference: "Genesis 1:1", count: 1)
        }
        for input in ["Gen1:1–3", "Gen1.1—3", "gen1,1-3", "gen1:1 to 3", "gen1:1 through 3",
                      "gen1:1 thru 3", "gen1 1 - 3", "gen1:1−3"] {
            assertPassage(input, reference: "Genesis 1:1–3", count: 3)
        }
    }

    func testNumberedAndSingleChapterBooks() {
        for input in ["1John1:1", "1 Jn 1.1", "1.John1:1", "IJohn1:1", "I John 1:1", "I. John 1:1", "First John 1:1", "1st John 1:1", "firstjohn1:1"] {
            assertPassage(input, reference: "1 John 1:1", count: 1)
        }
        for input in ["II Corinthians 5:17", "Second Cor5:17", "2nd Cor 5:17", "2Cor5.17"] {
            assertPassage(input, reference: "2 Corinthians 5:17", count: 1)
        }
        assertPassage("III John 4", reference: "3 John 1:4", count: 1)
        assertPassage("IIIJohn4", reference: "3 John 1:4", count: 1)
        assertPassage("thirdjohn4", reference: "3 John 1:4", count: 1)
        assertPassage("Jude5-7", reference: "Jude 1:5–7", count: 3)
        assertPassage("Phm 4", reference: "Philemon 1:4", count: 1)
        assertPassage("Obadiah 3", reference: "Obadiah 1:3", count: 1)
        assertPassage("2jn1:1-13", reference: "2 John 1:1–13", count: 13)
        // Roman numeral normalization must not damage Isaiah or other names.
        assertPassage("Isaiah1:1", reference: "Isaiah 1:1", count: 1)
        assertPassage("Isa1:1", reference: "Isaiah 1:1", count: 1)
        assertPassage("Ec1:1", reference: "Ecclesiastes 1:1", count: 1)
    }

    func testChapterRangesAndLists() {
        assertPassage("Psalm23", reference: "Psalms 23", count: 6)
        assertPassage("Ps119", reference: "Psalms 119", count: 176)
        assertPassage("Gen1-2", reference: "Genesis 1–2", count: 56)
        assertPassage("Gen1:31-2:3", reference: "Genesis 1:31–2:3", count: 4)
        assertPassage("Gen1,31-2,3", reference: "Genesis 1:31–2:3", count: 4)
        assertPassage("Gen1-2:3", reference: "Genesis 1–2:3", count: 34)
        let verses = parser.lookup("John3:16,18-20,22")
        XCTAssertNil(verses.error)
        XCTAssertEqual(verses.passages.map(\.reference), ["John 3:16", "John 3:18–20", "John 3:22"])
        XCTAssertEqual(verses.verseCount, 5)
        let chapters = parser.lookup("gen1,3,5")
        // The first comma in a coordinate pair is intentionally a colon.
        XCTAssertEqual(chapters.passages.map(\.reference), ["Genesis 1:3", "Genesis 1:5"])
        let list = parser.lookup("gen1;3;5")
        XCTAssertEqual(list.passages.map(\.reference), ["Genesis 1", "Genesis 3", "Genesis 5"])
        for separator in [";", " & ", " + ", " | ", " and ", "\n", " ", ", "] {
            let result = parser.lookup("gen1:1\(separator)John3:16")
            XCTAssertNil(result.error, "\(separator)")
            XCTAssertEqual(result.passages.map(\.reference), ["Genesis 1:1", "John 3:16"], "\(separator)")
        }
        let inherited = parser.lookup("gen1:1;4:4-5;John3:16;5:1")
        XCTAssertEqual(inherited.passages.map(\.reference), ["Genesis 1:1", "Genesis 4:4–5", "John 3:16", "John 5:1"])
        XCTAssertEqual(parser.lookup("gen1:1;gen1:1").verseCount, 1)
        XCTAssertEqual(parser.lookup("Gen1:1 John3:16 Rom8:28").passages.map(\.reference), ["Genesis 1:1", "John 3:16", "Romans 8:28"])
    }

    func testPrefixesTyposAndAmbiguity() {
        assertPassage("genes1:1", reference: "Genesis 1:1", count: 1)
        assertPassage("genisis1:1", reference: "Genesis 1:1", count: 1)
        assertPassage("genseis1:1", reference: "Genesis 1:1", count: 1)
        assertPassage("revelations22:21", reference: "Revelation 22:21", count: 1)
        assertPassage("Song of Songs2:1", reference: "Song of Solomon 2:1", count: 1)
        assertPassage("Canticles2:1", reference: "Song of Solomon 2:1", count: 1)
        let ambiguous = parser.lookup("ph1:1")
        XCTAssertNil(ambiguous.error)
        XCTAssertTrue(ambiguous.passages.isEmpty)
        XCTAssertEqual(ambiguous.suggestions.map(\.book.name), ["Philippians", "Philemon"])
        XCTAssertEqual(ambiguous.suggestions.map(\.query), ["Philippians 1:1", "Philemon 1:1"])
        XCTAssertFalse(ambiguous.canCopy)
        let listChoice = parser.lookup("gen1:1;ph1:1;John3:16").suggestions
        XCTAssertEqual(listChoice.count, 2)
        XCTAssertEqual(parser.lookup(listChoice[0].query).passages.map(\.reference),
                       ["Genesis 1:1", "Philippians 1:1", "John 3:16"])
        XCTAssertGreaterThan(parser.lookup("j1:1").suggestions.count, 1)
        XCTAssertTrue(parser.lookup("gen").suggestions.contains { $0.book.name == "Genesis" })
        XCTAssertTrue(parser.lookup("1").suggestions.contains { $0.book.name == "1 John" })
    }

    func testPlusSeparatesVersesWithInheritedChapter() {
        for input in ["heb13.7+13", "Hebrews 13:7 + 13", "heb13,7+13", "Ｈｅｂ１３．７＋１３"] {
            let result = parser.lookup(input)
            XCTAssertNil(result.error, input)
            XCTAssertEqual(result.passages.map(\.reference), ["Hebrews 13:7", "Hebrews 13:13"], input)
            XCTAssertEqual(result.verseCount, 2, input)
            XCTAssertTrue(result.canCopy, input)
        }
        for input in ["heb13.7+13+17-18", "heb13.7+13,17-18"] {
            let result = parser.lookup(input)
            XCTAssertNil(result.error, input)
            XCTAssertEqual(result.passages.map(\.reference), ["Hebrews 13:7", "Hebrews 13:13", "Hebrews 13:17–18"], input)
            XCTAssertEqual(result.verseCount, 4, input)
        }
        for input in ["heb13.7+13+John3:16", "heb13.7+13 John3:16"] {
            let result = parser.lookup(input)
            XCTAssertNil(result.error, input)
            XCTAssertEqual(result.passages.map(\.reference), ["Hebrews 13:7", "Hebrews 13:13", "John 3:16"], input)
        }
        XCTAssertEqual(parser.lookup("John3:16+4:2+4").passages.map(\.reference),
                       ["John 3:16", "John 4:2", "John 4:4"])
        XCTAssertEqual(parser.lookup("gen1+3").passages.map(\.reference), ["Genesis 1", "Genesis 3"])
        XCTAssertEqual(parser.lookup("heb13.7+13+1 John1:1").passages.map(\.reference),
                       ["Hebrews 13:7", "Hebrews 13:13", "1 John 1:1"])
        let incomplete = parser.lookup("heb13.7+")
        XCTAssertNil(incomplete.error)
        XCTAssertEqual(incomplete.passages.map(\.reference), ["Hebrews 13:7"])
        XCTAssertTrue(incomplete.isIncomplete)
        XCTAssertFalse(incomplete.canCopy)
        for input in ["heb13.7++13", "heb13.7+99"] {
            XCTAssertNotNil(parser.lookup(input).error, input)
            XCTAssertFalse(parser.lookup(input).canCopy, input)
        }
    }

    func testIncompleteTypingAndInvalidSuffixes() {
        XCTAssertTrue(parser.lookup("").passages.isEmpty)
        for input in ["Gen1:", "Gen1.", "Gen1/", "Gen1:1-", "Gen1:1;", "Gen1:1,"] {
            let result = parser.lookup(input)
            XCTAssertNil(result.error, input)
            XCTAssertFalse(result.passages.isEmpty, input)
            XCTAssertTrue(result.isIncomplete, input)
            XCTAssertFalse(result.canCopy, input)
        }
        for input in ["Gen0", "Gen51", "Gen1:0", "Gen1:32", "Gen2:3-1:1", "Gen1:3-1",
                      "Gen1:1;99:1", "Gen1:1 nonsense", "Gen1:1--3", "notabook1:1",
                      "1:1", "Gen999999999999999999999999999999", "Gen1:1;;2:1"] {
            let result = parser.lookup(input)
            XCTAssertNotNil(result.error, input)
            XCTAssertFalse(result.canCopy, input)
        }
        XCTAssertNotNil(parser.lookup(String(repeating: "x", count: 2_049)).error)
    }

    func testFullCanonicalTextAndEveryAddress() {
        XCTAssertEqual(Self.bible.verses.count, 31_102)
        XCTAssertEqual(Self.bible.chapterCount, 1_189)
        XCTAssertEqual(Self.bible.verses.filter(\.isOmitted).count, 17)
        XCTAssertEqual(Self.bible.verses.first?.text, "In the beginning God created the heavens and the earth.")
        XCTAssertEqual(Self.bible.verses.last?.text, "The grace of the Lord Jesus be with all.")
        for verse in Self.bible.verses {
            let input = "\(verse.book.name) \(verse.address.chapter):\(verse.address.verse)"
            let result = parser.lookup(input)
            guard result.error == nil, result.passages.first?.range == verse.id..<(verse.id + 1) else {
                XCTFail("Failed canonical reference: \(input), error: \(result.error ?? "none")")
                return
            }
        }
    }

    func testCopyIncludesReferenceTranslationAndAttribution() {
        let passages = parser.lookup("gen1:1;John3:16").passages
        let copy = Self.bible.text(for: passages)
        XCTAssertTrue(copy.hasPrefix("Genesis 1:1 (NET)\n1:1 In the beginning"))
        XCTAssertTrue(copy.contains("John 3:16 (NET)"))
        XCTAssertTrue(copy.hasSuffix(BibleStore.copyright))
        let omitted = parser.lookup("Matt17:21").passages
        XCTAssertTrue(Self.bible.text(for: omitted).contains("[This verse number has no text in this NET edition.]"))
    }

    func testCorruptedDataFailsRatherThanUsingPartialBible() {
        XCTAssertThrowsError(try BibleStore(text: "GEN 1:1 Example"))
        XCTAssertThrowsError(try BibleStore(text: "UNKNOWN 1:1 Example"))
        XCTAssertThrowsError(try BibleStore(text: "GEN 1:1 Example\nGEN 1:1 Duplicate"))
        XCTAssertThrowsError(try BibleStore(text: "GEN 2:1 Missing chapter"))
    }

    private func assertPassage(_ input: String, reference: String, count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let result = parser.lookup(input)
        XCTAssertNil(result.error, input, file: file, line: line)
        XCTAssertEqual(result.passages.map(\.reference), [reference], input, file: file, line: line)
        XCTAssertEqual(result.verseCount, count, input, file: file, line: line)
        XCTAssertTrue(result.canCopy, input, file: file, line: line)
    }
}
