import AppKit

// Entry point. MusicDesk is an agent app (LSUIElement): no Dock icon, no
// Cmd-Tab entry, no menu bar.
//
// Top-level code in main.swift is not implicitly main-actor isolated, but it
// always runs on the main thread, so `assumeIsolated` is safe and lets us
// create the @MainActor AppDelegate without concurrency diagnostics.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let appDelegate = AppDelegate()   // NSApplication.delegate is weak
    app.delegate = appDelegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(appDelegate) {
        app.run()
    }
}
