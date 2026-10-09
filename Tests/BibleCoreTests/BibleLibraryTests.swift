import Foundation
import XCTest
@testable import BibleCore

final class BibleLibraryTests: XCTestCase {
    func testDiscoversTextFilesAndUsesFilenamePrefixes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "GEN 1:1 Alpha text\nGEN 1:2 \n".write(to: directory.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        try "HEB 13:7 Beta text\nHEB 13:13 Another Beta verse\n".write(to: directory.appendingPathComponent("BetaBible.TXT"), atomically: true, encoding: .utf8)
        try "Ignored".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        XCTAssertEqual(library.translations.map(\.translation), ["Alpha", "Beta"])
        let alpha = try XCTUnwrap(library.bible(named: "ALPHA"))
        XCTAssertEqual(alpha.bookCount, 1)
        XCTAssertEqual(alpha.chapterCount, 1)
        XCTAssertEqual(ReferenceParser(bible: alpha).lookup("gen1").passages.map(\.reference), ["Genesis 1"])
        let omitted = ReferenceParser(bible: alpha).lookup("gen1:2")
        XCTAssertTrue(alpha.text(for: omitted.passages).contains("(Alpha)"))
        XCTAssertTrue(alpha.text(for: omitted.passages).contains("this Alpha edition"))
        XCTAssertFalse(alpha.text(for: omitted.passages).contains(BibleStore.copyright))
        let beta = try XCTUnwrap(library.bible(named: "Beta"))
        let lookup = ReferenceParser(bible: beta).lookup("heb13.7+13")
        XCTAssertNil(lookup.error)
        XCTAssertEqual(lookup.verseCount, 2)
        XCTAssertEqual(lookup.passages.map(\.reference), ["Hebrews 13:7", "Hebrews 13:13"])
        XCTAssertTrue(ReferenceParser(bible: beta).lookup("gen1:1").error?.contains("isn’t included in Beta") == true)
    }

    func testBundledTranslationsUseTheirOwnVerseNumbering() throws {
        let library = try BibleLibrary.bundled()
        XCTAssertEqual(library.defaultTranslation.translation, "NET")
        let sourceNames = try FileManager.default.contentsOfDirectory(at: XCTUnwrap(BibleStore.resourceDirectory), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "txt" }
            .map { String($0.deletingPathExtension().lastPathComponent.dropLast(5)) }
        XCTAssertEqual(Set(library.translations.map(\.translation)), Set(sourceNames))
        for bible in library.translations {
            let result = ReferenceParser(bible: bible).lookup("heb13.7+13")
            XCTAssertNil(result.error, bible.translation)
            XCTAssertEqual(result.verseCount, 2, bible.translation)
            for passage in result.passages {
                XCTAssertEqual(bible.verses[passage.range].first?.book.name, "Hebrews", bible.translation)
            }
        }
        // The supplied ESV/NASB editions include a fifteenth verse in 3 John;
        // NGU has partial Old Testament coverage. NET's limits must not leak.
        if let esv = library.bible(named: "ESV") {
            XCTAssertTrue(ReferenceParser(bible: esv).lookup("3john15").canCopy)
        }
        if let ngu = library.bible(named: "NGU") {
            XCTAssertTrue(ReferenceParser(bible: ngu).lookup("ps1:1").canCopy)
            XCTAssertNotNil(ReferenceParser(bible: ngu).lookup("gen1:1").error)
        }
    }

    func testInvalidResourceNamesTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "Invalid record".write(to: directory.appendingPathComponent("BrokenBible.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try BibleLibrary(directory: directory)) { error in
            XCTAssertTrue(error.localizedDescription.contains("BrokenBible.txt"))
        }
    }

