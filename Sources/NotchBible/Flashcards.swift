import Foundation

enum FlashcardPile: String, Codable, CaseIterable, Identifiable {
    case stove, fridge, freezer

    var id: String { rawValue }
    var name: String {
        switch self {
        case .stove: return "Stove"
        case .fridge: return "Fridge"
        case .freezer: return "Freezer"
        }
    }
    var symbol: String {
        switch self {
        case .stove: return "flame"
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        }
    }
    /// How often the whole pile should be worked through.
    var interval: TimeInterval {
        switch self {
        case .stove: return 48 * 3600
        case .fridge: return 7 * 86400
        case .freezer: return 30 * 86400
        }
    }
    var intervalDescription: String {
        switch self {
        case .stove: return "every 48 hours"
        case .fridge: return "every 7 days"
        case .freezer: return "every 30 days"
        }
    }
    var higher: [FlashcardPile] {
        switch self {
        case .stove: return [.fridge, .freezer]
        case .fridge: return [.freezer]
        case .freezer: return []
        }
    }
}

enum FlashcardTestMode: String, CaseIterable, Identifiable {
    case referenceShown, verseShown, mixed

    var id: String { rawValue }
    var name: String {
        switch self {
        case .referenceShown: return "Type the verse"
        case .verseShown: return "Type the reference"
        case .mixed: return "Mixed"
        }
    }
}

struct Flashcard: Codable, Identifiable, Equatable {
    var id = UUID()
    let reference: String
    let translation: String
    let text: String
    var pile = FlashcardPile.stove
    var added = Date()
    var lastReviewed: Date?
}

struct FlashcardDeck: Codable, Equatable {
    var cards: [Flashcard] = []
    /// When the current pass through each pile began. A card reviewed since
    /// then is done for this pass.
    var roundStarted: [String: Date] = [:]
    /// When each pile was last worked through completely.
    var lastCompleted: [String: Date] = [:]

    func cards(in pile: FlashcardPile) -> [Flashcard] { cards.filter { $0.pile == pile } }

    /// Cards still to check in the current pass, least recently checked first.
    func pending(in pile: FlashcardPile) -> [Flashcard] {
        let start = roundStarted[pile.rawValue] ?? .distantPast
        return cards(in: pile)
            .filter { ($0.lastReviewed ?? .distantPast) < start || $0.lastReviewed == nil }
            .sorted { ($0.lastReviewed ?? .distantPast, $0.added) < ($1.lastReviewed ?? .distantPast, $1.added) }
    }

    func isOverdue(_ pile: FlashcardPile, now: Date = Date()) -> Bool {
        guard !cards(in: pile).isEmpty else { return false }
        guard let completed = lastCompleted[pile.rawValue] else { return true }
        return now.timeIntervalSince(completed) > pile.interval
    }

    /// Records a check. A missed card always returns to the stove.
    mutating func review(_ id: UUID, correct: Bool, moveTo destination: FlashcardPile? = nil, now: Date = Date()) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let origin = cards[index].pile
        cards[index].lastReviewed = now
        if !correct { cards[index].pile = .stove }
        else if let destination { cards[index].pile = destination }
        if pending(in: origin).isEmpty { completeRound(origin, now: now) }
    }

    mutating func startRoundIfFinished(_ pile: FlashcardPile, now: Date = Date()) {
        if pending(in: pile).isEmpty { roundStarted[pile.rawValue] = now }
    }

    private mutating func completeRound(_ pile: FlashcardPile, now: Date) {
        lastCompleted[pile.rawValue] = now
        roundStarted[pile.rawValue] = now.addingTimeInterval(0.001)
    }

    /// Adds cards not already present, matched by reference and translation.
    mutating func merge(_ imported: [Flashcard]) {
        for card in imported where !cards.contains(where: { $0.reference == card.reference && $0.translation == card.translation }) {
            cards.append(card)
        }
    }
}

struct FlashcardSet: Codable {
    var format = "NotchBible Flashcards"
    var version = 1
    var cards: [Flashcard]
    var roundStarted: [String: Date]?
    var lastCompleted: [String: Date]?
}

final class FlashcardStore {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBible/Flashcards.json")
    }

    let url: URL
    private(set) var deck = FlashcardDeck()
    private var loadError: Error?

    init(url: URL = FlashcardStore.defaultURL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { deck = try Self.decoder.decode(FlashcardDeck.self, from: Data(contentsOf: url)) }
        catch { loadError = error }
    }

    func save(_ updated: FlashcardDeck) throws {
        // Preserve an unreadable existing file instead of overwriting it.
        if let loadError { throw loadError }
        guard updated != deck else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(updated).write(to: url, options: .atomic)
        deck = updated
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum AnswerCheck {
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Share of characters that match, from 0 to 1, by edit distance.
    static func similarity(_ answer: String, _ expected: String) -> Double {
        let a = Array(normalized(answer)), b = Array(normalized(expected))
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(1, a.count) where !a.isEmpty {
            current[0] = i
            for j in 1...max(1, b.count) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        let distance = a.isEmpty ? b.count : (b.isEmpty ? a.count : previous[b.count])
        return max(0, 1 - Double(distance) / Double(max(a.count, b.count)))
    }
}
