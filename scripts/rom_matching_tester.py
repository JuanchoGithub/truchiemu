#!/usr/bin/env python3
"""
ROM Matching Algorithm Tester

Tests multiple string matching algorithms against the ROM database to find
the best approach for identifying games by name.

Usage:
    python3 rom_matching_tester.py [--systems genesis,nes,snes] [--output results.csv]

This script:
1. Loads ROMs from the TruchiEmu SQLite database
2. Parses DAT files for ground truth (CRC -> game title)
3. Implements multiple matching algorithms
4. Compares results and outputs detailed analysis
"""

import argparse
import csv
import os
import re
import sqlite3
import sys
from collections import defaultdict
from difflib import SequenceMatcher
from pathlib import Path

# Database and DAT paths
DB_PATH = os.path.expanduser("~/Library/Application Support/TruchiEmu/TruchiEmu.sqlite")
DAT_DIR = os.path.expanduser("~/Library/Application Support/TruchiEmu/Dats")
REPO_DAT_DIR = "/Users/jayjay/gitrepos/truchiemu/TruchiEmu/Resources/Data/LibretroDats/LibretroDats"

# Systems to test
SYSTEMS_WITH_DAT = {
    "genesis": "Sega - Mega Drive - Genesis.dat",
    "nes": "Nintendo - Nintendo Entertainment System.dat",
    "snes": "Nintendo - Super Nintendo Entertainment System.dat",
}


# =============================================================================
# ALGORITHM IMPLEMENTATIONS
# =============================================================================

def strip_parentheses(s):
    """Strip parenthetical content from a title (matching Swift implementation)."""
    result = s
    result = re.sub(r'\s*\([^)]*\)\s*', ' ', result)
    result = re.sub(r'\s*\[[^\]]*\]\s*', ' ', result)
    result = ' '.join(result.split()).lower().strip()
    return result


def aggressively_normalized_title(s):
    """Aggressive normalization - strip all brackets, lowercase, replace & with 'and'."""
    result = s
    result = re.sub(r'\s*\([^)]*\)\s*', ' ', result)
    result = re.sub(r'\s*\[[^\]]*\]\s*', ' ', result)
    result = re.sub(r'\{[^}]*\}', '', result)
    result = result.lower()
    result = result.replace("'", "")
    result = result.replace("&", "and")
    result = re.sub(r'[^a-z0-9\s]', ' ', result)
    result = ' '.join(result.split()).strip()
    return result


def normalized_comparable_title(s):
    """Simple normalization - strip parentheses and lowercase."""
    return strip_parentheses(s).lower()


def roman_numeral_variants(normalized):
    """Generate variants with roman numeral <-> number conversions."""
    variants = set()
    arabic_to_roman = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "VI", 7: "VII", 8: "VIII", 9: "IX", 10: "X"}
    arabic_to_text = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten"}
    roman_to_arabic = {r.lower(): a for a, r in arabic_to_roman.items()}
    text_to_arabic = {t: a for a, t in arabic_to_text.items()}
    text_to_arabic.update({t.capitalize(): a for a, t in arabic_to_text.items()})

    # Number -> Roman
    for a, r in arabic_to_roman.items():
        pattern = r'(?<![a-zA-Z])\b' + str(a) + r'\b(?![a-zA-Z0-9])'
        new_s = re.sub(pattern, r, normalized, flags=re.IGNORECASE)
        if new_s != normalized:
            variants.add(new_s)

    # Number -> Text
    for a, t in arabic_to_text.items():
        pattern = r'(?<![a-zA-Z])\b' + str(a) + r'\b(?![a-zA-Z0-9])'
        new_s = re.sub(pattern, t, normalized, flags=re.IGNORECASE)
        if new_s != normalized:
            variants.add(new_s)

    # Roman -> Number
    for r, a in roman_to_arabic.items():
        esc = re.escape(r)
        if len(r) == 1:
            pattern = r'(?<![a-zA-Z])' + esc + r'(?![a-zA-Z0-9\'])'
        else:
            pattern = r'(?<![a-zA-Z])' + esc + r'(?![a-zA-Z0-9])'
        new_s = re.sub(pattern, str(a), normalized, flags=re.IGNORECASE)
        if new_s != normalized:
            variants.add(new_s)

    # Roman -> Text
    for r, a in roman_to_arabic.items():
        if a in arabic_to_text:
            esc = re.escape(r)
            pattern = r'(?<![a-zA-Z])' + esc + r'(?![a-zA-Z0-9])'
            new_s = re.sub(pattern, arabic_to_text[a], normalized, flags=re.IGNORECASE)
            if new_s != normalized:
                variants.add(new_s)

    # Text -> Roman
    for t, a in text_to_arabic.items():
        if a in arabic_to_roman:
            esc = re.escape(t)
            pattern = r'(?<![a-zA-Z])' + esc + r'(?![a-zA-Z0-9])'
            new_s = re.sub(pattern, arabic_to_roman[a], normalized, flags=re.IGNORECASE)
            if new_s != normalized:
                variants.add(new_s)

    # Remove common suffixes like " 1", " i"
    t = normalized.strip()
    for pat in [r' 1$', r' i$', r' one$']:
        new_s = re.sub(pat, '', t, flags=re.IGNORECASE).strip()
        if new_s != t and len(new_s) >= 2:
            variants.add(new_s)

    return list(variants)


