#!/usr/bin/env python3
"""
ROM Matching Algorithm Tester - Optimized Version

Tests multiple string matching algorithms against the ROM database.

Usage:
    python3 rom_matching_tester.py [--systems genesis,nes,snes] [--output results.csv]

    # Run threshold sweep analysis:
    python3 rom_matching_tester.py --threshold-sweep [--systems genesis,nes,snes]
"""

import argparse
import csv
import os
import re
import sqlite3
import sys
from collections import defaultdict

# Database and DAT paths
DB_PATH = os.path.expanduser("~/Library/Application Support/TruchiEmu/TruchiEmu.sqlite")
DAT_DIR = os.path.expanduser("~/Library/Application Support/TruchiEmu/Dats")
REPO_DAT_DIR = "/Users/jayjay/gitrepos/truchiemu/TruchiEmu/Resources/Data/LibretroDats/LibretroDats"

SYSTEMS_WITH_DAT = {
    "genesis": "Sega - Mega Drive - Genesis.dat",
    "nes": "Nintendo - Nintendo Entertainment System.dat",
    "snes": "Nintendo - Super Nintendo Entertainment System.dat",
    "nds": "Nintendo - Nintendo DS.dat",
    "sms": "Sega - Master System - Mark III.dat",
    "scummvm": "ScummVM.dat",
    "mame": "MAME.dat",
}

THRESHOLD_SWEEP_VALUES = [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90]


# =============================================================================
# STRING NORMALIZATION
# =============================================================================

def strip_parentheses(s):
    """Strip parenthetical content."""
    result = re.sub(r'\s*\([^)]*\)\s*', ' ', s)
    result = re.sub(r'\s*\[[^\]]*\]\s*', ' ', result)
    return ' '.join(result.split()).lower().strip()


def aggressively_normalized_title(s):
    """Aggressive normalization."""
    result = re.sub(r'\s*\([^)]*\)\s*', ' ', s)
    result = re.sub(r'\s*\[[^\]]*\]\s*', ' ', s)
    result = re.sub(r'\{[^}]*\}', '', result)
    result = result.lower().replace("'", "").replace("&", "and")
    result = re.sub(r'[^a-z0-9\s]', ' ', result)
    return ' '.join(result.split()).strip()


def normalized_comparable_title(s):
    """Simple normalization."""
    return strip_parentheses(s).lower()


def tokenize(s):
    """Tokenize a string into words."""
    s = s.lower().replace("'", "")
    return set(t for t in re.split(r'[^a-z0-9]+', s) if t)


ROMAN_NUMERALS = {'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x',
                   'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'}

def is_roman_numeral(token):
    """Check if token is a roman numeral."""
    return token.lower() in ROMAN_NUMERALS


def is_numeric_token(token):
    """Check if token is a numeric token (arabic or roman numeral)."""
    return token.isdigit() or is_roman_numeral(token)


def extract_numeric_tokens(tokens):
    """Extract only numeric tokens (arabic numbers and roman numerals)."""
    return frozenset(t for t in tokens if is_numeric_token(t))


def strip_common_suffixes(token):
    """Strip common English suffixes, but NOT roman numerals.

    This allows 'Aliens' -> 'Alien' (stripping plural 's')
    but prevents 'III' from being stripped and causing
    'Dragon Quest III' to match 'Dragon Quest I & II'
    """
    # Don't strip roman numerals - they're game numbers, not word suffixes
    if is_roman_numeral(token):
        return token

    for suffix in ['s', 'es', 'ed', 'ing', 'er', 'est', 'ly']:
        if token.endswith(suffix) and len(token) > len(suffix) + 1:
            return token[:-len(suffix)]
    return token


def dice_coefficient(set1, set2):
    """Sørensen-Dice coefficient."""
    if not set1 or not set2:
        return 0.0
    intersection = len(set1 & set2)
    return (2.0 * intersection) / (len(set1) + len(set2))


def levenshtein_distance(s1, s2):
    """Levenshtein edit distance."""
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)

    prev = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        curr = [i + 1]
        for j, c2 in enumerate(s2):
            curr.append(min(prev[j + 1] + 1, curr[j] + 1, prev[j] + (c1 != c2)))
        prev = curr
    return prev[-1]


