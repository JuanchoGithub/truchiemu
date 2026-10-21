#!/usr/bin/env python3
"""
Bundle the game-icons.net library for category iconography.

This script:
1. Downloads the game-icons.net SVG archive (black fill, transparent background)
2. Converts every SVG to a single-page PDF (vector, template-tintable) with rsvg-convert
3. Scrapes the game-icons.net tag pages into a manifest (id, display name, author, tags)
4. Emits TruchiEmu/Resources/GamingIcons/game-icons.zip + game-icons-manifest.json

The app unpacks game-icons.zip to Application Support on first launch and loads
icons on demand as template-tinted NSImages.

Requirements: rsvg-convert (brew install librsvg)
Run this once to generate the bundle, or to refresh the icon set.
Bump ICONS_VERSION whenever the bundle content changes so the app re-unpacks.
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

SVG_ZIP_URL = "https://game-icons.net/archives/000000/transparent/game-icons.net.svg.zip"
TAGS_INDEX_URL = "https://game-icons.net/tags.html"
TAG_PAGE_URL = "https://game-icons.net/tags/{}.html"
LICENSE_URL = "https://raw.githubusercontent.com/game-icons/icons/master/license.txt"

OUTPUT_DIR = Path("TruchiEmu/Resources/GamingIcons")
ZIP_NAME = "game-icons.zip"
MANIFEST_NAME = "game-icons-manifest.json"

ICONS_VERSION = 1
CREDITS = "Category icons by game-icons.net (Lorc, Delapouite & contributors), CC BY 3.0 (creativecommons.org/licenses/by/3.0)"

# Featured theme rows shown at the top of the icon picker.
# "key" is used for localization (icons.theme.<key>), "title" is the English fallback.
FEATURED_THEMES = [
    {"key": "vampires",   "title": "Vampires & Castles", "tags": ["vampire"]},
    {"key": "superMario", "title": "Super Mario",        "tags": ["super-mario"]},
    {"key": "zelda",      "title": "Zelda",              "tags": ["zelda"]},
    {"key": "fighting",   "title": "Fighting & Ninja",   "tags": ["ninja"]},
    {"key": "bloodGore",  "title": "Blood & Gore",       "tags": ["blood"]},
    {"key": "robots",     "title": "Robots & Machines",  "tags": ["robot", "machine"]},
    {"key": "weapons",    "title": "Weapons",            "tags": ["weapon"]},
    {"key": "blades",     "title": "Blades & Swords",    "tags": ["blade"]},
    {"key": "firearms",   "title": "Firearms",          "tags": ["gun"]},
    {"key": "explosions", "title": "Bombs & Explosions", "tags": ["bomb", "explosion"]},
    {"key": "death",      "title": "Skulls & Death",     "tags": ["death"]},
    {"key": "monsters",   "title": "Monsters",           "tags": ["creature"]},
    {"key": "zombies",    "title": "Zombies",            "tags": ["zombie"]},
    {"key": "arcade",     "title": "Arcade & Games",     "tags": ["video-game", "gui"]},
    {"key": "medieval",   "title": "Medieval Fantasy",   "tags": ["medieval-fantasy"]},
    {"key": "scifi",      "title": "Sci-Fi",             "tags": ["science-fiction"]},
    {"key": "sports",     "title": "Sports",             "tags": ["sport"]},
    {"key": "vehicles",   "title": "Vehicles & Racing",  "tags": ["vehicle"]},
    {"key": "dragons",    "title": "Dragons",            "tags": ["reptile"]},
    {"key": "diceCards",  "title": "Dice & Cards",       "tags": ["board", "dice"]},
]

ICON_LINK_RE = re.compile(r'href="/1x1/([a-z0-9-]+)/([a-z0-9-]+)\.html"')
TAG_LINK_RE = re.compile(r'href="/tags/([a-z0-9-]+)\.html"')
TAG_TITLE_RE = re.compile(r"<h1>\d+\s+(.+?)\s+icons")


def fetch(url: str, retries: int = 3) -> bytes:
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "TruchiEmu-bundler/1.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except Exception as exc:
            if attempt == retries - 1:
                raise RuntimeError(f"Failed to fetch {url}: {exc}") from exc
            print(f"  retry {attempt + 1} for {url}: {exc}")
    raise RuntimeError("unreachable")


def convert_svgs_to_pdfs(svg_root: Path, pdf_root: Path) -> int:
    """Convert every <author>/<name>.svg under svg_root to <author>/<name>.pdf under pdf_root."""
    svg_files = sorted(svg_root.glob("*/*.svg"))
    print(f"  converting {len(svg_files)} SVGs to PDF...")

    def convert(svg_path: Path) -> tuple[Path, Path]:
        rel = svg_path.relative_to(svg_root)
        pdf_path = pdf_root / rel.with_suffix(".pdf")
        pdf_path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["rsvg-convert", "-f", "pdf", "--dpi-x", "96", "--dpi-y", "96",
             "-o", str(pdf_path), str(svg_path)],
            check=True, capture_output=True,
        )
        return svg_path, pdf_path

    converted = 0
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(convert, p): p for p in svg_files}
        for future in as_completed(futures):
            future.result()
            converted += 1
            if converted % 500 == 0:
                print(f"    {converted}/{len(svg_files)}")
    return len(svg_files)


def scrape_tags() -> tuple[dict[str, str], dict[str, list[str]]]:
    """Return ({tag slug: tag display name}, {icon id: [tag slugs]})."""
    index_html = fetch(TAGS_INDEX_URL).decode("utf-8")
    tag_slugs = list(dict.fromkeys(TAG_LINK_RE.findall(index_html)))
    print(f"  scraping {len(tag_slugs)} tag pages...")

    tag_names: dict[str, str] = {}
    icon_tags: dict[str, list[str]] = {}

    def scrape_tag(slug: str) -> tuple[str, str, list[str]]:
        html = fetch(TAG_PAGE_URL.format(slug)).decode("utf-8")
        title_match = TAG_TITLE_RE.search(html)
        name = title_match.group(1) if title_match else slug.replace("-", " ").title()
        ids = [f"{author}/{icon}" for author, icon in ICON_LINK_RE.findall(html)]
        return slug, name, ids

    with ThreadPoolExecutor(max_workers=8) as pool:
        for future in as_completed([pool.submit(scrape_tag, s) for s in tag_slugs]):
            slug, name, ids = future.result()
            tag_names[slug] = name
            for icon_id in ids:
                icon_tags.setdefault(icon_id, []).append(slug)

    return tag_names, icon_tags


def scrape_authors() -> dict[str, str]:
    """Parse license.txt into {folder name: display name}."""
    text = fetch(LICENSE_URL).decode("utf-8")
    authors: dict[str, str] = {}
    for line in text.splitlines():
        if not line.startswith("- "):
            continue
        entry = line[2:]
        entry = re.sub(r"\s*-\s*CC0\s*$", "", entry)  # license suffix
        parts = [p.strip() for p in entry.split(",")]
        display = parts[0]
        folder = display.lower().replace(" ", "-")
        authors[folder] = display
    return authors


def display_name(file_stem: str) -> str:
    return file_stem.replace("-", " ").title()


def main() -> None:
    work = Path(tempfile.mkdtemp(prefix="game-icons-"))
    svg_root = work / "svg"
    pdf_root = work / "pdf"
    try:
        print("1. Downloading SVG archive...")
        svg_zip = work / "game-icons.net.svg.zip"
        svg_zip.write_bytes(fetch(SVG_ZIP_URL))
        with zipfile.ZipFile(svg_zip) as zf:
            zf.extractall(svg_root)
        # Archive layout: icons/000000/transparent/1x1/<author>/<name>.svg
        icon_base = svg_root / "icons" / "000000" / "transparent" / "1x1"
        if not icon_base.is_dir():
            sys.exit(f"Unexpected archive layout: {icon_base} not found")

        print("2. Scraping tag metadata...")
        tag_names, icon_tags = scrape_tags()
        authors = scrape_authors()

        print("3. Converting SVGs to PDFs...")
        count = convert_svgs_to_pdfs(icon_base, pdf_root)

        print("4. Writing manifest...")
        icons = []
        for pdf_path in sorted(pdf_root.glob("*/*.pdf")):
            author_folder = pdf_path.parent.name
            stem = pdf_path.stem
            icon_id = f"{author_folder}/{stem}"
            icons.append({
                "id": icon_id,
                "name": display_name(stem),
                "author": authors.get(author_folder, display_name(author_folder)),
                "tags": icon_tags.get(icon_id, []),
            })

        manifest = {
            "version": ICONS_VERSION,
            "source": "game-icons.net",
            "license": "CC BY 3.0",
            "licenseUrl": "https://creativecommons.org/licenses/by/3.0/",
            "credits": CREDITS,
            "tags": tag_names,
            "themes": FEATURED_THEMES,
            "icons": icons,
        }

        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        manifest_path = OUTPUT_DIR / MANIFEST_NAME
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, separators=(",", ":")))

        print("5. Writing zip...")
        zip_path = OUTPUT_DIR / ZIP_NAME
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
            for pdf_path in sorted(pdf_root.glob("*/*.pdf")):
                zf.write(pdf_path, arcname=f"{pdf_path.parent.name}/{pdf_path.name}")

        zip_mb = zip_path.stat().st_size / 1_000_000
        manifest_kb = manifest_path.stat().st_size / 1000
        print(f"\nDone: {count} icons")
        print(f"  {zip_path}  ({zip_mb:.1f} MB)")
        print(f"  {manifest_path}  ({manifest_kb:.0f} KB)")
        print(f"  version: {ICONS_VERSION} (bump ICONS_VERSION to force re-unpack)")
        for theme in FEATURED_THEMES:
            theme_count = sum(1 for i in icons if any(t in theme["tags"] for t in i["tags"]))
            print(f"    theme {theme['title']}: {theme_count} icons")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
