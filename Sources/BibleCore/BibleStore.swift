import Foundation

public struct VerseAddress: Hashable, Sendable {
    public let book: Int
    public let chapter: Int
    public let verse: Int
}

public struct BibleVerse: Identifiable, Sendable {
    public let id: Int
    public let address: VerseAddress
    public let text: String
    public var book: BibleBook { BibleBook.all[address.book] }
    /// Some traditional verse numbers have no text in this NET edition.
    public var isOmitted: Bool { text.isEmpty }
}

public struct BiblePassage: Identifiable, Sendable {
    public let range: Range<Int>
    public let reference: String
    public var id: String { "\(range.lowerBound)-\(range.upperBound)" }
    public var count: Int { range.count }
}

public enum BibleDataError: LocalizedError {
    case missingResource
    case invalidData(String)
    public var errorDescription: String? {
        switch self {
        case .missingResource: return "The bundled NET Bible text could not be found. Rebuild the app with scripts/build-app.sh."
        case .invalidData(let reason): return "The NET Bible text is incomplete or damaged: \(reason)"
        }
    }
}

/// An immutable, in-memory address index, built once. Lookup is a dictionary
/// access plus a slice of the canonical verse array, never a scan of the Bible.
public final class BibleStore: Sendable {
    public static let copyright = "Scripture quoted by permission. Quotations designated (NET) are from the NET Bible® copyright ©1996, 2019 by Biblical Studies Press, L.L.C. https://netbible.com. All rights reserved."
    public let verses: [BibleVerse]
    public let chapterCount: Int
    private let addresses: [VerseAddress: Int]
    private let chapters: [[Range<Int>]]

    public static func bundled() throws -> BibleStore {
        // The .app ships a plain resource; SwiftPM supplies its resource bundle
        // for `swift run` and tests. Neither route ever downloads anything.
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        let url = bundle.url(forResource: "NETBible", withExtension: "txt")
        guard let url else { throw BibleDataError.missingResource }
        return try BibleStore(text: String(contentsOf: url, encoding: .utf8))
    }

    public init(text: String) throws {
        let byCode = Dictionary(uniqueKeysWithValues: BibleBook.all.map { ($0.code, $0.id) })
        var verses: [BibleVerse] = []
        var addresses: [VerseAddress: Int] = [:]
        var chapters = Array(repeating: [Range<Int>](), count: 66)
        verses.reserveCapacity(31_102)
        addresses.reserveCapacity(31_102)
        var previous: VerseAddress?
        for line in text.split(whereSeparator: \.isNewline) {
            let pieces = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard pieces.count == 3, let book = byCode[String(pieces[0])] else {
                throw BibleDataError.invalidData("unrecognized verse record")
            }
            let location = pieces[1].split(separator: ":")
            guard location.count == 2, let chapter = Int(location[0]), let verse = Int(location[1]),
                  chapter > 0, verse > 0 else {
                throw BibleDataError.invalidData("invalid verse address")
            }
            let address = VerseAddress(book: book, chapter: chapter, verse: verse)
            if let previous {
                guard book > previous.book || (book == previous.book &&
                    (chapter > previous.chapter || (chapter == previous.chapter && verse > previous.verse))) else {
                    throw BibleDataError.invalidData("duplicate or out-of-order verse")
                }
            }
            if chapter > chapters[book].count {
                guard chapter == chapters[book].count + 1 else {
                    throw BibleDataError.invalidData("missing chapter in \(BibleBook.all[book].name)")
                }
                chapters[book].append(verses.count..<(verses.count + 1))
            } else {
                chapters[book][chapter - 1] = chapters[book][chapter - 1].lowerBound..<(verses.count + 1)
            }
            addresses[address] = verses.count
            verses.append(BibleVerse(id: verses.count, address: address, text: String(pieces[2])))
            previous = address
        }
        guard chapters.allSatisfy({ !$0.isEmpty }), chapters.reduce(0, { $0 + $1.count }) == 1_189,
              verses.count == 31_102, verses.first?.address == VerseAddress(book: 0, chapter: 1, verse: 1),
              verses.last?.address == VerseAddress(book: 65, chapter: 22, verse: 21) else {
            throw BibleDataError.invalidData("expected 66 books, 1,189 chapters, and 31,102 verses")
        }
        self.verses = verses
        self.addresses = addresses
        self.chapters = chapters
        self.chapterCount = 1_189
    }

    public func chapterCount(in book: BibleBook) -> Int { chapters[book.id].count }
    public func chapterRange(book: BibleBook, chapter: Int) -> Range<Int>? {
        guard chapter > 0, chapter <= chapters[book.id].count else { return nil }
        return chapters[book.id][chapter - 1]
    }
    public func verseCount(book: BibleBook, chapter: Int) -> Int? {
        guard let range = chapterRange(book: book, chapter: chapter) else { return nil }
        return verses[range.upperBound - 1].address.verse
    }
    public func offset(book: BibleBook, chapter: Int, verse: Int) -> Int? {
        addresses[VerseAddress(book: book.id, chapter: chapter, verse: verse)]
    }
    public func text(for passages: [BiblePassage]) -> String {
        passages.map { passage in
            let body = verses[passage.range].map { verse in
                "\(verse.address.chapter):\(verse.address.verse) \(verse.isOmitted ? "[This verse number has no text in this NET edition.]" : verse.text)"
            }.joined(separator: "\n")
            return "\(passage.reference) (NET)\n\(body)"
        }.joined(separator: "\n\n") + "\n\n" + Self.copyright
    }
}
