import XCTest

/// Guards the String Catalog: every string shown in the UI must ship in both
/// English (the source) and Vietnamese. Run scripts/sync-strings.sh after adding
/// UI text so new keys reach the catalog, then translate them.
final class LocalizationTests: XCTestCase {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable {
                    let state: String
                    let value: String
                }
                let stringUnit: StringUnit?
            }
            let localizations: [String: Localization]?
            let extractionState: String?
            let shouldTranslate: Bool?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func loadCatalog() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TwanClean/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    func testSourceLanguageIsEnglish() throws {
        XCTAssertEqual(try loadCatalog().sourceLanguage, "en")
    }

    func testEveryKeyHasVietnameseTranslation() throws {
        let catalog = try loadCatalog()
        let missing = catalog.strings.filter { _, entry in
            guard entry.shouldTranslate != false else { return false }
            guard let unit = entry.localizations?["vi"]?.stringUnit else { return true }
            return unit.state != "translated" || unit.value.isEmpty
        }
        XCTAssertTrue(missing.isEmpty, "Missing Vietnamese: \(missing.keys.sorted())")
    }

    func testNoStaleKeys() throws {
        let stale = try loadCatalog().strings.filter { $0.value.extractionState == "stale" }
        XCTAssertTrue(stale.isEmpty, "Remove stale keys: \(stale.keys.sorted())")
    }

    func testFormatSpecifiersMatchSource() throws {
        let pattern = try NSRegularExpression(pattern: #"%(\d+\$)?(lld|ld|d|@|f|\.\d+f|s|u|llu)"#)
        func specifiers(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }
                .sorted()
        }
        for (key, entry) in try loadCatalog().strings {
            guard let value = entry.localizations?["vi"]?.stringUnit?.value else { continue }
            XCTAssertEqual(specifiers(key), specifiers(value), "Format mismatch for \(key)")
        }
    }
}
