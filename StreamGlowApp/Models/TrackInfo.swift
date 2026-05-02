import Foundation

struct TrackInfo: Codable, Equatable {
    var available: Bool = false
    var state: String = "stopped"
    var source: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var durationMS: Int = 0
    var positionMS: Int = 0
    var artworkURL: String = ""
    var updatedAt: TimeInterval = Date().timeIntervalSince1970

    enum CodingKeys: String, CodingKey {
        case available
        case state
        case source
        case title
        case artist
        case album
        case durationMS = "duration_ms"
        case positionMS = "position_ms"
        case artworkURL = "artwork_url"
        case updatedAt = "updated_at"
    }

    static let empty = TrackInfo()

    var key: String {
        [source, title, artist, album].joined(separator: "::")
    }
}
