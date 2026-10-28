import Foundation
import Testing
@testable import Schichta

@Suite("Localizable.strings")
struct LocalizationTests {
    static func table(_ language: AppLanguage) throws -> [String: String] {
        let url = try #require(L10n.resourceBundle.url(forResource: "Localizable", withExtension: "strings",
                                                       subdirectory: nil, localization: language.rawValue))
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    static func placeholders(_ text: String) -> [String] {
        let withoutEscapes = text.replacingOccurrences(of: "%%", with: "")
        return withoutEscapes.matches(of: /%\d+\$@/).map { String($0.output) }.sorted()
    }

    static let sources: String = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/Schichta")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }()

    @Test func bothLanguagesHaveTheSameKeys() throws {
        let de = try Self.table(.de), en = try Self.table(.en)
        #expect(Set(de.keys).subtracting(en.keys).sorted() == [], "only in de.lproj")
        #expect(Set(en.keys).subtracting(de.keys).sorted() == [], "only in en.lproj")
    }

    @Test func translationsTakeTheSameArguments() throws {
        let de = try Self.table(.de), en = try Self.table(.en)
        for (key, deText) in de {
            guard let enText = en[key] else { continue }
            #expect(Self.placeholders(deText) == Self.placeholders(enText), "\(key)")
        }
    }

    /// Catches typos and leftover texts at call sites: a missing key would show up in the UI as the key itself.
    @Test func everyKeyUsedInTheCodeExists() throws {
        let de = try Self.table(.de)
        let calls = /(?:\bt|say|SchichtaError|L10n\.string|LocalizedText)\(\s*(?:key:\s*)?"([^"\\]*)"/
        let used = Set(Self.sources.matches(of: calls).map { String($0.output.1) })
        #expect(!used.isEmpty)
        #expect(used.subtracting(de.keys).sorted() == [])
    }

    /// Keys built at runtime ("main.markedAs.\(absence.rawValue)") count through their literal prefix.
    @Test func everyKeyInTheTablesIsUsed() throws {
        let de = try Self.table(.de)
        let dynamicPrefixes = Self.sources.matches(of: /"([a-zA-Z][\w.]*\.)\\\(/).map { String($0.output.1) }
        let unused = de.keys.filter { key in
            !Self.sources.contains("\"\(key)\"") && !dynamicPrefixes.contains { key.hasPrefix($0) }
        }
        #expect(unused.sorted() == [])
    }

    @Test func argumentsFillInByPosition() {
        #expect(L10n.string("notification.morning.body", ["Monday"], language: .en) == "Your bookings from Monday have not been finalized yet.")
        #expect(L10n.string("git.shellHookError", ["2", "boom"], language: .de) == "Shell-Hook Fehler (Exit 2): boom")
        #expect(L10n.string("no.such.key", language: .en) == "no.such.key")
    }
}
