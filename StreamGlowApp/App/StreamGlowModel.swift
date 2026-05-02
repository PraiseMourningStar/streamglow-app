import AppKit
import Foundation
import SwiftUI

@MainActor
final class StreamGlowModel: ObservableObject {
    @Published var track: TrackInfo = .empty
    @Published var theme: ThemeSettings {
        didSet {
            overlayServer.setTheme(theme)
            saveTheme()
        }
    }
    @Published private(set) var overlayURL: URL
    @Published private(set) var statusText = "Watching Apple Music and Spotify."
    @Published private(set) var helperText = "Paste the local URL below into an OBS Browser Source."
    @Published private(set) var isServerRunning = false
    @Published var previewReloadToken = UUID()

    private let overlayServer: OverlayServer
    private let nowPlayingService: NowPlayingService
    private let themeDefaultsKey = "com.streamglow.theme-settings"

    init(port: UInt16 = 8974) {
        theme = Self.loadSavedTheme()
        overlayURL = URL(string: "http://127.0.0.1:\(port)/")!
        overlayServer = OverlayServer(port: port)
        nowPlayingService = NowPlayingService(port: port)
        overlayServer.setTheme(theme)
        overlayServer.setTrack(track)

        nowPlayingService.onUpdate = { [weak self] snapshot in
            Task { @MainActor [weak self, snapshot] in
                self?.apply(snapshot)
            }
        }

        do {
            try overlayServer.start()
            isServerRunning = true
            statusText = "Watching Apple Music and Spotify."
            helperText = "Paste the local URL below into an OBS Browser Source."
        } catch {
            isServerRunning = false
            statusText = "Overlay port is unavailable."
            helperText = error.localizedDescription
        }

        nowPlayingService.start()
    }

    var urlString: String {
        overlayURL.absoluteString
    }

    var accentColor: Color {
        get { Color(nsColor: theme.accentColor) }
        set { theme.accentHex = NSColor(newValue).hexString }
    }

    var glowColor: Color {
        get { Color(nsColor: theme.glowColor) }
        set { theme.glowHex = NSColor(newValue).hexString }
    }

    var surfaceColor: Color {
        get { Color(nsColor: theme.surfaceColor) }
        set { theme.surfaceHex = NSColor(newValue).hexString }
    }

    var currentTitle: String {
        if track.available {
            return track.title
        }
        return "Nothing playing yet"
    }

    var currentSubtitle: String {
        if track.available {
            let source = track.source.isEmpty ? "Music" : track.source
            if track.album.isEmpty {
                return "\(track.artist) - \(source)"
            }
            return "\(track.artist) - \(track.album) - \(source)"
        }
        return "Open Music or Spotify to wake the overlay."
    }

    var privacyHint: String {
        "If macOS blocks the first launch, open it from Privacy & Security, then click Allow so StreamGlow can read Music and Spotify."
    }

    func applyPalette(accentHex: String, glowHex: String, surfaceHex: String) {
        var updatedTheme = theme
        updatedTheme.accentHex = accentHex
        updatedTheme.glowHex = glowHex
        updatedTheme.surfaceHex = surfaceHex
        theme = updatedTheme
    }

    func resetLayout() {
        var updatedTheme = theme
        updatedTheme.fillOBSWidth = ThemeSettings.default.fillOBSWidth
        updatedTheme.textScale = ThemeSettings.default.textScale
        updatedTheme.musicTileScale = ThemeSettings.default.musicTileScale
        updatedTheme.compactness = ThemeSettings.default.compactness
        theme = updatedTheme
    }

    func copyOBSURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        helperText = "Copied. Paste the local URL into an OBS Browser Source."
    }

    func openInBrowser() {
        NSWorkspace.shared.open(overlayURL)
    }

    func refreshPreview() {
        previewReloadToken = UUID()
    }

    func restartOverlay() {
        do {
            try overlayServer.restart()
            isServerRunning = true
            overlayServer.setTheme(theme)
            overlayServer.setTrack(track)
            helperText = "Overlay restarted. OBS can keep using the same URL."
            refreshPreview()
        } catch {
            isServerRunning = false
            helperText = error.localizedDescription
        }
    }

    private func apply(_ snapshot: NowPlayingSnapshot) {
        track = snapshot.track
        overlayServer.setTrack(snapshot.track)
        overlayServer.setArtwork(snapshot.artwork)

        if isServerRunning {
            if snapshot.track.available {
                let source = snapshot.track.source.isEmpty ? "Music" : snapshot.track.source
                statusText = "Reading \(source) for the live overlay."
            } else {
                statusText = "Watching Apple Music and Spotify."
            }
        }
    }

    private static func loadSavedTheme() -> ThemeSettings {
        guard let data = UserDefaults.standard.data(forKey: "com.streamglow.theme-settings"),
              let theme = try? JSONDecoder().decode(ThemeSettings.self, from: data) else {
            return .default
        }

        return theme
    }

    private func saveTheme() {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        UserDefaults.standard.set(data, forKey: themeDefaultsKey)
    }
}
