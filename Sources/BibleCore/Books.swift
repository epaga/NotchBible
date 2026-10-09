import Foundation

public struct BibleBook: Identifiable, Hashable, Sendable {
    public let id: Int
    public let code: String
    public let name: String
    public let aliases: [String]

    public static let all: [BibleBook] = {
        let entries: [(String, String, String)] = [
            ("GEN", "Genesis", "gen ge gn genes"),
            ("EXO", "Exodus", "ex exo exod exos"),
            ("LEV", "Leviticus", "lev le lv levit"),
            ("NUM", "Numbers", "num nu nm nb numb"),
            ("DEU", "Deuteronomy", "deut deu dt de deuter"),
            ("JOS", "Joshua", "josh jos jsh"),
            ("JDG", "Judges", "judg jdg jdgs jgs jg"),
            ("RUT", "Ruth", "ru rut rth"),
            ("1SA", "1 Samuel", "1sam 1sa 1sm"),
            ("2SA", "2 Samuel", "2sam 2sa 2sm"),
            ("1KI", "1 Kings", "1king 1kgs 1ki 1k"),
            ("2KI", "2 Kings", "2king 2kgs 2ki 2k"),
            ("1CH", "1 Chronicles", "1chron 1chr 1ch 1cr"),
            ("2CH", "2 Chronicles", "2chron 2chr 2ch 2cr"),
            ("EZR", "Ezra", "ezr ez"),
            ("NEH", "Nehemiah", "neh ne nmh"),
            ("EST", "Esther", "est esth es"),
            ("JOB", "Job", "jb"),
            ("PSA", "Psalms", "ps psa pss psalm psal"),
            ("PRO", "Proverbs", "prov pro pr prv"),
            ("ECC", "Ecclesiastes", "eccl ecc ec ecl qoh qoheleth"),
            ("SOL", "Song of Solomon", "song songs sos sng ss cant canticles songofsongs songofsong"),
            ("ISA", "Isaiah", "isa is isaia"),
            ("JER", "Jeremiah", "jer je jr jrm"),
            ("LAM", "Lamentations", "lam la lm lament"),
            ("EZE", "Ezekiel", "ezek ezk eze"),
            ("DAN", "Daniel", "dan da dn"),
            ("HOS", "Hosea", "hos ho hs"),
            ("JOE", "Joel", "joe jol jl"),
            ("AMO", "Amos", "am amo"),
            ("OBA", "Obadiah", "obad oba ob"),
            ("JON", "Jonah", "jon jnh"),
            ("MIC", "Micah", "mic mi mc"),
            ("NAH", "Nahum", "nah na nam nh"),
            ("HAB", "Habakkuk", "hab hb habak"),
            ("ZEP", "Zephaniah", "zeph zep zp"),
            ("HAG", "Haggai", "hag hg hagg"),
            ("ZEC", "Zechariah", "zech zec zc"),
            ("MAL", "Malachi", "mal ml"),
            ("MAT", "Matthew", "matt mat mt"),
            ("MAR", "Mark", "mar mrk mk mr"),
            ("LUK", "Luke", "luk lu lk"),
            ("JOH", "John", "joh jhn jn"),
            ("ACT", "Acts", "act ac"),
            ("ROM", "Romans", "rom ro rm rms"),
            ("1CO", "1 Corinthians", "1cor 1co 1c"),
            ("2CO", "2 Corinthians", "2cor 2co 2c"),
            ("GAL", "Galatians", "gal ga gl"),
            ("EPH", "Ephesians", "eph ep ephes"),
            ("PHI", "Philippians", "phil php pp philip"),
            ("COL", "Colossians", "col co cl colos"),
            ("1TH", "1 Thessalonians", "1thess 1thes 1th 1ths"),
            ("2TH", "2 Thessalonians", "2thess 2thes 2th 2ths"),
            ("1TI", "1 Timothy", "1tim 1ti 1tm"),
            ("2TI", "2 Timothy", "2tim 2ti 2tm"),
            ("TIT", "Titus", "tit ti tt"),
            ("PHM", "Philemon", "philem phile phlm phm pm"),
            ("HEB", "Hebrews", "heb he hbr"),
            ("JAM", "James", "jam jas jm jms"),
            ("1PE", "1 Peter", "1pet 1pe 1pt 1p"),
            ("2PE", "2 Peter", "2pet 2pe 2pt 2p"),
            ("1JO", "1 John", "1joh 1jhn 1jn 1jo 1j"),
            ("2JO", "2 John", "2joh 2jhn 2jn 2jo 2j"),
            ("3JO", "3 John", "3joh 3jhn 3jn 3jo 3j"),
            ("JUD", "Jude", "jud jd"),
            ("REV", "Revelation", "rev re rv revelation revelations apocalypse apoc")
        ]
        return entries.enumerated().map { index, entry in
            BibleBook(id: index, code: entry.0, name: entry.1,
                      aliases: entry.2.split(separator: " ").map(String.init))
        }
    }()
}

/// Precomputed exact and prefix indexes. A typo search is used only when
/// neither index matches; ambiguous abbreviations always offer a choice.
struct BookIndex {
    private var exact: [String: Set<Int>] = [:]
    private var prefixes: [String: Set<Int>] = [:]
    private var spellings: [(String, Int)] = []

    init() {
        for book in BibleBook.all {
            for alias in Set([book.name, book.code] + book.aliases) {
                let key = Self.key(alias)
                exact[key, default: []].insert(book.id)
                spellings.append((key, book.id))
                for length in 1...key.count {
                    prefixes[String(key.prefix(length)), default: []].insert(book.id)
                }
            }
        }
    }

    func resolve(_ text: String) -> (books: [BibleBook], corrected: Bool) {
        let key = Self.key(text)
        if let ids = exact[key] ?? prefixes[key] {
            return (ids.sorted().map { BibleBook.all[$0] }, false)
        }
        guard key.count >= 3 else { return ([], false) }
        let threshold = key.count >= 7 ? 2 : 1
        var best = threshold + 1
        var ids = Set<Int>()
        for (spelling, id) in spellings where abs(spelling.count - key.count) <= threshold {
            // Don't turn a mistyped ordinal into another numbered book.
            if key.first?.isNumber == true, spelling.first != key.first { continue }
            let distance = Self.distance(key, spelling)
            if distance < best { best = distance; ids = [id] }
            else if distance == best { ids.insert(id) }
        }
        guard best <= threshold else { return ([], false) }
        return (ids.sorted().map { BibleBook.all[$0] }, true)
    }

    static func key(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // Optimal string alignment: insertion, deletion, substitution, transposition.
    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var rows = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { rows[i][0] = i }
        for j in 0...b.count { rows[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                rows[i][j] = min(rows[i - 1][j] + 1, rows[i][j - 1] + 1,
                                 rows[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
                }
            }
        }
        return rows[a.count][b.count]
    }
}
