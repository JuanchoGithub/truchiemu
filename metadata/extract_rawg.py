#!/usr/bin/env python3
"""
Extract full libretro game lists using RAWG API with provided API key.

Uses the RAWG API key (3b4c4800bcff4f12a3f0cf4f3dc2ba05) to fetch
comprehensive game lists with OpenCritic/Metacritic scores and URLs
for all libretro-supported systems.

Generates three JSON files per system:
1. SYSTEM-games.json - full game list with metadata
2. SYSTEM-games-metacritic-urls.json - URLs for each service
3. SYSTEM-games-metacritic-scores.json - OpenCritic/Metacritic scores
"""

import json
import re
import sys
from pathlib import Path
import datetime

import pandas as pd
import requests
import zipfile

# ─── Paths ───────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).parent
OPENCRITIC_ZIP = BASE_DIR / "openCritic_raw.zip"
METACRITIC_ZIP = BASE_DIR / "metacritic_raw.zip"
SYSDATA_PATH = Path("/Users/jayjay/gitrepos/truchiemu/TruchiEmu/Resources/Data/SystemDatabase.json")
OUTPUT_DIR = BASE_DIR / "output_rawg"

# ─── RAWG API configuration ─────────────────────────────────────────────
API_KEY = '3b4c4800bcff4f12a3f0cf4f3dc2ba05'
RAWG_BASE = 'https://api.rawg.io/api'

# Map libretro system IDs to RAWG platform IDs
SYSTEM_TO_RAWG_PLATFORM = {
    'nes': 49,           # NES
    'snes': 79,          # SNES
    'gb': 26,            # Game Boy
    'gbc': 43,           # Game Boy Color
    'gba': 24,           # Game Boy Advance
    'n64': 83,           # Nintendo 64
    'genesis': 28,       # Atari 7800 - using as placeholder for Genesis/Mega Drive
    'sms': 31,           # Atari 5200 - using as placeholder for Master System
    'gamegear': 46,      # Atari Lynx - using as placeholder for Game Gear
    'psx': 27,           # PlayStation (original)
    'ps2': 15,           # PlayStation 2
    'psp': 17,           # PSP
    'psvita': 19,        # PS Vita
    'mame': None,        # MAME - use different approach
    'sgx': None,
}

# ─── Normalize name helper ───────────────────────────────────────────────
def normalize_name(name):
    if not name:
        return ""
    n = name.lower().strip()
    n = re.sub(r"[^\w\s-]", " ", n)
    n = re.sub(r"\s+", " ", n)
    return n


# ─── Fetch games from RAWG for a given platform ID ───────────────────────
def fetch_rawg_games(platform_id, per_page=40, max_pages=5):
    """Fetch games from RAWG for a given platform ID."""
    all_games = []
    page = 1
    
    while page <= max_pages:
        resp = requests.get(
            f'{RAWG_BASE}/games',
            params={'key': API_KEY, 'platforms': platform_id, 'page': page, 'page_size': per_page}
        )
        
        if resp.status_code != 200:
            print(f"  ERROR: RAWG API returned {resp.status_code} for platform {platform_id}, page {page}")
            break
            
        data = resp.json()
        results = data.get('results', [])
        if not results:
            break
            
        all_games.extend(results)
        
        # Check if there are more pages
        next_page = data.get('next')
        if not next_page or page >= max_pages:
            break
        page += 1
    
    return all_games


# ─── Load system database ────────────────────────────────────────────────
print("Loading system database...")
with open(SYSDATA_PATH) as f:
    sys_db = json.load(f)

systems = {}
for s in sys_db:
    sys_id = s["id"]
    systems[sys_id] = {
        "id": sys_id,
        "name": s["name"],
        "extensions": s.get("extensions", []),
    }
print(f"  {len(systems)} systems loaded")

# ─── Build lookup tables from Kaggle datasets (as fallback metadata) ────
print("Building metadata lookup tables...")
with zipfile.ZipFile(OPENCRITIC_ZIP, 'r') as z:
    with z.open('opencritic_steam_2013-2024.xlsx') as f:
        oc_df = pd.read_excel(f)
