import AppKit
import Foundation

/// Last saved window position (bottom-left origin in global screen
/// coordinates) plus the screen it was on.
struct SavedWindowPosition: Equatable {
    var origin: CGPoint
    var screenID: CGDirectDisplayID?
    var screenName: String?
}

/// AppKit-side access to the preferences in `UserDefaults.standard`
/// (domain `com.musicdesk.widget` inside the app bundle).
///
/// Every property reads and writes UserDefaults directly with the keys from
/// `SettingsKey`, so AppKit code (context menu, window placement, login item)
/// and SwiftUI views using `@AppStorage` always see the same values.
/// Appearance settings (colors, bar, title …) are read by the views
/// themselves via `@AppStorage`; `WidgetColorMode` lives in SettingsKeys.swift.
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Widget foreground color mode (falls back to the default for unknown values).
    var colorMode: WidgetColorMode {
        get {
            WidgetColorMode(rawValue: defaults.string(forKey: SettingsKey.colorMode) ?? "")
                ?? WidgetColorMode(rawValue: SettingsDefault.colorMode)
                ?? .black
        }
        set { defaults.set(newValue.rawValue, forKey: SettingsKey.colorMode) }
    }

    /// "Position sperren": the widget cannot be dragged.
    var positionLocked: Bool {
        get { defaults.bool(forKey: SettingsKey.positionLocked) }
        set { defaults.set(newValue, forKey: SettingsKey.positionLocked) }
    }

    var didAttemptInitialLoginRegistration: Bool {
        get { defaults.bool(forKey: SettingsKey.didAttemptInitialLoginRegistration) }
        set { defaults.set(newValue, forKey: SettingsKey.didAttemptInitialLoginRegistration) }
    }

    /// The saved window position, or nil if none was saved yet.
    var savedWindowPosition: SavedWindowPosition? {
        guard let x = (defaults.object(forKey: SettingsKey.windowOriginX) as? NSNumber)?.doubleValue,
              let y = (defaults.object(forKey: SettingsKey.windowOriginY) as? NSNumber)?.doubleValue,
              x.isFinite, y.isFinite else {
            return nil
        }
        let screenID = (defaults.object(forKey: SettingsKey.windowScreenID) as? NSNumber)?.uint32Value
        let screenName = defaults.string(forKey: SettingsKey.windowScreenName)
        return SavedWindowPosition(origin: CGPoint(x: x, y: y), screenID: screenID, screenName: screenName)
    }

    func saveWindowPosition(_ position: SavedWindowPosition) {
        defaults.set(Double(position.origin.x), forKey: SettingsKey.windowOriginX)
        defaults.set(Double(position.origin.y), forKey: SettingsKey.windowOriginY)
        if let id = position.screenID {
            defaults.set(Int(id), forKey: SettingsKey.windowScreenID)
        } else {
            defaults.removeObject(forKey: SettingsKey.windowScreenID)
        }
        if let name = position.screenName {
            defaults.set(name, forKey: SettingsKey.windowScreenName)
        } else {
            defaults.removeObject(forKey: SettingsKey.windowScreenName)
        }
    }
}
