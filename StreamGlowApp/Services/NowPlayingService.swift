import Foundation

struct NowPlayingSnapshot {
    let track: TrackInfo
    let artwork: ArtworkSnapshot?
}

final class NowPlayingService {
    var onUpdate: @Sendable (NowPlayingSnapshot) -> Void = { _ in }

    private let overlayPort: UInt16
    private let queue = DispatchQueue(label: "com.streamglow.nowplaying", qos: .userInitiated)
    private let fieldSeparator = String(UnicodeScalar(30))
    private let artworkFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("streamglow-current-artwork.bin")
    private let lookupRetryInterval: TimeInterval = 12
    private let session: URLSession

    private var timer: DispatchSourceTimer?
    private var cachedArtworkKey = ""
    private var cachedArtwork: ArtworkSnapshot?
    private var cachedArtworkVersion = 0
    private var lastArtworkAttemptKey = ""
    private var lastArtworkAttemptAt = Date.distantPast

    init(port: UInt16 = 8974) {
        self.overlayPort = port

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration)
    }

    func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        let candidates = [queryMusic(), querySpotify()].compactMap { $0 }
        let selectedTrack = selectTrack(from: candidates)
        let snapshot = buildSnapshot(from: selectedTrack)
        onUpdate(snapshot)
    }

    private func selectTrack(from candidates: [TrackInfo]) -> TrackInfo {
        if let playing = candidates.first(where: { $0.available && $0.state == "playing" }) {
            return playing
        }

        if let paused = candidates.first(where: { $0.available && $0.state == "paused" }) {
            return paused
        }

        return .empty
    }

    private func buildSnapshot(from baseTrack: TrackInfo) -> NowPlayingSnapshot {
        guard baseTrack.available else {
            clearArtworkCache()
            return NowPlayingSnapshot(track: .empty, artwork: nil)
        }

        var hydratedTrack = baseTrack

        if shouldResolveArtwork(for: hydratedTrack.key) {
            lastArtworkAttemptKey = hydratedTrack.key
            lastArtworkAttemptAt = Date()
            cachedArtworkKey = hydratedTrack.key
            cachedArtwork = resolveArtwork(for: hydratedTrack)
            if cachedArtwork != nil {
                cachedArtworkVersion = Int(Date().timeIntervalSince1970 * 1000)
            }
        }

        if cachedArtwork != nil {
            hydratedTrack.artworkURL = "http://127.0.0.1:\(overlayPort)/artwork?t=\(cachedArtworkVersion)"
        }

        return NowPlayingSnapshot(track: hydratedTrack, artwork: cachedArtwork)
    }

    private func shouldResolveArtwork(for key: String) -> Bool {
        if key != cachedArtworkKey {
            return true
        }

        if cachedArtwork != nil {
            return false
        }

        if key != lastArtworkAttemptKey {
            return true
        }

        return Date().timeIntervalSince(lastArtworkAttemptAt) >= lookupRetryInterval
    }

    private func clearArtworkCache() {
        cachedArtworkKey = ""
        cachedArtwork = nil
        cachedArtworkVersion = 0
        lastArtworkAttemptKey = ""
        lastArtworkAttemptAt = Date.distantPast
    }

    private func resolveArtwork(for track: TrackInfo) -> ArtworkSnapshot? {
        if track.source == "Music", let artwork = loadMusicArtwork() {
            return artwork
        }

        if let artwork = downloadArtwork(from: track.artworkURL) {
            return artwork
        }

        guard let fallbackURL = lookupCatalogArtwork(for: track) else {
            return nil
        }

        return downloadArtwork(from: fallbackURL)
    }

    private func queryMusic() -> TrackInfo? {
        guard isProcessRunning(named: "Music") else { return nil }

        let script = """
        set fieldSeparator to character id 30
        tell application "Music"
            if player state is stopped then
                return ""
            end if
            set trackState to player state as text
            set trackTitle to ""
            set trackArtist to ""
            set trackAlbum to ""
            set trackDuration to ""
            set trackPosition to ""
            try
                if exists current track then
                    set trackTitle to name of current track as text
                    set trackArtist to artist of current track as text
                    set trackAlbum to album of current track as text
                    set trackDuration to duration of current track as text
                end if
            end try
            try
                set trackPosition to player position as text
            end try
            set AppleScript's text item delimiters to fieldSeparator
            return {trackState, trackTitle, trackArtist, trackAlbum, trackDuration, trackPosition} as text
        end tell
        """

        guard let output = runAppleScript(script), !output.isEmpty else { return nil }
        let fields = output.components(separatedBy: fieldSeparator)
        guard fields.count >= 6 else { return nil }

        let durationMS = normalizeDuration(raw: fields[4], source: "Music")
        let positionMS = normalizePosition(raw: fields[5], durationMS: durationMS)

        return TrackInfo(
            available: !(fields[1].isEmpty && fields[2].isEmpty),
            state: fields[0].lowercased(),
            source: "Music",
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            durationMS: durationMS,
            positionMS: min(positionMS, durationMS == 0 ? positionMS : durationMS),
            artworkURL: "",
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private func querySpotify() -> TrackInfo? {
        guard isProcessRunning(named: "Spotify") else { return nil }

        let script = """
        set fieldSeparator to character id 30
        tell application "Spotify"
            if player state is stopped then
                return ""
            end if
            set trackState to player state as text
            set trackTitle to ""
            set trackArtist to ""
            set trackAlbum to ""
            set trackDuration to ""
            set trackPosition to ""
            set trackArtwork to ""
            try
                set trackTitle to name of current track as text
                set trackArtist to artist of current track as text
                set trackAlbum to album of current track as text
                set trackDuration to duration of current track as text
                set trackPosition to player position as text
                set trackArtwork to artwork url of current track as text
            end try
            set AppleScript's text item delimiters to fieldSeparator
            return {trackState, trackTitle, trackArtist, trackAlbum, trackDuration, trackPosition, trackArtwork} as text
        end tell
        """

        guard let output = runAppleScript(script), !output.isEmpty else { return nil }
        let fields = output.components(separatedBy: fieldSeparator)
        guard fields.count >= 7 else { return nil }

        let durationMS = normalizeDuration(raw: fields[4], source: "Spotify")
        let positionMS = normalizePosition(raw: fields[5], durationMS: durationMS)

        return TrackInfo(
            available: !(fields[1].isEmpty && fields[2].isEmpty),
            state: fields[0].lowercased(),
            source: "Spotify",
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            durationMS: durationMS,
            positionMS: min(positionMS, durationMS == 0 ? positionMS : durationMS),
            artworkURL: fields[6],
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private func loadMusicArtwork() -> ArtworkSnapshot? {
        let escapedPath = artworkFileURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        set artworkFile to "\(escapedPath)"
        tell application "Music"
            if player state is stopped then return ""
            try
                set currentTrack to current track
                set artworkBlob to data of artwork 1 of currentTrack
                set outputFile to (open for access (POSIX file artworkFile) with write permission)
                set eof of outputFile to 0
                write artworkBlob to outputFile
                try
                    close access (POSIX file artworkFile)
                end try
                return "ok"
            on error
                try
                    close access (POSIX file artworkFile)
                end try
                return ""
            end try
        end tell
        """

        guard let result = runAppleScript(script), result == "ok" else { return nil }
        guard let data = try? Data(contentsOf: artworkFileURL), !data.isEmpty else { return nil }
        let mimeType = detectMimeType(for: data)
        guard mimeType.hasPrefix("image/") else { return nil }
        return ArtworkSnapshot(data: data, mimeType: mimeType)
    }

    private func downloadArtwork(from urlString: String) -> ArtworkSnapshot? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let (data, mimeType) = fetchData(from: url),
              !data.isEmpty,
              mimeType.hasPrefix("image/") else {
            return nil
        }

        return ArtworkSnapshot(data: data, mimeType: mimeType)
    }

    private func lookupCatalogArtwork(for track: TrackInfo) -> String? {
        let query = [track.title, track.artist, track.album]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !query.isEmpty else {
            return nil
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]

        guard let url = components?.url,
              let (data, _) = fetchData(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else {
            return nil
        }

        let title = normalizeMatchText(track.title)
        let artist = normalizeMatchText(track.artist)
        let album = normalizeMatchText(track.album)

        var bestURL = ""
        var bestScore = -1

        for item in results {
            let itemArtist = normalizeMatchText(item["artistName"] as? String ?? "")
            let itemTrack = normalizeMatchText(item["trackName"] as? String ?? "")
            let itemAlbum = normalizeMatchText(item["collectionName"] as? String ?? "")
            let artworkURL = item["artworkUrl100"] as? String ?? ""

            guard !artworkURL.isEmpty else { continue }

            var score = 0
            if !title.isEmpty && (itemTrack.contains(title) || title.contains(itemTrack)) {
                score += 3
            }
            if !artist.isEmpty && (itemArtist.contains(artist) || artist.contains(itemArtist)) {
                score += 2
            }
            if !album.isEmpty && (itemAlbum.contains(album) || album.contains(itemAlbum)) {
                score += 1
            }

            if score > bestScore {
                bestScore = score
                bestURL = artworkURL
            }
        }

        if bestURL.isEmpty {
            bestURL = results.first?["artworkUrl100"] as? String ?? ""
        }

        return bestURL.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    }

    private func fetchData(from url: URL) -> (Data, String)? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5

        let semaphore = DispatchSemaphore(value: 0)
        var output: (Data, String)?

        let task = session.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode),
                  let data,
                  !data.isEmpty else {
                return
            }

            let mimeType = httpResponse.mimeType ?? self.detectMimeType(for: data)
            output = (data, mimeType)
        }

        task.resume()
        let timedOut = semaphore.wait(timeout: .now() + 6) == .timedOut
        if timedOut {
            task.cancel()
        }

        return output
    }

    private func runAppleScript(_ script: String) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isProcessRunning(named name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", name]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func normalizeDuration(raw: String, source: String) -> Int {
        guard let value = Double(raw) else { return 0 }

        if source == "Spotify", value > 1000 {
            return Int(round(value))
        }

        return Int(round(value * 1000))
    }

    private func normalizePosition(raw: String, durationMS: Int) -> Int {
        guard let value = Double(raw) else { return 0 }

        if durationMS > 0, value > Double(durationMS) + 1000 {
            return Int(round(value))
        }

        if durationMS > 0, value > 1000, value <= Double(durationMS) {
            return Int(round(value))
        }

        return Int(round(value * 1000))
    }

    private func normalizeMatchText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func detectMimeType(for data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }

        if data.starts(with: Array("GIF87a".utf8)) || data.starts(with: Array("GIF89a".utf8)) {
            return "image/gif"
        }

        if data.count > 12,
           Array(data.prefix(4)) == [0x52, 0x49, 0x46, 0x46],
           Array(data.dropFirst(8).prefix(4)) == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }

        return "application/octet-stream"
    }
}