def strip_common_suffixes(token):
    """Strip common English suffixes from a token for better matching."""
    suffixes = ['s', 'es', 'ed', 'ing', 'er', 'est', 'ly']
    for suffix in suffixes:
        if token.endswith(suffix) and len(token) > len(suffix) + 1:
            return token[:-len(suffix)]
    return token


def tokenize(s):
    """Tokenize a string into a set of words."""
    s = s.lower().replace("'", "")
    tokens = re.split(r'[^a-z0-9]+', s)
    return set(t for t in tokens if t)


def dice_coefficient(set1, set2):
    """Sørensen-Dice coefficient between two sets."""
    if not set1 or not set2:
        return 0.0
    intersection = len(set1 & set2)
    return (2.0 * intersection) / (len(set1) + len(set2))


def levenshtein_distance(s1, s2):
    """Compute Levenshtein edit distance between two strings."""
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def jaro_winkler_similarity(s1, s2):
    """Jaro-Winkler similarity (0-1, higher is better)."""
    if s1 == s2:
        return 1.0

    len1, len2 = len(s1), len(s2)
    if len1 == 0 or len2 == 0:
        return 0.0

    match_distance = max(len1, len2) // 2 - 1
    if match_distance < 0:
        match_distance = 0

    s1_matches = [False] * len1
    s2_matches = [False] * len2
    matches = 0
    transpositions = 0

    for i in range(len1):
        start = max(0, i - match_distance)
        end = min(i + match_distance + 1, len2)
        for j in range(start, end):
            if s2_matches[j] or s1[i] != s2[j]:
                continue
            s1_matches[i] = True
            s2_matches[j] = True
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

    jaro = (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3
    # Winkler modification
    prefix_len = 0
    for i in range(min(len1, len2, 4)):
        if s1[i] == s2[i]:
            prefix_len += 1
        else:
            break

    return jaro + prefix_len * 0.1 * (1 - jaro)


# =============================================================================
# MATCHING ALGORITHMS
# =============================================================================

class MatchingAlgorithm:
    """Base class for matching algorithms."""

    name = "base"

    def match(self, query, candidates):
        """Return best match for query from candidates list, or None."""
        raise NotImplementedError


class CurrentAlgorithm(MatchingAlgorithm):
    """Current Sørensen-Dice approach from TruchiEmu."""

    name = "current_dice_065"

    def __init__(self, dat_entries):
        self.dat_entries = dat_entries
        self.exact_map = defaultdict(list)
        self.aggressive_map = defaultdict(list)
        self.all_entries = []

        for entry in dat_entries:
            normalized = normalized_comparable_title(entry['name'])
            aggressive = aggressively_normalized_title(entry['name'])

            self.exact_map[normalized].append(entry)
            if len(normalized) >= 3:
                self.all_entries.append(entry)

            self.aggressive_map[aggressive].append(entry)

    def match(self, query, candidates=None):
        """Match using current Dice approach with 0.65 threshold."""
        query_base = normalized_comparable_title(query)
        if len(query_base) < 2:
            return None

        # PASS 1: Exact normalized match
        exact = self.exact_map.get(query_base, [])

        # PASS 2: Roman numeral variants
        if not exact:
            for variant in roman_numeral_variants(query_base):
                exact = self.exact_map.get(variant, [])
                if exact:
                    break

        # PASS 3: Aggressive normalization
        if not exact:
            aggressive_query = aggressively_normalized_title(query)
            if len(aggressive_query) >= 2:
                exact = self.aggressive_map.get(aggressive_query, [])
                if not exact:
                    for variant in roman_numeral_variants(aggressive_query):
                        exact = self.aggressive_map.get(variant, [])
                        if exact:
                            break

        return exact[0] if exact else None


class SuffixStripDice(MatchingAlgorithm):
    """Dice with suffix stripping for plural/tense handling."""

    name = "suffix_strip_dice"

    def __init__(self, dat_entries):
        self.dat_entries = dat_entries
        self.entries_by_normalized = defaultdict(list)

        for entry in dat_entries:
            normalized = normalized_comparable_title(entry['name'])
            tokens = tokenize(normalized)
            # Also store with suffix-stripped tokens
            stripped_tokens = {strip_common_suffixes(t) for t in tokens if len(t) > 2}
            if stripped_tokens:
                key = ' '.join(sorted(stripped_tokens))
                self.entries_by_normalized[key].append(entry)
            # Original
            self.entries_by_normalized[normalized].append(entry)

    def match(self, query, candidates=None):
        query_base = normalized_comparable_title(query)
        if len(query_base) < 2:
            return None

        # Try with suffix stripping
        tokens = tokenize(query_base)
        stripped_tokens = {strip_common_suffixes(t) for t in tokens if len(t) > 2}

        # Build variants to try
        variants = set()
        variants.add(query_base)
        variants.add(' '.join(sorted(stripped_tokens)))

        for variant in roman_numeral_variants(query_base):
            variants.add(variant)
            tokens = tokenize(variant)
            stripped = {strip_common_suffixes(t) for t in tokens if len(t) > 2}
            variants.add(' '.join(sorted(stripped)))

        for variant in variants:
            if variant in self.entries_by_normalized:
                return self.entries_by_normalized[variant][0]

        return None


class TokenLevenshtein(MatchingAlgorithm):
    """Token-level Levenshtein matching for handling small typos."""

    name = "token_levenshtein"

    def __init__(self, dat_entries):
        self.dat_entries = dat_entries
        self.entries_for_match = []

        for entry in dat_entries:
            normalized = normalized_comparable_title(entry['name'])
            if len(normalized) >= 3:
                self.entries_for_match.append({
                    'entry': entry,
                    'normalized': normalized,
                    'tokens': tokenize(normalized)
                })

    def match(self, query, candidates=None):
        query_base = normalized_comparable_title(query)
        if len(query_base) < 2:
            return None

        query_tokens = tokenize(query_base)
        best_match = None
        best_score = 0.0

        for item in self.entries_for_match:
            # Check for exact token match first
            if query_tokens == item['tokens']:
                return item['entry']

            # Try Levenshtein on individual tokens
            match_score = 0.0
            matched_tokens = 0

            for qt in query_tokens:
                qt_stripped = strip_common_suffixes(qt)
                for dt in item['tokens']:
                    dt_stripped = strip_common_suffixes(dt)
                    dist = levenshtein_distance(qt_stripped, dt_stripped)
                    max_len = max(len(qt_stripped), len(dt_stripped), 1)
                    similarity = 1.0 - (dist / max_len)
                    if similarity >= 0.75:  # 75% similarity threshold
                        matched_tokens += 1
                        match_score += similarity

            if matched_tokens > 0 and match_score > best_score:
                # Require at least half the tokens to match reasonably
                if matched_tokens >= min(len(query_tokens), len(item['tokens'])) / 2:
                    best_score = match_score
                    best_match = item['entry']

        return best_match


class JaroWinklerMatch(MatchingAlgorithm):
    """Jaro-Winkler similarity for short string matching."""

    name = "jaro_winkler"

    def __init__(self, dat_entries):
        self.dat_entries = dat_entries
        self.entries_for_match = []

        for entry in dat_entries:
            normalized = normalized_comparable_title(entry['name'])
            if len(normalized) >= 3:
                self.entries_for_match.append({
                    'entry': entry,
                    'normalized': normalized
                })

    def match(self, query, candidates=None):
        query_base = normalized_comparable_title(query)
        if len(query_base) < 2:
            return None

        best_match = None
        best_score = 0.0

        for item in self.entries_for_match:
            # Exact match
            if query_base == item['normalized']:
                return item['entry']

            # Try full string Jaro-Winkler
            score = jaro_winkler_similarity(query_base, item['normalized'])
            if score > best_score and score >= 0.85:
                best_score = score
                best_match = item['entry']

            # Try on stripped versions (without parentheses)
            query_stripped = strip_parentheses(query)
            item_stripped = strip_parentheses(item['normalized'])
            if query_stripped != query_base or item_stripped != item['normalized']:
                score2 = jaro_winkler_similarity(query_stripped, item_stripped)
                if score2 > best_score and score2 >= 0.85:
                    best_score = score2
                    best_match = item['entry']

        return best_match


class HybridBestOf(MatchingAlgorithm):
    """Run all algorithms and take the best result with confidence scoring."""

    name = "hybrid_best_of"

    def __init__(self, dat_entries):
        self.algorithms = [
            SuffixStripDice(dat_entries),
            TokenLevenshtein(dat_entries),
            JaroWinklerMatch(dat_entries),
            CurrentAlgorithm(dat_entries),  # Include current as fallback
        ]

    def match(self, query, candidates=None):
        results = []
        for algo in self.algorithms:
            result = algo.match(query)
            if result:
                results.append((algo.name, result))

        if not results:
            return None

        # For now, just return the first successful match (suffix strip has priority)
        # In a more sophisticated implementation, we'd do confidence voting
        return results[0][1]


# =============================================================================
# DAT PARSING
# =============================================================================

def parse_dat_file(dat_path):
    """Parse a ClrMamePro .dat file and return list of game entries."""
    entries = []
    current_game = None
    in_game = False

    try:
        with open(dat_path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()

                if line.startswith('game (') or line.startswith('machine ('):
                    current_game = {
                        'name': '',
                        'description': '',
                        'crc': None,
                    }
                    in_game = True
                elif line == ')' and current_game:
                    # Determine title
                    if current_game['description'] and len(current_game['description']) < 150:
                        name = current_game['description']
                    else:
                        name = current_game['name']

                    if current_game['crc']:
                        entries.append({
                            'name': name,
                            'crc': current_game['crc'].upper(),
                            'stripped_name': normalized_comparable_title(name),
                            'aggressive_name': aggressively_normalized_title(name),
                        })
                    current_game = None
                    in_game = False
                elif in_game and current_game:
                    if line.startswith('name '):
                        current_game['name'] = line[5:].strip('" ')
                    elif line.startswith('description '):
                        current_game['description'] = line[12:].strip('" ')
                    elif line.startswith('rom '):
                        # Extract CRC from rom line
                        match = re.search(r'crc\s+([0-9A-Fa-f]{8})', line)
                        if match:
                            current_game['crc'] = match.group(1)

    except FileNotFoundError:
        print(f"Warning: DAT file not found: {dat_path}")
        return []

    return entries


# =============================================================================
# DATABASE LOADING
# =============================================================================

def load_roms_from_db(systems):
    """Load ROMs from the TruchiEmu database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    roms = []
    for system_id in systems:
        cursor.execute("""
            SELECT e.ZNAME, e.ZPATH, e.ZSYSTEMID, e.ZCRC32, m.ZTITLE, m.ZCRC32
            FROM ZROMENTRY e
            LEFT JOIN ZROMMETADATAENTRY m ON e.ZPATH = m.ZPATHKEY
            WHERE e.ZSYSTEMID = ?
        """, (system_id,))

        for row in cursor.fetchall():
            roms.append({
                'name': row[0],
                'path': row[1],
                'system_id': row[2],
                'crc': row[3],
                'metadata_title': row[4],
                'metadata_crc': row[5],
            })

    conn.close()
    return roms


# =============================================================================
# MAIN TEST LOGIC
# =============================================================================

def run_tests(systems, output_file=None):
    """Run matching algorithm tests on specified systems."""

    all_results = []

    for system_id in systems:
        print(f"\n{'='*60}")
        print(f"Testing system: {system_id}")
        print(f"{'='*60}")

        # Find DAT file
        dat_filename = SYSTEMS_WITH_DAT.get(system_id)
        if not dat_filename:
            print(f"No DAT mapping for {system_id}, skipping")
            continue

        dat_path = os.path.join(REPO_DAT_DIR, dat_filename)
        if not os.path.exists(dat_path):
            # Try App Support Dats dir
            dat_path = os.path.join(DAT_DIR, dat_filename)

        print(f"Using DAT: {dat_path}")

        # Parse DAT
        dat_entries = parse_dat_file(dat_path)
        print(f"Parsed {len(dat_entries)} entries from DAT")

        if not dat_entries:
            continue

        # Create CRC lookup for ground truth
        crc_to_entry = {}
        for entry in dat_entries:
            if entry['crc']:
                crc_to_entry[entry['crc']] = entry

        # Load ROMs
        roms = [r for r in load_roms_from_db([system_id]) if r['system_id'] == system_id]
        print(f"Loaded {len(roms)} ROMs from database")

        # Create algorithms
        algorithms = [
            CurrentAlgorithm(dat_entries),
            SuffixStripDice(dat_entries),
            TokenLevenshtein(dat_entries),
            JaroWinklerMatch(dat_entries),
            HybridBestOf(dat_entries),
        ]

        # Run tests
        system_results = {
            'system': system_id,
            'total_roms': len(roms),
            'by_algorithm': {},
            'differences': []
        }

        for algo in algorithms:
            matched = 0
            crc_correct = 0
            for rom in roms:
                result = algo.match(rom['name'])
                if result:
                    matched += 1
                    # Check CRC if available
                    if rom['crc'] and result['crc'] == rom['crc']:
                        crc_correct += 1

            system_results['by_algorithm'][algo.name] = {
                'matched': matched,
                'match_rate': matched / len(roms) if roms else 0,
                'crc_correct': crc_correct,
            }

        # Find differences between current and improved algorithms
        current_algo = algorithms[0]  # CurrentAlgorithm
        improved_algo = algorithms[3]  # JaroWinklerMatch (often best for fuzzy)

        for rom in roms:
            current_result = current_algo.match(rom['name'])
            improved_result = improved_algo.match(rom['name'])

            # Check if they differ
            differs = False
            if current_result is None and improved_result is not None:
                differs = True
                diff_type = 'improvement'
            elif current_result is not None and improved_result is None:
                differs = True
                diff_type = 'regression'
            elif current_result is not None and improved_result is not None:
                if current_result['name'] != improved_result['name']:
                    differs = True
                    # Check if improved is actually better (matches CRC)
                    if rom['crc']:
                        if improved_result['crc'] == rom['crc'] and current_result['crc'] != rom['crc']:
                            diff_type = 'improvement'
                        elif current_result['crc'] == rom['crc'] and improved_result['crc'] != rom['crc']:
                            diff_type = 'regression'
                        else:
                            diff_type = 'different_match'
                    else:
                        diff_type = 'different_match'

            if differs:
                system_results['differences'].append({
                    'rom_name': rom['name'],
                    'path': rom['path'],
                    'crc': rom['crc'],
                    'current_match': current_result['name'] if current_result else None,
                    'current_crc': current_result['crc'] if current_result else None,
                    'improved_match': improved_result['name'] if improved_result else None,
                    'improved_crc': improved_result['crc'] if improved_result else None,
                    'diff_type': diff_type,
                })

        # Print summary
        print(f"\nResults for {system_id}:")
        print(f"{'Algorithm':<25} {'Matched':<10} {'Rate':<10} {'CRC Correct':<15}")
        print("-" * 60)
        for algo in algorithms:
            stats = system_results['by_algorithm'][algo.name]
            print(f"{algo.name:<25} {stats['matched']:<10} {stats['match_rate']:.2%}     {stats['crc_correct']}")

        print(f"\nDifferences found: {len(system_results['differences'])}")
        if system_results['differences']:
            print("\nSample differences:")
            for diff in system_results['differences'][:10]:
                print(f"  {diff['rom_name']}")
                print(f"    Current:  {diff['current_match']} (CRC: {diff['current_crc']})")
                print(f"    Improved: {diff['improved_match']} (CRC: {diff['improved_crc']})")
                print(f"    Type: {diff['diff_type']}")

        all_results.append(system_results)

    # Write CSV output if requested
    if output_file:
        with open(output_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['System', 'ROM Name', 'Path', 'CRC', 'Current Match', 'Improved Match', 'Diff Type'])

            for result in all_results:
                for diff in result['differences']:
                    writer.writerow([
                        result['system'],
                        diff['rom_name'],
                        diff['path'],
                        diff['crc'] or '',
                        diff['current_match'] or '',
                        diff['improved_match'] or '',
                        diff['diff_type']
                    ])

        print(f"\nResults written to {output_file}")

    return all_results


def main():
    parser = argparse.ArgumentParser(description='Test ROM matching algorithms')
    parser.add_argument('--systems', default='genesis,nes,snes',
                        help='Comma-separated list of systems to test')
    parser.add_argument('--output', default=None,
                        help='Output CSV file for differences')

    args = parser.parse_args()
    systems = args.systems.split(',')

    print(f"Testing systems: {systems}")
    print(f"Database: {DB_PATH}")

    run_tests(systems, args.output)


if __name__ == '__main__':
    main()