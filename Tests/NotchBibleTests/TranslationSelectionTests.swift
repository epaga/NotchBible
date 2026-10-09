import Foundation
import XCTest
import BibleCore
@testable import NotchBible

final class TranslationSelectionTests: XCTestCase {
    func testSwitchingTranslationsChangesReferenceLanguageAndSuggestions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "GEN 1:1 God appears in this test verse.\n"
            .write(to: directory.appendingPathComponent("EnglishBible.txt"), atomically: true, encoding: .utf8)
        try "GEN 1:1 Gott steht in diesem Testvers.\n"
            .write(to: directory.appendingPathComponent("DeutschBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        await MainActor.run {
            let suite = "NotchBibleTests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let model = LookupModel(library: library, preferences: preferences)
            model.selectTranslation("English")
            model.query = "gen1:1"
            XCTAssertEqual(model.resultSummary, "Genesis 1:1")
            model.selectTranslation("Deutsch")
            XCTAssertEqual(model.query, "gen1:1")
            XCTAssertEqual(model.resultSummary, "1. Mose 1:1")
            XCTAssertTrue(model.bible.text(for: model.result.passages).hasPrefix("1. Mose 1:1 (Deutsch)"))
            model.query = "1.Mo"
            XCTAssertEqual(model.result.suggestions.first?.book.name, "1. Mose")
            model.submit()
            XCTAssertEqual(model.query, "1. Mose 1:1")
            XCTAssertEqual(model.resultSummary, "1. Mose 1:1")
        }
    }

    func testSearchUsesSelectedTranslationAndKeepsAllHitsForCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let alpha = (1...120).map { "GEN 1:\($0) God created love." }.joined(separator: "\n")
        try alpha.write(to: directory.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        try "PSA 1:1 God created hope.\nPSA 1:2 Love.\n"
            .write(to: directory.appendingPathComponent("BetaBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        await MainActor.run {
            let suite = "NotchBibleTests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let model = LookupModel(library: library, preferences: preferences)
            model.query = "book:gen book:ps CREATED god"
            XCTAssertTrue(model.result.isSearch)
            XCTAssertEqual(model.result.verseCount, 120)
            XCTAssertEqual(model.displayPassages.count, 100)
            XCTAssertEqual(model.resultSummary, "120 verses · 1–100")
            XCTAssertTrue(model.bible.text(for: model.result.passages).contains("Genesis 1:120 (Alpha)"))
            XCTAssertEqual(model.searchPageCount, 2)
            model.moveSearchPage(1)
            XCTAssertEqual(model.displayPassages.count, 20)
            XCTAssertEqual(model.displayPassages.first?.reference, "Genesis 1:101")
            XCTAssertEqual(model.resultSummary, "120 verses · 101–120")
            model.moveSearchPage(1)
            XCTAssertEqual(model.searchPage, 1)
            model.moveSearchPage(-1)
            XCTAssertEqual(model.searchPage, 0)
            model.moveSearchPage(-1)
            XCTAssertEqual(model.searchPage, 0)
            model.moveSearchPage(1)
            model.selectTranslation("Beta")
            XCTAssertEqual(model.searchPage, 0)
            XCTAssertEqual(model.query, "book:gen book:ps CREATED god")
            XCTAssertEqual(model.result.verseCount, 1)
            XCTAssertEqual(model.resultSummary, "1 verse")
            XCTAssertEqual(model.displayPassages.first?.reference, "Psalms 1:1")
            let copy = model.bible.text(for: model.result.passages)
            XCTAssertTrue(copy.contains("God created hope."))
            XCTAssertTrue(copy.contains("(Beta)"))
            XCTAssertFalse(copy.contains("Alpha"))
            model.query = "notaword"
            XCTAssertFalse(model.hasPassages)
            XCTAssertFalse(model.result.canCopy)
            XCTAssertNotNil(model.result.hint)
            XCTAssertEqual(model.searchPageCount, 0)
        }
    }

    func testSelectionReparsesTheReferenceAndPersistsAcrossLaunches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "GEN 1:1 Alpha\nGEN 1:2 Alpha\nHEB 13:7 Alpha seven\nHEB 13:13 Alpha thirteen\n"
            .write(to: directory.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        try "HEB 13:7 Beta seven\nHEB 13:13 Beta thirteen\n"
            .write(to: directory.appendingPathComponent("BetaBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        await MainActor.run {
            let suite = "NotchBibleTests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let model = LookupModel(library: library, preferences: preferences)
            XCTAssertEqual(model.selectedTranslation, "Alpha")
            model.query = "heb13.7+13"
            XCTAssertEqual(model.result.passages.first?.range.lowerBound, 2)
            model.copied = true
            model.selectTranslation("Beta")
            XCTAssertEqual(model.query, "heb13.7+13")
            XCTAssertEqual(model.selectedTranslation, "Beta")
            XCTAssertEqual(model.result.passages.first?.range.lowerBound, 0)
            XCTAssertEqual(model.result.verseCount, 2)
            XCTAssertFalse(model.copied)
            let copy = model.bible.text(for: model.result.passages)
            XCTAssertTrue(copy.contains("Beta seven"))
            XCTAssertTrue(copy.contains("(Beta)"))
            XCTAssertFalse(copy.contains("Alpha"))
            let nextLaunch = LookupModel(library: library, preferences: preferences)
            XCTAssertEqual(nextLaunch.selectedTranslation, "Beta")
            nextLaunch.query = "gen1:1"
            XCTAssertNotNil(nextLaunch.result.error)
            XCTAssertFalse(nextLaunch.result.canCopy)
            nextLaunch.selectTranslation("Alpha")
            XCTAssertEqual(nextLaunch.query, "gen1:1")
            XCTAssertTrue(nextLaunch.result.canCopy)
            preferences.set("Removed translation", forKey: "selectedTranslation")
            XCTAssertEqual(LookupModel(library: library, preferences: preferences).selectedTranslation, "Alpha")
        }
    }
}
