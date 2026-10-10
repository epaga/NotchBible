import AppKit
import BibleCore
import SwiftUI
import XCTest
@testable import NotchBible

final class PassageTextViewTests: XCTestCase {
    @MainActor
    private func passageScroll(in view: NSView) -> PassageScrollView? {
        if let scroll = view as? PassageScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.passageScroll(in: $0) }.first
    }

    @MainActor
    private func settleLayout(_ host: NSView) async {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    @MainActor
    func testNewChapterStartsAtTheTopAfterLayoutAndKeepsManualScrolling() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var records: [String] = []
        for chapter in [2, 23] {
            for verse in 1...25 {
                let body = chapter == 23 && verse == 1 ? "A short first verse." :
                    "A longer verse that wraps across lines in the passage with enough words to fill the viewport."
                records.append("GEN \(chapter):\(verse) \(body)")
            }
        }
        try records.joined(separator: "\n").write(to: directory.appendingPathComponent("TestBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        let suite = "PassageTextViewTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = LookupModel(library: library, preferences: preferences,
                                noteStore: NoteStore(url: directory.appendingPathComponent("Notes.json")))
        model.query = "Genesis 2"
        let host = NSHostingView(rootView: LookupView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 724, height: 650)
        await settleLayout(host)
        let scroll = try XCTUnwrap(passageScroll(in: host))
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.documentView!.frame.minY + 150))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settleLayout(host)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 150, accuracy: 0.1)
        model.query = "Genesis 23"
        await settleLayout(host)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.documentView!.frame.minY + 150))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settleLayout(host)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 150, accuracy: 0.1)
    }

    @MainActor
    func testTranslationSwitchKeepsTheTopVerseAcrossDifferentTextLengthsAndCoverage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["Alpha", "Beta"] {
            var records: [String] = []
            // Earlier coverage changes passage array indices between editions.
            if name == "Beta" { records.append("GEN 1:1 God in an earlier chapter.") }
            for chapter in [2, 23] {
                for verse in 1...40 where name != "Beta" || verse != 24 {
                    let body = "God in \(name) chapter \(chapter) verse \(verse). " +
                        String(repeating: "Words that wrap onto another line. ", count: name == "Alpha" ? 2 : 5)
                    records.append("GEN \(chapter):\(verse) \(body)")
                }
            }
            try records.joined(separator: "\n").write(to: directory.appendingPathComponent(name + "Bible.txt"),
                                                       atomically: true, encoding: .utf8)
        }
        let library = try BibleLibrary(directory: directory)
        let suite = "PassageTextViewTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = LookupModel(library: library, preferences: preferences,
                                noteStore: NoteStore(url: directory.appendingPathComponent("Notes.json")))
        model.query = "Genesis 23"
        let host = NSHostingView(rootView: LookupView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 724, height: 650)
        await settleLayout(host)
        let scroll = try XCTUnwrap(passageScroll(in: host))

        func firstLine(of verse: Int) throws -> NSRect {
            let text = try XCTUnwrap(scroll.documentView as? NSTextView)
            let layout = try XCTUnwrap(text.layoutManager)
            let body = "God in \(model.selectedTranslation) chapter 23 verse \(verse)."
            let range = (text.string as NSString).range(of: body)
            XCTAssertNotEqual(range.location, NSNotFound)
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                .offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
        }
        func scrollTo(_ verse: Int, offset: CGFloat = 0) throws {
            let line = try firstLine(of: verse)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.documentView!.frame.minY + line.minY + offset))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        try scrollTo(13, offset: 12)
        await settleLayout(host)
        model.selectTranslation("Beta")
        await settleLayout(host)
        XCTAssertEqual(scroll.documentVisibleRect.minY, try firstLine(of: 13).minY, accuracy: 0.1)
        model.selectTranslation("Alpha")
        await settleLayout(host)
        XCTAssertEqual(scroll.documentVisibleRect.minY, try firstLine(of: 13).minY, accuracy: 0.1)

        try scrollTo(24)
        await settleLayout(host)
        model.selectTranslation("Beta")
        await settleLayout(host)
        XCTAssertEqual(scroll.documentVisibleRect.minY, try firstLine(of: 25).minY, accuracy: 0.1)
        model.query = "Genesis 2"
        await settleLayout(host)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.1)
    }
}
