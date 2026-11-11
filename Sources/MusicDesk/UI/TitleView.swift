import AppKit
import SwiftUI

/// Row-1 title: optional source icon, then "Titel, Künstler" on one line.
///
/// Fills whatever frame the parent gives it (the parent adds the hit-test
/// background and the window-drag overlay). Leading aligned, vertically
/// centred, 26 pt semibold SF Pro. Long text is truncated with "…" or, with
/// the "Laufschrift" setting, scrolls as a marquee (only when it overflows;
/// "Bewegung reduzieren" falls back to truncation).
@MainActor
struct TitleView: View {
    let state: NowPlaying
    let color: Color

    @AppStorage(SettingsKey.showSourceIcon) private var showSourceIcon = SettingsDefault.showSourceIcon
    @AppStorage(SettingsKey.titleOverflow) private var titleOverflowRaw = SettingsDefault.titleOverflow
    @AppStorage(SettingsKey.dimArtist) private var dimArtist = SettingsDefault.dimArtist

    /// Same font as `titleFont`, used to measure the text width.
    static let measuringFont = NSFont.systemFont(ofSize: WidgetLayout.titleFontSize, weight: .semibold)
    static let titleFont = Font.system(size: WidgetLayout.titleFontSize, weight: .semibold)
    static let iconSpacing: CGFloat = 8
    static let iconSize: CGFloat = 22
    static let dimmedArtistOpacity: Double = 0.6

    // Explicit init: the private property wrappers would otherwise make the
    // memberwise initializer private.
    init(state: NowPlaying, color: Color) {
        self.state = state
        self.color = color
    }

    var body: some View {
        HStack(spacing: Self.iconSpacing) {
            if showSourceIcon && state.hasTrack {
                SourceIconView(state: state, color: color, size: Self.iconSize)
            }

            MarqueeText(
                text: styledText,
                measureString: state.displayText,
                font: Self.measuringFont,
                isEnabled: overflow == .marquee
            )
            // New text → fresh marquee state (restarts with the pause).
            .id(state.displayText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: state.displayText))
        .accessibilityAddTraits(.isStaticText)
    }

    private var overflow: TitleOverflow {
        TitleOverflow(rawValue: titleOverflowRaw) ?? .truncate
    }

    /// One concatenated Text so truncation applies to the whole string.
    private var styledText: Text {
        var result = Text(verbatim: state.displayTitle).foregroundColor(color)
        if let artist = state.displayArtist {
            let artistColor = dimArtist ? color.opacity(Self.dimmedArtistOpacity) : color
            result = result + Text(verbatim: ", \(artist)").foregroundColor(artistColor)
        }
        return result.font(Self.titleFont)
    }
}