def jaro_winkler_similarity(s1, s2):
    """Jaro-Winkler similarity (0-1)."""
    if s1 == s2:
        return 1.0
    if not s1 or not s2:
        return 0.0

    len1, len2 = len(s1), len(s2)
    match_dist = max(len1, len2) // 2 - 1
    if match_dist < 0:
        match_dist = 0

    s1_matches = [False] * len1
    s2_matches = [False] * len2
    matches = transpositions = 0

    for i in range(len1):
        start = max(0, i - match_dist)
        end = min(i + match_dist + 1, len2)
        for j in range(start, end):
            if s2_matches[j] or s1[i] != s2[j]:
                continue
            s1_matches[i] = s2_matches[j] = True
            matches += 1
            break

    if matches == 0:
        return 0.0

    k = 0
    for i in range(len1):
        if not s1_matches[i]:
            continue
        while not s2_matches[k]:
            k += 1
        if s1[i] != s2[k]:
            transpositions += 1
        k += 1

    jaro = (matches/len1 + matches/len2 + (matches - transpositions/2)/matches) / 3
    prefix = sum(1 for i in range(min(len1, len2, 4)) if s1[i] == s2[i])
    return jaro + prefix * 0.1 * (1 - jaro)


# =============================================================================
# ALGORITHMS
# =============================================================================

class CurrentDice:
    """Current Sørensen-Dice approach."""
    name = "current_dice_065"

    def __init__(self, entries):
        self.exact_map = defaultdict(list)
        self.aggressive_map = defaultdict(list)
        self.all_entries = []

        for e in entries:
            n = normalized_comparable_title(e['name'])
            a = aggressively_normalized_title(e['name'])
            self.exact_map[n].append(e)
            self.aggressive_map[a].append(e)
            if len(n) >= 3:
                self.all_entries.append(e)

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        # Try exact
        if self.exact_map[q]:
            return self.exact_map[q][0]

        # Try roman numeral variants
        for variant in self._roman_variants(q):
            if self.exact_map.get(variant):
                return self.exact_map[variant][0]

        # Try aggressive
        a = aggressively_normalized_title(query)
        if len(a) >= 2:
            if self.aggressive_map.get(a):
                return self.aggressive_map[a][0]
            for variant in self._roman_variants(a):
                if self.aggressive_map.get(variant):
                    return self.aggressive_map[variant][0]

        return None

    def _roman_variants(self, s):
        """Generate roman numeral variants."""
        variants = set()
        ar2rom = {1:"I",2:"II",3:"III",4:"IV",5:"V",6:"VI",7:"VII",8:"VIII",9:"IX",10:"X"}
        rom2ar = {r.lower():a for a,r in ar2rom.items()}
        ar2text = {1:"one",2:"two",3:"three",4:"four",5:"five",6:"six",7:"seven",8:"eight",9:"nine",10:"ten"}
        text2ar = {t:a for a,t in ar2text.items()}
        text2ar.update({t.capitalize():a for a,t in ar2text.items()})

        for a,r in ar2rom.items():
            ns = re.sub(r'(?<![a-zA-Z])\b' + str(a) + r'\b(?![a-zA-Z0-9])', r, s, flags=re.IGNORECASE)
            if ns != s: variants.add(ns)
        for a,t in ar2text.items():
            ns = re.sub(r'(?<![a-zA-Z])\b' + str(a) + r'\b(?![a-zA-Z0-9])', t, s, flags=re.IGNORECASE)
            if ns != s: variants.add(ns)
        for r,a in rom2ar.items():
            ns = re.sub(r'(?<![a-zA-Z])' + re.escape(r) + r'(?![a-zA-Z0-9])', str(a), s, flags=re.IGNORECASE)
            if ns != s: variants.add(ns)

        return variants


class SuffixStripDice:
    """Dice with suffix stripping."""
    name = "suffix_strip_dice"

    def __init__(self, entries):
        self.exact_map = defaultdict(list)

        for e in entries:
            n = normalized_comparable_title(e['name'])
            tokens = tokenize(n)
            stripped = {' '.join(sorted(strip_common_suffixes(t) for t in tokens if len(t) > 2))}
            for key in [n] + list(stripped):
                self.exact_map[key].append(e)

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        tokens = tokenize(q)
        stripped = ' '.join(sorted(strip_common_suffixes(t) for t in tokens if len(t) > 2))

        for key in [q, stripped]:
            if self.exact_map.get(key):
                return self.exact_map[key][0]

        return None


