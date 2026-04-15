import json
import os
import re

def match_systems():
    json_path = 'TruchieEmu/Resources/SystemDatabase.json'
    png_dir = 'TruchieEmu/Resources/retroarch/dot-art/png'
    output_path = 'system_png_mapping.md'

    if not os.path.exists(json_path):
        print(f"Error: {json_path} not found")
        return

    if not os.path.exists(png_dir):
        print(f"Error: {png_dir} not found")
        return

    with open(json_path, 'r') as f:
        systems = json.load(f)

    png_files = [f for f in os.listdir(png_dir) if f.endswith('.png') and "-content" not in f]
    png_files.sort()

    mappings = []

    for system in systems:
        sys_id = system.get('id', '').lower()
        sys_name = system.get('name', '').lower()
        
        if not sys_id:
            continue

        best_match = None
        max_score = -1

        for png in png_files:
            png_lower = png.lower().replace('.png', '')
            score = 0
            
            # 1. Exact ID match
            if sys_id == png_lower:
                score += 1000
            
            # 2. Exact Name match
            elif sys_name == png_lower:
                score += 1000
            
            # 3. ID is a whole word in the filename
            elif re.search(rf'\b{re.escape(sys_id)}\b', png_lower):
                score += 500
            
            # 4. Name is a whole phrase in the filename
            elif sys_name in png_lower:
                score += 400
                # Specificity bonus: prefer closer length match to avoid "PlayStation" -> "PlayStation Portable"
                length_diff = abs(len(png_lower) - len(sys_name))
                score += (50 - length_diff) if length_diff < 50 else 0

            # 5. Partial name match (word by word)
            else:
                # Only use partial word matching if name is not too short to avoid false positives like "ii"
                if len(sys_name) > 3:
                    name_words = re.findall(r'\w+', sys_name)
                    stop_words = {'and', 'the', 'of', 'in', 'on', 'at', 'with', 'for', 'a', 'an'}
                    name_words = [w for w in name_words if w not in stop_words and len(w) > 1]
                    
                    if name_words:
                        match_count = 0
                        for word in name_words:
                            if re.search(rf'\b{re.escape(word)}\b', png_lower):
                                match_count += 1
                        score += (match_count / len(name_words)) * 100

            if score > max_score and score > 0:
                max_score = score
                best_match = png

        if best_match:
            mappings.append({
                'id': sys_id,
                'name': system.get('name'),
                'png': best_match
            })
        else:
            mappings.append({
                'id': sys_id,
                'name': system.get('name'),
                'png': 'NOT FOUND'
            })

    # Write to Markdown
    with open(output_path, 'w') as f:
        f.write("# System ID to PNG Mapping\n\n")
        f.write("| System ID | System Name | PNG Filename |\n")
        f.write("| --- | --- | --- |\n")
        for m in mappings:
            f.write(f"| {m['id']} | {m['name']} | {m['png']} |\n")

    print(f"Successfully created {output_path}")

if __name__ == "__main__":
    match_systems()