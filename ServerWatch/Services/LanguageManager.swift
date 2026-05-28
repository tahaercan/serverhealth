import Foundation
import SwiftUI

/// In-app language switching.
///
/// iOS resolves the app's display language at launch from the `AppleLanguages`
/// UserDefault. There is no robust API on iOS 17+ to change the active
/// localization bundle at runtime — SwiftUI's text lookup happens through
/// internal mechanisms that ignore `Bundle.main` class swizzling.
///
/// So our model is:
///   - User picks a language → we write `AppleLanguages` (and our own
///     `appLanguage` key, used to remember the choice across launches).
///   - On next launch iOS automatically loads the matching `.lproj` bundle.
///   - We show a one-time notice in Settings: "Restart the app to apply."
///
/// On a fresh install with no override set, the device's system language
/// (already in `AppleLanguages`) wins. If the device language is not one of
/// our 7 supported, iOS falls back to the development language (English).
@MainActor
final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    static let supported: [Language] = [
        Language(code: "en",    name: "English"),
        Language(code: "tr",    name: "Türkçe"),
        Language(code: "fr",    name: "Français"),
        Language(code: "de",    name: "Deutsch"),
        Language(code: "es",    name: "Español"),
        Language(code: "it",    name: "Italiano"),
        Language(code: "pt-BR", name: "Português (Brasil)"),
    ]

    struct Language: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }

    private static let overrideKey      = "appLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    /// User's explicit choice; "" means "follow system".
    @Published private(set) var override: String

    /// The language that's actually displayed right now (resolved from the
    /// override, or from the system). Use this to label things in Settings.
    @Published private(set) var currentLanguage: String

    /// True if the user changed the language since app launch — UI uses this
    /// to show a "restart required" hint.
    @Published private(set) var pendingRestart: Bool = false

    private init() {
        let storedOverride = UserDefaults.standard.string(forKey: Self.overrideKey) ?? ""
        self.override = storedOverride
        self.currentLanguage = Self.resolveCurrentLanguage(override: storedOverride)
    }

    /// Apply a user choice. Writes to `AppleLanguages` so iOS picks it up on
    /// the next launch. Returns nothing; UI shows the "restart" hint via
    /// `pendingRestart`.
    func setOverride(_ code: String) {
        let defaults = UserDefaults.standard
        if code.isEmpty {
            // Follow system → remove our overrides; iOS resolves from the device.
            defaults.removeObject(forKey: Self.overrideKey)
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set(code, forKey: Self.overrideKey)
            defaults.set([code], forKey: Self.appleLanguagesKey)
        }
        defaults.synchronize()
        override = code
        pendingRestart = true
        objectWillChange.send()
    }

    /// Resolve which language code is currently being used for display.
    /// Used purely for UI labelling (which option is "current" in the picker).
    private static func resolveCurrentLanguage(override: String) -> String {
        if !override.isEmpty { return override }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let supportedCodes = Set(supported.map(\.code))
        if supportedCodes.contains(preferred) { return preferred }
        let primary = String(preferred.split(separator: "-").first ?? "en")
        if supportedCodes.contains(primary) { return primary }
        if primary == "pt" { return "pt-BR" }
        return "en"
    }
}
