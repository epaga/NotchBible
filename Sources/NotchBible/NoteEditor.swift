import AppKit

@MainActor
final class NoteEditorPanel: NSPanel {
    let editor: NoteEditorViewController

    static func height(history: Int) -> CGFloat { history > 0 ? 226 : 190 }

    init(note: VerseNote, isExisting: Bool = true, history: [AnnotationChoice] = [],
         onAnnotationChange: @escaping (VerseNote) -> Void, onRemove: ((VerseNote) -> Bool)? = nil,
         onSave: @escaping (VerseNote) -> Bool) {
        editor = NoteEditorViewController(note: note, isExisting: isExisting, history: history,
                                          onAnnotationChange: onAnnotationChange, onRemove: onRemove, onSave: onSave)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 322, height: NoteEditorPanel.height(history: history.count)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Note"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentViewController = editor
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { _ = editor.save() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 36 || event.keyCode == 76 {
            _ = editor.save()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class NoteEditorViewController: NSViewController {
    private var note: VerseNote
    private let onAnnotationChange: (VerseNote) -> Void
    private let onRemove: ((VerseNote) -> Bool)?
    private let onSave: (VerseNote) -> Bool
    private let isExisting: Bool
    private let history: [AnnotationChoice]
    private var touched = false
    let text = NSTextView()
    private var styleButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private let colors = NSStackView()

    init(note: VerseNote, isExisting: Bool = true, history: [AnnotationChoice] = [],
         onAnnotationChange: @escaping (VerseNote) -> Void, onRemove: ((VerseNote) -> Bool)? = nil,
         onSave: @escaping (VerseNote) -> Bool) {
        self.note = note
        self.isExisting = isExisting
        self.history = history
        self.onAnnotationChange = onAnnotationChange
        self.onRemove = onRemove
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor
        root.layer?.cornerRadius = 12
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        root.appearance = NSAppearance(named: .darkAqua)
        view = root

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        text.string = note.text
        text.font = .systemFont(ofSize: 14)
        text.textColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        text.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 7, height: 7)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.allowsUndo = true
        text.setAccessibilityLabel("Note text")
        scroll.documentView = text

        let styles = NSStackView()
        styles.orientation = .horizontal
        styles.distribution = .fillEqually
        styles.spacing = 4
        for (index, style) in AnnotationStyle.allCases.enumerated() {
            let button = NSButton(image: AnnotationDrawing.icon(style, color: AnnotationColors.color(note.color)),
                                  target: self, action: #selector(selectStyle(_:)))
            button.tag = index
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.toolTip = style.name
            button.setAccessibilityLabel(style.name)
            button.setButtonType(.toggle)
            styleButtons.append(button)
            styles.addArrangedSubview(button)
        }
        colors.orientation = .horizontal
        colors.distribution = .fillEqually
        colors.spacing = 6
        for index in AnnotationColors.values.indices {
            let button = NSButton(image: NSImage(), target: self, action: #selector(selectColor(_:)))
            button.tag = index
            button.isBordered = false
            button.toolTip = AnnotationColors.names[index]
            button.setAccessibilityLabel(AnnotationColors.names[index])
            button.setButtonType(.toggle)
            colorButtons.append(button)
            colors.addArrangedSubview(button)
        }

        let recent = NSStackView()
        recent.orientation = .horizontal
        recent.distribution = .fillEqually
        recent.spacing = 4
        for (index, choice) in history.prefix(8).enumerated() {
            let button = NSButton(image: AnnotationDrawing.icon(choice.style, color: AnnotationColors.color(choice.color)),
                                  target: self, action: #selector(selectRecent(_:)))
            button.tag = index
            button.isBordered = false
            button.toolTip = "\(choice.style.name), \(AnnotationColors.names[choice.color])"
            button.setAccessibilityLabel(button.toolTip)
            recent.addArrangedSubview(button)
        }
        if history.count < 8 {
            // Keep each icon the same width as the style row above.
            for _ in history.count..<8 { recent.addArrangedSubview(NSView()) }
        }

        let stack = NSStackView(views: history.isEmpty ? [scroll, colors, styles] : [scroll, colors, styles, recent])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 94),
            styles.widthAnchor.constraint(equalTo: stack.widthAnchor),
            styles.heightAnchor.constraint(equalToConstant: 32),
            colors.widthAnchor.constraint(equalTo: stack.widthAnchor),
            colors.heightAnchor.constraint(equalToConstant: 24)
        ])
        if !history.isEmpty {
            NSLayoutConstraint.activate([
                recent.widthAnchor.constraint(equalTo: stack.widthAnchor),
                recent.heightAnchor.constraint(equalToConstant: 28)
            ])
        }
        refreshButtons()
    }

    func save() -> Bool {
        note.text = text.string
        // An annotation with no text is kept once the user has picked a look for it.
        let blank = note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if note.style == .delete || (!isExisting && !touched && blank) { return onRemove?(note) ?? true }
        return onSave(note)
    }

    @objc private func selectStyle(_ sender: NSButton) {
        let style = AnnotationStyle.allCases[sender.tag]
        if style == .delete {
            note.style = .delete
            _ = save()
            return
        }
        touched = true
        note.style = style
        refreshButtons()
        onAnnotationChange(note)
    }
    @objc private func selectRecent(_ sender: NSButton) {
        guard history.indices.contains(sender.tag) else { return }
        touched = true
        note.style = history[sender.tag].style
        note.color = history[sender.tag].color
        refreshButtons()
        onAnnotationChange(note)
    }
    @objc private func selectColor(_ sender: NSButton) {
        touched = true
        note.color = sender.tag
        refreshButtons()
        onAnnotationChange(note)
    }
    private func refreshButtons() {
        for (index, button) in styleButtons.enumerated() {
            let style = AnnotationStyle.allCases[index]
            button.image = AnnotationDrawing.icon(style, color: AnnotationColors.color(note.color))
            button.state = style == note.style ? .on : .off
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(style == note.style ? 0.14 : 0).cgColor
        }
        for (index, button) in colorButtons.enumerated() {
            button.state = index == note.color ? .on : .off
            button.image = NSImage(size: NSSize(width: 23, height: 23), flipped: true) { [note] _ in
                AnnotationColors.color(index).setFill()
                NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 17, height: 17)).fill()
                if index == note.color {
                    NSColor.white.setStroke()
                    let border = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 21, height: 21))
                    border.lineWidth = 1.3
                    border.stroke()
                }
                return true
            }
        }
    }
}
