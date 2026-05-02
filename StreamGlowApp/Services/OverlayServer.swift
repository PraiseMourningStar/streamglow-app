import Foundation
import Network

struct ArtworkSnapshot: Equatable {
    let data: Data
    let mimeType: String
}

final class OverlayServer: @unchecked Sendable {
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.streamglow.overlay-server", qos: .userInitiated)
    private let lock = NSLock()
    private let encoder = JSONEncoder()

    private var listener: NWListener?
    private var track: TrackInfo = .empty
    private var theme: ThemeSettings = .default
    private var artwork: ArtworkSnapshot?
    private lazy var resourceRoots: [URL] = {
        var roots: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL.appendingPathComponent("Overlay", isDirectory: true))
            roots.append(resourceURL)
        }

        let sourceOverlayURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Overlay", isDirectory: true)
        roots.append(sourceOverlayURL)

        return roots
    }()

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        stop()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "StreamGlow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The overlay port \(port) is invalid."
            ])
        }

        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("StreamGlow listener failed: \(error.localizedDescription)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func restart() throws {
        stop()
        try start()
    }

    func setTrack(_ track: TrackInfo) {
        lock.lock()
        self.track = track
        lock.unlock()
    }

    func setTheme(_ theme: ThemeSettings) {
        lock.lock()
        self.theme = theme
        lock.unlock()
    }

    func setArtwork(_ artwork: ArtworkSnapshot?) {
        lock.lock()
        self.artwork = artwork
        lock.unlock()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }

            self.respond(to: connection, requestData: data)
        }
    }

    private func respond(to connection: NWConnection, requestData: Data) {
        let request = String(decoding: requestData, as: UTF8.self)
        let requestLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let rawPath = parts.count > 1 ? String(parts[1]) : "/"
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath

        switch path {
        case "/", "/index.html":
            serveResource(named: "index", ext: "html", contentType: "text/html; charset=utf-8", connection: connection)
        case "/styles.css":
            serveResource(named: "styles", ext: "css", contentType: "text/css; charset=utf-8", connection: connection)
        case "/overlay.js":
            serveResource(named: "overlay", ext: "js", contentType: "application/javascript; charset=utf-8", connection: connection)
        case "/api/now-playing":
            serveTrack(connection: connection)
        case "/api/settings":
            serveTheme(connection: connection)
        case "/artwork":
            serveArtwork(connection: connection)
        case "/favicon.ico":
            send(status: "204 No Content", contentType: "text/plain", body: Data(), connection: connection)
        default:
            send(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not found".utf8), connection: connection)
        }
    }

    private func serveTrack(connection: NWConnection) {
        lock.lock()
        let snapshot = track
        lock.unlock()

        guard let body = try? encoder.encode(snapshot) else {
            send(status: "500 Internal Server Error", contentType: "text/plain; charset=utf-8", body: Data("Encoding failed".utf8), connection: connection)
            return
        }

        send(status: "200 OK", contentType: "application/json; charset=utf-8", body: body, connection: connection)
    }

    private func serveTheme(connection: NWConnection) {
        lock.lock()
        let snapshot = theme
        lock.unlock()

        guard let body = try? encoder.encode(snapshot) else {
            send(status: "500 Internal Server Error", contentType: "text/plain; charset=utf-8", body: Data("Encoding failed".utf8), connection: connection)
            return
        }

        send(status: "200 OK", contentType: "application/json; charset=utf-8", body: body, connection: connection)
    }

    private func serveArtwork(connection: NWConnection) {
        lock.lock()
        let snapshot = artwork
        lock.unlock()

        guard let snapshot else {
            send(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("No artwork".utf8), connection: connection)
            return
        }

        send(status: "200 OK", contentType: snapshot.mimeType, body: snapshot.data, connection: connection)
    }

    private func serveResource(named name: String, ext: String, contentType: String, connection: NWConnection) {
        guard let url = resolveResourceURL(named: name, ext: ext),
              let data = try? Data(contentsOf: url) else {
            send(status: "500 Internal Server Error", contentType: "text/plain; charset=utf-8", body: Data("Missing resource".utf8), connection: connection)
            return
        }

        send(status: "200 OK", contentType: contentType, body: data, connection: connection)
    }

    private func resolveResourceURL(named name: String, ext: String) -> URL? {
        for root in resourceRoots {
            let candidate = root.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Overlay")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    private func send(status: String, contentType: String, body: Data, connection: NWConnection) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"

        var payload = Data(header.utf8)
        payload.append(body)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
