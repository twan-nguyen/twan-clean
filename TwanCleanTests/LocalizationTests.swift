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

    private func catalogURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TwanClean/Resources/\(name).xcstrings")
    }

    private func loadCatalog(_ name: String = "Localizable") throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL(name)))
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

    /// The permission prompts and the app name shown by macOS come from here.
    func testInfoPlistIsTranslatedForEveryKey() throws {
        let catalog = try loadCatalog("InfoPlist")
        XCTAssertEqual(catalog.sourceLanguage, "en")
        XCTAssertFalse(catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            for language in ["en", "vi"] {
                let unit = entry.localizations?[language]?.stringUnit
                XCTAssertEqual(unit?.state, "translated", "\(key) is not translated to \(language)")
                XCTAssertFalse(unit?.value.isEmpty ?? true, "\(key) has no \(language) text")
            }
        }
    }

    /// English counts need singular and plural forms, or the UI says "1 items".
    func testCountedPhrasesHavePluralForms() throws {
        let data = try Data(contentsOf: catalogURL("Localizable"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        let counted = ["%lld locations skipped", "%lld items selected", "Move %lld items to the Trash?"]
        for key in counted {
            let english = (strings[key]?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let plural = (english?["variations"] as? [String: Any])?["plural"] as? [String: Any]
            XCTAssertNotNil(plural?["one"], "\(key) has no singular form")
            XCTAssertNotNil(plural?["other"], "\(key) has no plural form")
        }
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
