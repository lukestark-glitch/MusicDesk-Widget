import AppKit
import SwiftUI

/// All UserDefaults keys. Views use `@AppStorage(SettingsKey.x)` with the
/// default from `SettingsDefault`, AppKit code reads `UserDefaults.standard`.
/// Existing 1.0 keys keep their names so old preferences survive the update.
enum SettingsKey {
    // 1.0
    static let colorMode = "colorMode"                       // WidgetColorMode.rawValue
    static let positionLocked = "positionLocked"             // Bool
    static let windowOriginX = "windowOriginX"
    static let windowOriginY = "windowOriginY"
    static let windowScreenID = "windowScreenID"
    static let windowScreenName = "windowScreenName"
    static let didAttemptInitialLoginRegistration = "didAttemptInitialLoginRegistration"
    // 1.1
    static let sourcePreference = "sourcePreference"         // SourcePreference.rawValue
    static let showSourceIcon = "showSourceIcon"             // Bool
    static let customColorHex = "customColorHex"             // "#RRGGBB"
    static let readabilityShadow = "readabilityShadow"       // Bool
    static let barOpacity = "barOpacity"                     // Double 0.15...1
    static let barGlass = "barGlass"                         // Bool
    static let highlightPlayed = "highlightPlayed"           // Bool
    static let knobVisibility = "knobVisibility"             // KnobVisibility.rawValue
    static let titleOverflow = "titleOverflow"               // TitleOverflow.rawValue
    static let dimArtist = "dimArtist"                       // Bool
    static let autoCheckUpdates = "autoCheckUpdates"         // Bool
    static let lastUpdateCheck = "lastUpdateCheck"           // Double (timeIntervalSince1970)

    /// Keys reset by "Auf Standard zurücksetzen" (not position/login state).
    static let resettable: [String] = [
        colorMode, sourcePreference, showSourceIcon, customColorHex,
        readabilityShadow, barOpacity, barGlass, highlightPlayed,
        knobVisibility, titleOverflow, dimArtist, autoCheckUpdates,
    ]
}

/// Defaults matching the 1.0 look.
enum SettingsDefault {
    static let colorMode = WidgetColorMode.black.rawValue
    static let sourcePreference = SourcePreference.automatic.rawValue
    static let showSourceIcon = false
    static let customColorHex = "#000000"
    static let readabilityShadow = false
    static let barOpacity: Double = 1.0
    static let barOpacityRange: ClosedRange<Double> = 0.15...1.0
    static let barGlass = false
    static let highlightPlayed = true
    static let knobVisibility = KnobVisibility.always.rawValue
    static let titleOverflow = TitleOverflow.truncate.rawValue
    static let dimArtist = true
    static let autoCheckUpdates = true
}

/// Widget foreground color. Raw values persisted (1.0: black/white/automatic).
enum WidgetColorMode: String, CaseIterable, Sendable {
    case black, white, automatic
    case graphite, blue, purple, pink, red, orange, yellow, green, mint
    case custom

    /// German title.
    var title: String {
        switch self {
        case .black: return "Schwarz"
        case .white: return "Weiß"
        case .automatic: return "Automatisch"
        case .graphite: return "Graphit"
        case .blue: return "Blau"
        case .purple: return "Lila"
        case .pink: return "Pink"
        case .red: return "Rot"
        case .orange: return "Orange"
        case .yellow: return "Gelb"
        case .green: return "Grün"
        case .mint: return "Mint"
        case .custom: return "Eigene"
        }
    }

    /// Presets shown as color dots (everything except `.custom`).
    static let presets: [WidgetColorMode] = allCases.filter { $0 != .custom }

    /// Resolved color. `colorScheme` drives `.automatic` (and the dynamic
    /// system colors); `customHex` is used for `.custom`.
    func color(colorScheme: ColorScheme, customHex: String) -> Color {
        switch self {
        case .black: return .black
        case .white: return .white
        case .automatic: return colorScheme == .dark ? .white : .black
        case .graphite: return Color(nsColor: .systemGray)
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink: return Color(nsColor: .systemPink)
        case .red: return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .mint:
            if #available(macOS 12.0, *) { return Color(nsColor: .systemMint) }
            return Color(red: 0, green: 0.78, blue: 0.75)
        case .custom: return HexColor.color(from: customHex) ?? .black
        }
    }
}

/// "Regler anzeigen".
enum KnobVisibility: String, CaseIterable, Sendable {
    case always, hover, never
    var title: String {
        switch self {
        case .always: return "Immer"
        case .hover: return "Nur beim Überfahren"
        case .never: return "Nie"
        }
    }
}

/// "Langer Titel".
enum TitleOverflow: String, CaseIterable, Sendable {
    case truncate, marquee
    var title: String {
        switch self {
        case .truncate: return "Abkürzen (…)"
        case .marquee: return "Laufschrift"
        }
    }
}

/// #RRGGBB helpers.
enum HexColor {
    /// Parses "#RRGGBB" or "RRGGBB" (case-insensitive). nil when invalid.
    static func nsColor(from hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    static func color(from hex: String) -> Color? {
        nsColor(from: hex).map { Color(nsColor: $0) }
    }

    static func isValid(_ hex: String) -> Bool { nsColor(from: hex) != nil }

    /// "#RRGGBB" in sRGB (alpha ignored).
    static func hexString(from color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
