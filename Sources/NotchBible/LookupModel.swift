import AppKit
import BibleCore
import Combine

@MainActor
final class LookupModel: ObservableObject {
    let library: BibleLibrary
    private let lookups: [String: BibleLookupEngine]
    private let preferences: UserDefaults
    private let noteStore: NoteStore
    @Published private(set) var notes: [VerseNote]
    @Published private(set) var visibleVerses: Set<NoteVerse> = []
    var finishNoteEditing: (() -> Bool)?
    @Published private(set) var selectedTranslation: String
    @Published private(set) var fontSize: CGFloat
    static let defaultFontSize: CGFloat = 20
    static let fontSizeRange: ClosedRange<CGFloat> = 12...40
    private var lookup: BibleLookupEngine { lookups[selectedTranslation]! }
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            guard finishNoteEditing?() != false else { query = oldValue; return }
            if flashcardMode { setFlashcardMode(false) }
            updateLookup()
        }
    }
    @Published private(set) var result = ReferenceLookup()
    @Published private(set) var searchPage = 0
    @Published var selectedSuggestion = 0
    @Published var copied = false
    @Published var focusRequest = 0
    @Published var availableBodyHeight: CGFloat = 370
    @Published var notchWidth: CGFloat = 0
    @Published private(set) var preferredPanelSize: NSSize?
    @Published var resizedPanelHeight: CGFloat?
    var onLayoutChange: (() -> Void)?
    var onDismiss: (() -> Void)?
    private var copyReset: Task<Void, Never>?
    let flashcards: FlashcardModel
    @Published private(set) var flashcardMode = false
    @Published private(set) var toast: String?
    private var toastReset: Task<Void, Never>?
    @Published private(set) var history: ReadingHistory
    // Position of the shown text after Back/Forward, which must not reorder the history.
    @Published private(set) var historyIndex: Int?
    var historyDelay: Duration = .seconds(5)
    var isPanelVisible = true { didSet { scheduleHistory() } }
    private var historyCandidate: HistoryEntry?
    private var historyTask: Task<Void, Never>?

    init(library: BibleLibrary, preferences: UserDefaults = .standard, noteStore: NoteStore = NoteStore(),
         flashcards: FlashcardModel? = nil) {
        self.flashcards = flashcards ?? FlashcardModel()
        self.library = library
        self.preferences = preferences
        self.noteStore = noteStore
        self.notes = noteStore.notes
        self.history = ReadingHistory(stored: preferences.array(forKey: "readingHistory"))
        self.lookups = Dictionary(uniqueKeysWithValues: library.translations.map { ($0.translation, BibleLookupEngine(bible: $0)) })
        let saved = preferences.string(forKey: "selectedTranslation")
        self.selectedTranslation = saved.flatMap { library.bible(named: $0)?.translation } ?? library.defaultTranslation.translation
        let savedFontSize = CGFloat(preferences.double(forKey: "passageFontSize"))
        self.fontSize = Self.fontSizeRange.contains(savedFontSize) ? savedFontSize : Self.defaultFontSize
        if let size = preferences.dictionary(forKey: "panelSize"),
           let width = size["width"] as? Double, let height = size["height"] as? Double,
           width.isFinite, height.isFinite, width > 0, height > 0 {
            self.preferredPanelSize = NSSize(width: width, height: height)
        }
        self.flashcards.referenceMatches = { [weak self] answer, card in
            guard let engine = self?.lookups[card.translation] ?? self?.lookups.values.first else { return false }
            let found = engine.lookup(answer)
            guard found.error == nil, found.suggestions.isEmpty, !found.isSearch, !found.passages.isEmpty else { return false }
            return found.passages.map(\.reference).joined(separator: "; ") == card.reference
        }
        self.flashcards.onLayoutChange = { [weak self] in self?.onLayoutChange?() }
    }
    var bible: BibleStore { lookup.bible }
    var isEmpty: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isAllNotesSearch: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "note:*" }
    var hasPassages: Bool { !result.passages.isEmpty && result.error == nil && result.suggestions.isEmpty }
    // Keep native text layout bounded on each keystroke. Copy retains every hit.
    static let searchDisplayLimit = 100
    var searchPageCount: Int {
        result.isSearch ? (result.passages.count + Self.searchDisplayLimit - 1) / Self.searchDisplayLimit : 0
    }
    var displayPassages: [BiblePassage] {
        guard result.isSearch else { return result.passages }
        let start = min(searchPage * Self.searchDisplayLimit, result.passages.count)
        return Array(result.passages[start..<min(start + Self.searchDisplayLimit, result.passages.count)])
    }
    var resultSummary: String {
        guard result.isSearch else { return result.passages.map(\.reference).joined(separator: "; ") }
        let count = result.verseCount
        let summary = "\(count) \(count == 1 ? "verse" : "verses")"
        guard count > Self.searchDisplayLimit else { return summary }
        let start = searchPage * Self.searchDisplayLimit + 1
        let end = min(start + Self.searchDisplayLimit - 1, count)
        return summary + " · \(start)–\(end)"
    }
    var translationBarHeight: CGFloat { flashcardMode ? 0 : 36 }
    var bodyHeight: CGFloat {
        if let resizedPanelHeight { return max(0, resizedPanelHeight - panelChromeHeight) }
        if flashcardMode { return min(340, availableBodyHeight) }
        if isEmpty { return min(260, availableBodyHeight) }
        if !result.suggestions.isEmpty { return min(CGFloat(result.suggestions.count) * 45 + 22, availableBodyHeight) }
        if result.error != nil { return min(110, availableBodyHeight) }
        guard hasPassages else { return min(150, availableBodyHeight) }
        var height: CGFloat = 94
        let passages = displayPassages
        let scale = Double(fontScale)
        for passage in passages {
            if result.isSearch || passages.count > 1 { height += 38 * fontScale }
            for verse in bible.verses[passage.range] {
                height += CGFloat(max(1, Int(ceil(Double(verse.text.count) * scale / 48)))) * 29 * fontScale + 12
                if height >= availableBodyHeight { return availableBodyHeight }
            }
        }
        return min(max(130, height), availableBodyHeight)
    }
    var panelChromeHeight: CGFloat {
        translationBarHeight + (isEmpty || flashcardMode ? 88 : 89) + (notchWidth > 0 ? NotchLayout.topInset - 6 : 0)
    }
    var panelHeight: CGFloat { resizedPanelHeight ?? (bodyHeight + panelChromeHeight) }

    func setPanelSize(_ size: NSSize) {
        preferredPanelSize = size
        onLayoutChange?()
    }
    func savePanelSize() {
        guard let preferredPanelSize else { return }
        preferences.set(["width": Double(preferredPanelSize.width), "height": Double(preferredPanelSize.height)],
                        forKey: "panelSize")
    }

    var fontScale: CGFloat { fontSize / Self.defaultFontSize }
    func changeFontSize(by delta: CGFloat) { setFontSize(fontSize + delta) }
    func resetFontSize() { setFontSize(Self.defaultFontSize) }
    private func setFontSize(_ size: CGFloat) {
        let clamped = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        guard clamped != fontSize else { return }
        fontSize = clamped
        preferences.set(Double(clamped), forKey: "passageFontSize")
        onLayoutChange?()
    }

    func selectTranslation(_ name: String) {
        guard let bible = library.bible(named: name), bible.translation != selectedTranslation else { return }
        guard finishNoteEditing?() != false else { return }
        selectedTranslation = bible.translation
        preferences.set(selectedTranslation, forKey: "selectedTranslation")
        updateLookup()
    }
    func moveTranslation(_ delta: Int) {
        let translations = library.translations
        guard translations.count > 1,
              let index = translations.firstIndex(where: { $0.translation == selectedTranslation }) else { return }
        let nextIndex = (index + delta + translations.count) % translations.count
        selectTranslation(translations[nextIndex].translation)
    }
    @discardableResult
    func moveChapter(_ delta: Int) -> Bool {
        guard delta == -1 || delta == 1, result.canCopy, !result.isSearch,
              result.suggestions.isEmpty, result.passages.count == 1,
              let passage = result.passages.first else { return false }
        let address = bible.verses[passage.range.lowerBound].address
        guard passage.range == bible.chapterRange(book: bible.books[address.book], chapter: address.chapter) else { return false }
        let offset = delta > 0 ? passage.range.upperBound : passage.range.lowerBound - 1
        guard bible.verses.indices.contains(offset) else { return true }
        guard finishNoteEditing?() != false else { return true }
        let next = bible.verses[offset].address
        let book = bible.books[next.book]
        var reference = "\(book.name) \(next.chapter)"
        // A bare number in a single-chapter book is parsed as a verse.
        if book.isSingleChapter, let range = bible.chapterRange(book: book, chapter: next.chapter) {
            reference += ":\(bible.verses[range.lowerBound].address.verse)-\(bible.verses[range.upperBound - 1].address.verse)"
        }
        query = reference
        return true
    }
    private func updateLookup() {
        visibleVerses = []
        result = lookup.lookup(query, notes: notes.compactMap { $0.searchNote(in: bible) })
        searchPage = 0
        selectedSuggestion = 0
        copied = false
        copyReset?.cancel()
        scheduleHistory()
        onLayoutChange?()
    }
    func moveSearchPage(_ delta: Int) {
        guard searchPageCount > 1 else { return }
        guard finishNoteEditing?() != false else { return }
        visibleVerses = []
        searchPage = min(max(0, searchPage + delta), searchPageCount - 1)
        onLayoutChange?()
    }
    func focus() {
        guard finishNoteEditing?() != false else { return }
        focusRequest += 1
    }

    func saveNote(_ note: VerseNote) throws {
        try noteStore.save(note)
        guard notes != noteStore.notes else { return }
        notes = noteStore.notes
        if result.isSearch { updateLookup() }
    }
    func makeNote(translation: String, segments: [NoteSegment]) -> VerseNote {
        let style = preferences.string(forKey: "noteAnnotationStyle").flatMap(AnnotationStyle.init(rawValue:)) ?? .underline
        let color = preferences.integer(forKey: "noteAnnotationColor")
        return VerseNote(translation: translation, segments: segments, style: style,
                         color: AnnotationColors.values.indices.contains(color) ? color : 0)
    }
    func rememberAnnotation(_ note: VerseNote) {
        preferences.set(note.style.rawValue, forKey: "noteAnnotationStyle")
        preferences.set(note.color, forKey: "noteAnnotationColor")
    }
    func setVisibleVerses(_ verses: Set<NoteVerse>) {
        guard visibleVerses != verses else { return }
        visibleVerses = verses
    }
    func noteCount(for translation: String) -> Int {
        if isAllNotesSearch { return notes.filter { $0.translation == translation }.count }
        guard hasPassages, translation != selectedTranslation else { return 0 }
        return notes.filter { note in
            note.translation == translation && note.segments.contains { visibleVerses.contains($0.verse) }
        }.count
    }
    func choose(_ suggestion: ReferenceSuggestion) {
        query = suggestion.query
        focus()
    }
    func moveSuggestion(_ delta: Int) {
        guard !result.suggestions.isEmpty else { return }
        selectedSuggestion = (selectedSuggestion + delta + result.suggestions.count) % result.suggestions.count
    }
    func submit() {
        if !result.suggestions.isEmpty {
            choose(result.suggestions[min(selectedSuggestion, result.suggestions.count - 1)])
        } else { copy() }
    }
    func setFlashcardMode(_ on: Bool) {
        guard on != flashcardMode else { return }
        guard finishNoteEditing?() != false else { return }
        flashcardMode = on
        if !on { flashcards.endSession() }
        scheduleHistory()
        onLayoutChange?()
    }
    var canAddFlashcard: Bool { result.canCopy && !result.isSearch && result.suggestions.isEmpty && hasPassages }
    func addFlashcards() {
        guard canAddFlashcard else { return }
        var added: [String] = [], existing: [String] = []
        for passage in result.passages {
            let text = bible.verses[passage.range].filter { !$0.isOmitted }.map(\.text).joined(separator: " ")
            let outcome = flashcards.add(reference: passage.reference, translation: selectedTranslation, text: text)
            if outcome.existed { existing.append("\(passage.reference) is already in the \(outcome.pile.name)") }
            else { added.append(passage.reference) }
        }
        showToast(added.isEmpty ? existing.joined(separator: " · ")
                  : "Added \(added.joined(separator: "; ")) (\(selectedTranslation)) to the Stove")
    }
    var shownHistoryEntry: HistoryEntry? {
        guard !flashcardMode, hasPassages, !result.isSearch else { return nil }
        return HistoryEntry(reference: result.passages.map(\.reference).joined(separator: "; "),
                            translation: selectedTranslation, date: Date())
    }
    private func historyEntryIsShown(_ index: Int) -> Bool {
        guard history.entries.indices.contains(index), let shown = shownHistoryEntry else { return false }
        return history.entries[index].matches(shown)
    }
    var historyBackIndex: Int? {
        let index = historyIndex.map { historyEntryIsShown($0) ? $0 + 1 : $0 } ?? (historyEntryIsShown(0) ? 1 : 0)
        return history.entries.indices.contains(index) ? index : nil
    }
    var historyForwardIndex: Int? {
        guard let historyIndex, historyIndex > 0, historyEntryIsShown(historyIndex) else { return nil }
        return historyIndex - 1
    }
    func moveHistory(_ delta: Int) {
        guard let index = delta < 0 ? historyBackIndex : historyForwardIndex else { return }
        showHistoryEntry(at: index, reorder: false)
    }
    /// Opening an entry from the history list counts as a new visit once it settles.
    func showHistoryEntry(at index: Int, reorder: Bool = true) {
        guard history.entries.indices.contains(index), finishNoteEditing?() != false else { return }
        let entry = history.entries[index]
        historyIndex = reorder ? nil : index
        setFlashcardMode(false)
        var changed = false
        if let bible = library.bible(named: entry.translation), bible.translation != selectedTranslation {
            selectedTranslation = bible.translation
            preferences.set(selectedTranslation, forKey: "selectedTranslation")
            changed = true
        }
        if query != entry.reference { query = entry.reference }
        else if changed { updateLookup() }
        else { scheduleHistory() }
    }
    private func scheduleHistory() {
        let shown = isPanelVisible ? shownHistoryEntry : nil
        if let shown, let historyCandidate, historyCandidate.matches(shown), historyTask != nil { return }
        historyTask?.cancel()
        historyTask = nil
        historyCandidate = nil
        guard let shown, !(historyIndex.map(historyEntryIsShown) ?? false) else { return }
        historyCandidate = shown
        historyTask = Task { [weak self, historyDelay] in
            try? await Task.sleep(for: historyDelay)
            guard !Task.isCancelled, let self else { return }
            self.historyTask = nil
            self.historyCandidate = nil
            guard let current = self.shownHistoryEntry, current.matches(shown) else { return }
            self.history.record(current)
            self.historyIndex = nil
            self.preferences.set(self.history.stored, forKey: "readingHistory")
        }
    }
    private func showToast(_ message: String) {
        toast = message
        toastReset?.cancel()
        toastReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
    func copy() {
        guard result.canCopy && result.suggestions.isEmpty else { return }
        let text = bible.text(for: result.passages)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { return }
        copied = true
        copyReset?.cancel()
        copyReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }
}
