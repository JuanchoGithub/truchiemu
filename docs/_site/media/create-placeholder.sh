#!/bin/bash
# Create placeholder images for docs
# This script creates basic colored PNG placeholders

# Create a simple colored PNG using built-in tools
create_placer() {
  local width=$1
  local height=$2
  local color=$3
  local output=$4
  
  # Create a simple image using sips with a base image
  # We'll create a temporary image and resize it
  
  # Method: use built-in screenshot tools or create minimal PNG
  # Using a hack: create a tiny base64 PNG and scale it
  
  # Simple 1x1 pixel base64 PNG:
  # Base64 for 1x1 red pixel PNG
  case "$color" in
    "red")
      BASE64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErJggg=="
      ;;
    "blue")
      BASE64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAGDPRyhbQAAAABJRU5ErJggg=="
      ;;
    "green")
      BASE64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwACIQGAFHcpfQAAAABJRU5ErJggg=="
      ;;
    "purple")
      BASE64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+O9RBgACQAG/SfH9YQAAAABJRU5ErJggg=="
      ;;
    *)
      BASE64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErJggg=="
      ;;
  esac
  
  echo "$BASE64" | base64 -d > "/tmp/placeholder.png"
  
  # Resize using sips
  sips -z "$height" "$width" "/tmp/placeholder.png" --out "$output" 2>/dev/null || cp "/tmp/placeholder.png" "$output"
  
  echo "Created placeholder: $output (${width}x${height}, $color)"
}

# Create media directory if it doesn't exist
mkdir -p "$(dirname "$0")"

echo "Creating placeholder images for TruchiEmu docs..."

# Tier 1: Main images
create_placer 1920 1080 blue "$(dirname "$0")/hero-banner.jpg"
create_placer 512 512 blue "$(dirname "$0")/logo-icon.png"
create_placer 1600 1000 purple "$(dirname "$0")/app-window.png"

# Tier 2: Screenshots
create_placer 1400 900 green "$(dirname "$0")/screenshots/library-grid.png"
create_placer 1400 900 green "$(dirname "$0")/screenshots/game-detail.png"
create_placer 1200 800 green "$(dirname "$0")/screenshots/shader-picker.png"
create_placer 1200 800 green "$(dirname "$0")/screenshots/achievements-list.png"
create_placer 1200 800 green "$(dirname "$0")/screenshots/save-state-browser.png"
create_placer 1200 800 green "$(dirname "$0")/screenshots/controller-mapping.png"
create_placer 1200 800 green "$(dirname "$0")/screenshots/core-settings.png"
create_placer 1200 800 green "$(dirname "$0")/screenshots/settings-main.png"
create_placer 1200 800 green "$(dirname "$0")/screenshots/mame-verify.png"

# Tier 3: Shader comparisons
create_placer 1600 900 red "$(dirname "$0")/features/crt-lottes-before.png"
create_placer 1600 900 purple "$(dirname "$0")/features/crt-lottes-after.png"
create_placer 1600 900 red "$(dirname "$0")/features/lcd-dmg-before.png"
create_placer 1600 900 purple "$(dirname "$0")/features/lcd-dmg-after.png"
create_placer 1600 900 red "$(dirname "$0")/features/sharp-bilinear.png"
create_placer 1600 900 purple "$(dirname "$0")/features/passthrough.png"
create_placer 1600 900 purple "$(dirname "$0")/features/scale-smooth.png"
create_placer 1600 900 purple "$(dirname "$0")/features/lite-crt.png"
create_placer 1600 900 purple "$(dirname "$0")/features/crt-multipass.png"
create_placer 1600 900 purple "$(dirname "$0")/features/gba-shader.png"
create_placer 1600 900 purple "$(dirname "$0")/features/gbc-shader.png"
create_placer 1600 900 purple "$(dirname "$0")/features/dot-matrix.png"

# Tier 4: System banners
create_placer 1200 400 blue "$(dirname "$0")/systems/nes-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/snes-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/n64-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/gba-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/genesis-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/mame-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/dosbox-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/scummvm-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/psp-banner.png"
create_placer 1200 400 blue "$(dirname "$0")/systems/ps1-banner.png"

echo "Done! Created all placeholder images."
echo "You can replace these with real images later using the same filenames."
