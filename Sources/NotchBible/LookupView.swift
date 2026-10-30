import BibleCore
import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.94, green: 0.92, blue: 0.87)
    static let muted = Color(red: 0.56, green: 0.55, blue: 0.52)
    static let gold = Color(red: 0.88, green: 0.71, blue: 0.46)
}

struct LookupView: View {
    @ObservedObject var model: LookupModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ReferenceField(model: model)
                historyButtons
                Button { model.setFlashcardMode(!model.flashcardMode) } label: {
                    Image(systemName: model.flashcardMode ? "rectangle.stack.fill" : "rectangle.stack")
                        .font(.system(size: 15))
                        .foregroundStyle(model.flashcardMode ? Palette.gold : Palette.muted)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help(model.flashcardMode ? "Leave flashcard mode" : "Flashcards")
                    .accessibilityLabel("Flashcard mode")
                    .accessibilityAddTraits(model.flashcardMode ? .isSelected : [])
            }
                .frame(height: 30)
                .padding(.horizontal, 25).padding(.vertical, 20)
            if model.flashcardMode {
                Rectangle().fill(Color.white.opacity(0.075)).frame(height: 1).padding(.horizontal, 25)
                FlashcardView(model: model.flashcards).frame(height: model.bodyHeight, alignment: .top)
            } else if !model.isEmpty {
                Rectangle().fill(Color.white.opacity(0.075)).frame(height: 1).padding(.horizontal, 25)
                Group {
                    if let error = model.result.error { errorView(error) }
                    else if !model.result.suggestions.isEmpty { suggestions }
                    else if model.hasPassages { passages }
                    else if let hint = model.result.hint { errorView(hint) }
                }.frame(height: model.bodyHeight, alignment: .top)
            } else {
                syntaxHelp.frame(height: model.bodyHeight, alignment: .top)
            }
            if !model.flashcardMode { translationTabs.frame(height: model.translationBarHeight) }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(white: 0.16), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    .padding(.bottom, 48).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, model.notchWidth > 0 ? NotchLayout.topInset : 0)
        .background {
            NotchSurface(notchWidth: model.notchWidth)
                .fill(Color.black)
                .overlay {
                    GeometryReader { geometry in
                        let border = Color.white.opacity(0.14)
                        let connected = model.notchWidth > 0
                        let height = max(1, geometry.size.height)
                        NotchSurface(notchWidth: model.notchWidth, outline: true)
                            .stroke(LinearGradient(
                                colors: [connected ? .black : border, border],
                                startPoint: UnitPoint(x: 0.5, y: connected ? NotchLayout.overlap / height : 0),
                                endPoint: UnitPoint(x: 0.5, y: connected ? NotchLayout.topInset / height : 1)
                            ), lineWidth: 0.75)
                    }
                }
        }
        .padding(.horizontal, 10).padding(.bottom, 12).padding(.top, model.notchWidth > 0 ? 0 : 6)
        .overlay(alignment: .bottomTrailing) {
            PanelResizeHandle().frame(width: 24, height: 24)
                .padding(.trailing, 16).padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
    }

    private var historyButtons: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                historyArrow("chevron.left", label: "Back", enabled: model.historyBackIndex != nil) { model.moveHistory(-1) }
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 16)
                historyArrow("chevron.right", label: "Forward", enabled: model.historyForwardIndex != nil) { model.moveHistory(1) }
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.14)))
            GeometryReader { geometry in
                Button { HistoryMenu.show(for: model, below: geometry.frame(in: .global)) } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(model.history.entries.isEmpty)
                    .accessibilityLabel("History")
            }.frame(width: 30, height: 30)
        }
    }

    private func historyArrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted.opacity(enabled ? 1 : 0.4))
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label)
    }

    private func errorView(_ error: String) -> some View {
        Text(error).font(.system(size: 13)).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(25)
    }

    private var syntaxHelp: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                helpExample("John 3:16", "A single verse")
                helpExample("John 3:16-18", "A verse range")
                helpExample("Psalm 23", "A whole chapter")
                helpExample("Gen1:1;John3:16", "Multiple passages")
                helpExample("created God", "Both words, in any order")
                helpExample("\"for God\"", "An exact phrase")
                helpExample("note:love", "Search only notes")
                helpExample("note:\"for God\"", "An exact phrase in notes")
                helpExample("note:*", "All notes; counts on translation tabs")
                helpExample("love -world", "Exclude a word")
                helpExample("love* / *love*", "Words starting with / containing love")
                helpExample("book:gen love", "Search one book")
                helpExample("in:nt love", "New Testament; in:ot for Old Testament")
            }
            .font(.system(size: 11)).foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 25).padding(.top, 12).padding(.bottom, 20)
        }.scrollIndicators(.hidden)
    }

    private func helpExample(_ example: String, _ explanation: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(example).monospaced().fixedSize()
            Text(explanation).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var translationTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(model.library.translations) { bible in
                    let selected = bible.translation == model.selectedTranslation
                    let count = model.noteCount(for: bible.translation)
                    Button { model.selectTranslation(bible.translation) } label: {
                        VStack(spacing: 5) {
                            HStack(spacing: 4) {
                                Text(bible.translation)
                                    .font(.system(size: 10, weight: selected ? .medium : .regular))
                                    .foregroundStyle(selected ? Palette.ink : Palette.muted)
                                if count > 0 || model.isAllNotesSearch {
                                    Text("\(count)").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                        .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                                        .background(Palette.gold.opacity(0.25), in: Capsule())
                                }
                            }
                            Capsule().fill(selected ? Palette.ink.opacity(0.8) : .clear)
                                .frame(height: 1)
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .help(bible.attribution ?? bible.translation)
                        .accessibilityLabel(bible.translation)
                        .accessibilityValue(model.isAllNotesSearch ? "\(count) notes" : (count > 0 ? "\(count) notes for visible verses" : ""))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(.horizontal, 25)
        }.scrollIndicators(.hidden)
    }

    private var suggestions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.result.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button { model.choose(suggestion) } label: {
                            HStack {
                                Text(suggestion.book.name).font(.system(size: 17, weight: .regular, design: .serif))
                                Spacer()
                                if index == model.selectedSuggestion {
                                    Image(systemName: "arrow.turn.down.left").font(.system(size: 10)).foregroundStyle(Palette.gold)
                                }
                            }
                            .foregroundStyle(Palette.ink).padding(.horizontal, 15).frame(height: 43)
                            .background(index == model.selectedSuggestion ? Color.white.opacity(0.07) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).id(suggestion.id)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 11)
            }.onChange(of: model.selectedSuggestion) { _, index in
                guard model.result.suggestions.indices.contains(index) else { return }
                proxy.scrollTo(model.result.suggestions[index].id)
            }
        }
    }

    private var passages: some View {
        let bible = model.bible
        let passages = model.displayPassages
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(model.resultSummary)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.gold.opacity(0.9))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if model.searchPageCount > 1 {
                    searchPageButton("chevron.left", delta: -1, disabled: model.searchPage == 0)
                    searchPageButton("chevron.right", delta: 1, disabled: model.searchPage + 1 == model.searchPageCount)
                }
                Button { model.addFlashcards() } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!model.canAddFlashcard)
                    .opacity(model.canAddFlashcard ? 1 : 0.35)
                    .help("Add to flashcards (Stove)")
                    .accessibilityLabel("Add passage to flashcards")
                Button { model.copy() } label: {
                    Image(systemName: model.copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(model.copied ? Color(red: 0.66, green: 0.79, blue: 0.61) : Palette.muted)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!model.result.canCopy)
                    .opacity(model.result.canCopy ? 1 : 0.35)
                    .help(model.result.isSearch ? "Copy all matching verses · ↵ or ⇧⌘C" : "Copy passage · ↵ or ⇧⌘C")
                    .accessibilityLabel(model.copied ? "Verses copied" : (model.result.isSearch ? "Copy all matching verses" : "Copy passage"))
            }.padding(.horizontal, 25).padding(.top, 12).padding(.bottom, 11)

            PassageTextView(model: model, bible: bible, passages: passages, showsReferences: model.result.isSearch) { reference in
                model.query = reference
                model.focus()
            }
                .frame(height: max(0, model.bodyHeight - 51)).clipped()
        }
    }

    private func searchPageButton(_ symbol: String, delta: Int, disabled: Bool) -> some View {
        Button { model.moveSearchPage(delta) } label: {
            Image(systemName: symbol).font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .frame(width: 24, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.35 : 1)
            .help(delta < 0 ? "Previous matching verses" : "Next matching verses")
            .accessibilityLabel(delta < 0 ? "Previous matching verses" : "Next matching verses")
    }
}

