import Foundation

/// Discovers and indexes every local translation once. Each edition retains
/// its own addresses, omissions, and coverage; array offsets are never shared.
public final class BibleLibrary: Sendable {
    public let translations: [BibleStore]
    public var defaultTranslation: BibleStore {
        translations.first { $0.translation.uppercased() == "NET" } ?? translations[0]
    }

    public static func bundled() throws -> BibleLibrary {
        guard let directory = BibleStore.resourceDirectory else { throw BibleDataError.missingResource }
        return try BibleLibrary(directory: directory)
    }

    public init(directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.pathExtension.lowercased() == "txt" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        guard !files.isEmpty else { throw BibleDataError.missingResource }
        var names = Set<String>()
        var translations: [BibleStore] = []
        for file in files {
            let stem = file.deletingPathExtension().lastPathComponent
            let prefix = stem.lowercased().hasSuffix("bible") ? String(stem.dropLast(5)) : stem
            let name = prefix.isEmpty ? stem : prefix
            guard names.insert(name.lowercased()).inserted else {
                throw BibleDataError.invalidData("duplicate translation name: \(name)")
            }
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                translations.append(try BibleStore(text: text, translation: name, requiresCompleteBible: name.uppercased() == "NET"))
            } catch {
                throw BibleDataError.invalidData("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        self.translations = translations.sorted {
            let firstIsNET = $0.translation.uppercased() == "NET"
            let secondIsNET = $1.translation.uppercased() == "NET"
            if firstIsNET != secondIsNET { return firstIsNET }
            return $0.translation.localizedStandardCompare($1.translation) == .orderedAscending
        }
    }

    public func bible(named translation: String) -> BibleStore? {
        translations.first { $0.translation.caseInsensitiveCompare(translation) == .orderedSame }
    }
}