class DiceWithSuffixStrip:
    """Dice coefficient with suffix stripping on both query and candidate."""
    name = "dice_suffix_strip"

    def __init__(self, entries):
        self.entries = []
        for e in entries:
            n = normalized_comparable_title(e['name'])
            tokens = tokenize(n)
            self.entries.append({
                'entry': e,
                'normalized': n,
                'stripped_tokens': frozenset(strip_common_suffixes(t) for t in tokens if len(t) > 2),
                'tokens': frozenset(tokens)
            })

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        query_tokens = tokenize(q)
        query_numeric = extract_numeric_tokens(query_tokens)
        query_stripped = frozenset(strip_common_suffixes(t) for t in query_tokens if len(t) > 2)

        best = None
        best_score = 0

        for e in self.entries:
            entry_tokens = e['tokens']
            entry_numeric = extract_numeric_tokens(entry_tokens)

            # Exact match first
            if entry_tokens == frozenset(query_tokens):
                return e['entry']

            # Numeric token validation: if both have numeric tokens, they must match
            if query_numeric and entry_numeric and query_numeric != entry_numeric:
                continue  # Different numeric tokens = likely different game, skip

            # Conservative exact stripped match: only accept if stripped tokens are a subset
            # This prevents "Star Fleet" (star, fleet) from matching "Phantasy Star II" (phantasy, star, ii)
            # because {star, fleet} is NOT a subset of {phantasy, star, ii}
            if query_stripped and query_stripped.issubset(entry_tokens):
                return e['entry']

            # Stripped token match (exact equality)
            if query_stripped and e['stripped_tokens'] == query_stripped:
                return e['entry']

            # Dice score - only if Dice >= 0.6 for more confidence
            score = dice_coefficient(query_stripped, e['stripped_tokens'])
            if score > best_score and score >= 0.6:
                best_score = score
                best = e['entry']

        return best


class LevenshteinMatch:
    """Token-level Levenshtein matching."""
    name = "levenshtein"

    def __init__(self, entries):
        self.entries = []
        for e in entries:
            n = normalized_comparable_title(e['name'])
            tokens = [t for t in re.split(r'[^a-z0-9]+', n) if t]
            self.entries.append({
                'entry': e,
                'normalized': n,
                'tokens': tokens
            })

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        query_tokens = [t for t in re.split(r'[^a-z0-9]+', q) if t]

        best = None
        best_score = 0

        for e in self.entries:
            # Exact match
            if q == e['normalized']:
                return e['entry']

            # Token-level Levenshtein
            if len(query_tokens) == len(e['tokens']) or abs(len(query_tokens) - len(e['tokens'])) <= 1:
                matched = 0
                for qt in query_tokens:
                    qt_s = strip_common_suffixes(qt)
                    for et in e['tokens']:
                        et_s = strip_common_suffixes(et)
                        dist = levenshtein_distance(qt_s, et_s)
                        max_len = max(len(qt_s), len(et_s), 1)
                        if 1 - (dist / max_len) >= 0.75:
                            matched += 1
                            break

                if matched >= min(len(query_tokens), len(e['tokens'])) / 2:
                    score = matched / max(len(query_tokens), len(e['tokens']))
                    if score > best_score:
                        best_score = score
                        best = e['entry']

        return best


class JaroWinklerMatch:
    """Jaro-Winkler similarity."""
    name = "jaro_winkler"

    def __init__(self, entries):
        self.entries = []
        for e in entries:
            n = normalized_comparable_title(e['name'])
            if len(n) >= 3:
                self.entries.append({
                    'entry': e,
                    'normalized': n
                })

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        best = None
        best_score = 0

        for e in self.entries:
            if q == e['normalized']:
                return e['entry']

            score = jaro_winkler_similarity(q, e['normalized'])
            if score > best_score and score >= 0.85:
                best_score = score
                best = e['entry']

        return best


class SpaceAgnostic:
    """Match by removing spaces."""
    name = "space_agnostic"

    def __init__(self, entries):
        self.entries = []
        for e in entries:
            n = normalized_comparable_title(e['name'])
            no_space = n.replace(' ', '')
            if len(no_space) >= 4:
                self.entries.append({
                    'entry': e,
                    'no_space': no_space,
                    'normalized': n
                })

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 3:
            return None

        q_ns = q.replace(' ', '')

        for e in self.entries:
            if q_ns == e['no_space']:
                return e['entry']

        return None


class CombinedAlgorithm:
    """Combined best-of approach."""
    name = "combined"

    def __init__(self, entries):
        self.algorithms = [
            SpaceAgnostic(entries),  # Fast exact match for no-space variants
            SuffixStripDice(entries),  # Handles plurals
            DiceWithSuffixStrip(entries),  # Dice with suffix stripping
            JaroWinklerMatch(entries),  # Good for short strings
            CurrentDice(entries),  # Fallback to current
        ]

    def match(self, query):
        for algo in self.algorithms:
            result = algo.match(query)
            if result:
                return result
        return None


# =============================================================================
# DAT PARSING
# =============================================================================

