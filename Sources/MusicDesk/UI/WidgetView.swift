import AppKit
import SwiftUI

/// Fixed geometry of the widget (points, origin top-left). Matches the Figma
/// layout of 1.0 – do not change without updating the design.
enum WidgetLayout {
    static let width: CGFloat = 560
    static let height: CGFloat = 114
    static let horizontalPadding: CGFloat = 32
    static let innerWidth: CGFloat = width - 2 * horizontalPadding   // 496

    /// Row 1 (title + buttons), vertical center from top.
    static let row1CenterY: CGFloat = 43
    static let row1Height: CGFloat = 36
    /// Row 2 (progress bar), vertical center from top.
    static let row2CenterY: CGFloat = 71
    /// Height of the frame handed to `ProgressBar` (bar centred inside, the
    /// whole frame is the click/drag zone).
    static let barAreaHeight: CGFloat = 30
    /// 1.0 name of `barAreaHeight`, kept for existing references.
    static let barHitHeight: CGFloat = barAreaHeight

    static let titleFontSize: CGFloat = 26
    static let minimumTitleGap: CGFloat = 20
    static let buttonSpacing: CGFloat = 15
    /// Font size of the SF Symbols; renders the glyph box at roughly 26 pt height.
    static let buttonGlyphSize: CGFloat = 24
    static let buttonHitSize: CGFloat = 36

    /// Practically invisible fill that makes transparent areas hit-testable
    /// (the window server passes clicks through fully transparent pixels).
    static let hitTestOpacity: Double = 0.011
}

/// What the widget's controls do. The live widget forwards to `MediaManager`,
/// the settings preview uses `.noop`.
struct WidgetActions {
    var playPause: () -> Void
    var next: () -> Void
    var previous: () -> Void
    /// Absolute target position in seconds.
    var seek: (Double) -> Void

    /// Does nothing (settings preview).
    static let noop = WidgetActions(
        playPause: {},
        next: {},
        previous: {},
        seek: { _ in }
    )
}

/// The whole desktop widget: title + transport buttons, progress bar below.
///
/// Pure presentation: gets a `NowPlaying` snapshot and the actions; all
/// appearance settings are read directly from UserDefaults via `@AppStorage`,
/// so the widget and the settings preview update live.
@MainActor
struct WidgetView: View {
    let state: NowPlaying
    let actions: WidgetActions
    /// Settings-window preview: no window dragging, no seeking.
    let isPreview: Bool

    @AppStorage(SettingsKey.colorMode) private var colorMode = SettingsDefault.colorMode
    @AppStorage(SettingsKey.customColorHex) private var customColorHex = SettingsDefault.customColorHex
    @AppStorage(SettingsKey.readabilityShadow) private var readabilityShadow = SettingsDefault.readabilityShadow
    @AppStorage(SettingsKey.positionLocked) private var positionLocked = false

    @Environment(\.colorScheme) private var colorScheme

    // Explicit init: the private property wrappers would otherwise make the
    // memberwise initializer inaccessible from other files.
    init(state: NowPlaying, actions: WidgetActions, isPreview: Bool = false) {
        self.state = state
        self.actions = actions
        self.isPreview = isPreview
    }

    var body: some View {
        let color = foreground
        let shadow = ReadabilityShadow(
            isEnabled: readabilityShadow,
            isLightForeground: isLightForeground
        )

        ZStack {
            titleRow(color: color, shadow: shadow)
                .frame(width: WidgetLayout.innerWidth, height: WidgetLayout.row1Height)
                .position(x: WidgetLayout.width / 2, y: WidgetLayout.row1CenterY)

            ProgressBar(
                state: state,
                color: color,
                isInteractive: !isPreview,
                onSeek: actions.seek
            )
            .modifier(shadow)
            .frame(width: WidgetLayout.innerWidth, height: WidgetLayout.barAreaHeight)
            .position(x: WidgetLayout.width / 2, y: WidgetLayout.row2CenterY)
        }
        .frame(width: WidgetLayout.width, height: WidgetLayout.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("MusicDesk"))
    }

    // MARK: - Color

    private var resolvedMode: WidgetColorMode {
        WidgetColorMode(rawValue: colorMode) ?? .black
    }

    /// `colorScheme` tracks the hosting view's effective appearance, so
    /// "Automatisch" (and the dynamic system colors) update live.
    private var foreground: Color {
        resolvedMode.color(colorScheme: colorScheme, customHex: customColorHex)
    }

