import AppKit
import Foundation

struct ThemeSettings: Codable, Equatable {
    var accentHex: String = "#D9FF2F"
    var glowHex: String = "#34D8FF"
    var surfaceHex: String = "#FF7A18"
    var panelOpacity: Double = 0.35
    var glowStrength: Double = 0.10
    var fillOBSWidth: Bool = false
    var textScale: Double = 1.0
    var musicTileScale: Double = 1.0
    var compactness: Double = 0.35

    enum CodingKeys: String, CodingKey {
        case accentHex = "accent_hex"
        case glowHex = "glow_hex"
        case surfaceHex = "surface_hex"
        case panelOpacity = "panel_opacity"
        case glowStrength = "glow_strength"
        case fillOBSWidth = "fill_obs_width"
        case textScale = "text_scale"
        case musicTileScale = "music_tile_scale"
        case compactness
    }

    static let `default` = ThemeSettings()

    init(
        accentHex: String = "#D9FF2F",
        glowHex: String = "#34D8FF",
        surfaceHex: String = "#FF7A18",
        panelOpacity: Double = 0.35,
        glowStrength: Double = 0.10,
        fillOBSWidth: Bool = false,
        textScale: Double = 1.0,
        musicTileScale: Double = 1.0,
        compactness: Double = 0.35
    ) {
        self.accentHex = accentHex
        self.glowHex = glowHex
        self.surfaceHex = surfaceHex
        self.panelOpacity = panelOpacity
        self.glowStrength = glowStrength
        self.fillOBSWidth = fillOBSWidth
        self.textScale = textScale
        self.musicTileScale = musicTileScale
        self.compactness = compactness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ThemeSettings.default
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? defaults.accentHex
        glowHex = try container.decodeIfPresent(String.self, forKey: .glowHex) ?? defaults.glowHex
        surfaceHex = try container.decodeIfPresent(String.self, forKey: .surfaceHex) ?? defaults.surfaceHex
        panelOpacity = try container.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? defaults.panelOpacity
        glowStrength = try container.decodeIfPresent(Double.self, forKey: .glowStrength) ?? defaults.glowStrength
        fillOBSWidth = try container.decodeIfPresent(Bool.self, forKey: .fillOBSWidth) ?? defaults.fillOBSWidth
        textScale = try container.decodeIfPresent(Double.self, forKey: .textScale) ?? defaults.textScale
        musicTileScale = try container.decodeIfPresent(Double.self, forKey: .musicTileScale) ?? defaults.musicTileScale
        compactness = try container.decodeIfPresent(Double.self, forKey: .compactness) ?? defaults.compactness
    }

    var accentColor: NSColor {
        NSColor(hex: accentHex) ?? NSColor(calibratedRed: 0.85, green: 1.0, blue: 0.18, alpha: 1.0)
    }

    var glowColor: NSColor {
        NSColor(hex: glowHex) ?? NSColor(calibratedRed: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
    }

    var surfaceColor: NSColor {
        NSColor(hex: surfaceHex) ?? NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.09, alpha: 1.0)
    }

    func matchesPalette(accentHex: String, glowHex: String, surfaceHex: String) -> Bool {
        self.accentHex.normalizedHex == accentHex.normalizedHex
            && self.glowHex.normalizedHex == glowHex.normalizedHex
            && self.surfaceHex.normalizedHex == surfaceHex.normalizedHex
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    var hexString: String {
        let resolved = usingColorSpace(.deviceRGB) ?? self
        let red = Int(round(resolved.redComponent * 255))
        let green = Int(round(resolved.greenComponent * 255))
        let blue = Int(round(resolved.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension String {
    var normalizedHex: String {
        trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
    }
}