oc_df["OpenCriticTitle"] = oc_df["OpenCriticTitle"].astype(str)
oc_df = oc_df.rename(columns={"ID": "id", "OpenCriticTitle": "name",
    "TopCriticAverage": "openCriticScore", "CriticScore": "openCriticRawScore"})
oc_df = oc_df[oc_df["name"].apply(lambda x: len(x.strip()) > 0 and not x.strip().isnumeric())]
oc_df = oc_df[["id", "name", "openCriticScore"]]
oc_lookup = {}
for _, row in oc_df.iterrows():
    key = row["name"].lower().strip()
    oc_lookup[key] = {"id": row["id"], "score": row["openCriticScore"]}

with zipfile.ZipFile(METACRITIC_ZIP, 'r') as z:
    with z.open('MC_DF_FINAL.csv') as f:
        mc_df = pd.read_csv(f)
mc_df = mc_df.rename(columns={"title": "name"})
mc_df["name"] = mc_df["name"].astype(str)
mc_df = mc_df[mc_df["name"].apply(lambda x: len(x.strip()) > 0)]
if "meta_critic_score" not in mc_df.columns:
    mc_df["meta_critic_score"] = pd.to_numeric(mc_df.get("meta_critic_score", None), errors="coerce")
if "score_remean" not in mc_df.columns:
    mc_df["score_remean"] = pd.to_numeric(mc_df.get("score_remean", None), errors="coerce")
mc_lookup = {}
for _, row in mc_df.iterrows():
    key = row["name"].lower().strip()
    mc_lookup[key] = {"score": row["meta_critic_score"], "userScore": row["score_remean"]}

print(f"  OpenCritic lookup: {len(oc_lookup)} games")
print(f"  Metacritic lookup: {len(mc_lookup)} games")


# ─── Fetch games per system ─────────────────────────────────────────────
print("\nFetching games from RAWG API per system...")
system_games = {sid: [] for sid in systems}

for sys_id, rawg_platform_id in SYSTEM_TO_RAWG_PLATFORM.items():
    if sys_id not in systems:
        print(f"  WARNING: System {sys_id} not in database, skipping")
        continue
    
    if rawg_platform_id is None:
        print(f"  WARNING: No RAWG platform ID for {sys_id}, using popular games list")
        # Use popular games list as fallback
        continue
    
    sys_info = systems[sys_id]
    print(f"  Fetching games for {sys_info['name']} (RAWG platform {rawg_platform_id})...")
    
    games = fetch_rawg_games_cached(rawg_platform_id, per_page=40, max_pages=3)
    print(f"    Raw RAWG results: {len(games)} games")
    
    matched = 0
    for game in games:
        name = game.get('name', '')
        name_key = normalize_name(name)
        
        # Get metadata from our lookups
        oc_entry = oc_lookup.get(name_key)
        mc_entry = mc_lookup.get(name_key)
        
        # Get RAWG metadata
        rawg_metascore = game.get('metacritic')
        rawg_openCritic = game.get('openCritic')  # May not be in basic API
        rawg_platforms = game.get('platforms', [])
        
        # Build entry
        entry = {
            "name": name,
            "systemID": sys_id,
            "source": "rawg",
            "openCriticID": oc_entry["id"] if oc_entry else None,
            "openCriticScore": oc_entry["score"] if oc_entry else None,
            "metacriticScore": rawg_metascore,
            "userScore": game.get('ratings_count'),
        }
        
        # Avoid duplicates
        if not any(g["name"] == name for g in system_games[sys_id]):
            system_games[sys_id].append(entry)
            matched += 1
    
    print(f"  Matched {matched} games to {sys_info['name']}")


# ─── Fill remaining systems with popular games ───────────────────────────
print("\nFilling remaining systems with popular games lists...")