/// One black silhouette grows out of the camera area. The outline follows its
/// shoulders and rounded corners, leaving the connection to the notch open.
private struct NotchSurface: Shape {
    var notchWidth: CGFloat
    var outline = false

    func path(in rect: CGRect) -> Path {
        guard notchWidth > 0 else {
            return Path(roundedRect: rect, cornerRadius: 21)
        }
        let radius: CGFloat = 21
        let shoulder = NotchLayout.shoulder
        let k: CGFloat = 0.5522847498
        let halfNotch = min(notchWidth / 2, rect.width / 2 - radius - shoulder)
        let left = rect.midX - halfNotch
        let right = rect.midX + halfNotch
        let join = rect.minY + NotchLayout.overlap
        let top = join + shoulder
        var path = Path()
        path.move(to: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: join))
        path.addCurve(to: CGPoint(x: right + shoulder, y: top),
                      control1: CGPoint(x: right, y: join + shoulder * k),
                      control2: CGPoint(x: right + shoulder * (1 - k), y: top))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addCurve(to: CGPoint(x: rect.maxX, y: top + radius),
                      control1: CGPoint(x: rect.maxX - radius * (1 - k), y: top),
                      control2: CGPoint(x: rect.maxX, y: top + radius * (1 - k)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY - radius * (1 - k)),
                      control2: CGPoint(x: rect.maxX - radius * (1 - k), y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                      control1: CGPoint(x: rect.minX + radius * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.maxY - radius * (1 - k)))
        path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
        path.addCurve(to: CGPoint(x: rect.minX + radius, y: top),
                      control1: CGPoint(x: rect.minX, y: top + radius * (1 - k)),
                      control2: CGPoint(x: rect.minX + radius * (1 - k), y: top))
        path.addLine(to: CGPoint(x: left - shoulder, y: top))
        path.addCurve(to: CGPoint(x: left, y: join),
                      control1: CGPoint(x: left - shoulder * (1 - k), y: top),
                      control2: CGPoint(x: left, y: join + shoulder * k))
        path.addLine(to: CGPoint(x: left, y: rect.minY))
        if !outline { path.closeSubpath() }
        return path
    }
}

