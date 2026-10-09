import Foundation

public struct ReferenceSuggestion: Identifiable, Sendable {
    public let book: BibleBook
    public let query: String
    public var id: Int { book.id }
}

public struct ReferenceLookup: Sendable {
    public var passages: [BiblePassage] = []
    public var suggestions: [ReferenceSuggestion] = []
    public var hint: String?
    public var error: String?
    public var isIncomplete = false
    public var isSearch = false
    public var verseCount: Int { passages.reduce(0) { $0 + $1.count } }
    public var canCopy: Bool { !passages.isEmpty && error == nil && !isIncomplete }
    public init() {}
}

/// A tolerant reference grammar, not a text search. Common punctuation,
/// abbreviations, prefixes, small misspellings, ordinals, and shorthand are
/// normalized before parsing. No debounce and no network are needed.
public final class ReferenceParser: Sendable {
    public let bible: BibleStore
    private let books: BookIndex
    public init(bible: BibleStore) {
        self.bible = bible
        self.books = BookIndex(books: bible.books)
    }

    func recognizesReference(_ input: String) -> Bool {
        // Quotes and wildcards explicitly select search, even for book names.
        guard input.count <= 2_048, !input.contains(where: { "\"“”*".contains($0) }) else { return false }
        let normalized = Self.normalize(input)
        if ["1", "2", "3", "4", "5"].contains(normalized) { return !books.resolve(normalized).books.isEmpty }
        guard let match = Self.bookPrefix.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let nameRange = Range(match.range(at: 1), in: normalized) else { return false }
        let resolution = books.resolve(String(normalized[nameRange]))
        guard !resolution.books.isEmpty else { return false }
        let rest = normalized.dropFirst(match.range.length).trimmingCharacters(in: .whitespaces)
        // Bare fuzzy matches (e.g. “sons” → Song of Solomon) are search words.
        return rest.isEmpty ? !resolution.corrected : rest.first?.isNumber == true
    }

