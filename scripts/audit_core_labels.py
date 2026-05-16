#!/usr/bin/env python3
import json
import re
import os

CORE_LABELS_DIR = "/Users/jayjay/gitrepos/truchiemu/TruchiEmu/Resources/Data/CoreButtonSplit/coreLabels"
DOCS_CACHE_DIR = "/Users/jayjay/gitrepos/truchiemu/scripts/.docs_cache"

RETROPAD_IMG_TO_BUTTON = {
    "retro_b.png": "b", "retro_a.png": "a", "retro_y.png": "y", "retro_x.png": "x",
    "retro_select.png": "select", "retro_start.png": "start",
    "retro_dpad_up.png": "up", "retro_dpad_down.png": "down",
    "retro_dpad_left.png": "left", "retro_dpad_right.png": "right",
    "retro_l1.png": "l1", "retro_r1.png": "r1",
    "retro_l2.png": "l2", "retro_r2.png": "r2",
    "retro_l3.png": "l3", "retro_r3.png": "r3",
    "retro_left_stick.png": "lStick",
    "retro_right_stick.png": "rStick",
}

VALID_BUTTONS = {
    "a", "b", "x", "y", "select", "start",
    "up", "down", "left", "right",
    "l1", "r1", "l2", "r2", "l3", "r3",
    "lStickLeft", "lStickRight", "lStickUp", "lStickDown",
    "rStickLeft", "rStickRight", "rStickUp", "rStickDown",
    "c", "z", "pause", "coin1", "reset"
}

USER1_HEADER_PATTERNS = [
    r'User\s+1\s+input\s+descriptors',
    r'User\s+1\s*-\s*\d+\s+input\s+descriptors',
    r'User\s+1\s*-\s*\d+\s+Remap\s+descriptors',
    r'User\s+1\s+Remap\s+descriptors',
    r'User\s+1\s+input\s+descriptors\s+for',
    r'Player\s+1[/.]\d+.*\b(?:Joystick|Joypad|Input)',
    r'User\s+1\s*-\s*\d+\s+device\s+types',
]

RETROPAD_HEADER_PATTERNS = [
    r'RetroPad\s+Inputs?',
]

CORE_INPUT_HEADER_PATTERNS = [
    r'.*\bcore\s+inputs?\b',
    r'.*\bCursor\s+Joystick\b',
    r'^\s*RetroPad\s*$',
]


def find_col_index(header_line, patterns):
    cells = [c.strip() for c in header_line.split('|')]
    while cells and not cells[0]: cells.pop(0)
    while cells and not cells[-1]: cells.pop()
    for idx, cell in enumerate(cells):
        cell_clean = re.sub(r'\[.*?\]\(.*?\)', '', cell).strip()
        for pat in patterns:
            if re.search(pat, cell_clean, re.IGNORECASE):
                return idx
    return None


def find_user1_col_index(header_line):
    return find_col_index(header_line, USER1_HEADER_PATTERNS)


def find_retropad_col_index(header_line):
    return find_col_index(header_line, RETROPAD_HEADER_PATTERNS)


def find_core_input_col_index(header_line):
    return find_col_index(header_line, CORE_INPUT_HEADER_PATTERNS)


def clean_label(text):
    text = re.sub(r'!\[.*?\]\(.*?\)', '', text)
    text = re.sub(r'\[(.*?)\]\(.*?\)', r'\1', text)
    text = text.replace('<br>', ' ')
    text = re.sub(r'\s+', ' ', text).strip()
    return text if text else None


def is_separator_row(line):
    return bool(re.match(r'^[\|\s\-:]+$', line))


def parse_cells(line):
    cells = [c.strip() for c in line.split('|')]
    while cells and not cells[0]: cells.pop(0)
    while cells and not cells[-1]: cells.pop()
    return cells


