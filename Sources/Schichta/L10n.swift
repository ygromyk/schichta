import Foundation

/// UI texts live in Resources/<de|en>.lproj/Localizable.strings under dotted keys ("notification.askLater").
/// Lookups take the app's own language setting, not the system language, so both tables are loaded side by side.
enum L10n {
    /// `key` in `language`; `args` fill `%1$@`, `%2$@`, … A missing key comes back as the key itself
    /// (the strings test keeps both tables complete).
    static func string(_ key: String, _ args: [String] = [], language: AppLanguage = .current) -> String {
        let format = bundles[language]?.localizedString(forKey: key, value: nil, table: nil) ?? key
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    /// SwiftPM's resource bundle. In Schichta.app it sits in Contents/Resources (build-desktop.sh copies it there;
    /// `Bundle.module` would look in the app's root, which code signing doesn't allow); `swift run` and the tests use `Bundle.module`.
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Schichta_Schichta.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    private nonisolated(unsafe) static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.compactMap { language in
            resourceBundle.url(forResource: language.rawValue, withExtension: "lproj")
                .flatMap(Bundle.init(url:))
                .map { (language, $0) }
        })
}
