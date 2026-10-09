import Foundation

/// Discovers and indexes every local translation once. Each edition retains
/// its own addresses, omissions, and coverage; array offsets are never shared.
public final class BibleLibrary: Sendable {
    public let translations: [BibleStore]
    public let loadingWarnings: [String]
    public var defaultTranslation: BibleStore {
        translations.first { $0.translation.uppercased() == "NET" } ?? translations[0]
    }

    public static var userTranslationsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchBible/Translations", isDirectory: true)
    }

    public static func bundled(additionalDirectory: URL? = nil) throws -> BibleLibrary {
        guard let directory = BibleStore.resourceDirectory else { throw BibleDataError.missingResource }
        return try BibleLibrary(directory: directory, additionalDirectory: additionalDirectory)
    }

    public init(directory: URL, additionalDirectory: URL? = nil) throws {
        let files = try Self.textFiles(in: directory)
        guard !files.isEmpty else { throw BibleDataError.missingResource }
        var names = Set<String>()
        var translations: [BibleStore] = []
        var warnings: [String] = []
        func load(_ file: URL) throws {
            do {
                let stem = file.deletingPathExtension().lastPathComponent
                let prefix = stem.lowercased().hasSuffix("bible") ? String(stem.dropLast(5)) : stem
                let name = prefix.isEmpty ? stem : prefix
                guard !names.contains(name.lowercased()) else {
                    throw BibleDataError.invalidData("duplicate translation name: \(name)")
                }
                let text = try String(contentsOf: file, encoding: .utf8)
                translations.append(try BibleStore(text: text, translation: name, requiresCompleteBible: name.uppercased() == "NET"))
                names.insert(name.lowercased())
            } catch {
                throw BibleDataError.invalidData("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        for file in files { try load(file) }
        // Optional user files must not replace bundled editions or prevent launch.
        if let additionalDirectory, FileManager.default.fileExists(atPath: additionalDirectory.path) {
            do {
                for file in try Self.textFiles(in: additionalDirectory) {
                    do { try load(file) }
                    catch { warnings.append(error.localizedDescription) }
                }
            } catch {
                warnings.append("Couldn’t read \(additionalDirectory.path): \(error.localizedDescription)")
            }
        }
        self.loadingWarnings = warnings
        self.translations = translations.sorted {
            let firstIsNET = $0.translation.uppercased() == "NET"
            let secondIsNET = $1.translation.uppercased() == "NET"
            if firstIsNET != secondIsNET { return firstIsNET }
            return $0.translation.localizedStandardCompare($1.translation) == .orderedAscending
        }
    }

    private static func textFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.pathExtension.lowercased() == "txt" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public func bible(named translation: String) -> BibleStore? {
        translations.first { $0.translation.caseInsensitiveCompare(translation) == .orderedSame }
    }
}
