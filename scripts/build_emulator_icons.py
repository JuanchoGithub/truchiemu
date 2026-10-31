#!/usr/bin/env python3
"""Generate the missing EmulatorIcons size variants and gap-fill icons.

The "default" system-icon set (TruchiEmu/Resources/EmulatorIcons) ships two
renditions of each system icon:

  600/<BASE>.png                    square 600x600, art centered
  132/<lowercase(base)>@132w.png    132x143, art fit to width

SystemInfo.emuImage(size:) probes the 132 names only at size 132 and the plain
names at any other size, so a system is only fully covered when both files
exist. Many systems have only one rendition, and a handful have neither.

This script fills the gaps, in priority order:

  1. 600 -> 132 (and 132 -> 600) size variants for every canonical base
  2. copies for semantic aliases (3DO <- PANASONIC, 32X <- SEGA32X)
  3. new icons drawn from the ControllerIcons .ico set (Jaguar, Wii, Switch, Xbox)
  4. for systems with no colored art: the bundled RetroArch dot-art line icon,
     or a monogram badge (see DOTART / MONOGRAM)

Fallback icons (4) share one neutral "badge" style: a rounded grey tile with a
white glyph, so they read as deliberate placeholders next to the colored renders.

It never overwrites an existing file, so it is safe to re-run. System ids are
wired to a canonical base in SystemDatabase.json (emuIconName); this script only
produces the image files.
"""

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "TruchiEmu", "Resources", "EmulatorIcons")
DIR_600 = os.path.join(ICONS, "600")
DIR_132 = os.path.join(ICONS, "132")
CONTROLLER_ICONS = os.path.join(ROOT, "TruchiEmu", "Resources", "ControllerIcons")
DOTART = os.path.join(ROOT, "TruchiEmu_Resources", "retroarch_images", "dot-art")

CANVAS_132 = (132, 143)
FIT_132 = 128
FIT_600 = 470

# Badge (fallback) geometry: (tile size, corner radius, glyph fit, top-left)
BADGE_600 = (420, 96, 250, (90, 90))
BADGE_132 = (116, 27, 66, (8, 14))
BADGE_TOP = (0x6C, 0x6C, 0x74)
BADGE_BOTTOM = (0x3C, 0x3C, 0x42)

MONOGRAM_FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def load_rgba(path):
    return Image.open(path).convert("RGBA")


def trimmed(image):
    return image.crop(image.getbbox())


def fit_within(image, limit):
    factor = min(limit / image.width, limit / image.height)
    size = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
    return image.resize(size, Image.LANCZOS)


def render_132(source):
    art = fit_within(trimmed(load_rgba(source)), FIT_132)
    canvas = Image.new("RGBA", CANVAS_132, (0, 0, 0, 0))
    canvas.alpha_composite(art, ((CANVAS_132[0] - art.width) // 2,
                                 (CANVAS_132[1] - art.height) // 2))
    return canvas


def render_600(source):
    art = fit_within(trimmed(load_rgba(source)), FIT_600)
    canvas = Image.new("RGBA", (600, 600), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((600 - art.width) // 2, (600 - art.height) // 2))
    return canvas


def badge(glyph, tile, radius, fit, origin):
    """White glyph centered on a rounded tile with a subtle grey gradient."""
    size, origin = tile, origin
    start, end = BADGE_TOP, BADGE_BOTTOM
    scale = size - 1
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = canvas.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * scale)
            pixels[x, y] = (round(start[0] + (end[0] - start[0]) * t),
                            round(start[1] + (end[1] - start[1]) * t),
                            round(start[2] + (end[2] - start[2]) * t), 255)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1),
                                           radius=radius, fill=255)
    canvas.putalpha(mask)

    art = fit_within(glyph, fit)
    canvas.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))

    frame = Image.new("RGBA", (600, 600) if size > 200 else CANVAS_132, (0, 0, 0, 0))
    frame.alpha_composite(canvas, origin)
    return frame


def dotart_glyph(relative_path):
    """White glyph from a dot-art drawing.

    dot-art PNGs are black ink on a white fill, with alpha describing the outer
    body silhouette. The ink is the mask, so combine the inverted luminance with
    alpha, otherwise the whole body renders as a solid blob.
    """
    art = load_rgba(os.path.join(DOTART, relative_path))
    ink = ImageOps.invert(art.convert("L"))
    mask = ImageChops.multiply(ink, art.getchannel("A"))
    glyph = Image.new("RGBA", art.size, (255, 255, 255, 0))
    glyph.putalpha(mask)
    return glyph.crop(mask.getbbox())


def monogram_glyph(text):
    font = ImageFont.truetype(MONOGRAM_FONT, 200)
    box = font.getbbox(text)
    glyph = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (255, 255, 255, 0))
    draw = ImageDraw.Draw(glyph)
    draw.text((-box[0], -box[1]), text, font=font, fill=(255, 255, 255, 255))
    return glyph


def badge_pair(base, glyph):
    created = []
    if not os.path.exists(path_600(base)):
        badge(glyph, *BADGE_600).save(path_600(base))
        created.append(f"600/{base}.png")
    if not os.path.exists(path_132(base)):
        badge(glyph, *BADGE_132).save(path_132(base))
        created.append(f"132/{base.lower()}@132w.png")
    return created


def path_600(base):
    return os.path.join(DIR_600, f"{base}.png")


def path_132(base):
    return os.path.join(DIR_132, f"{base.lower()}@132w.png")


def source_for(base):
    """Best available source image for a canonical base, or None."""
    for candidate in (path_600(base), path_132(base)):
        if os.path.exists(candidate):
            return candidate
    return None


