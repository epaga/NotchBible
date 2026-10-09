import Foundation

/// Routes ordinary text to search while retaining reference suggestions,
/// unfinished addresses, and useful errors for recognized references.
public final class BibleLookupEngine: Sendable {
    public let bible: BibleStore
    private let references: ReferenceParser

    public init(bible: BibleStore) {
        self.bible = bible
        references = ReferenceParser(bible: bible)
    }

    public func lookup(_ input: String) -> ReferenceLookup {
        references.recognizesReference(input) ? references.lookup(input) : bible.search(input)
    }
}

private enum SearchText {
    static let locale = Locale(identifier: "en_US_POSIX")
    static let wordCharacters = CharacterSet.alphanumerics.union(.nonBaseCharacters)

    static func words(_ text: String, wildcards: Bool = false) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: locale)
            .precomposedStringWithCanonicalMapping
        return folded.unicodeScalars.split {
            !wordCharacters.contains($0) && !(wildcards && $0 == "*")
        }.map(String.init)
    }
}

private struct SearchTerm {
    let words: [String]
    let excluded: Bool
}

private struct SearchQuery {
    var terms: [SearchTerm] = []
    var books: Set<Int> = []
    var testaments: Set<Int> = []
    var excludedBooks: Set<Int> = []
    var excludedTestaments: Set<Int> = []
    var hint: String?
    var error: String?
    var isIncomplete = false
    var hasClauses: Bool {
        !terms.isEmpty || !books.isEmpty || !testaments.isEmpty ||
            !excludedBooks.isEmpty || !excludedTestaments.isEmpty
    }

    init(_ input: String, bookIndex: BookIndex) {
        guard input.count <= 2_048 else {
            error = "That search is too long. Try fewer words or filters."
            return
        }
        let characters = Array(input.replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\""))
        var cursor = 0
        while cursor < characters.count {
            if characters[cursor].isWhitespace { cursor += 1; continue }
            let excluded = characters[cursor] == "-"
            if excluded { cursor += 1 }
            var tag: String?
            var tagEnd = cursor
            while tagEnd < characters.count, characters[tagEnd].isLetter { tagEnd += 1 }
            if tagEnd < characters.count, characters[tagEnd] == ":" {
                tag = String(characters[cursor..<tagEnd]).lowercased()
                cursor = tagEnd + 1
            }
            var value = ""
            var quoted = false
            var insideQuote = false
            while cursor < characters.count {
                let character = characters[cursor]
                if character.isWhitespace && !insideQuote { break }
                if character == "\\", cursor + 1 < characters.count, characters[cursor + 1] == "\"" {
                    value.append("\"")
                    cursor += 2
                    continue
                }
                if character == "\"" {
                    quoted = true
                    insideQuote.toggle()
                } else { value.append(character) }
                cursor += 1
            }
            if insideQuote {
                isIncomplete = true
                hint = "Close the quotation mark to finish the search."
            }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isIncomplete = true
                hint = tag.map { "Add a value after \($0):." } ?? "Add a search word."
                continue
            }
            switch tag {
            case "book":
                let resolution = bookIndex.resolve(value).books
                guard resolution.count == 1 else {
                    error = resolution.isEmpty ? "No book matches “\(value)”. Try book:gen or book:ps." :
                        "“\(value)” matches several books. Use \(resolution.map { "book:\($0.code.lowercased())" }.joined(separator: " or "))."
                    return
                }
                if excluded { excludedBooks.insert(resolution[0].id) }
                else { books.insert(resolution[0].id) }
            case "in":
                let testament: Int
                switch BookIndex.key(value) {
                case "ot", "old", "oldtestament": testament = 0
                case "nt", "new", "newtestament": testament = 1
                default:
                    error = "Unknown testament “\(value)”. Use in:ot or in:nt."
                    return
                }
                if excluded { excludedTestaments.insert(testament) }
                else { testaments.insert(testament) }
            case .some(let name):
                error = "Unknown search filter “\(name):”. Use book: or in:."
                return
            case nil:
                let words = SearchText.words(value, wildcards: true)
                guard !words.isEmpty else { continue }
                if quoted { terms.append(SearchTerm(words: words, excluded: excluded)) }
                else { terms += words.map { SearchTerm(words: [$0], excluded: excluded) } }
            }
        }
    }
}

/// An immutable inverted word index with compact token positions. AND/NOT
/// queries merge sorted verse postings; phrases inspect only their candidates.
/// Wildcards expand the vocabulary, not the complete verse text.
struct VerseSearchIndex: Sendable {
    private let books: [BibleBook]
    private let bookIndex: BookIndex
    private let wordIDs: [String: UInt32]
    private let postings: [[Int]]
    private let vocabulary: [String]
    private let tokens: [UInt32]
    private let tokenRanges: [Range<Int>]
    private let bookPostings: [[Int]]
    private let testamentPostings: [[Int]]
    private let allVerses: [Int]

