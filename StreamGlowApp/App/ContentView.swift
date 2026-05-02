import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: StreamGlowModel
    private let themePalettes = ThemePalette.presets

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundLayer

                HStack(alignment: .top, spacing: 20) {
                    sidebar
                        .frame(width: sidebarWidth(for: proxy.size.width))
                        .frame(maxHeight: .infinity, alignment: .top)

                    previewColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(22)
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.08),
                    model.surfaceColor.opacity(0.46),
                    Color(red: 0.07, green: 0.10, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    model.accentColor.opacity(0.34),
                    .clear
                ],
                center: .topLeading,
                startRadius: 60,
                endRadius: 420
            )
            .offset(x: -120, y: -80)

            RadialGradient(
                colors: [
                    model.glowColor.opacity(0.30),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 80,
                endRadius: 480
            )
            .offset(x: 220, y: 160)

            Circle()
                .fill(model.surfaceColor.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 150)
                .offset(x: -280, y: 240)

            Circle()
                .fill(model.glowColor.opacity(0.12))
                .frame(width: 520, height: 520)
                .blur(radius: 170)
                .offset(x: 320, y: -180)

            AngularGradient(
                colors: [
                    model.surfaceColor.opacity(0.25),
                    model.accentColor.opacity(0.12),
                    model.glowColor.opacity(0.18),
                    model.surfaceColor.opacity(0.25)
                ],
                center: .center
            )
            .blur(radius: 120)
            .blendMode(.plusLighter)
            .opacity(0.7)
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard(tint: model.surfaceColor) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("StreamGlow")
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                Text("Native OBS now-playing app for your Mac")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.62))
                            }

                            Spacer()

                            Image("DemonPanda")
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(model.surfaceColor.opacity(0.22))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                                )
                                .shadow(color: model.accentColor.opacity(0.26), radius: 18, x: 0, y: 10)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(model.accentColor)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.statusText)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.94))

                                Text(model.helperText)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.64))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(model.glowColor)
                                .padding(.top, 2)

                            Text(model.privacyHint)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()
                            .overlay(.white.opacity(0.08))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.currentTitle)
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.94))
                                .lineLimit(2)

                            Text(model.currentSubtitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.66))
                                .lineLimit(2)
                        }

                        Text("Demon panda approved.")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(model.accentColor)
                    }
                }

                PanelCard(tint: model.glowColor) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OBS Setup")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.94))

                            Text("Double-click app, unblock it once if macOS complains, then paste this into a Browser Source")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        urlField

                        HStack(spacing: 10) {
                            Button("Copy OBS URL") {
                                model.copyOBSURL()
                            }
                            .buttonStyle(PrimaryPillButtonStyle(tint: model.accentColor))

                            Button("Restart Overlay") {
                                model.restartOverlay()
                            }
                            .buttonStyle(SecondaryPillButtonStyle(tint: model.surfaceColor))

                            Button("Refresh") {
                                model.refreshPreview()
                            }
                            .buttonStyle(SecondaryPillButtonStyle(tint: model.glowColor))
                        }

                        Text("In OBS: add a Browser Source, paste the URL above, then size it around 720x220 to start.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                PanelCard(tint: model.accentColor) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Theme Lab")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.94))

                            Text("More color, more glow, and quick palette swaps")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Palette Presets")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(themePalettes) { palette in
                                        ThemePaletteButton(
                                            palette: palette,
                                            isSelected: model.theme.matchesPalette(
                                                accentHex: palette.accentHex,
                                                glowHex: palette.glowHex,
                                                surfaceHex: palette.surfaceHex
                                            )
                                        ) {
                                            model.applyPalette(
                                                accentHex: palette.accentHex,
                                                glowHex: palette.glowHex,
                                                surfaceHex: palette.surfaceHex
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        HStack(spacing: 12) {
                            ThemeSwatchTile(title: "Accent", color: accentBinding, shadowColor: model.accentColor)
                            ThemeSwatchTile(title: "Glow", color: glowBinding, shadowColor: model.glowColor)
                            ThemeSwatchTile(title: "Tint", color: surfaceBinding, shadowColor: model.surfaceColor)
                        }

                        sliderRow(title: "Panel Transparency", value: $model.theme.panelOpacity)
                        sliderRow(title: "Glow Strength", value: $model.theme.glowStrength)

                        Divider()
                            .overlay(.white.opacity(0.08))

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Layout")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))

                                Spacer()

                                Button("Reset") {
                                    model.resetLayout()
                                }
                                .buttonStyle(MiniGhostButtonStyle(tint: model.glowColor))
                            }

                            Toggle("Fill OBS Width", isOn: $model.theme.fillOBSWidth)
                                .toggleStyle(SwitchToggleStyle(tint: model.accentColor))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.86))

                            sliderRow(title: "Text Size", value: $model.theme.textScale, range: 0.75 ... 1.60)
                            sliderRow(title: "Music Tile Size", value: $model.theme.musicTileScale, range: 0.65 ... 1.40)
                            sliderRow(title: "Compactness", value: $model.theme.compactness, range: 0.0 ... 1.0)
                        }
                    }
                }
            }
            .padding(.trailing, 8)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live Preview")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("This is exactly what OBS will pull from your local browser source.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Button("Open In Browser") {
                    model.openInBrowser()
                }
                .buttonStyle(SecondaryPillButtonStyle(tint: model.glowColor))
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                model.surfaceColor.opacity(0.24),
                                model.glowColor.opacity(0.18),
                                Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(model.glowColor.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: model.surfaceColor.opacity(0.24), radius: 26, x: 0, y: 16)

                PreviewWebView(url: model.overlayURL, reloadToken: model.previewReloadToken)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var urlField: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.black.opacity(0.42))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(model.glowColor.opacity(0.22), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Text(model.urlString)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 14)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(height: 40)
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { model.accentColor },
            set: { model.accentColor = $0 }
        )
    }

    private var glowBinding: Binding<Color> {
        Binding(
            get: { model.glowColor },
            set: { model.glowColor = $0 }
        )
    }

    private var surfaceBinding: Binding<Color> {
        Binding(
            get: { model.surfaceColor },
            set: { model.surfaceColor = $0 }
        )
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double> = 0.0 ... 1.0) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Slider(value: value, in: range)
                .tint(model.accentColor)
        }
    }

    private func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        min(468, max(384, totalWidth * 0.36))
    }
}