    public func lookup(_ input: String) -> ReferenceLookup {
        var result = ReferenceLookup()
        guard input.count <= 2_048 else {
            result.error = "That reference is too long. Try a shorter passage list."
            return result
        }
        let normalized = Self.normalize(input)
        guard !normalized.isEmpty else { return result }
        var currentBook: BibleBook?
        var seen = Set<Range<Int>>()
        let segments = normalized.components(separatedBy: ";")
        for (segmentIndex, raw) in segments.enumerated() {
            var rest = raw.trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                if segmentIndex == segments.count - 1 {
                    result.isIncomplete = true
                    result.hint = "Add another reference after the separator."
                    continue
                }
                result.error = "Add a reference between the separators."
                return result
            }
            if let match = Self.bookPrefix.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
               let nameRange = Range(match.range(at: 1), in: rest) {
                let name = String(rest[nameRange])
                let resolution = books.resolve(name)
                rest = String(rest.dropFirst(match.range.length)).trimmingCharacters(in: .whitespaces)
                guard !resolution.books.isEmpty else {
                    result.error = "No book matches “\(name.trimmingCharacters(in: .whitespaces))”. Try Genesis, John, or Psalms."
                    return result
                }
                if resolution.books.count > 1 || rest.isEmpty {
                    result.suggestions = resolution.books.map {
                        var completed = segments
                        completed[segmentIndex] = "\($0.name) \(rest.isEmpty ? "1:1" : rest)"
                        return ReferenceSuggestion(book: $0, query: completed.joined(separator: "; "))
                    }
                    result.hint = resolution.corrected ? "Choose the book you meant." : "Choose a book, or keep typing."
                    return result
                }
                currentBook = resolution.books[0]
                if resolution.corrected { result.hint = "Showing \(resolution.books[0].name)." }
            } else if currentBook == nil {
                // An ordinal alone is a useful prefix while entering 1 John.
                if ["1", "2", "3", "4", "5"].contains(rest), !books.resolve(rest).books.isEmpty {
                    result.suggestions = books.resolve(rest).books.map {
                        ReferenceSuggestion(book: $0, query: "\($0.name) 1:1")
                    }
                    return result
                }
                result.error = "Start with a book name, such as Gen 1:1."
                return result
            }
            guard let book = currentBook else { return result }
            var listChapter: Int?
            var verseList = false
            while !rest.isEmpty {
                do {
                    let start = try readPoint(&rest, inheritedChapter: verseList ? listChapter : nil,
                                              commaIsCoordinate: !verseList, book: book)
                    var end = start
                    var rangeGiven = false
                    rest = rest.trimmingCharacters(in: .whitespaces)
                    if rest.first == "-" {
                        rangeGiven = true
                        rest.removeFirst()
                        rest = rest.trimmingCharacters(in: .whitespaces)
                        if rest.isEmpty {
                            result.isIncomplete = true
                            result.hint = "Keep typing to finish the range."
                        } else {
                            end = try readPoint(&rest, inheritedChapter: start.verse == nil ? nil : start.chapter,
                                                commaIsCoordinate: start.verse == nil || start.commaCoordinates, book: book)
                        }
                    }
                    let passage = try makePassage(book: book, start: start, end: end, rangeGiven: rangeGiven)
                    if seen.insert(passage.range).inserted { result.passages.append(passage) }
                    listChapter = end.chapter
                    verseList = end.verse != nil
                    rest = rest.trimmingCharacters(in: .whitespaces)
                    if rest.isEmpty { break }
                    guard rest.first == "," || rest.first == "+" else {
                        // A trailing colon/dot is an unfinished verse, so the
                        // chapter stays visible while the user enters a digit.
                        if [":", ".", "/"].contains(rest) {
                            result.isIncomplete = true
                            result.hint = "Add a verse number."
                            break
                        }
                        throw ParseError.message("Couldn’t read “\(rest)”. Try Gen 1:1–3 or Gen 1:1; 2:3.")
                    }
                    rest.removeFirst()
                    rest = rest.trimmingCharacters(in: .whitespaces)
                    if rest.isEmpty {
                        result.isIncomplete = true
                        result.hint = "Add another reference after the separator."
                    }
                } catch {
                    result.error = error.localizedDescription
                    return result
                }
            }
        }
        // Avoid displaying earlier selections as the result of a bad suffix.
        return result
    }

    private struct Point { let chapter: Int; let verse: Int?; var commaCoordinates = false }
    private enum ParseError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private func readPoint(_ rest: inout String, inheritedChapter: Int?, commaIsCoordinate: Bool,
                           book: BibleBook) throws -> Point {
        rest = rest.trimmingCharacters(in: .whitespaces)
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty, let first = Int(digits) else {
            throw ParseError.message("Add a chapter or verse number after \(book.name).")
        }
        rest.removeFirst(digits.count)
        let beforeTrim = rest
        rest = rest.trimmingCharacters(in: .whitespaces)
        let hadSpace = beforeTrim != rest
        let delimiters: Set<Character> = commaIsCoordinate ? [":", ".", ",", "/"] : [":", ".", "/"]
        if let delimiter = rest.first, delimiters.contains(delimiter) {
            let after = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            if after.first?.isNumber == true {
                rest = after
                let verseDigits = rest.prefix(while: \.isNumber)
                guard let verse = Int(verseDigits) else { throw ParseError.message("That verse number is too large.") }
                rest.removeFirst(verseDigits.count)
                return Point(chapter: first, verse: verse, commaCoordinates: delimiter == ",")
            }
        } else if hadSpace, rest.first?.isNumber == true {
            let verseDigits = rest.prefix(while: \.isNumber)
            guard let verse = Int(verseDigits) else { throw ParseError.message("That verse number is too large.") }
            rest.removeFirst(verseDigits.count)
            return Point(chapter: first, verse: verse)
        }
        if let inheritedChapter { return Point(chapter: inheritedChapter, verse: first) }
        if book.isSingleChapter { return Point(chapter: 1, verse: first) }
        return Point(chapter: first, verse: nil)
    }

    private func makePassage(book: BibleBook, start: Point, end: Point, rangeGiven: Bool) throws -> BiblePassage {
        func offset(_ point: Point, last: Bool) throws -> Int {
            guard let chapter = bible.chapterRange(book: book, chapter: point.chapter) else {
                if bible.chapterCount(in: book) == 0 {
                    throw ParseError.message("\(book.name) isn’t included in \(bible.translation).")
                }
                if point.chapter <= bible.chapterCount(in: book) {
                    throw ParseError.message("\(book.name) \(point.chapter) isn’t included in \(bible.translation).")
                }
                throw ParseError.message("\(book.name) has \(bible.chapterCount(in: book)) chapters.")
            }
            if let verse = point.verse {
                guard let index = bible.offset(book: book, chapter: point.chapter, verse: verse) else {
                    if verse > 0, verse <= (bible.verseCount(book: book, chapter: point.chapter) ?? 0) {
                        throw ParseError.message("\(book.name) \(point.chapter):\(verse) isn’t included in \(bible.translation).")
                    }
                    throw ParseError.message("\(book.name) \(point.chapter) has \(bible.verseCount(book: book, chapter: point.chapter) ?? 0) verses.")
                }
                return index
            }
            return last ? chapter.upperBound - 1 : chapter.lowerBound
        }
        let first = try offset(start, last: false)
        let last = try offset(end, last: true)
        guard last >= first else { throw ParseError.message("The end of a passage must come after its beginning.") }
        var reference = "\(book.name) \(start.chapter)"
        if let verse = start.verse { reference += ":\(verse)" }
        if rangeGiven && (start.chapter != end.chapter || start.verse != end.verse) {
            if start.verse == nil && end.verse == nil { reference += "–\(end.chapter)" }
            else if start.chapter == end.chapter, let verse = end.verse { reference += "–\(verse)" }
            else {
                reference += "–\(end.chapter)"
                if let verse = end.verse { reference += ":\(verse)" }
            }
        }
        return BiblePassage(range: first..<(last + 1), reference: reference)
    }

    private static let bookPrefix = try! NSRegularExpression(pattern: #"^\s*((?:[1-5]\s*)?[a-z]+(?:[.\s]+[a-z]+)*)[.\s]*"#)
    private static let replacements: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            (#"(?i)\b(?:net\s*bible|net)\s*$"#, ""),
            (#"(?i)\b(?:see|cf|book\s+of)\.?\s+"#, ""),
            (#"\b([1-5])\s*\.\s*(?=[a-z])"#, "$1"),
            (#"\biii(?=(?:john|joh|jhn|jn)(?:[.\s\d]|$))"#, "3"),
            (#"\bii(?=(?:samuel|sam|kings|kgs|chronicles|chron|corinthians|cor|thessalonians|thess|timothy|tim|peter|pet|john|joh|jhn|jn)(?:[.\s\d]|$))"#, "2"),
            (#"\bi(?=(?:samuel|sam|kings|kgs|chronicles|chron|corinthians|cor|thessalonians|thess|timothy|tim|peter|pet|john|joh|jhn|jn)(?:[.\s\d]|$))"#, "1"),
            (#"(?i)\b(?:third|3rd)\s*(?=[a-z])|\biii[.\s]+(?=[a-z])"#, "3"),
            (#"(?i)\b(?:second|2nd)\s*(?=[a-z])|\bii[.\s]+(?=[a-z])"#, "2"),
            (#"(?i)\b(?:first|1st)\s*(?=[a-z])|\bi[.\s]+(?=[a-z])"#, "1"),
            (#"(?i)\bchapters?\b|\bch(?:ap)?\.?\s*(?=\d)|(?<=\s)c(?=\d)"#, " "),
            (#"(?i)\bverses?\b|\b(?:vv?|vs)\.?\s*(?=\d)|(?<=\d)v\.?\s*(?=\d)"#, ":"),
            (#"(?i)\s*(?:\bthrough\b|\bthru\b|\bto\b)\s*"#, "-"),
            (#"(?i)\s+and\s+|[&|\n\r]"#, ";"),
            // Numeric additions stay in the current verse/chapter list. A
            // new book starts a separate reference, including numbered books.
            (#"\+\s*(?=(?:[1-5]\s*)?[a-z])"#, ";"),
            (#"([a-z][0-9\s:.,/+\-]*\d)[\s,]+(?=(?:[1-5]\s*)?[a-z])"#, "$1;")
        ]
        return patterns.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    private static func normalize(_ text: String) -> String {
        var text = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        for character in ["–", "—", "−", "‑", "﹣"] { text = text.replacingOccurrences(of: character, with: "-") }
        for character in ["：", "∶"] { text = text.replacingOccurrences(of: character, with: ":") }
        for character in ["·", "．"] { text = text.replacingOccurrences(of: character, with: ".") }
        for character in ["(", ")", "[", "]", "{", "}"] { text = text.replacingOccurrences(of: character, with: " ") }
        for (expression, replacement) in replacements {
            text = expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