    init(verses: [BibleVerse], books: [BibleBook]) {
        self.books = books
        self.bookIndex = BookIndex(books: books)
        var wordIDs: [String: UInt32] = [:]
        var postings: [[Int]] = []
        var tokens: [UInt32] = []
        var tokenRanges: [Range<Int>] = []
        var bookPostings = Array(repeating: [Int](), count: books.count)
        var testamentPostings = Array(repeating: [Int](), count: 2)
        var allVerses: [Int] = []
        tokens.reserveCapacity(verses.count * 25)
        tokenRanges.reserveCapacity(verses.count)
        for verse in verses {
            let start = tokens.count
            for word in SearchText.words(verse.text) {
                let id: UInt32
                if let existing = wordIDs[word] { id = existing }
                else {
                    id = UInt32(postings.count)
                    wordIDs[word] = id
                    postings.append([])
                }
                tokens.append(id)
                if postings[Int(id)].last != verse.id { postings[Int(id)].append(verse.id) }
            }
            tokenRanges.append(start..<tokens.count)
            if start != tokens.count {
                bookPostings[verse.address.book].append(verse.id)
                testamentPostings[verse.address.book < 39 ? 0 : 1].append(verse.id)
                allVerses.append(verse.id)
            }
        }
        self.wordIDs = wordIDs
        self.postings = postings
        vocabulary = wordIDs.keys.sorted()
        self.tokens = tokens
        self.tokenRanges = tokenRanges
        self.bookPostings = bookPostings
        self.testamentPostings = testamentPostings
        self.allVerses = allVerses
    }

    func lookup(_ input: String, verses: [BibleVerse]) -> ReferenceLookup {
        let query = SearchQuery(input, bookIndex: bookIndex)
        var result = ReferenceLookup()
        result.isSearch = true
        result.error = query.error
        result.hint = query.hint
        result.isIncomplete = query.isIncomplete
        guard query.error == nil, query.hasClauses else { return result }
        var required = query.terms.filter { !$0.excluded }.map(self.matches)
        if !query.books.isEmpty { required.append(Self.union(query.books.map { bookPostings[$0] })) }
        if !query.testaments.isEmpty { required.append(Self.union(query.testaments.map { testamentPostings[$0] })) }
        required.sort { $0.count < $1.count }
        var matches = required.first ?? allVerses
        for other in required.dropFirst() {
            matches = Self.merge(matches, other)
            if matches.isEmpty { break }
        }
        if !matches.isEmpty {
            for term in query.terms where term.excluded {
                matches = Self.merge(matches, self.matches(term), subtract: true)
            }
            if !query.excludedBooks.isEmpty {
                matches = Self.merge(matches, Self.union(query.excludedBooks.map { bookPostings[$0] }), subtract: true)
            }
            if !query.excludedTestaments.isEmpty {
                matches = Self.merge(matches, Self.union(query.excludedTestaments.map { testamentPostings[$0] }), subtract: true)
            }
        }
        result.passages = matches.map { offset in
            let verse = verses[offset]
            return BiblePassage(range: offset..<(offset + 1),
                                reference: "\(books[verse.address.book].name) \(verse.address.chapter):\(verse.address.verse)")
        }
        if matches.isEmpty && result.hint == nil { result.hint = "No verses match this search in the selected translation." }
        return result
    }

    private func matches(_ term: SearchTerm) -> [Int] {
        if term.words.count == 1, term.words[0].allSatisfy({ $0 == "*" }) { return allVerses }
        let ids = term.words.map(matchingWords)
        if ids.contains(where: \.isEmpty) { return [] }
        var candidates = ids.map { Self.union($0.map { postings[Int($0)] }) }
        candidates.sort { $0.count < $1.count }
        var verses = candidates[0]
        for other in candidates.dropFirst() {
            verses = Self.merge(verses, other)
            if verses.isEmpty { return [] }
        }
        guard ids.count > 1 else { return verses }
        let allowed = ids.map(Set.init)
        return verses.filter { verse in
            let range = tokenRanges[verse]
            guard range.count >= allowed.count else { return false }
            for start in range.lowerBound...(range.upperBound - allowed.count) {
                if allowed.indices.allSatisfy({ allowed[$0].contains(tokens[start + $0]) }) { return true }
            }
            return false
        }
    }

    private func matchingWords(_ pattern: String) -> [UInt32] {
        guard pattern.contains("*") else { return wordIDs[pattern].map { [$0] } ?? [] }
        let prefix = String(pattern.prefix { $0 != "*" })
        var low = 0, high = vocabulary.count
        while low < high {
            let middle = (low + high) / 2
            if vocabulary[middle] < prefix { low = middle + 1 } else { high = middle }
        }
        var ids: [UInt32] = []
        for word in vocabulary[low...] {
            if !word.hasPrefix(prefix) { break }
            if Self.wildcard(pattern, matches: word) { ids.append(wordIDs[word]!) }
        }
        return ids
    }

    private static func wildcard(_ pattern: String, matches word: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false)
        var cursor = word.startIndex
        for (index, part) in parts.enumerated() where !part.isEmpty {
            if index == 0 {
                guard word.hasPrefix(part) else { return false }
                cursor = word.index(cursor, offsetBy: part.count)
            } else if index == parts.count - 1 {
                return word[cursor...].hasSuffix(part)
            } else {
                guard let range = word.range(of: part, range: cursor..<word.endIndex) else { return false }
                cursor = range.upperBound
            }
        }
        return true
    }

    private static func union(_ lists: [[Int]]) -> [Int] {
        if lists.count == 1 { return lists[0] }
        var values = Set<Int>()
        for list in lists { values.formUnion(list) }
        return values.sorted()
    }

    private static func merge(_ lhs: [Int], _ rhs: [Int], subtract: Bool = false) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(subtract ? lhs.count : min(lhs.count, rhs.count))
        var right = 0
        for left in lhs {
            while right < rhs.count && rhs[right] < left { right += 1 }
            let present = right < rhs.count && rhs[right] == left
            if present != subtract { result.append(left) }
            if !subtract && right == rhs.count { break }
        }
        return result
    }
}