private struct PanelCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.22),
                                Color.white.opacity(0.10),
                                Color.black.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.24),
                                .white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(0.12), radius: 18, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 12)
    }
}

private struct ThemeSwatchTile: View {
    let title: String
    @Binding var color: Color
    let shadowColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(shadowColor.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(color)
                    .frame(width: 44, height: 18)
                    .shadow(color: color.opacity(0.6), radius: 12, x: 0, y: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)

            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .opacity(0.015)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 108)
    }
}

private struct PrimaryPillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(configuration.isPressed ? 0.82 : 1.0),
                                tint.opacity(configuration.isPressed ? 0.58 : 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: tint.opacity(0.28), radius: 12, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

private struct SecondaryPillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

private struct MiniGhostButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
    }
}

private struct ThemePalette: Identifiable {
    let name: String
    let accentHex: String
    let glowHex: String
    let surfaceHex: String
    let note: String

    var id: String { name }

    var accentColor: Color {
        Color(nsColor: NSColor(hex: accentHex) ?? .systemYellow)
    }

    var glowColor: Color {
        Color(nsColor: NSColor(hex: glowHex) ?? .systemBlue)
    }

    var surfaceColor: Color {
        Color(nsColor: NSColor(hex: surfaceHex) ?? .systemOrange)
    }

    static let presets: [ThemePalette] = [
        ThemePalette(name: "Volt", accentHex: "#D9FF2F", glowHex: "#34D8FF", surfaceHex: "#FF7A18", note: "acid + ice"),
        ThemePalette(name: "Lagoon", accentHex: "#46F6FF", glowHex: "#78FFB7", surfaceHex: "#11324A", note: "aqua + mint"),
        ThemePalette(name: "Sunset", accentHex: "#FF9A3C", glowHex: "#FF5F8A", surfaceHex: "#5A2435", note: "warm + loud"),
        ThemePalette(name: "Aurora", accentHex: "#8BFFCC", glowHex: "#88D5FF", surfaceHex: "#0E4F57", note: "cool + airy"),
        ThemePalette(name: "Ember", accentHex: "#FFD34A", glowHex: "#FF6A3D", surfaceHex: "#44230F", note: "gold + flame"),
        ThemePalette(name: "Rosé", accentHex: "#FF7C6B", glowHex: "#70D8FF", surfaceHex: "#4B2638", note: "coral + sky")
    ]
}

private struct ThemePaletteButton: View {
    let palette: ThemePalette
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(palette.accentColor)
                    Circle()
                        .fill(palette.glowColor)
                    Circle()
                        .fill(palette.surfaceColor)
                }
                .frame(height: 14)

                Text(palette.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Text(palette.note)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(14)
            .frame(width: 122, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.surfaceColor.opacity(0.28),
                                .white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? palette.accentColor.opacity(0.92) : .white.opacity(0.06), lineWidth: isSelected ? 1.6 : 1)
            )
            .shadow(color: palette.glowColor.opacity(isSelected ? 0.22 : 0.10), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
