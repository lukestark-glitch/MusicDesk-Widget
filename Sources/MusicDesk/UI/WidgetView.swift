import AppKit
import SwiftUI

/// Fixed geometry of the widget (points, origin top-left).
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
    static let barHitHeight: CGFloat = 30

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

/// The whole desktop widget: title + transport buttons, progress bar below.
@MainActor
struct WidgetView: View {
    @ObservedObject var music: MusicController
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    // Explicit init: the private @Environment property would otherwise make
    // the memberwise initializer inaccessible from AppDelegate.swift.
    init(music: MusicController, settings: AppSettings) {
        _music = ObservedObject(wrappedValue: music)
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        ZStack {
            titleRow
                .frame(width: WidgetLayout.innerWidth, height: WidgetLayout.row1Height)
                .position(x: WidgetLayout.width / 2, y: WidgetLayout.row1CenterY)

            ProgressBar(state: music.state, color: foreground) { seconds in
                music.seek(to: seconds)
            }
            .frame(width: WidgetLayout.innerWidth, height: WidgetLayout.barHitHeight)
            .position(x: WidgetLayout.width / 2, y: WidgetLayout.row2CenterY)
        }
        .frame(width: WidgetLayout.width, height: WidgetLayout.height)
    }

    /// Black / white / follow system appearance. `colorScheme` tracks the
    /// hosting view's effectiveAppearance, so "automatic" updates live.
    private var foreground: Color {
        switch settings.colorMode {
        case .black: return .black
        case .white: return .white
        case .automatic: return colorScheme == .dark ? .white : .black
        }
    }

    private var titleRow: some View {
        HStack(spacing: WidgetLayout.minimumTitleGap) {
            Text(music.state.displayText)
                .font(.system(size: WidgetLayout.titleFontSize, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.black.opacity(WidgetLayout.hitTestOpacity))
                // Dragging the title moves the window (disabled when locked).
                .overlay(WindowDragArea(isEnabled: !settings.positionLocked))

            controls
                .fixedSize()
                .layoutPriority(1)
        }
    }

    private var controls: some View {
        HStack(spacing: WidgetLayout.buttonSpacing) {
            ControlButton(
                systemName: "backward.fill",
                accessibilityTitle: "Vorheriger Titel",
                color: foreground,
                action: { music.previousTrack() }
            )
            ControlButton(
                systemName: music.state.isPlaying ? "pause.fill" : "play.fill",
                accessibilityTitle: music.state.isPlaying ? "Pause" : "Wiedergabe",
                color: foreground,
                fixedWidth: WidgetLayout.buttonHitSize, // play/pause glyphs differ in width
                action: { music.playPause() }
            )
            ControlButton(
                systemName: "forward.fill",
                accessibilityTitle: "Nächster Titel",
                color: foreground,
                glyphAlignment: .trailing, // glyph flush with the end of the bar
                action: { music.nextTrack() }
            )
        }
    }
}

/// SF Symbol button with a ≥36×36 pt hit area and 50 % pressed opacity.
@MainActor
private struct ControlButton: View {
    let systemName: String
    let accessibilityTitle: String
    let color: Color
    var fixedWidth: CGFloat? = nil
    var glyphAlignment: Alignment = .center
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: WidgetLayout.buttonGlyphSize, weight: .regular))
                .foregroundStyle(color)
                .frame(width: fixedWidth)
                .frame(
                    minWidth: WidgetLayout.buttonHitSize,
                    minHeight: WidgetLayout.buttonHitSize,
                    alignment: glyphAlignment
                )
                .background(Color.black.opacity(WidgetLayout.hitTestOpacity))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimButtonStyle())
        .accessibilityLabel(Text(accessibilityTitle))
    }
}
