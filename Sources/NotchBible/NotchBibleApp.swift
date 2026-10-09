import AppKit
import BibleCore

@main
enum NotchBibleApp {
    @MainActor
    static func main() {
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let bible = try BibleStore.bundled()
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.contains("--check") {
                print("NET Bible: 66 books, \(bible.chapterCount) chapters, \(bible.verses.count) verse addresses (\(bible.verses.filter { !$0.isOmitted }.count) with text).")
                print(String(format: "Loaded and indexed locally in %.1f ms.", (CFAbsoluteTimeGetCurrent() - start) * 1_000))
                return
            }
            if let index = arguments.firstIndex(of: "--lookup"), arguments.indices.contains(index + 1) {
                let result = ReferenceParser(bible: bible).lookup(arguments[index + 1])
                if let error = result.error { throw CLIError.message(error) }
                if !result.suggestions.isEmpty {
                    print(result.suggestions.map(\.query).joined(separator: "\n"))
                } else { print(bible.text(for: result.passages)) }
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
                return
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate(bible: bible, preview: arguments.contains("--preview"))
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
