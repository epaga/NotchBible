import AppKit
import Foundation

struct FlashcardSession {
    enum Phase: Equatable {
        case asking
        /// Correct, waiting for the choice of where the card goes next.
        case correct(Double)
        /// At least 90% of the characters match; the user decides.
        case close(Double)
        case wrong(Double)
        case unknown
        case finished
    }

    let pile: FlashcardPile
    var queue: [UUID]
    var position = 0
    var showsReference = true
    var phase = Phase.asking
    var answer = ""
    var reviewed = 0
}

@MainActor
final class FlashcardModel: ObservableObject {
    private let store: FlashcardStore
    private let preferences: UserDefaults
    @Published private(set) var deck: FlashcardDeck
    @Published var session: FlashcardSession?
    @Published var error: String?
    @Published var testMode: FlashcardTestMode {
        didSet { preferences.set(testMode.rawValue, forKey: "flashcardTestMode") }
    }
    var referenceMatches: ((String, Flashcard) -> Bool)?
    var onLayoutChange: (() -> Void)?

    init(store: FlashcardStore = FlashcardStore(), preferences: UserDefaults = .standard) {
        self.store = store
        self.preferences = preferences
        self.deck = store.deck
        self.testMode = preferences.string(forKey: "flashcardTestMode").flatMap(FlashcardTestMode.init(rawValue:)) ?? .referenceShown
    }

    var currentCard: Flashcard? {
        guard let session, session.queue.indices.contains(session.position) else { return nil }
        return deck.cards.first { $0.id == session.queue[session.position] }
    }

    private func save(_ updated: FlashcardDeck) {
        do {
            try store.save(updated)
            deck = store.deck
        } catch { self.error = "Couldn't save flashcards: \(error.localizedDescription)" }
    }

    /// Returns the pile the card is in, and whether it was already there.
    @discardableResult
    func add(reference: String, translation: String, text: String) -> (pile: FlashcardPile, existed: Bool) {
        if let existing = deck.cards.first(where: { $0.reference == reference && $0.translation == translation }) {
            return (existing.pile, true)
        }
        var updated = deck
        updated.cards.append(Flashcard(reference: reference, translation: translation, text: text))
        save(updated)
        return (.stove, false)
    }

    func start(_ pile: FlashcardPile) {
        var updated = deck
        updated.startRoundIfFinished(pile)
        save(updated)
        let queue = deck.pending(in: pile).map(\.id)
        guard !queue.isEmpty else { return }
        session = FlashcardSession(pile: pile, queue: queue)
        prepareCard()
    }

    func endSession() {
        session = nil
        onLayoutChange?()
    }

    private func prepareCard() {
        guard var session else { return }
        session.answer = ""
        session.phase = currentCard == nil ? .finished : .asking
        switch testMode {
        case .referenceShown: session.showsReference = true
        case .verseShown: session.showsReference = false
        case .mixed: session.showsReference = Bool.random()
        }
        self.session = session
        onLayoutChange?()
    }

    func submit() {
        guard var session, session.phase == .asking, let card = currentCard else { return }
        let answer = session.answer
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let score: Double
        if session.showsReference { score = AnswerCheck.similarity(answer, card.text) }
        else { score = referenceMatches?(answer, card) == true ? 1 : AnswerCheck.similarity(answer, card.reference) }
        if score >= 1 { session.phase = .correct(1) }
        else if score >= 0.9 { session.phase = .close(score) }
        else {
            session.phase = .wrong(score)
            record(card, correct: false)
        }
        self.session = session
    }

    func dontKnow() {
        guard var session, session.phase == .asking, let card = currentCard else { return }
        session.phase = .unknown
        self.session = session
        record(card, correct: false)
    }

    /// Settles a close answer.
    func judge(correct: Bool) {
        guard var session, case .close(let score) = session.phase, let card = currentCard else { return }
        session.phase = correct ? .correct(score) : .wrong(score)
        self.session = session
        if !correct { record(card, correct: false) }
    }

    /// Moves on, filing a correct card in `destination` (or leaving it in place).
    func next(moveTo destination: FlashcardPile? = nil) {
        guard var session else { return }
        if case .correct = session.phase, let card = currentCard { record(card, correct: true, moveTo: destination) }
        session.position += 1
        self.session = session
        prepareCard()
    }

    private func record(_ card: Flashcard, correct: Bool, moveTo destination: FlashcardPile? = nil) {
        var updated = deck
        updated.review(card.id, correct: correct, moveTo: destination)
        save(updated)
        session?.reviewed += 1
    }

    func replace(with set: FlashcardSet) {
        session = nil
        save(FlashcardDeck(cards: set.cards, roundStarted: set.roundStarted ?? [:], lastCompleted: set.lastCompleted ?? [:]))
    }

    func merge(_ set: FlashcardSet) {
        var updated = deck
        updated.merge(set.cards)
        save(updated)
    }

    func exportSet(_ pile: FlashcardPile?) -> FlashcardSet {
        guard let pile else { return FlashcardSet(cards: deck.cards, roundStarted: deck.roundStarted, lastCompleted: deck.lastCompleted) }
        return FlashcardSet(cards: deck.cards(in: pile))
    }
}
