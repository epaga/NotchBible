import AppKit
import BibleCore
import Combine

@MainActor
final class LookupModel: ObservableObject {
    let parser: ReferenceParser
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            result = parser.lookup(query)
            selectedSuggestion = 0
            copied = false
            onLayoutChange?()
        }
    }
    @Published private(set) var result = ReferenceLookup()
    @Published var selectedSuggestion = 0
    @Published var copied = false
    @Published var focusRequest = 0
    @Published var availableBodyHeight: CGFloat = 370
    @Published var notchWidth: CGFloat = 0
    var onLayoutChange: (() -> Void)?
    var onDismiss: (() -> Void)?
    private var copyReset: Task<Void, Never>?

    init(bible: BibleStore) { parser = ReferenceParser(bible: bible) }
    var bible: BibleStore { parser.bible }
    var isEmpty: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasPassages: Bool { !result.passages.isEmpty && result.error == nil && result.suggestions.isEmpty }
    var bodyHeight: CGFloat {
        if isEmpty { return 0 }
        if !result.suggestions.isEmpty { return min(CGFloat(result.suggestions.count) * 45 + 22, availableBodyHeight) }
        if result.error != nil { return min(110, availableBodyHeight) }
        guard hasPassages else { return min(150, availableBodyHeight) }
        var height: CGFloat = 94
        for passage in result.passages {
            if result.passages.count > 1 { height += 38 }
            for verse in bible.verses[passage.range] {
                height += CGFloat(max(1, Int(ceil(Double(verse.text.count) / 48)))) * 29 + 12
                if height >= availableBodyHeight { return availableBodyHeight }
            }
        }
        return min(max(130, height), availableBodyHeight)
    }
    var panelHeight: CGFloat {
        bodyHeight + (isEmpty ? 88 : 89) + (notchWidth > 0 ? NotchLayout.topInset - 6 : 0)
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
