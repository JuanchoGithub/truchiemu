import re
import os
import shutil

def organize_pngs():
    mapping_file = 'system_png_mapping.md'
    source_dir = 'TruchieEmu/Resources/retroarch/dot-art/png'
    target_dir = 'TruchieEmu/Resources/retroarch/dot-art/systems'

    if not os.path.exists(mapping_file):
        print(f"Error: {mapping_file} not found")
        return

    if not os.path.exists(source_dir):
        print(f"Error: {source_dir} not found")
        return

    # Create target directory if it doesn't exist
    os.makedirs(target_dir, exist_ok=True)

    with open(mapping_file, 'r') as f:
        lines = f.readlines()

    count = 0
    for line in lines:
        # Match the table rows: | id | name | png |
        match = re.match(r'\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|', line)
        if match:
            sys_id = match.group(1).strip()
            sys_name = match.group(2).strip()
            png_filename = match.group(3).strip()

            if png_filename != "NOT FOUND":
                source_path = os.path.join(source_dir, png_filename)
                target_path = os.path.join(target_dir, f"{sys_id}.png")

                if os.path.exists(source_path):
                    shutil.copy2(source_path, target_path)
                    print(f"Copied: {png_filename} -> {sys_id}.png")
                    count += 1
                else:
                    print(f"Warning: Source file {source_path} not found")
            else:
                print(f"Skipping {sys_id}: NOT FOUND")

    print(f"Successfully organized {count} files into {target_dir}")

if __name__ == "__main__":
    organize_pngs()