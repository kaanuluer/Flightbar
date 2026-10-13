import Foundation

/// Looks up `key` in Localizable.strings. English is the key, so a missing
/// translation stays in English. Format arguments follow the Mac's locale.
func localized(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale.current, arguments: arguments)
}
