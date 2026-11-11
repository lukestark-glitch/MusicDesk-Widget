import AppKit
import Combine
import Foundation

/// Text/bar color of the widget.
enum WidgetColorMode: String, CaseIterable {
    case black
    case white
    /// Follows the system appearance: black in light mode, white in dark mode.
    case automatic

    /// German title used in the context menu.
    var menuTitle: String {
        switch self {
        case .black: return "Schwarz"
        case .white: return "Weiß"
        case .automatic: return "Automatisch"
        }
    }
}

/// Last saved window position (bottom-left origin in global screen
/// coordinates) plus the screen it was on.
struct SavedWindowPosition: Equatable {
    var origin: CGPoint
    var screenID: CGDirectDisplayID?
    var screenName: String?
}

/// User preferences, persisted in `UserDefaults.standard`
/// (domain `com.musicdesk.widget` inside the app bundle).
@MainActor
final class AppSettings: ObservableObject {
    /// All UserDefaults keys used by the app.
    enum Key {
        static let colorMode = "colorMode"
        static let positionLocked = "positionLocked"
        static let windowOriginX = "windowOriginX"
        static let windowOriginY = "windowOriginY"
        static let windowScreenID = "windowScreenID"
        static let windowScreenName = "windowScreenName"
        static let didAttemptInitialLoginRegistration = "didAttemptInitialLoginRegistration"
    }

    private let defaults: UserDefaults

    @Published var colorMode: WidgetColorMode {
        didSet { defaults.set(colorMode.rawValue, forKey: Key.colorMode) }
    }

    @Published var positionLocked: Bool {
        didSet { defaults.set(positionLocked, forKey: Key.positionLocked) }
    }

    var didAttemptInitialLoginRegistration: Bool {
        get { defaults.bool(forKey: Key.didAttemptInitialLoginRegistration) }
        set { defaults.set(newValue, forKey: Key.didAttemptInitialLoginRegistration) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        self.colorMode = WidgetColorMode(rawValue: defaults.string(forKey: Key.colorMode) ?? "") ?? .black
        self.positionLocked = defaults.bool(forKey: Key.positionLocked)
    }

    /// The saved window position, or nil if none was saved yet.
    var savedWindowPosition: SavedWindowPosition? {
        guard let x = (defaults.object(forKey: Key.windowOriginX) as? NSNumber)?.doubleValue,
              let y = (defaults.object(forKey: Key.windowOriginY) as? NSNumber)?.doubleValue,
              x.isFinite, y.isFinite else {
            return nil
        }
        let screenID = (defaults.object(forKey: Key.windowScreenID) as? NSNumber)?.uint32Value
        let screenName = defaults.string(forKey: Key.windowScreenName)
        return SavedWindowPosition(origin: CGPoint(x: x, y: y), screenID: screenID, screenName: screenName)
    }

    func saveWindowPosition(_ position: SavedWindowPosition) {
        defaults.set(Double(position.origin.x), forKey: Key.windowOriginX)
        defaults.set(Double(position.origin.y), forKey: Key.windowOriginY)
        if let id = position.screenID {
            defaults.set(Int(id), forKey: Key.windowScreenID)
        } else {
            defaults.removeObject(forKey: Key.windowScreenID)
        }
        if let name = position.screenName {
            defaults.set(name, forKey: Key.windowScreenName)
        } else {
            defaults.removeObject(forKey: Key.windowScreenName)
        }
    }
}