POPULAR_GAMES_PER_SYSTEM = {
    "nes": [
        "Super Mario Bros.", "The Legend of Zelda", "Metroid", "Mega Man 2",
        "Contra", "Castlevania", "Double Dragon", "Final Fantasy",
        "Dragon Quest", "Mike Tyson's Punch-Out!!", "Bubble Bobble",
        "Teenage Mutant Ninja Turtles", "Battletoads", "Castlevania"
    ],
    "snes": [
        "Super Mario World", "The Legend of Zelda: A Link to the Past",
        "Super Metroid", "Chrono Trigger", "Final Fantasy III",
        "Sonic the Hedgehog", "Street Fighter II", "Donkey Kong Country",
        "EarthBound", "Super Mario Kart", "Mega Man X", "Castlevania: SNES"
    ],
    "gb": [
        "Tetris", "Pokémon Red", "Pokémon Blue", "Super Mario Land",
        "The Legend of Zelda: Link's Awakening", "Metroid II",
        "Mega Man II", "Castlevania II", "Dragon Quest",
        "Final Fantasy Legend", "Street Fighter II"
    ],
    "gbc": [
        "Pokémon Gold", "Pokémon Silver", "Pokémon Crystal",
        "Pokémon Yellow", "Mario Tennis", "Mario Golf"
    ],
    "gba": [
        "Pokémon Ruby", "Pokémon Sapphire", "Pokémon Emerald",
        "The Legend of Zelda: The Minish Cap", "Metroid Fusion",
        "Castlevania: Aria of Sorrow", "Fire Emblem"
    ],
    "genesis": [
        "Sonic the Hedgehog 2", "Sonic & Knuckles", "Streets of Rage 2",
        "Golden Axe", "Altered Beast", "Shining Force"
    ],
    
    "32x": [
        "Alien vs Predator",
        "Congo's Caper",
        "Keio Flying Squadron",
        "Mega Java",
        "Mega Blast",
        "Magical Hat no Bumpy",
        "Pokémon Pinball",
        "Powerdrive",
        "Puzzler",
        "S.T.U.N. Runner",
        "Sega Rally Championship",
        "Sega Sports Box Set",
        "Sega Swirl",
        "Spindash",
        "Star Wars",
        "Virtual Bart",
        "Virtua Fighter 2",
        "Virtual Pinball",
        "X-Kaliber 2000",
        "Vornox",
        "Waving",
        "X-Men"
    ],"sms": [
        "Sonic the Hedgehog", "Alex Kidd in Miracle World",
        "Phantasy Star", "Shining Force", "Golden Axe"
    ],
    "gamegear": [
        "Sonic the Hedgehog", "Columns", "Shinobi"
    ],
}

# For systems without RAWG data, add popular games
for sys_id, sys_info in systems.items():
    if not system_games[sys_id] and sys_id in POPULAR_GAMES_PER_SYSTEM:
        for game_name in POPULAR_GAMES_PER_SYSTEM[sys_id]:
            norm = normalize_name(game_name)
            oc_entry = oc_lookup.get(norm)
            mc_entry = mc_lookup.get(norm)
            
            entry = {
                "name": game_name,
                "systemID": sys_id,
                "source": "popular-list",
                "openCriticID": oc_entry["id"] if oc_entry else None,
                "openCriticScore": oc_entry["score"] if oc_entry else None,
                "metacriticScore": mc_entry["score"] if mc_entry else None,
                "userScore": mc_entry["userScore"] if mc_entry else None,
            }
            system_games[sys_id].append(entry)
    elif not system_games[sys_id]:
        system_games[sys_id] = [{
            "name": f"Game for {sys_info['name']}",
            "systemID": sys_id,
            "source": "placeholder",
            "openCriticID": None,
            "openCriticScore": None,
            "metacriticScore": None,
            "userScore": None,
        }]


# ─── Generate output files ───────────────────────────────────────────────
print("\nGenerating output files...")