    func testUserTranslationsMergeAndRemovalIsPickedUpOnNextLoad() throws {
        let directories = try makeTranslationDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        try "GEN 1:1 Bundled text\n".write(to: directories.bundled.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        let personalFile = directories.user.appendingPathComponent("PersonalBible.TXT")
        try "HEB 13:7 Personal hope\nHEB 13:13 More hope\n".write(to: personalFile, atomically: true, encoding: .utf8)
        try "Ignored".write(to: directories.user.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let library = try BibleLibrary(directory: directories.bundled, additionalDirectory: directories.user)
        XCTAssertEqual(library.translations.map(\.translation), ["Alpha", "Personal"])
        XCTAssertTrue(library.loadingWarnings.isEmpty)
        let personal = try XCTUnwrap(library.bible(named: "PERSONAL"))
        XCTAssertEqual(ReferenceParser(bible: personal).lookup("heb13.7+13").verseCount, 2)
        XCTAssertEqual(BibleLookupEngine(bible: personal).lookup("hope").verseCount, 2)

        try FileManager.default.removeItem(at: personalFile)
        let nextLaunch = try BibleLibrary(directory: directories.bundled, additionalDirectory: directories.user)
        XCTAssertEqual(nextLaunch.translations.map(\.translation), ["Alpha"])
        XCTAssertTrue(nextLaunch.loadingWarnings.isEmpty)
    }

    func testMissingUserDirectoryUsesBundledTranslations() throws {
        let directories = try makeTranslationDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        try "GEN 1:1 Bundled text\n".write(to: directories.bundled.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: directories.user)

        let library = try BibleLibrary(directory: directories.bundled, additionalDirectory: directories.user)
        XCTAssertEqual(library.translations.map(\.translation), ["Alpha"])
        XCTAssertTrue(library.loadingWarnings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.user.path))
    }

    func testBadAndDuplicateUserFilesDoNotHideBundledTranslations() throws {
        let directories = try makeTranslationDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        try "GEN 1:1 Bundled text\n".write(to: directories.bundled.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        try "GEN 1:1 Replacement\n".write(to: directories.user.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try "Invalid record".write(to: directories.user.appendingPathComponent("BrokenBible.txt"), atomically: true, encoding: .utf8)
        try "PSA 1:1 Personal text\n".write(to: directories.user.appendingPathComponent("PersonalBible.txt"), atomically: true, encoding: .utf8)

        let library = try BibleLibrary(directory: directories.bundled, additionalDirectory: directories.user)
        XCTAssertEqual(library.translations.map(\.translation), ["Alpha", "Personal"])
        XCTAssertEqual(library.defaultTranslation.verses.first?.text, "Bundled text")
        XCTAssertEqual(library.loadingWarnings.count, 2)
        XCTAssertTrue(library.loadingWarnings.contains { $0.contains("alpha.txt") && $0.contains("duplicate translation name") })
        XCTAssertTrue(library.loadingWarnings.contains { $0.contains("BrokenBible.txt") })
    }

    func testUserPathThatIsNotDirectoryReportsWarningWithoutPreventingLaunch() throws {
        let directories = try makeTranslationDirectories()
        defer { try? FileManager.default.removeItem(at: directories.root) }
        try "GEN 1:1 Bundled text\n".write(to: directories.bundled.appendingPathComponent("AlphaBible.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: directories.user)
        try "Not a directory".write(to: directories.user, atomically: true, encoding: .utf8)

        let library = try BibleLibrary(directory: directories.bundled, additionalDirectory: directories.user)
        XCTAssertEqual(library.translations.map(\.translation), ["Alpha"])
        XCTAssertEqual(library.loadingWarnings.count, 1)
        XCTAssertTrue(library.loadingWarnings[0].contains(directories.user.path))
    }

    private func makeTranslationDirectories() throws -> (root: URL, bundled: URL, user: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundled = root.appendingPathComponent("Bundled", isDirectory: true)
        let user = root.appendingPathComponent("User", isDirectory: true)
        for directory in [bundled, user] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return (root, bundled, user)
    }
}
