import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.94, green: 0.92, blue: 0.87)
    static let muted = Color(red: 0.56, green: 0.55, blue: 0.52)
    static let gold = Color(red: 0.88, green: 0.71, blue: 0.46)
    static let green = Color(red: 0.66, green: 0.79, blue: 0.61)
    static let red = Color(red: 0.87, green: 0.48, blue: 0.42)
}

struct FlashcardView: View {
    @ObservedObject var model: FlashcardModel

    var body: some View {
        Group {
            if model.session != nil { SessionView(model: model) }
            else { piles }
        }
        .alert("Flashcards", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var piles: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(FlashcardPile.allCases) { pile in pileColumn(pile) }
            }
            HStack(spacing: 14) {
                Picker("", selection: $model.testMode) {
                    ForEach(FlashcardTestMode.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer(minLength: 0)
                Menu {
                    Button("All Piles…") { FlashcardFiles.export(nil, model: model) }
                    Divider()
                    ForEach(FlashcardPile.allCases) { pile in
                        Button("\(pile.name)…") { FlashcardFiles.export(pile, model: model) }
                            .disabled(model.deck.cards(in: pile).isEmpty)
                    }
                } label: { Text("Export").font(.system(size: 11)) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.deck.cards.isEmpty)
                Button("Import…") { FlashcardFiles.importSet(model: model) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 25).padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func pileColumn(_ pile: FlashcardPile) -> some View {
        let cards = model.deck.cards(in: pile)
        let pending = model.deck.pending(in: pile).count
        let overdue = model.deck.isOverdue(pile)
        return VStack(spacing: 8) {
            Button { model.start(pile) } label: {
                VStack(spacing: 8) {
                    Image(systemName: pile.symbol).font(.system(size: 24, weight: .light))
                        .foregroundStyle(Palette.gold)
                    Text(pile.name).font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Palette.ink)
                    Text("\(cards.count) \(cards.count == 1 ? "card" : "cards")")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if pending > 0 && pending < cards.count {
                        Text("\(pending) left this round").font(.system(size: 10)).foregroundStyle(Palette.gold.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(overdue ? Palette.red.opacity(0.6) : Color.white.opacity(0.08)))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(cards.isEmpty)
                .help("Review the \(pile.name.lowercased()) · due \(pile.intervalDescription)")
            Text(lastCompletedText(pile))
                .font(.system(size: 10)).multilineTextAlignment(.center)
                .foregroundStyle(overdue ? Palette.red : Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button { FlashcardFiles.printPile(pile, model: model) } label: {
                Label("Print", systemImage: "printer").font(.system(size: 10))
            }.buttonStyle(.plain).foregroundStyle(Palette.muted).disabled(cards.isEmpty)
                .opacity(cards.isEmpty ? 0.35 : 1)
                .help("Export the \(pile.name.lowercased()) as index cards (PDF)")
        }.frame(maxWidth: .infinity)
    }

    private func lastCompletedText(_ pile: FlashcardPile) -> String {
        guard let date = model.deck.lastCompleted[pile.rawValue] else { return "Never completed" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "Completed " + relative.localizedString(for: date, relativeTo: Date())
    }
}

private struct SessionView: View {
    @ObservedObject var model: FlashcardModel
    @FocusState private var answerFocused: Bool

    var body: some View {
        if let session = model.session {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { model.endSession() } label: {
                        Label("Piles", systemImage: "chevron.left").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("\(session.pile.name) · \(min(session.position + 1, session.queue.count)) of \(session.queue.count)")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.gold.opacity(0.9))
                }
                if session.phase == .finished { finished(session) }
                else if let card = model.currentCard { cardView(card, session: session) }
            }
            .padding(.horizontal, 25).padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func finished(_ session: FlashcardSession) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.green)
            Text("\(session.pile.name) done · \(session.reviewed) checked")
                .font(.system(size: 14, design: .serif)).foregroundStyle(Palette.ink)
            Button("Back to piles") { model.endSession() }.keyboardShortcut(.defaultAction)
        }.frame(maxWidth: .infinity).padding(.top, 30)
    }

    @ViewBuilder
    private func cardView(_ card: Flashcard, session: FlashcardSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.showsReference ? "Type the verse" : "Type the reference")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text(session.showsReference ? card.reference : card.text)
                    .font(.system(size: session.showsReference ? 22 : 17, design: .serif))
                    .foregroundStyle(Palette.ink).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.translation).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.hidden).frame(maxHeight: 130)

        if session.phase == .asking {
            TextField(session.showsReference ? "Verse text" : "Reference", text: Binding(
                get: { model.session?.answer ?? "" }, set: { model.session?.answer = $0 }
            ), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14))
                .lineLimit(1...5).padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .focused($answerFocused).onSubmit { model.submit() }
                .onAppear { answerFocused = true }
            HStack {
                Button("I don't know") { model.dontKnow() }
                Spacer()
                Button("Submit") { model.submit() }.keyboardShortcut(.defaultAction)
                    .disabled(session.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            result(card, session: session)
        }
    }

    @ViewBuilder
    private func result(_ card: Flashcard, session: FlashcardSession) -> some View {
        let expected = session.showsReference ? card.text : card.reference
        switch session.phase {
        case .correct(let score):
            status(score >= 1 ? "Correct" : "Counted as correct", color: Palette.green, symbol: "checkmark.circle")
            if score < 1 { answers(session.answer, expected) }
            HStack {
                ForEach(session.pile.higher) { pile in
                    Button("Move to \(pile.name)") { model.next(moveTo: pile) }
                }
                Spacer()
                Button(session.pile.higher.isEmpty ? "Next" : "Keep in \(session.pile.name)") { model.next() }
                    .keyboardShortcut(.defaultAction)
            }
        case .close(let score):
            status("\(Int((score * 100).rounded(.down)))% match — was that right?", color: Palette.gold, symbol: "questionmark.circle")
            answers(session.answer, expected)
            HStack {
                Button("No, it was wrong") { model.judge(correct: false) }
                Spacer()
                Button("Yes, count it correct") { model.judge(correct: true) }.keyboardShortcut(.defaultAction)
            }
        case .wrong(let score):
            status("Not quite (\(Int((score * 100).rounded(.down)))%)" + (session.pile == .stove ? "" : " · back to the Stove"),
                   color: Palette.red, symbol: "xmark.circle")
            answers(session.answer, expected)
            nextButton
        case .unknown:
            status(session.pile == .stove ? "The answer" : "The answer · back to the Stove", color: Palette.muted, symbol: "eye")
            answers(nil, expected)
            nextButton
        case .asking, .finished: EmptyView()
        }
    }

    private var nextButton: some View {
        HStack { Spacer(); Button("Next") { model.next() }.keyboardShortcut(.defaultAction) }
    }

    private func status(_ text: String, color: Color, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
    }

    private func answers(_ given: String?, _ expected: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let given {
                    Text("You: ").foregroundStyle(Palette.muted) + Text(given).foregroundStyle(Palette.ink.opacity(0.75))
                }
                Text(expected).foregroundStyle(Palette.ink).font(.system(size: 14, design: .serif))
            }.font(.system(size: 13)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }.scrollIndicators(.hidden).frame(maxHeight: 120)
    }
}