def extract_tables_from_section(tables_text):
    """Split section text into individual tables (list of list of cells, first sublist is header)."""
    lines = tables_text.split('\n')
    tables = []
    current_table = []
    in_table = False

    for line in lines:
        if '|' not in line:
            if in_table and current_table:
                tables.append(current_table)
                current_table = []
                in_table = False
            continue

        if is_separator_row(line):
            continue

        cells = parse_cells(line)
        if not cells:
            continue

        # Detect header row by checking for header keywords AFTER removing image references
        is_header = False
        joined_raw = ' '.join(cells).lower()
        joined = re.sub(r'!\[.*?\]\(.*?\)', '', joined_raw)
        joined = re.sub(r'retropad/\w+', '', joined)
        # Strict header detection: require "retropad" + "input/descriptor/user" combos,
        # or "user" + "input/remap/descriptor", or "player" + "joystick/joypad"
        is_header = bool(
            re.search(r'retropad.*input|input.*retropad|remap.*descriptor|descriptor.*remap', joined) or
            re.search(r'user\s+\d+.*(?:input|remap|device)', joined) or
            re.search(r'player\s+\d+.*(?:joystick|joypad)', joined) or
            re.search(r'v-liner', joined)
        )
        if not is_header and not in_table:
            is_header = False
            in_table = True
            current_table.append(cells)
            continue

        if is_header:
            if in_table and current_table:
                tables.append(current_table)
            current_table = [cells]
            in_table = True
        else:
            if not in_table:
                in_table = True
                current_table = []
            current_table.append(cells)

    if current_table:
        tables.append(current_table)

    return tables


def find_label_in_row(row, img_cell_idx, user1_col, core_input_col):
    """Find the label for a button given the row cells and known column indices.
    Handles empty user1_col cells by falling back to other columns."""
    # Try user1_col first
    if user1_col is not None and user1_col < len(row):
        label = clean_label(row[user1_col])
        if label:
            return label

    # Try core_input_col
    if core_input_col is not None and core_input_col < len(row):
        label = clean_label(row[core_input_col])
        if label:
            return label

    # Fallback: find the first non-image, non-empty cell that isn't the image cell
    # Prefer the first text cell we find, but skip cells that are just "RetroPad"
    for idx, c in enumerate(row):
        if idx == img_cell_idx:
            continue
        l = clean_label(c)
        if l and l not in ('RetroPad', 'RetroPad Inputs', '---', ':-:', '-'):
            return l

    return None


def parse_single_table(table_rows):
    """Parse a single table into dict of button -> label and stick info."""
    result = {}
    has_left_stick = False
    has_right_stick = False
    left_stick_x_label = None
    left_stick_y_label = None
    right_stick_x_label = None
    right_stick_y_label = None

    if not table_rows:
        return result, has_left_stick, has_right_stick, left_stick_x_label, left_stick_y_label, right_stick_x_label, right_stick_y_label

    header = table_rows[0]
    data_rows = table_rows[1:] if len(table_rows) > 1 else []

    header_line = '| ' + ' | '.join(header) + ' |'
    user1_col = find_user1_col_index(header_line)
    retropad_col = find_retropad_col_index(header_line)
    core_input_col = find_core_input_col_index(header_line)

    has_header = user1_col is not None or retropad_col is not None

    if not has_header:
        # Headerless table - determine format from first row
        if table_rows and re.search(r'retropad/', '|'.join(table_rows[0])):
            data_rows = table_rows
        else:
            # First row might be a header without recognized keywords
            # Check if first row has any text cells (non-image)
            first_row = table_rows[0]
            has_images = any(re.search(r'retropad/', c) for c in first_row)
            has_text = any(clean_label(c) for c in first_row if not re.search(r'retropad/', c))
            if has_images and not has_text:
                # Pure image row - skip
                data_rows = table_rows[1:] if len(table_rows) > 1 else []
            else:
                data_rows = table_rows

        if data_rows:
            first_row = data_rows[0]
            # Find which column has the image
            for idx, cell in enumerate(first_row):
                if re.search(r'retropad/', cell):
                    img_col = idx
                    # The label is in the other column
                    if img_col == 0:
                        user1_col = 1
                    elif img_col == 1 and len(first_row) >= 3:
                        # 3-col: col0=label, col1=image, col2=extra
                        # Try col0 first
                        label0 = clean_label(first_row[0])
                        if label0:
                            user1_col = 0
                        else:
                            # col0 is empty, label is in col2
                            user1_col = 2
                    elif img_col == 1:
                        user1_col = 0
                    else:
                        user1_col = 0
                    break
        else:
            return result, has_left_stick, has_right_stick, left_stick_x_label, left_stick_y_label, right_stick_x_label, right_stick_y_label

    # Now parse all data rows
    for row in data_rows:
        for cell_idx, cell in enumerate(row):
            img_matches = re.findall(r'retropad/(retro_\w+\.png)', cell)
            if not img_matches:
                continue

            for img_name in img_matches:
                button = RETROPAD_IMG_TO_BUTTON.get(img_name)
                if not button:
                    continue

                axis = None
                axis_match = re.search(r'retro_(?:left|right)_stick\.png\)\s*(X|Y)', cell)
                if axis_match:
                    axis = axis_match.group(1)

                label = find_label_in_row(row, cell_idx, user1_col, core_input_col)

                if button == "lStick":
                    has_left_stick = True
                    if axis == 'X':
                        left_stick_x_label = label
                    elif axis == 'Y':
                        left_stick_y_label = label
                elif button == "rStick":
                    has_right_stick = True
                    if axis == 'X':
                        right_stick_x_label = label
                    elif axis == 'Y':
                        right_stick_y_label = label
                else:
                    if label is not None:
                        result[button] = label

    return result, has_left_stick, has_right_stick, left_stick_x_label, left_stick_y_label, right_stick_x_label, right_stick_y_label