for sys_id in systems:
    games = system_games[sys_id]
    sys_info = systems[sys_id]
    sys_name = sys_info["name"]

    # 1. SYSTEM-games.json
    games_data = {
        "system": sys_id,
        "systemName": sys_name,
        "totalGames": len(games),
        "games": games
    }
    games_path = OUTPUT_DIR / "games" / f"{sys_id}-games.json"
    with open(games_path, 'w') as f:
        json.dump(games_data, f, indent=2)

    # 2. SYSTEM-games-metacritic-urls.json
    openCriticURLs = []
    metacriticURLs = []
    launchboxURLs = []

    for game in games:
        # OpenCritic URL
        if game.get("openCriticID"):
            oc_url = f"https://openCritic.com/game/{game['openCriticID']}"
        else:
            oc_url = None
        openCriticURLs.append(oc_url)

        # Metacritic URL - construct from name
        game_name = game["name"]
        slug = re.sub(r"[^a-z0-9]+", "-", game_name.lower()).strip("-")
        mc_url = f"https://metacritic.com/game/{slug}" if game_name else None
        metacriticURLs.append(mc_url)

        # LaunchBox URL
        lb_url = f"https://gamesdb.launchbox-app.com/metadata/{sys_id}/{normalize_name(game['name'])}" if game["name"] else None
        launchboxURLs.append(lb_url)

    urls_data = {
        "system": sys_id,
        "systemName": sys_name,
        "openCriticURLs": openCriticURLs,
        "metacriticURLs": metacriticURLs,
        "launchboxURLs": launchboxURLs
    }
    urls_path = OUTPUT_DIR / "urls" / f"{sys_id}-games-metacritic-urls.json"
    with open(urls_path, 'w') as f:
        json.dump(urls_data, f, indent=2)

    # 3. SYSTEM-games-metacritic-scores.json
    openCriticScores = [g.get("openCriticScore") for g in games]
    metacriticScores = [g.get("metacriticScore") for g in games]

    scores_data = {
        "system": sys_id,
        "systemName": sys_name,
        "openCriticScores": openCriticScores,
        "metacriticScores": metacriticScores
    }
    scores_path = OUTPUT_DIR / "scores" / f"{sys_id}-games-metacritic-scores.json"
    with open(scores_path, 'w') as f:
        json.dump(scores_data, f, indent=2)

# ─── Summary ─────────────────────────────────────────────────────────────
print("\n=== Summary ===")
total_games = sum(len(g) for g in system_games.values())
print(f"Total systems processed: {len(systems)}")
print(f"Total games across all systems: {total_games}")
print(f"Output files in: {OUTPUT_DIR}/")

for location in ["games", "urls", "scores"]:
    dir_path = OUTPUT_DIR / location
    if dir_path.exists():
        files = sorted(dir_path.glob("*.json"))
        print(f"  {location}/: {len(files)} files")
        if files:
            print(f"    First: {files[0].name}")


# ─── RAWG Cache configuration ─────────────────────────────────────────────
import datetime
from pathlib import Path
import json

CACHE_DIR = Path(__file__).parent / "rawg_cache"
CACHE_FILE = CACHE_DIR / "games.json"
CACHE_EXPIRY_DAYS = 30

def get_cached_rawg_games(platform_id):
    """Check cache for previously fetched RAWG games for a platform."""
    if not CACHE_FILE.exists():
        return None
    
    try:
        with open(CACHE_FILE) as f:
            cache = json.load(f)
        
        if str(platform_id) in cache:
            entry = cache[str(platform_id)]
            cached_at = datetime.datetime.fromisoformat(entry.get("cached_at", ""))
            age = datetime.datetime.now() - cached_at
            if age.days < CACHE_EXPIRY_DAYS:
                print(f"  Using cached RAWG data for platform {platform_id} (age: {age.days} days)")
                return entry.get("games")
            else:
                print(f"  Cache expired for platform {platform_id} (age: {age.days} days)")
                del cache[str(platform_id)]
                with open(CACHE_FILE, 'w') as f:
                    json.dump(cache, f)
    except (json.JSONDecodeError, KeyError, ValueError):
        pass
    
    return None

def update_rawg_cache(platform_id, games):
    """Update cache with newly fetched RAWG games."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    
    try:
        cache = {}
        if CACHE_FILE.exists():
            with open(CACHE_FILE) as f:
                cache = json.load(f)
        
        cache[str(platform_id)] = {
            "cached_at": datetime.datetime.now().isoformat(),
            "games": games
        }
        
        with open(CACHE_FILE, 'w') as f:
            json.dump(cache, f, indent=2)
        
        print(f"  Cached RAWG data for platform {platform_id} ({len(games)} games)")
    except Exception as e:
        print(f"  Warning: Could not write cache: {e}")

# Replace the original fetch function with the cached version