def parse_dat_file(dat_path):
    """Parse a ClrMamePro .dat file."""
    entries = []
    current = None

    try:
        with open(dat_path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()

                if line.startswith('game (') or line.startswith('machine ('):
                    current = {'name': '', 'description': '', 'crc': None}
                elif line == ')' and current:
                    name = current['description'] if current['description'] and len(current['description']) < 150 else current['name']
                    if current['crc']:
                        entries.append({
                            'name': name,
                            'crc': current['crc'].upper(),
                        })
                    current = None
                elif current:
                    if line.startswith('name '):
                        current['name'] = line[5:].strip('" ')
                    elif line.startswith('description '):
                        current['description'] = line[12:].strip('" ')
                    elif 'crc ' in line:
                        m = re.search(r'crc\s+([0-9A-Fa-f]{8})', line)
                        if m:
                            current['crc'] = m.group(1)
    except FileNotFoundError:
        print(f"Warning: {dat_path} not found")
        return []

    return entries


# =============================================================================
# DATABASE LOADING
# =============================================================================

def load_roms_from_db(systems):
    """Load ROMs from database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    roms = []
    for sys_id in systems:
        cursor.execute("""
            SELECT e.ZNAME, e.ZPATH, e.ZSYSTEMID, e.ZCRC32
            FROM ZROMENTRY e
            WHERE e.ZSYSTEMID = ?
        """, (sys_id,))

        for row in cursor.fetchall():
            roms.append({
                'name': row[0],
                'path': row[1],
                'system_id': row[2],
                'crc': row[3],
            })

    conn.close()
    return roms


# =============================================================================
# MAIN TEST
# =============================================================================

def run_tests(systems, output_file=None):
    """Run tests on specified systems."""

    all_results = []

    for sys_id in systems:
        print(f"\n{'='*60}")
        print(f"System: {sys_id}")
        print(f"{'='*60}")

        dat_file = SYSTEMS_WITH_DAT.get(sys_id)
        if not dat_file:
            print(f"No DAT mapping for {sys_id}")
            continue

        dat_path = os.path.join(REPO_DAT_DIR, dat_file)
        if not os.path.exists(dat_path):
            dat_path = os.path.join(DAT_DIR, dat_file)

        entries = parse_dat_file(dat_path)
        print(f"DAT entries: {len(entries)}")

        roms = [r for r in load_roms_from_db([sys_id]) if r['system_id'] == sys_id]
        print(f"ROMs in DB: {len(roms)}")

        if not roms:
            continue

        # Create algorithms
        algos = [
            CurrentDice(entries),
            SuffixStripDice(entries),
            DiceWithSuffixStrip(entries),
            LevenshteinMatch(entries),
            JaroWinklerMatch(entries),
            SpaceAgnostic(entries),
            CombinedAlgorithm(entries),
        ]

        # Test each algorithm
        results_by_algo = {a.name: {'matched': 0, 'crc_correct': 0} for a in algos}
        differences = []

        for i, rom in enumerate(roms):
            if i % 50 == 0:
                print(f"  Progress: {i}/{len(roms)}")

            rom_crc = rom['crc']
            algo_results = {}

            for algo in algos:
                result = algo.match(rom['name'])
                algo_results[algo.name] = result
                if result:
                    results_by_algo[algo.name]['matched'] += 1
                    if rom_crc and result['crc'] == rom_crc:
                        results_by_algo[algo.name]['crc_correct'] += 1

            # Find differences between current and combined
            current = algo_results.get('current_dice_065')
            combined = algo_results.get('combined')

            if current != combined:
                differences.append({
                    'rom_name': rom['name'],
                    'rom_path': rom['path'],
                    'rom_crc': rom_crc,
                    'current_match': current['name'] if current else None,
                    'current_crc': current['crc'] if current else None,
                    'combined_match': combined['name'] if combined else None,
                    'combined_crc': combined['crc'] if combined else None,
                })

        # Print results
        print(f"\nResults:")
        print(f"{'Algorithm':<22} {'Matched':>8} {'%':>6} {'CRC OK':>8}")
        print("-" * 50)
        for algo in algos:
            stats = results_by_algo[algo.name]
            pct = (stats['matched'] / len(roms) * 100) if roms else 0
            print(f"{algo.name:<22} {stats['matched']:>8} {pct:>5.1f}% {stats['crc_correct']:>8}")

        print(f"\nDifferences (current vs combined): {len(differences)}")

        # Show specific differences
        if differences:
            improvements = [d for d in differences if d['combined_match'] and not d['current_match']]
            regressions = [d for d in differences if d['current_match'] and not d['combined_match']]
            other = [d for d in differences if d['current_match'] and d['combined_match']]

            print(f"  Improvements: {len(improvements)}")
            print(f"  Regressions: {len(regressions)}")
            print(f"  Other differences: {len(other)}")

            if improvements:
                print("\n  Sample improvements:")
                for d in improvements[:5]:
                    print(f"    {d['rom_name']}")
                    print(f"      Current:  {d['current_match']}")
                    print(f"      Combined: {d['combined_match']}")

        all_results.append({
            'system': sys_id,
            'total': len(roms),
            'by_algo': results_by_algo,
            'differences': differences
        })

    # Write CSV
    if output_file:
        with open(output_file, 'w', newline='') as f:
            writer = csv.writer(f, quoting=csv.QUOTE_ALL)
            writer.writerow(['System', 'ROM', 'Path', 'CRC', 'Current', 'Combined', 'Type'])
            for r in all_results:
                for d in r['differences']:
                    diff_type = 'improvement' if (d['combined_match'] and not d['current_match']) else \
                                'regression' if (d['current_match'] and not d['combined_match']) else 'other'
                    writer.writerow([
                        r['system'], d['rom_name'], d['rom_path'], d['rom_crc'] or '',
                        d['current_match'] or '', d['combined_match'] or '', diff_type
                    ])
        print(f"\nResults written to {output_file}")

    return all_results


def run_threshold_sweep(systems):
    """Run the matching algorithm with different thresholds to find optimal value."""

    print("\n" + "=" * 80)
    print("THRESHOLD SWEEP ANALYSIS")
    print("=" * 80)
    print(f"Testing thresholds: {THRESHOLD_SWEEP_VALUES}")
    print()

    all_results = {}

    for sys_id in systems:
        print(f"\n{'='*60}")
        print(f"System: {sys_id}")
        print(f"{'='*60}")

        dat_file = SYSTEMS_WITH_DAT.get(sys_id)
        if not dat_file:
            continue

        dat_path = os.path.join(REPO_DAT_DIR, dat_file)
        if not os.path.exists(dat_path):
            dat_path = os.path.join(DAT_DIR, dat_file)

        entries = parse_dat_file(dat_path)
        roms = [r for r in load_roms_from_db([sys_id]) if r['system_id'] == sys_id]

        print(f"DAT entries: {len(entries)}, ROMs: {len(roms)}")

        # Get current matches for baseline
        current_algo = CurrentDice(entries)
        current_matches = set()
        for rom in roms:
            result = current_algo.match(rom['name'])
            if result:
                current_matches.add(rom['name'])

        print(f"Current algorithm matches: {len(current_matches)}")

        # Test each threshold
        for threshold in THRESHOLD_SWEEP_VALUES:
            algo = ThresholdSweepAlgo(entries, threshold)
            matched = 0
            matched_names = []

            for rom in roms:
                result = algo.match(rom['name'])
                if result:
                    matched += 1
                    matched_names.append((rom['name'], result['name']))

            new_matches = matched - len(current_matches)

            if sys_id not in all_results:
                all_results[sys_id] = {}

            all_results[sys_id][threshold] = {
                'matched': matched,
                'new_matches': new_matches,
                'match_rate': matched / len(roms) if roms else 0,
                'samples': matched_names[-20:]  # Last 20 for inspection
            }

    # Print summary table
    print("\n" + "=" * 100)
    print("THRESHOLD SWEEP RESULTS")
    print("=" * 100)

    # Header
    header = f"{'Threshold':<12}"
    for sys_id in systems:
        short = sys_id[:6]
        header += f"{short} Match{'':5}{'':4}{short} +New{'':3}"
    header += f"{'Total':<12}{'Total +New':<12}"
    print(header)
    print("-" * 100)

    for threshold in THRESHOLD_SWEEP_VALUES:
        row = f"{threshold:<12.2f}"
        total_matched = 0
        total_new = 0

        for sys_id in systems:
            if sys_id in all_results and threshold in all_results[sys_id]:
                r = all_results[sys_id][threshold]
                matched_str = str(r['matched'])
                new_str = str(r['new_matches'])
                row += f"{matched_str:<15}{new_str:<10}"
                total_matched += r['matched']
                total_new += r['new_matches']
            else:
                row += f"{'N/A':<15}{'N/A':<10}"

        row += f"{total_matched:<12}{total_new:<12}"
        print(row)

    print("\n" + "=" * 100)
    print("SAMPLE MATCHES BY THRESHOLD")
    print("=" * 100)

    for threshold in THRESHOLD_SWEEP_VALUES:
        print(f"\n>>> Threshold: {threshold:.2f}")
        for sys_id in systems:
            if sys_id in all_results and threshold in all_results[sys_id]:
                samples = all_results[sys_id][threshold]['samples']
                if samples:
                    print(f"  {sys_id}: {samples[:5]}")

    return all_results


class DiceOnlyAlgo:
    """Algorithm WITHOUT subset matching - uses only exact + Dice matching."""

    name = "dice_only"

    def __init__(self, entries, threshold=0.6):
        self.entries = []
        self.threshold = threshold
        for e in entries:
            n = normalized_comparable_title(e['name'])
            tokens = tokenize(n)
            self.entries.append({
                'entry': e,
                'normalized': n,
                'tokens': frozenset(tokens),
                'stripped_tokens': frozenset(strip_common_suffixes(t) for t in tokens if len(t) > 2)
            })

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        query_tokens = tokenize(q)
        query_numeric = extract_numeric_tokens(query_tokens)
        query_stripped = frozenset(strip_common_suffixes(t) for t in query_tokens if len(t) > 2)

        best = None
        best_score = 0

        for e in self.entries:
            # Exact match
            if e['tokens'] == frozenset(query_tokens):
                return e['entry']

            # Numeric token validation
            entry_numeric = extract_numeric_tokens(e['tokens'])
            if query_numeric and entry_numeric and query_numeric != entry_numeric:
                continue

            # NO subset match here - only Dice

            # Dice score only
            score = dice_coefficient(query_stripped, e['stripped_tokens'])
            if score > best_score and score >= self.threshold:
                best_score = score
                best = e['entry']

        return best


def run_dice_only_test(systems):
    """Test algorithm WITHOUT subset matching - uses only exact + Dice."""

    print("\n" + "=" * 80)
    print("TESTING: Dice-Only Algorithm (NO SUBSET MATCHING)")
    print("=" * 80)

    all_results = {}

    for sys_id in systems:
        print(f"\n{'='*60}")
        print(f"System: {sys_id}")
        print(f"{'='*60}")

        dat_file = SYSTEMS_WITH_DAT.get(sys_id)
        if not dat_file:
            continue

        dat_path = os.path.join(REPO_DAT_DIR, dat_file)
        if not os.path.exists(dat_path):
            dat_path = os.path.join(DAT_DIR, dat_file)

        entries = parse_dat_file(dat_path)
        roms = [r for r in load_roms_from_db([sys_id]) if r['system_id'] == sys_id]

        print(f"DAT entries: {len(entries)}, ROMs: {len(roms)}")

        current_algo = CurrentDice(entries)
        dice_algo = DiceOnlyAlgo(entries, threshold=0.6)

        current_matches = {}
        dice_matches = {}
        differences = []

        for rom in roms:
            current = current_algo.match(rom['name'])
            dice_result = dice_algo.match(rom['name'])

            if current:
                current_matches[rom['name']] = current['name']
            if dice_result:
                dice_matches[rom['name']] = dice_result['name']

            if current is None and dice_result is not None:
                differences.append(('new', rom['name'], '', dice_result['name']))
            elif current is not None and dice_result is None:
                differences.append(('lost', rom['name'], current['name'], ''))
            elif current is not None and dice_result is not None and current['name'] != dice_result['name']:
                differences.append(('diff', rom['name'], current['name'], dice_result['name']))

        print(f"Current algorithm matches: {len(current_matches)}")
        print(f"Dice-only matches: {len(dice_matches)}")
        print(f"New matches found: {sum(1 for d in differences if d[0] == 'new')}")
        print(f"Lost matches: {sum(1 for d in differences if d[0] == 'lost')}")
        print(f"Different matches: {sum(1 for d in differences if d[0] == 'diff')}")

        all_results[sys_id] = {
            'current': len(current_matches),
            'dice': len(dice_matches),
            'differences': differences
        }

    # Print summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"{'System':<15}{'Current':<12}{'DiceOnly':<12}{'New':<10}{'Lost':<10}{'Diff':<10}")
    print("-" * 70)

    total_current = total_dice = total_new = total_lost = total_diff = 0

    for sys_id, r in all_results.items():
        diffs = r['differences']
        new_c = sum(1 for d in diffs if d[0] == 'new')
        lost_c = sum(1 for d in diffs if d[0] == 'lost')
        diff_c = sum(1 for d in diffs if d[0] == 'diff')
        print(f"{sys_id:<15}{r['current']:<12}{r['dice']:<12}{new_c:<10}{lost_c:<10}{diff_c:<10}")
        total_current += r['current']
        total_dice += r['dice']
        total_new += new_c
        total_lost += lost_c
        total_diff += diff_c

    print("-" * 70)
    print(f"{'TOTAL':<15}{total_current:<12}{total_dice:<12}{total_new:<10}{total_lost:<10}{total_diff:<10}")

    # Check for false positives
    print("\n" + "=" * 80)
    print("CHECKING FOR FALSE POSITIVES")
    print("=" * 80)

    KNOWN_WRONG = [
        ('Star Fleet', 'Phantasy Star'),
        ('Commandos', 'Papi Commando'),
        ('Outland', 'Outlander'),
        ('Dyna Head', 'Dyna Brothers'),
        ('Sonic 4', 'Sonic The Hedgehog'),
    ]

    for sys_id, r in all_results.items():
        fps = []
        for diff_type, rom, old_match, new_match in r['differences']:
            if new_match:
                for bad_rom, bad_fragment in KNOWN_WRONG:
                    if bad_rom.lower() == rom.lower() and bad_fragment.lower() in new_match.lower():
                        fps.append((rom, new_match))
                        break
        if fps:
            print(f"\n{sys_id} FALSE POSITIVES:")
            for rom, match in fps:
                print(f"  {rom} -> {match[:60]}")

    if not any(fps for fps_list in [r['differences'] for r in all_results.values()] for fps in fps_list):
        print("  (none found!)")

    print("\n" + "=" * 80)
    print("SAMPLE NEW MATCHES")
    print("=" * 80)

    for sys_id, r in all_results.items():
        new_matches = [(d[1], d[3]) for d in r['differences'] if d[0] == 'new']
        if new_matches:
            print(f"\n{sys_id} (first 10 new matches):")
            for rom, match in new_matches[:10]:
                print(f"  {rom} -> {match[:60]}")

    return all_results


class SubsetOnlyAlgo:
    """Algorithm WITHOUT Dice matching - uses only exact/subset matching."""

    name = "subset_only"

    def __init__(self, entries):
        self.entries = []
        for e in entries:
            n = normalized_comparable_title(e['name'])
            tokens = tokenize(n)
            self.entries.append({
                'entry': e,
                'normalized': n,
                'tokens': frozenset(tokens),
                'stripped_tokens': frozenset(strip_common_suffixes(t) for t in tokens if len(t) > 2)
            })

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        query_tokens = tokenize(q)
        query_numeric = extract_numeric_tokens(query_tokens)
        query_stripped = frozenset(strip_common_suffixes(t) for t in query_tokens if len(t) > 2)

        for e in self.entries:
            # Exact match
            if e['tokens'] == frozenset(query_tokens):
                return e['entry']

            # Numeric token validation
            entry_numeric = extract_numeric_tokens(e['tokens'])
            if query_numeric and entry_numeric and query_numeric != entry_numeric:
                continue

            # Stripped subset match only (NO Dice fallback)
            if query_stripped and query_stripped.issubset(e['tokens']):
                return e['entry']

        return None


class ThresholdSweepAlgo:
    """Test algorithm with configurable threshold."""

    name = "threshold_sweep"

    def __init__(self, entries, threshold):
        self.entries = []
        self.threshold = threshold

        for e in entries:
            n = normalized_comparable_title(e['name'])
            tokens = tokenize(n)
            self.entries.append({
                'entry': e,
                'normalized': n,
                'tokens': frozenset(tokens),
                'stripped_tokens': frozenset(strip_common_suffixes(t) for t in tokens if len(t) > 2)
            })

    def match(self, query):
        q = normalized_comparable_title(query)
        if len(q) < 2:
            return None

        query_tokens = tokenize(q)
        query_numeric = extract_numeric_tokens(query_tokens)
        query_stripped = frozenset(strip_common_suffixes(t) for t in query_tokens if len(t) > 2)

        best = None
        best_score = 0

        for e in self.entries:
            # Exact match
            if e['tokens'] == frozenset(query_tokens):
                return e['entry']

            # Numeric token validation
            entry_numeric = extract_numeric_tokens(e['tokens'])
            if query_numeric and entry_numeric and query_numeric != entry_numeric:
                continue

            # Stripped subset match (conservative)
            if query_stripped and query_stripped.issubset(e['tokens']):
                return e['entry']

            # Dice score
            score = dice_coefficient(query_stripped, e['stripped_tokens'])
            if score > best_score and score >= self.threshold:
                best_score = score
                best = e['entry']

        return best


def run_subset_only_test(systems):
    """Test algorithm WITHOUT Dice matching - uses only exact/subset matching."""

    print("\n" + "=" * 80)
    print("TESTING: Subset-Only Algorithm (NO DICE MATCHING)")
    print("=" * 80)

    all_results = {}

    for sys_id in systems:
        print(f"\n{'='*60}")
        print(f"System: {sys_id}")
        print(f"{'='*60}")

        dat_file = SYSTEMS_WITH_DAT.get(sys_id)
        if not dat_file:
            continue

        dat_path = os.path.join(REPO_DAT_DIR, dat_file)
        if not os.path.exists(dat_path):
            dat_path = os.path.join(DAT_DIR, dat_file)

        entries = parse_dat_file(dat_path)
        roms = [r for r in load_roms_from_db([sys_id]) if r['system_id'] == sys_id]

        print(f"DAT entries: {len(entries)}, ROMs: {len(roms)}")

        current_algo = CurrentDice(entries)
        subset_algo = SubsetOnlyAlgo(entries)

        current_matches = {}
        subset_matches = {}
        differences = []

        for rom in roms:
            current = current_algo.match(rom['name'])
            subset = subset_algo.match(rom['name'])

            if current:
                current_matches[rom['name']] = current['name']
            if subset:
                subset_matches[rom['name']] = subset['name']

            if current is None and subset is not None:
                differences.append(('new', rom['name'], '', subset['name']))
            elif current is not None and subset is None:
                differences.append(('lost', rom['name'], current['name'], ''))
            elif current is not None and subset is not None and current['name'] != subset['name']:
                differences.append(('diff', rom['name'], current['name'], subset['name']))

        print(f"Current algorithm matches: {len(current_matches)}")
        print(f"Subset-only matches: {len(subset_matches)}")
        print(f"New matches found: {sum(1 for d in differences if d[0] == 'new')}")
        print(f"Lost matches: {sum(1 for d in differences if d[0] == 'lost')}")
        print(f"Different matches: {sum(1 for d in differences if d[0] == 'diff')}")

        all_results[sys_id] = {
            'current': len(current_matches),
            'subset': len(subset_matches),
            'differences': differences
        }

    # Print summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"{'System':<15}{'Current':<12}{'Subset':<12}{'New':<10}{'Lost':<10}{'Diff':<10}")
    print("-" * 70)

    total_current = total_subset = total_new = total_lost = total_diff = 0

    for sys_id, r in all_results.items():
        diffs = r['differences']
        new_c = sum(1 for d in diffs if d[0] == 'new')
        lost_c = sum(1 for d in diffs if d[0] == 'lost')
        diff_c = sum(1 for d in diffs if d[0] == 'diff')
        print(f"{sys_id:<15}{r['current']:<12}{r['subset']:<12}{new_c:<10}{lost_c:<10}{diff_c:<10}")
        total_current += r['current']
        total_subset += r['subset']
        total_new += new_c
        total_lost += lost_c
        total_diff += diff_c

    print("-" * 70)
    print(f"{'TOTAL':<15}{total_current:<12}{total_subset:<12}{total_new:<10}{total_lost:<10}{total_diff:<10}")

    # Check for false positives
    print("\n" + "=" * 80)
    print("CHECKING FOR FALSE POSITIVES")
    print("=" * 80)

    KNOWN_WRONG = [
        ('Star Fleet', 'Phantasy Star'),
        ('Commandos', 'Papi Commando'),
        ('Outland', 'Outlander'),
        ('Dyna Head', 'Dyna Brothers'),
        ('Sonic 4', 'Sonic The Hedgehog'),
    ]

    for sys_id, r in all_results.items():
        fps = []
        for diff_type, rom, old_match, new_match in r['differences']:
            if new_match:
                for bad_rom, bad_fragment in KNOWN_WRONG:
                    if bad_rom.lower() == rom.lower() and bad_fragment.lower() in new_match.lower():
                        fps.append((rom, new_match))
                        break
        if fps:
            print(f"\n{sys_id} FALSE POSITIVES:")
            for rom, match in fps:
                print(f"  {rom} -> {match[:60]}")

    if not any(fps for fps_list in [r['differences'] for r in all_results.values()] for fps in fps_list):
        print("  (none found!)")

    print("\n" + "=" * 80)
    print("SAMPLE NEW MATCHES")
    print("=" * 80)

    for sys_id, r in all_results.items():
        new_matches = [(d[1], d[3]) for d in r['differences'] if d[0] == 'new']
        if new_matches:
            print(f"\n{sys_id} (first 10 new matches):")
            for rom, match in new_matches[:10]:
                print(f"  {rom} -> {match[:60]}")

    return all_results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--systems', default='genesis,nes,snes')
    parser.add_argument('--output', default=None)
    parser.add_argument('--threshold-sweep', action='store_true',
                        help='Run threshold sweep analysis')
    parser.add_argument('--subset-only', action='store_true',
                        help='Test algorithm without Dice matching')
    parser.add_argument('--dice-only', action='store_true',
                        help='Test algorithm without subset matching')
    args = parser.parse_args()

    systems = args.systems.split(',')

    if args.subset_only:
        run_subset_only_test(systems)
    elif args.dice_only:
        run_dice_only_test(systems)
    elif args.threshold_sweep:
        run_threshold_sweep(systems)
    else:
        run_tests(systems, args.output)


if __name__ == '__main__':
    main()