def parse_joypad_section(md_content):
    """Find and parse the Joypad/Controller/Input section from markdown doc."""
    lines = md_content.split('\n')

    # Find relevant sections (Joypad, Controller, Input Devices)
    sections = []
    current_section = None
    joypad_depth = 999

    for i, line in enumerate(lines):
        heading_match = re.match(r'^(#+)\s+(.*)', line)
        if heading_match:
            level = len(heading_match.group(1))
            title = heading_match.group(2).strip()

            if re.search(r'(?:Joypad|Controller|Input\s+Device)', title, re.IGNORECASE):
                # Save any existing section first
                if current_section is not None:
                    sections.append('\n'.join(current_section))
                current_section = []
                joypad_depth = level
                current_section.append(line)
                continue

            if current_section is not None and level <= joypad_depth:
                sections.append('\n'.join(current_section))
                current_section = None
                continue

        if current_section is not None:
            current_section.append(line)

    if current_section:
        sections.append('\n'.join(current_section))

    if not sections:
        # Fallback: search for any table containing retropad images
        if 'retropad' in md_content.lower():
            # Try to find tables by looking for retropad image lines
            return parse_fallback_tables(md_content)
        return {}, False, False, None, None, None, None

    best_result = {}
    best_sticks = (False, False, None, None, None, None)
    best_count = 0

    for section_text in sections:
        # Look for "#### Joypad" sub-section specifically
        joypad_sub = None

        # Try multiple heading levels
        sub_match = re.search(r'^#{2,4}\s+Joypad\s*$', section_text, re.MULTILINE)
        if sub_match:
            start = sub_match.start()
            rest = section_text[start:]
            # Find next same-or-higher level heading
            heading_level = len(re.match(r'^(#+)', rest).group(1))
            end_match = re.search(r'\n^#{1,' + str(heading_level) + r'}\s+', rest[1:], re.MULTILINE)
            if end_match:
                joypad_sub = rest[:1 + end_match.start()]
            else:
                joypad_sub = rest

        text_to_parse = joypad_sub if joypad_sub else section_text
        tables = extract_tables_from_section(text_to_parse)

        for table_rows in tables:
            result, has_ls, has_rs, lsx, lsy, rsx, rsy = parse_single_table(table_rows)
            if result and len(result) > best_count:
                best_result = result
                best_sticks = (has_ls, has_rs, lsx, lsy, rsx, rsy)
                best_count = len(result)

    return best_result, best_sticks[0], best_sticks[1], best_sticks[2], best_sticks[3], best_sticks[4], best_sticks[5]


def parse_fallback_tables(md_content):
    """Fallback: find any table with retropad images when no Joypad/Controller section found."""
    lines = md_content.split('\n')
    # Collect all table lines
    table_lines = []
    in_table = False
    for line in lines:
        if '|' in line and not is_separator_row(line):
            cells = parse_cells(line)
            if cells:
                # Check if this row has retropad images or is a header for such a table
                has_img = any(re.search(r'retropad/', c) for c in cells)
                joined = re.sub(r'!\[.*?\]\(.*?\)', '', ' '.join(cells).lower())
                has_header_kw = any(kw in joined for kw in ['retropad', 'user', 'input', 'joystick', 'joypad'])
                if has_img or has_header_kw:
                    if not in_table:
                        in_table = True
                        table_lines.append([])
                    table_lines[-1].append(cells)
                elif in_table:
                    in_table = False
        else:
            if in_table:
                in_table = False

    best_result = {}
    best_sticks = (False, False, None, None, None, None)
    best_count = 0

    for table_rows in table_lines:
        result, has_ls, has_rs, lsx, lsy, rsx, rsy = parse_single_table(table_rows)
        if result and len(result) > best_count:
            best_result = result
            best_sticks = (has_ls, has_rs, lsx, lsy, rsx, rsy)
            best_count = len(result)

    return best_result, best_sticks[0], best_sticks[1], best_sticks[2], best_sticks[3], best_sticks[4], best_sticks[5]


