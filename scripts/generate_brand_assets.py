#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
BRANDING_DIR = ROOT / "branding"
WINDOWS_DIR = BRANDING_DIR / "windows"
ASSETS_DIR = ROOT / "StreamGlowApp" / "Resources" / "Assets.xcassets"
APP_ICON_DIR = ASSETS_DIR / "AppIcon.appiconset"
MASCOT_DIR = ASSETS_DIR / "DemonPanda.imageset"
ACCENT_DIR = ASSETS_DIR / "AccentColor.colorset"


def ensure_directories() -> None:
    for directory in (BRANDING_DIR, WINDOWS_DIR, APP_ICON_DIR, MASCOT_DIR, ACCENT_DIR):
        directory.mkdir(parents=True, exist_ok=True)


def draw_glow(base: Image.Image, color: tuple[int, int, int, int], bounds: tuple[int, int, int, int], blur: int) -> None:
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse(bounds, fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(glow)


def draw_mascot(size: int = 1024) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def scale(value: float) -> int:
        return int(round(value * size / 1024))

    red = (255, 64, 64, 255)
    dark_red = (210, 24, 24, 255)
    pink = (255, 145, 158, 255)
    outline = (8, 7, 10, 255)
    white = (255, 255, 255, 255)
    black = (12, 11, 15, 255)

    tail_points = [
        (scale(110), scale(770)),
        (scale(80), scale(630)),
        (scale(108), scale(510)),
        (scale(170), scale(438)),
        (scale(216), scale(450)),
        (scale(182), scale(540)),
        (scale(174), scale(650)),
        (scale(248), scale(760)),
        (scale(206), scale(790)),
        (scale(164), scale(760)),
    ]
    draw.line(tail_points, fill=outline, width=scale(52), joint="curve")
    draw.line(tail_points, fill=dark_red, width=scale(34), joint="curve")
    draw.polygon(
        [(scale(84), scale(594)), (scale(178), scale(548)), (scale(150), scale(668))],
        fill=outline,
    )
    draw.polygon(
        [(scale(98), scale(602)), (scale(166), scale(566)), (scale(146), scale(652))],
        fill=dark_red,
    )

    draw.ellipse((scale(264), scale(536), scale(802), scale(982)), fill=outline)
    draw.ellipse((scale(288), scale(562), scale(780), scale(954)), fill=dark_red)

    draw.ellipse((scale(582), scale(610), scale(904), scale(954)), fill=outline)
    draw.ellipse((scale(606), scale(634), scale(880), scale(930)), fill=red)

    paw_center = (scale(748), scale(760))
    paw_radius = scale(126)
    draw.ellipse(
        (
            paw_center[0] - paw_radius,
            paw_center[1] - paw_radius,
            paw_center[0] + paw_radius,
            paw_center[1] + paw_radius,
        ),
        fill=outline,
    )
    inner_paw = scale(104)
    draw.ellipse(
        (
            paw_center[0] - inner_paw,
            paw_center[1] - inner_paw,
            paw_center[0] + inner_paw,
            paw_center[1] + inner_paw,
        ),
        fill=(190, 26, 26, 255),
    )

    draw.ellipse((scale(198), scale(78), scale(864), scale(626)), fill=outline)
    draw.ellipse((scale(220), scale(112), scale(840), scale(612)), fill=pink)

    draw.pieslice((scale(136), scale(152), scale(406), scale(402)), start=115, end=260, fill=outline)
    draw.pieslice((scale(616), scale(90), scale(930), scale(372)), start=-70, end=90, fill=outline)

    draw.polygon(
        [(scale(240), scale(86)), (scale(182), scale(0)), (scale(136), scale(164)), (scale(262), scale(190))],
        fill=outline,
    )
    draw.polygon(
        [(scale(754), scale(72)), (scale(866), scale(0)), (scale(914), scale(136)), (scale(816), scale(202))],
        fill=outline,
    )
    draw.polygon(
        [(scale(260), scale(112)), (scale(206), scale(18)), (scale(168), scale(160)), (scale(274), scale(178))],
        fill=red,
    )
    draw.polygon(
        [(scale(746), scale(102)), (scale(852), scale(18)), (scale(886), scale(136)), (scale(798), scale(190))],
        fill=red,
    )

    draw.ellipse((scale(248), scale(236), scale(440), scale(446)), fill=outline)
    draw.ellipse((scale(564), scale(220), scale(824), scale(482)), fill=outline)

    draw.ellipse((scale(314), scale(320), scale(374), scale(390)), fill=white)
    draw.ellipse((scale(686), scale(302), scale(754), scale(372)), fill=white)

    draw.ellipse((scale(504), scale(360), scale(560), scale(412)), fill=outline)
    draw.arc((scale(442), scale(412), scale(626), scale(522)), start=18, end=164, fill=outline, width=scale(18))

    return image


def draw_app_icon(base_mascot: Image.Image, size: int = 1024) -> Image.Image:
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)

    background = Image.new("RGBA", (size, size), (11, 17, 28, 255))
    background_draw = ImageDraw.Draw(background)
    background_draw.rounded_rectangle((0, 0, size, size), radius=int(size * 0.24), fill=(6, 8, 13, 255))
    icon.alpha_composite(background)

    draw_glow(icon, (255, 64, 64, 96), (60, 96, 960, 930), blur=72)
    draw_glow(icon, (255, 145, 158, 92), (118, 40, 860, 670), blur=54)

    mascot = base_mascot.resize((int(size * 0.90), int(size * 0.90)), Image.Resampling.LANCZOS)
    mascot_position = (int(size * 0.05), int(size * 0.06))
    shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    shadow.alpha_composite(mascot, (mascot_position[0] + 18, mascot_position[1] + 24))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    icon.alpha_composite(shadow)
    icon.alpha_composite(mascot, mascot_position)

    draw.rounded_rectangle(
        (int(size * 0.03), int(size * 0.03), int(size * 0.97), int(size * 0.97)),
        radius=int(size * 0.22),
        outline=(255, 255, 255, 30),
        width=max(2, int(size * 0.006)),
    )

    return icon