    /// Whether the foreground is light – then the readability shadow is dark
    /// (and vice versa).
    private var isLightForeground: Bool {
        switch resolvedMode {
        case .black: return false
        case .white: return true
        case .automatic: return colorScheme == .dark
        default:
            guard let rgb = NSColor(foreground).usingColorSpace(.sRGB) else { return false }
            let luminance = 0.2126 * rgb.redComponent
                + 0.7152 * rgb.greenComponent
                + 0.0722 * rgb.blueComponent
            return luminance > 0.55
        }
    }

    // MARK: - Row 1

    private func titleRow(color: Color, shadow: ReadabilityShadow) -> some View {
        HStack(spacing: WidgetLayout.minimumTitleGap) {
            TitleView(state: state, color: color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .modifier(shadow)
                .background(Color.black.opacity(WidgetLayout.hitTestOpacity))
                // Dragging the title moves the window (disabled when locked,
                // absent in the settings preview).
                .overlay {
                    if !isPreview {
                        WindowDragArea(isEnabled: !positionLocked)
                    }
                }

            controls(color: color)
                .modifier(shadow)
                .fixedSize()
                .layoutPriority(1)
        }
    }

    private func controls(color: Color) -> some View {
        let isPlaying = state.isPlaying
        return HStack(spacing: WidgetLayout.buttonSpacing) {
            ControlButton(
                systemName: "backward.fill",
                accessibilityTitle: "Vorheriger Titel",
                helpText: "Vorheriger Titel",
                color: color,
                action: actions.previous
            )
            ControlButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                accessibilityTitle: isPlaying ? "Pause" : "Wiedergabe",
                helpText: isPlaying ? "Pausieren" : "Abspielen",
                color: color,
                // play/pause glyphs differ in width – keep the row stable.
                fixedWidth: WidgetLayout.buttonHitSize,
                action: actions.playPause
            )
            ControlButton(
                systemName: "forward.fill",
                accessibilityTitle: "Nächster Titel",
                helpText: "Nächster Titel",
                color: color,
                // Glyph flush with the end of the progress bar.
                glyphAlignment: .trailing,
                action: actions.next
            )
        }
    }
}

/// Renders `WidgetView` for the live state of a `MediaManager`.
@MainActor
struct LiveWidgetView: View {
    @ObservedObject private var media: MediaManager

    init(media: MediaManager) {
        _media = ObservedObject(wrappedValue: media)
    }

    var body: some View {
        WidgetView(state: media.state, actions: actions)
    }

    private var actions: WidgetActions {
        let media = self.media
        return WidgetActions(
            playPause: { media.playPause() },
            next: { media.nextTrack() },
            previous: { media.previousTrack() },
            seek: { seconds in media.seek(to: seconds) }
        )
    }
}

// MARK: - Readability shadow

/// Optional, subtle halo that separates the foreground from busy wallpapers:
/// a soft 8 pt glow plus a tight contour, in the opposite brightness of the
/// foreground. When disabled the shadows are fully transparent, so the view
/// structure (and the state of hover/marquee animations) never changes.
private struct ReadabilityShadow: ViewModifier {
    let isEnabled: Bool
    let isLightForeground: Bool

    func body(content: Content) -> some View {
        let base: Color = isLightForeground ? .black : .white
        content
            .shadow(color: base.opacity(isEnabled ? 0.25 : 0), radius: 8, x: 0, y: 0)
            .shadow(color: base.opacity(isEnabled ? 0.12 : 0), radius: 2, x: 0, y: 0)
    }
}

// MARK: - Transport button

/// SF Symbol button with a ≥36×36 pt hit area, subtle hover/press feedback,
/// German VoiceOver label and tooltip.
@MainActor
private struct ControlButton: View {
    let systemName: String
    let accessibilityTitle: String
    let helpText: String
    let color: Color
    var fixedWidth: CGFloat? = nil
    var glyphAlignment: Alignment = .center
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: fixedWidth)
                .frame(
                    minWidth: WidgetLayout.buttonHitSize,
                    minHeight: WidgetLayout.buttonHitSize,
                    alignment: glyphAlignment
                )
                .background(Color.black.opacity(WidgetLayout.hitTestOpacity))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimButtonStyle(
            isHovered: isHovered,
            scaleAnchor: glyphAlignment == .trailing ? .trailing : .center
        ))
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(Text(accessibilityTitle))
        .help(Text(helpText))
    }

    /// On macOS 14+ a change of the symbol (play ↔ pause) uses the native
    /// SF Symbols "replace" transition; macOS 13 swaps instantly.
    @ViewBuilder
    private var glyph: some View {
        let image = Image(systemName: systemName)
            .font(.system(size: WidgetLayout.buttonGlyphSize, weight: .regular))
            .foregroundStyle(color)

        if #available(macOS 14.0, *) {
            image
                .contentTransition(.symbolEffect(.replace))
                .animation(
                    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                    value: systemName
                )
        } else {
            image
        }
    }
}
