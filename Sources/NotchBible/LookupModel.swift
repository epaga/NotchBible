import AppKit
import BibleCore
import Combine

@MainActor
final class LookupModel: ObservableObject {
    let library: BibleLibrary
    private let lookups: [String: BibleLookupEngine]
    private let preferences: UserDefaults
    @Published private(set) var selectedTranslation: String
    private var lookup: BibleLookupEngine { lookups[selectedTranslation]! }
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
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

    init(library: BibleLibrary, preferences: UserDefaults = .standard) {
        self.library = library
        self.preferences = preferences
        self.lookups = Dictionary(uniqueKeysWithValues: library.translations.map { ($0.translation, BibleLookupEngine(bible: $0)) })
        let saved = preferences.string(forKey: "selectedTranslation")
        self.selectedTranslation = saved.flatMap { library.bible(named: $0)?.translation } ?? library.defaultTranslation.translation
        if let size = preferences.dictionary(forKey: "panelSize"),
           let width = size["width"] as? Double, let height = size["height"] as? Double,
           width.isFinite, height.isFinite, width > 0, height > 0 {
            self.preferredPanelSize = NSSize(width: width, height: height)
        }
    }
    var bible: BibleStore { lookup.bible }
    var isEmpty: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
    var translationBarHeight: CGFloat { isEmpty ? 0 : 36 }
    var bodyHeight: CGFloat {
        if isEmpty { return 0 }
        if let resizedPanelHeight { return max(0, resizedPanelHeight - panelChromeHeight) }
        if !result.suggestions.isEmpty { return min(CGFloat(result.suggestions.count) * 45 + 22, availableBodyHeight) }
        if result.error != nil { return min(110, availableBodyHeight) }
        guard hasPassages else { return min(150, availableBodyHeight) }
        var height: CGFloat = 94
        let passages = displayPassages
        for passage in passages {
            if result.isSearch || passages.count > 1 { height += 38 }
            for verse in bible.verses[passage.range] {
                height += CGFloat(max(1, Int(ceil(Double(verse.text.count) / 48)))) * 29 + 12
                if height >= availableBodyHeight { return availableBodyHeight }
            }
        }
        return min(max(130, height), availableBodyHeight)
    }
    var panelChromeHeight: CGFloat {
        translationBarHeight + (isEmpty ? 88 : 89) + (notchWidth > 0 ? NotchLayout.topInset - 6 : 0)
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

    func selectTranslation(_ name: String) {
        guard let bible = library.bible(named: name), bible.translation != selectedTranslation else { return }
        selectedTranslation = bible.translation
        preferences.set(selectedTranslation, forKey: "selectedTranslation")
        updateLookup()
    }
    private func updateLookup() {
        result = lookup.lookup(query)
        searchPage = 0
        selectedSuggestion = 0
        copied = false
        copyReset?.cancel()
        onLayoutChange?()
    }
    func moveSearchPage(_ delta: Int) {
        guard searchPageCount > 1 else { return }
        searchPage = min(max(0, searchPage + delta), searchPageCount - 1)
        onLayoutChange?()
    }
    func focus() { focusRequest += 1 }
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
