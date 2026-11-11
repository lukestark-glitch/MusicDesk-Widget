import AppKit
import CoreGraphics

/// Detects whether another app is in full-screen mode on the widget's screen.
///
/// The widget panel uses `.canJoinAllSpaces`, so macOS also shows it on the
/// separate Space of a full-screen app (e.g. behind letterboxed video). There
/// is no collection behavior for "all Spaces except full-screen ones", so we
/// detect full screen ourselves and hide the panel while it lasts.
///
/// Detection: an on-screen, normal-level (layer 0) window of another process
/// that covers the whole screen frame, including the menu bar area. A merely
/// maximized ("zoomed") window leaves the menu bar visible and does not count.
/// Only window bounds are read – no screen-recording permission needed.
@MainActor
final class FullScreenObserver {
    /// Called on the main actor when the state changes.
    var onChange: ((Bool) -> Void)?
    private(set) var isFullScreenActive = false

    private weak var window: NSWindow?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow) {
        self.window = window
    }

    func start() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluate()
                    // Space switches animate; check again once they have settled.
                    self?.evaluate(after: 0.6)
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        // Entering full screen inside the same app (green button) posts no
        // workspace notification, so poll as well. CGWindowList is cheap.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func evaluate(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    private func evaluate() {
        let active = Self.isFullScreenWindowPresent(on: window?.screen ?? NSScreen.main)
        guard active != isFullScreenActive else { return }
        isFullScreenActive = active
        onChange?(active)
    }

    /// True when another process shows a window covering the whole `screen`.
    static func isFullScreenWindowPresent(on screen: NSScreen?) -> Bool {
        guard let screen,
              let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else {
            return false
        }
        // CGWindow bounds use a top-left origin relative to the primary screen.
        let f = screen.frame
        let screenRect = CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let tolerance: CGFloat = 1
        // On displays with a notch, full-screen windows start below the
        // camera housing (the strip above stays black).
        var topSlack = tolerance
        if #available(macOS 12.0, *) {
            topSlack += screen.safeAreaInsets.top
        }

        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            if bounds.minX <= screenRect.minX + tolerance,
               bounds.minY <= screenRect.minY + topSlack,
               bounds.maxX >= screenRect.maxX - tolerance,
               bounds.maxY >= screenRect.maxY - tolerance {
                return true
            }
        }
        return false
    }
}
