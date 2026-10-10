import BibleCore
import Foundation

enum AnnotationStyle: String, Codable, CaseIterable {
    case underline, dottedUnderline, box, oval, highlight, bottomBox, topBox

    var name: String {
        switch self {
        case .underline: return "Underline"
        case .dottedUnderline: return "Dotted underline"
        case .box: return "Box"
        case .oval: return "Oval"
        case .highlight: return "Background highlight"
        case .bottomBox: return "Bottom half of a box"
        case .topBox: return "Top half of a box"
        }
    }
}

struct NoteVerse: Codable, Hashable {
    let book: Int
    let chapter: Int
    let verse: Int

    init(_ address: VerseAddress) {
        book = address.book
        chapter = address.chapter
        verse = address.verse
    }
}

/// Offsets are UTF-16, matching AppKit. The quote protects against changed
/// user-installed translation files silently moving a note to different text.
struct NoteSegment: Codable, Equatable {
    let verse: NoteVerse
    let location: Int
    let length: Int
    let quote: String

    func range(in text: String) -> NSRange? {
        let body = text as NSString
        guard location >= 0, length > 0, location <= body.length,
              length <= body.length - location else { return nil }
        let range = NSRange(location: location, length: length)
        return body.substring(with: range) == quote ? range : nil
    }
}

struct VerseNote: Codable, Identifiable, Equatable {
    var id = UUID()
    let translation: String
    let segments: [NoteSegment]
    var text = ""
    var style = AnnotationStyle.underline
    var color = 0
}

final class NoteStore {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBible/Notes.json")
    }

    let url: URL
    private(set) var notes: [VerseNote] = []
    private var loadError: Error?

    init(url: URL = NoteStore.defaultURL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            notes = try JSONDecoder().decode([VerseNote].self, from: Data(contentsOf: url))
        } catch { loadError = error }
    }

    func save(_ note: VerseNote) throws {
        // Preserve an unreadable existing file instead of overwriting it.
        if let loadError { throw loadError }
        var updated = notes
        if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.removeAll { $0.id == note.id }
        } else if let index = updated.firstIndex(where: { $0.id == note.id }) { updated[index] = note }
        else { updated.append(note) }
        guard updated != notes else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        notes = updated
    }
}

struct DisplayedVerse {
    let verse: NoteVerse
    let range: NSRange
    let text: String
    var allowsNotes = true

    static func segments(in selection: NSRange, verses: [DisplayedVerse]) -> [NoteSegment] {
        verses.compactMap { displayed in
            guard displayed.allowsNotes else { return nil }
            let intersection = NSIntersectionRange(selection, displayed.range)
            guard intersection.length > 0 else { return nil }
            let local = NSRange(location: intersection.location - displayed.range.location, length: intersection.length)
            return NoteSegment(verse: displayed.verse, location: local.location, length: local.length,
                               quote: (displayed.text as NSString).substring(with: local))
        }
    }
}
