import AppKit
import BibleCore
import XCTest
@testable import NotchBible

final class PanelSizeTests: XCTestCase {
    func testManualSizeSurvivesLookupChangesAndAnotherLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "GEN 1:1 In the beginning.\nGEN 1:2 The earth.\n"
            .write(to: directory.appendingPathComponent("SampleBible.txt"), atomically: true, encoding: .utf8)
        let library = try BibleLibrary(directory: directory)
        await MainActor.run {
            let suite = "NotchBibleTests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let model = LookupModel(library: library, preferences: preferences)
            XCTAssertNil(model.preferredPanelSize)
            model.query = "gen1:1"
            model.savePanelSize()
            XCTAssertNil(preferences.object(forKey: "panelSize"))

            let size = NSSize(width: 740, height: 520)
            model.setPanelSize(size)
            model.resizedPanelHeight = size.height
            model.savePanelSize()
            for query in ["gen1:1", "gen1", "unknown book", ""] {
                model.query = query
                XCTAssertEqual(model.panelHeight, size.height)
                XCTAssertEqual(model.preferredPanelSize, size)
                XCTAssertEqual(model.bodyHeight + model.panelChromeHeight, size.height)
            }
            let nextLaunch = LookupModel(library: library, preferences: preferences)
            XCTAssertEqual(nextLaunch.preferredPanelSize, size)

            // Invalid stored dimensions must fall back to the normal layout.
            for invalidSize in [["width": -1.0, "height": 520.0],
                                ["width": 740.0, "height": 0.0],
                                ["width": Double.infinity, "height": 520.0]] {
                preferences.set(invalidSize, forKey: "panelSize")
                XCTAssertNil(LookupModel(library: library, preferences: preferences).preferredPanelSize)
            }
        }
    }
}