def extract_core_name(filename):
    match = re.match(r'input_coreLabels_(.+)\.json', filename)
    if match:
        return match.group(1)
    return None


def find_doc_file(core_name):
    doc_path = os.path.join(DOCS_CACHE_DIR, f"{core_name}.md")
    if os.path.exists(doc_path):
        return doc_path
    return None


def verify_core(core_name, json_path, doc_path):
    issues = []

    try:
        with open(json_path, 'r') as f:
            json_data = json.load(f)
    except Exception as e:
        return "FAIL", [f"Cannot parse JSON: {e}"]

    try:
        with open(doc_path, 'r') as f:
            doc_content = f.read()
    except Exception as e:
        return "FAIL", [f"Cannot read doc: {e}"]

    doc_buttons, has_left_stick, has_right_stick, left_x_label, left_y_label, right_x_label, right_y_label = parse_joypad_section(doc_content)

    if not doc_buttons and not has_left_stick and not has_right_stick:
        if 'retropad' not in doc_content.lower() and 'joypad' not in doc_content.lower():
            if not json_data:
                return "PASS", []
            else:
                return "PASS", ["JSON has buttons but doc has no controller info"]
        else:
            issues.append("WARNING: Could not parse Joypad table from doc - manual review needed")
            for btn in json_data:
                if btn not in VALID_BUTTONS:
                    issues.append(f"Invalid button name in JSON: '{btn}'")
            if any('Invalid' in i for i in issues):
                return "FAIL", issues
            return "PASS", issues

    # Check each button in doc exists in JSON with correct label
    for btn, label in doc_buttons.items():
        if btn not in json_data:
            issues.append(f"MISSING button: '{btn}' (doc label: '{label}')")
        else:
            json_label = json_data[btn].get('label', '')
            if json_label != label:
                issues.append(f"WRONG label for '{btn}': JSON='{json_label}', doc='{label}'")

    # Check for invalid button names in JSON
    for btn in json_data:
        if btn not in VALID_BUTTONS:
            issues.append(f"Invalid button name in JSON: '{btn}'")

    # Check analog sticks
    json_has_lstick = any(k.startswith('lStick') for k in json_data)
    json_has_rstick = any(k.startswith('rStick') for k in json_data)

    if has_left_stick and not json_has_lstick:
        has_real_labels = (left_x_label and left_x_label not in ('X', 'Y', '-', 'None', '')) or \
                          (left_y_label and left_y_label not in ('X', 'Y', '-', 'None', ''))
        if has_real_labels:
            issues.append(f"CRITICAL: Doc has retro_left_stick.png with labels but JSON has NO lStick entries (doc: X='{left_x_label}', Y='{left_y_label}')")
        else:
            issues.append(f"INFO: Doc has retro_left_stick.png but only axis markers (X/Y), JSON has no lStick - may be intentional")

    if has_right_stick and not json_has_rstick:
        has_real_labels = (right_x_label and right_x_label not in ('X', 'Y', '-', 'None', '')) or \
                          (right_y_label and right_y_label not in ('X', 'Y', '-', 'None', ''))
        if has_real_labels:
            issues.append(f"CRITICAL: Doc has retro_right_stick.png with labels but JSON has NO rStick entries (doc: X='{right_x_label}', Y='{right_y_label}')")
        else:
            issues.append(f"INFO: Doc has retro_right_stick.png but only axis markers (X/Y), JSON has no rStick - may be intentional")

    if not has_left_stick and json_has_lstick:
        issues.append(f"INFO: JSON has lStick entries but doc has no retro_left_stick.png")

    if not has_right_stick and json_has_rstick:
        issues.append(f"INFO: JSON has rStick entries but doc has no retro_right_stick.png")

    # Check analog stick labels - only flag if doc has real labels (not bare X/Y)
    if has_left_stick and json_has_lstick:
        if left_x_label and left_x_label not in ('X', 'Y', '-', 'None', ''):
            json_lx = json_data.get('lStickLeft', {}).get('label', '')
            if json_lx and json_lx != left_x_label:
                issues.append(f"lStick X label mismatch: JSON='{json_lx}', doc='{left_x_label}'")
        if left_y_label and left_y_label not in ('X', 'Y', '-', 'None', ''):
            json_ly = json_data.get('lStickUp', {}).get('label', '')
            if json_ly and json_ly != left_y_label:
                issues.append(f"lStick Y label mismatch: JSON='{json_ly}', doc='{left_y_label}'")

    if has_right_stick and json_has_rstick:
        if right_x_label and right_x_label not in ('X', 'Y', '-', 'None', ''):
            json_rx = json_data.get('rStickLeft', {}).get('label', '')
            if json_rx and json_rx != right_x_label:
                issues.append(f"rStick X label mismatch: JSON='{json_rx}', doc='{right_x_label}'")
        if right_y_label and right_y_label not in ('Y', '-', 'None', ''):
            json_ry = json_data.get('rStickUp', {}).get('label', '')
            if json_ry and json_ry != right_y_label:
                issues.append(f"rStick Y label mismatch: JSON='{json_ry}', doc='{right_y_label}'")

    critical_issues = [i for i in issues if 'CRITICAL' in i or 'MISSING' in i or 'WRONG' in i or 'Invalid' in i]
    if critical_issues:
        return "FAIL", issues
    return "PASS", issues


