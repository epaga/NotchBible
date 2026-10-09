import AppKit
import BibleCore

@main
enum NotchBibleApp {
    @MainActor
    static func main() {
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let library = try BibleLibrary.bundled(additionalDirectory: BibleLibrary.userTranslationsDirectory)
            let arguments = Array(CommandLine.arguments.dropFirst())
            for warning in library.loadingWarnings {
                FileHandle.standardError.write(Data("NotchBible: \(warning)\n".utf8))
            }
            var bible = library.defaultTranslation
            if let index = arguments.firstIndex(of: "--translation"), arguments.indices.contains(index + 1) {
                let name = arguments[index + 1]
                guard let translation = library.bible(named: name) else { throw CLIError.message("No local translation named \(name).") }
                bible = translation
            }
            if arguments.contains("--check") {
                for bible in library.translations {
                    print("\(bible.translation): \(bible.bookCount) books, \(bible.chapterCount) chapters, \(bible.verses.count) verse addresses (\(bible.verses.filter { !$0.isOmitted }.count) with text).")
                }
                print(String(format: "Loaded and indexed locally in %.1f ms.", (CFAbsoluteTimeGetCurrent() - start) * 1_000))
                return
            }
            if let index = arguments.firstIndex(of: "--lookup"), arguments.indices.contains(index + 1) {
                let result = BibleLookupEngine(bible: bible).lookup(arguments[index + 1])
                if let error = result.error { throw CLIError.message(error) }
                if !result.suggestions.isEmpty {
                    print(result.suggestions.map(\.query).joined(separator: "\n"))
                } else if result.passages.isEmpty { print(result.hint ?? "No verses selected.") }
                else { print(bible.text(for: result.passages)) }
                return
            }
            if arguments.contains("--benchmark") {
                let parser = ReferenceParser(bible: bible)
                let fixtures = ["gen1,1", "Genesis 1:1", "gen1.1-2.3", "gen1.1;4:4-5", "John 3:16,18-20", "Psalm 119", "1cor13", "rev22:21", "genisis1:1", "ph1:1", "gen1-50"]
                var samples: [Double] = []
                for _ in 0..<100 {
                    for fixture in fixtures {
                        let time = CFAbsoluteTimeGetCurrent()
                        _ = parser.lookup(fixture)
                        samples.append((CFAbsoluteTimeGetCurrent() - time) * 1_000)
                    }
                }
                samples.sort()
                print(String(format: "%d lookups · p50 %.3f ms · p95 %.3f ms · max %.3f ms", samples.count, samples[samples.count / 2], samples[Int(Double(samples.count) * 0.95)], samples.last!))
                let lookup = BibleLookupEngine(bible: bible)
                let searches = ["created God", "\"for God\"", "love* -world", "book:gen book:ps created God", "in:ot God", "in:nt love", "in:ot in:nt God", "*love*", "-God", "*"]
                var searchSamples: [Double] = []
                for _ in 0..<100 {
                    for search in searches {
                        let time = CFAbsoluteTimeGetCurrent()
                        _ = lookup.lookup(search)
                        searchSamples.append((CFAbsoluteTimeGetCurrent() - time) * 1_000)
                    }
                }
                searchSamples.sort()
                print(String(format: "%d searches · p50 %.3f ms · p95 %.3f ms · max %.3f ms", searchSamples.count, searchSamples[searchSamples.count / 2], searchSamples[Int(Double(searchSamples.count) * 0.95)], searchSamples.last!))
                return
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate(library: library, preview: arguments.contains("--preview"))
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch {
            if CommandLine.arguments.count > 1 {
                FileHandle.standardError.write(Data("NotchBible: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let alert = NSAlert()
            alert.messageText = "NotchBible couldn’t open"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    private enum CLIError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