# Canonical bases referenced from SystemDatabase.json. Includes bases that only
# need generating so a re-run stays declarative.
BASES = [
    "FC", "SFC", "N64", "GBA", "GB", "GBC", "NDS", "MD", "MS", "GG",
    "SATURN", "DC", "32X", "SEGA32X", "3DO", "PANASONIC", "PS", "PSP",
    "MAME", "FBNEO", "ATARI2600", "ATARI5200", "ATARI7800", "LYNX", "JAGUAR",
    "NGP", "PCE", "PCFX", "DOS", "SCUMMVM", "AMIGA", "INTELLIVISION",
    "POKEMINI", "WS", "WSC", "DOOM", "C64", "PC98", "PC88", "QUAKE",
    "TYRQUAKE", "VB", "ARDUBOY", "CPET", "CHAILOVE", "NGC", "CPC", "NEOGEO",
    "ENTERPRISE", "TIC", "MSX", "PICO", "3DS", "CPLUS4", "VIC20", "X1",
    "MEGADUCK", "X68000", "COLECO", "DAPHNE", "VIDEOPAC", "LOWRESNX", "ZXS",
    "SUPERVISION", "XRICK", "DINOTHAWR", "VECTREX", "SEGACD", "SG1000",
    "SFX", "PCECD", "VMAC", "UZEBOX", "CAVESTORY", "WOLF", "TI83", "ATARIST",
    "ARCADE", "WII", "SWITCH", "XBOX",
]

# Canonical base -> ControllerIcons file stem, for bases with no raster art.
FROM_CONTROLLER_ICONS = {
    "JAGUAR": "jaguar",
    "WII": "wii",
    "SWITCH": "switch",
    "XBOX": "xbox",
}

# Canonical base -> existing base whose art is reused (same hardware).
ALIASES = {
    "3DO": "PANASONIC",
    "32X": "SEGA32X",
}

# Canonical base -> dot-art file (relative to retroarch_images/dot-art).
DOTART_ICONS = {
    "PSVITA": "png/Sony - PlayStation Vita.png",
    "EPOCHCV": "systems/epochcv.png",
    "GAME2048": "systems/2048.png",
    "MESS": "systems/mess.png",
    "GAME_MUSIC": "systems/game_music.png",
    "APPLE_II": "png/Apple - II.png",
    "MUSIC": "systems/music.png",
    "BBCMICRO": "png/Acorn - BBC Micro.png",
    "CHIP8": "png/CHIP-8.png",
    "CBM2": "systems/commodore_cbm2.png",
    "BOMBERMAN": "png/MrBoom.png",
    "BGDI": "systems/bgdi.png",
    "J2ME": "systems/J2ME.png",
    "CDI": "png/Philips - CD-i.png",
    "OPENLARA": "png/Tomb Raider.png",
    "DOOM3": "systems/doom_3.png",
    "ARCADIA": "png/Emerson - Arcadia 2001.png",
    "GONG": "systems/gong.png",
    "JUMPNBUMP": "png/Jump 'n Bump.png",
    "PCXT": "systems/pcxt.png",
    "CRAFT": "systems/craft.png",
    "ADVTESTCORE": "systems/adv_test_core.png",
    "ZX81": "png/Sinclair - ZX 81.png",
    "ZMACHINE": "systems/zmachine.png",
    "UNKNOWN": "systems/unknown.png",
    "SEGAPICO": "png/Sega - PICO.png",
}

# Canonical base -> short label, for systems with no art anywhere.
MONOGRAM = {
    "SDLPAL": "SD",
    "PUZZLESCRIPT": "PU",
    "UW8": "UW",
    "CRUZES": "CZ",
    "TAMAGOTCHI": "TM",
    "GAM4980": "G4",
    "ONSCRIPTER": "ON",
    "SYOBONACTION": "SY",
    "RVVM": "RV",
    "REDBOOK": "RB",
    "UXN": "UX",
    "TAYLOR": "TA",
    "P2000T": "P2",
    "ANARCH": "AN",
    "WASM4": "W4",
    "SUPERBROSWAR": "SB",
    "VAPORSPEC": "VS",
    "VIRCON32": "V3",
    "ONSYURI": "ON",
}


def main():
    created = []
    missing_sources = []

    def fill(base, source):
        if source is not None and os.path.exists(source):
            if not os.path.exists(path_600(base)):
                render_600(source).save(path_600(base))
                created.append(f"600/{base}.png")
            if not os.path.exists(path_132(base)):
                render_132(source).save(path_132(base))
                created.append(f"132/{base.lower()}@132w.png")
            return True
        return False

    for base in BASES:
        source = source_for(base)
        if source is None and base in FROM_CONTROLLER_ICONS:
            source = os.path.join(CONTROLLER_ICONS, f"{FROM_CONTROLLER_ICONS[base]}.ico")
        if source is None and base in ALIASES:
            source = source_for(ALIASES[base])
        if not fill(base, source):
            missing_sources.append(base)

    for base, dotart_path in DOTART_ICONS.items():
        created.extend(badge_pair(base, dotart_glyph(dotart_path)))

    for base, label in MONOGRAM.items():
        created.extend(badge_pair(base, monogram_glyph(label)))

    for entry in created:
        print(f"created {entry}")
    if missing_sources:
        print(f"no source for: {', '.join(sorted(set(missing_sources)))}")
    print(f"done: {len(created)} file(s) created")
    return 0


if __name__ == "__main__":
    sys.exit(main())