def main():
    json_files = sorted(os.listdir(CORE_LABELS_DIR))
    json_files = [f for f in json_files if f.startswith('input_coreLabels_') and f.endswith('.json')]

    print(f"Found {len(json_files)} core label JSON files\n")

    results = {}

    for json_file in json_files:
        core_name = extract_core_name(json_file)
        json_path = os.path.join(CORE_LABELS_DIR, json_file)
        doc_path = find_doc_file(core_name)

        if not doc_path:
            results[core_name] = ("NO_DOC", ["No corresponding doc file found"])
            continue

        status, issues = verify_core(core_name, json_path, doc_path)
        results[core_name] = (status, issues)

    pass_count = 0
    fail_count = 0
    no_doc_count = 0

    print("=" * 80)
    print("CORE LABEL AUDIT REPORT")
    print("=" * 80)

    print("\n--- PASS ---\n")
    for core_name in sorted(results.keys()):
        status, issues = results[core_name]
        if status == "PASS":
            pass_count += 1
            if issues:
                print(f"  {core_name}: ({'; '.join(issues)})")
            else:
                print(f"  {core_name}")

    print("\n--- FAIL ---\n")
    for core_name in sorted(results.keys()):
        status, issues = results[core_name]
        if status == "FAIL":
            fail_count += 1
            print(f"  {core_name}:")
            for issue in issues:
                print(f"    - {issue}")

    print("\n--- NO DOC FILE ---\n")
    for core_name in sorted(results.keys()):
        status, issues = results[core_name]
        if status == "NO_DOC":
            no_doc_count += 1
            print(f"  {core_name}")

    print("\n" + "=" * 80)
    total = pass_count + fail_count + no_doc_count
    print(f"SUMMARY: {pass_count} passed, {fail_count} failed, {no_doc_count} no doc out of {len(json_files)} total")
    print("=" * 80)

    # Categorize failures
    wrong_label_cores = []
    missing_button_cores = []
    critical_stick_cores = []
    invalid_button_cores = []

    for core_name in sorted(results.keys()):
        status, issues = results[core_name]
        if status != "FAIL":
            continue
        for issue in issues:
            if issue.startswith('WRONG label'):
                wrong_label_cores.append(core_name)
                break
        for issue in issues:
            if issue.startswith('MISSING button'):
                missing_button_cores.append(core_name)
                break
        for issue in issues:
            if issue.startswith('CRITICAL'):
                critical_stick_cores.append(core_name)
                break
        for issue in issues:
            if issue.startswith('Invalid button'):
                invalid_button_cores.append(core_name)
                break

    print("\n--- FAILURE CATEGORIES ---\n")
    print(f"  WRONG labels (button has different label than doc): {len(wrong_label_cores)}")
    print(f"    {', '.join(sorted(wrong_label_cores))}")
    print(f"\n  MISSING buttons (doc has button that JSON lacks): {len(missing_button_cores)}")
    print(f"    {', '.join(sorted(missing_button_cores))}")
    print(f"\n  CRITICAL analog stick (doc has stick, JSON doesn't): {len(critical_stick_cores)}")
    print(f"    {', '.join(sorted(critical_stick_cores))}")
    print(f"\n  Invalid button names in JSON: {len(invalid_button_cores)}")
    print(f"    {', '.join(sorted(invalid_button_cores))}")
    print("=" * 80)


if __name__ == "__main__":
    main()