@MainActor
private final class HistoryMenu: NSObject {
    private static var current: HistoryMenu?
    private let model: LookupModel

    private init(model: LookupModel) { self.model = model }

    static func show(for model: LookupModel, below frame: CGRect) {
        guard let host = NSApp.windows.first(where: { $0 is LookupPanel })?.contentView else { return }
        let target = HistoryMenu(model: model)
        current = target
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        for (index, entry) in model.history.entries.enumerated() {
            let title = NSMutableAttributedString(string: "\(entry.reference)  ", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph
            ])
            title.append(NSAttributedString(string: entry.translation, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor
            ]))
            title.append(NSAttributedString(string: "\n" + entry.date.formatted(date: .abbreviated, time: .shortened), attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph
            ]))
            let item = NSMenuItem(title: entry.reference, action: #selector(choose(_:)), keyEquivalent: "")
            item.attributedTitle = title
            item.target = target
            item.tag = index
            if model.shownHistoryEntry.map(entry.matches) == true { item.state = .on }
            menu.addItem(item)
        }
        let flipped = host.isFlipped
        let point = NSPoint(x: frame.minX, y: flipped ? frame.maxY + 4 : host.bounds.height - frame.maxY - 4)
        menu.popUp(positioning: nil, at: point, in: host)
    }

    @objc private func choose(_ item: NSMenuItem) { model.showHistoryEntry(at: item.tag) }
}
