import Foundation

struct HistoryEntry: Equatable {
    var reference: String
    var translation: String
    var date: Date

    func matches(_ other: HistoryEntry) -> Bool { reference == other.reference && translation == other.translation }
}

struct ReadingHistory {
    static let limit = 50
    private(set) var entries: [HistoryEntry]

    init(entries: [HistoryEntry] = []) { self.entries = Array(entries.prefix(Self.limit)) }

    /// Puts the entry at the front, dropping any earlier visit to the same text and translation.
    mutating func record(_ entry: HistoryEntry) {
        entries.removeAll { $0.matches(entry) }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    init(stored: Any?) {
        let records = stored as? [[String: Any]] ?? []
        self.init(entries: records.compactMap { record in
            guard let reference = record["reference"] as? String, let translation = record["translation"] as? String,
                  let date = record["date"] as? Date else { return nil }
            return HistoryEntry(reference: reference, translation: translation, date: date)
        })
    }
    var stored: [[String: Any]] {
        entries.map { ["reference": $0.reference, "translation": $0.translation, "date": $0.date] }
    }
}
