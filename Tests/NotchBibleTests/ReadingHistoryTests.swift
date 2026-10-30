import AppKit
import BibleCore
import XCTest
@testable import NotchBible

final class ReadingHistoryTests: XCTestCase {
    func testRecordingMovesRepeatsToFrontAndKeepsFifty() {
        var history = ReadingHistory()
        for chapter in 1...55 {
            history.record(HistoryEntry(reference: "Genesis \(chapter)", translation: "KJV", date: Date()))
        }
        XCTAssertEqual(history.entries.count, 50)
        XCTAssertEqual(history.entries.first?.reference, "Genesis 55")
        history.record(HistoryEntry(reference: "Genesis 20", translation: "KJV", date: Date()))
        history.record(HistoryEntry(reference: "Genesis 20", translation: "WEB", date: Date()))
        XCTAssertEqual(history.entries.prefix(2).map(\.translation), ["WEB", "KJV"])
        XCTAssertEqual(history.entries.filter { $0.reference == "Genesis 20" }.count, 2)
        XCTAssertEqual(ReadingHistory(stored: history.stored).entries, history.entries)
    }

    @MainActor
    func testRecordsSettledTextsAndNavigatesWithoutReordering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = (1...3).flatMap { chapter in (1...3).map { "GEN \(chapter):\($0) In the beginning." } }
        for name in ["KJV", "WEB"] {
            try records.joined(separator: "\n").write(to: directory.appendingPathComponent("\(name).txt"),
                                                      atomically: true, encoding: .utf8)
        }
        let suite = "ReadingHistoryTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = LookupModel(library: try BibleLibrary(directory: directory), preferences: preferences,
                                noteStore: NoteStore(url: directory.appendingPathComponent("Notes.json")))
        model.historyDelay = .milliseconds(50)
        let settle = { try await Task.sleep(for: .milliseconds(150)) }

        model.selectTranslation("KJV")
        model.query = "Genesis 1"
        try await settle()
        model.query = "Genesis 2"
        model.query = "Genesis 3"
        try await settle()
        XCTAssertEqual(model.history.entries.map(\.reference), ["Genesis 3", "Genesis 1"],
                       "Texts shown briefly are not recorded")

        model.selectTranslation("WEB")
        try await settle()
        XCTAssertEqual(model.history.entries.map(\.translation), ["WEB", "KJV", "KJV"])

        model.moveHistory(-1)
        XCTAssertEqual(model.selectedTranslation, "KJV")
        try await settle()
        model.moveHistory(-1)
        XCTAssertEqual(model.resultSummary, "Genesis 1")
        try await settle()
        XCTAssertEqual(model.history.entries.map(\.reference), ["Genesis 3", "Genesis 3", "Genesis 1"])
        XCTAssertNil(model.historyBackIndex)
        model.moveHistory(1)
        model.moveHistory(1)
        XCTAssertEqual(model.selectedTranslation, "WEB")
        XCTAssertNil(model.historyForwardIndex)

        model.showHistoryEntry(at: 2)
        try await settle()
        XCTAssertEqual(model.history.entries.first?.reference, "Genesis 1", "Choosing from the list is a new visit")
        XCTAssertEqual(ReadingHistory(stored: preferences.array(forKey: "readingHistory")).entries.count, 3)
    }
}