def resize(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def write_asset_catalog_contents() -> None:
    (ASSETS_DIR / "Contents.json").write_text(
        '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n',
        encoding="utf-8",
    )

    (ACCENT_DIR / "Contents.json").write_text(
        '{\n'
        '  "colors" : [\n'
        '    {\n'
        '      "idiom" : "universal",\n'
        '      "color" : {\n'
        '        "color-space" : "srgb",\n'
        '        "components" : {\n'
        '          "alpha" : "1.000",\n'
        '          "red" : "0.851",\n'
        '          "green" : "1.000",\n'
        '          "blue" : "0.184"\n'
        '        }\n'
        '      }\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n',
        encoding="utf-8",
    )

    (MASCOT_DIR / "Contents.json").write_text(
        '{\n'
        '  "images" : [\n'
        '    {\n'
        '      "filename" : "demon-panda.png",\n'
        '      "idiom" : "universal",\n'
        '      "scale" : "1x"\n'
        '    },\n'
        '    {\n'
        '      "filename" : "demon-panda@2x.png",\n'
        '      "idiom" : "universal",\n'
        '      "scale" : "2x"\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n',
        encoding="utf-8",
    )

    app_icon_entries = [
        ("16x16", "16", "1x", "appicon-16.png"),
        ("16x16", "16", "2x", "appicon-32.png"),
        ("32x32", "32", "1x", "appicon-32.png"),
        ("32x32", "32", "2x", "appicon-64.png"),
        ("128x128", "128", "1x", "appicon-128.png"),
        ("128x128", "128", "2x", "appicon-256.png"),
        ("256x256", "256", "1x", "appicon-256.png"),
        ("256x256", "256", "2x", "appicon-512.png"),
        ("512x512", "512", "1x", "appicon-512.png"),
        ("512x512", "512", "2x", "appicon-1024.png"),
    ]
    entries = []
    for size, idiom_size, scale, filename in app_icon_entries:
        entries.append(
            '    {\n'
            f'      "filename" : "{filename}",\n'
            '      "idiom" : "mac",\n'
            f'      "scale" : "{scale}",\n'
            f'      "size" : "{size}"\n'
            '    }'
        )

    (APP_ICON_DIR / "Contents.json").write_text(
        "{\n  \"images\" : [\n"
        + ",\n".join(entries)
        + '\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n',
        encoding="utf-8",
    )


def main() -> None:
    ensure_directories()

    mascot = draw_mascot()
    app_icon = draw_app_icon(mascot)

    mascot.save(BRANDING_DIR / "demon-panda.png")
    app_icon.save(BRANDING_DIR / "streamglow-icon-base.png")
    app_icon.save(WINDOWS_DIR / "streamglow.png")
    app_icon.save(WINDOWS_DIR / "streamglow.ico", sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])

    resize(mascot, 512).save(MASCOT_DIR / "demon-panda.png")
    resize(mascot, 1024).save(MASCOT_DIR / "demon-panda@2x.png")

    for size in (16, 32, 64, 128, 256, 512, 1024):
        resize(app_icon, size).save(APP_ICON_DIR / f"appicon-{size}.png")

    write_asset_catalog_contents()


if __name__ == "__main__":
    main()
