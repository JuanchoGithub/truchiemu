#!/bin/bash

# Project Name Variable
PROJECT_NAME="TruchieEmu"

echo "🚀 Starting Feature-Driven Reorganization..."

# Function to safely move files
safe_move() {
    local src=$1
    local dest=$2
    if [ -e "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        mv "$src" "$dest"
        echo "✅ Moved $src to $dest"
    else
        echo "⚠️  Skip: $src not found"
    fi
}

# ---------------------------------------------------------
echo "📂 Stage 1: Infrastructure, Shared, & Resources..."
# ---------------------------------------------------------

# Resources
safe_move "Asset.xcassets" "$PROJECT_NAME/Resources/Assets.xcassets"
safe_move "$PROJECT_NAME/Resources/ControllerIcons" "$PROJECT_NAME/Resources/Assets.xcassets/ControllerIcons"
safe_move "$PROJECT_NAME/Resources/SystemIcons" "$PROJECT_NAME/Resources/Assets.xcassets/SystemIcons"
safe_move "$PROJECT_NAME/Resources/LibretroDats" "$PROJECT_NAME/Resources/Data/LibretroDats"
safe_move "$PROJECT_NAME/Resources/mame_unified.json" "$PROJECT_NAME/Resources/Data/mame_unified.json"
safe_move "$PROJECT_NAME/Resources/SystemDatabase.json" "$PROJECT_NAME/Resources/Data/SystemDatabase.json"
safe_move "$PROJECT_NAME/Resources/Info.plist" "$PROJECT_NAME/Resources/Plist/Info.plist"
safe_move "$PROJECT_NAME/Resources/TruchieEmu.entitlements" "$PROJECT_NAME/Resources/Plist/TruchieEmu.entitlements"

# Shared Infrastructure
safe_move "$PROJECT_NAME/Services/Database" "$PROJECT_NAME/Shared/Infrastructure/Database"
safe_move "$PROJECT_NAME/Services/Persistence" "$PROJECT_NAME/Shared/Infrastructure/Persistence"
safe_move "$PROJECT_NAME/Services/LoggerService.swift" "$PROJECT_NAME/Shared/Services/LoggerService.swift"
safe_move "$PROJECT_NAME/Services/LogManager.swift" "$PROJECT_NAME/Shared/Services/LogManager.swift"
safe_move "$PROJECT_NAME/Services/ImageCache.swift" "$PROJECT_NAME/Shared/Services/ImageCache.swift"
safe_move "$PROJECT_NAME/Services/ResourceCacheInterceptor.swift" "$PROJECT_NAME/Shared/Services/ResourceCacheInterceptor.swift"
safe_move "$PROJECT_NAME/Models/SystemInfo.swift" "$PROJECT_NAME/Shared/Models/SystemInfo.swift"
safe_move "$PROJECT_NAME/Models/SwiftDataModels.swift" "$PROJECT_NAME/Shared/Models/SwiftDataModels.swift"
safe_move "$PROJECT_NAME/Design/DesignSystem.swift" "$PROJECT_NAME/Shared/UI/DesignSystem.swift"
safe_move "$PROJECT_NAME/Extensions" "$PROJECT_NAME/Shared/Extensions"
safe_move "$PROJECT_NAME/Utilities" "$PROJECT_NAME/Shared/Utilities"

# ---------------------------------------------------------
echo "📂 Stage 2: Core Engine & Shaders..."
# ---------------------------------------------------------

# Engine files
ENGINE_FILES=("libretro.h" "LibretroBridge.h" "LibretroBridge.mm" "LibretroBridgeImpl.h" "LibretroBridgeImpl.mm" "LibretroBridgeSwift.swift" "LibretroCallbacks.h" "LibretroCallbacks.mm" "LibretroGlobals.h" "LibretroGlobals.mm" "TruchieEmu-Bridging-Header.h" "AudioRingBuffer.hpp")

for file in "${ENGINE_FILES[@]}"; do
    safe_move "$PROJECT_NAME/Engine/$file" "$PROJECT_NAME/Core/Engine/$file"
done

safe_move "$PROJECT_NAME/Engine/Runners" "$PROJECT_NAME/Core/Engine/Runners"
safe_move "$PROJECT_NAME/Shaders" "$PROJECT_NAME/Core/Shaders"
safe_move "$PROJECT_NAME/Engine/LibretroCore.swift" "$PROJECT_NAME/Core/Models/LibretroCore.swift"

# ---------------------------------------------------------
echo "📂 Stage 3: Features - Library & MAME..."
# ---------------------------------------------------------

# Library
safe_move "$PROJECT_NAME/Services/ROMScanner.swift" "$PROJECT_NAME/Features/Library/Services/ROMScanner.swift"
safe_move "$PROJECT_NAME/Services/ROMLibrary.swift" "$PROJECT_NAME/Features/Library/Services/ROMLibrary.swift"
safe_move "$PROJECT_NAME/Services/CategoryManager.swift" "$PROJECT_NAME/Features/Library/Services/CategoryManager.swift"
safe_move "$PROJECT_NAME/Services/LibraryAutomationCoordinator.swift" "$PROJECT_NAME/Features/Library/Services/LibraryAutomationCoordinator.swift"
safe_move "$PROJECT_NAME/Views/Library" "$PROJECT_NAME/Features/Library/Views"
safe_move "$PROJECT_NAME/Models/ROM.swift" "$PROJECT_NAME/Features/Library/Models/ROM.swift"
safe_move "$PROJECT_NAME/Models/GameCategory.swift" "$PROJECT_NAME/Features/Library/Models/GameCategory.swift"

# MAME
safe_move "$PROJECT_NAME/Services/MAMEUnifiedService.swift" "$PROJECT_NAME/Features/MAME/Services/MAMEUnifiedService.swift"
safe_move "$PROJECT_NAME/Services/MAMEImportService.swift" "$PROJECT_NAME/Features/MAME/Services/MAMEImportService.swift"
safe_move "$PROJECT_NAME/Services/MAMEVerificationService.swift" "$PROJECT_NAME/Features/MAME/Services/MAMEVerificationService.swift"
safe_move "$PROJECT_NAME/Services/MAMEDependencyService.swift" "$PROJECT_NAME/Features/MAME/Services/MAMEDependencyService.swift"
safe_move "$PROJECT_NAME/Services/MAMEModels.swift" "$PROJECT_NAME/Features/MAME/Models/MAMEModels.swift"
safe_move "$PROJECT_NAME/Services/MAMERomEntry.swift" "$PROJECT_NAME/Features/MAME/Models/MAMERomEntry.swift"
safe_move "$PROJECT_NAME/Services/MAMEVerificationRecord.swift" "$PROJECT_NAME/Features/MAME/Models/MAMEVerificationRecord.swift"
safe_move "$PROJECT_NAME/Views/MAME" "$PROJECT_NAME/Features/MAME/Views"

# ---------------------------------------------------------
echo "📂 Stage 4: Features - Player & Settings..."
# ---------------------------------------------------------

# Player
safe_move "$PROJECT_NAME/Services/GameLauncher.swift" "$PROJECT_NAME/Features/Player/Services/GameLauncher.swift"
safe_move "$PROJECT_NAME/Services/RunningGamesTracker.swift" "$PROJECT_NAME/Features/Player/Services/RunningGamesTracker.swift"
safe_move "$PROJECT_NAME/Services/CheatManagerService.swift" "$PROJECT_NAME/Features/Player/Services/CheatManagerService.swift"
safe_move "$PROJECT_NAME/Services/ShaderManager.swift" "$PROJECT_NAME/Features/Player/Services/ShaderManager.swift"
safe_move "$PROJECT_NAME/Services/ShaderMetadataLoader.swift" "$PROJECT_NAME/Features/Player/Services/ShaderMetadataLoader.swift"
safe_move "$PROJECT_NAME/Services/Bezels" "$PROJECT_NAME/Features/Player/Services/Bezels"
safe_move "$PROJECT_NAME/Views/Player" "$PROJECT_NAME/Features/Player/Views"
safe_move "$PROJECT_NAME/Views/Bezels" "$PROJECT_NAME/Features/Player/Views/Bezels"
safe_move "$PROJECT_NAME/Views/BoxArt" "$PROJECT_NAME/Features/Player/Views/BoxArt"
safe_move "$PROJECT_NAME/Models/ShaderPreset.swift" "$PROJECT_NAME/Features/Player/Models/ShaderPreset.swift"
safe_move "$PROJECT_NAME/Models/Achievement.swift" "$PROJECT_NAME/Features/Player/Models/Achievement.swift"
safe_move "$PROJECT_NAME/Models/Cheat.swift" "$PROJECT_NAME/Features/Player/Models/Cheat.swift"

# Settings
safe_move "$PROJECT_NAME/Views/Settings" "$PROJECT_NAME/Features/Settings/Views"
safe_move "$PROJECT_NAME/Services/CoreOptionsManager.swift" "$PROJECT_NAME/Features/Settings/Services/CoreOptionsManager.swift"
safe_move "$PROJECT_NAME/Services/ControllerService.swift" "$PROJECT_NAME/Features/Settings/Services/ControllerService.swift"

# Cleanup empty directories
find "$PROJECT_NAME" -type d -empty -delete

echo "✨ Disk Reorganization Complete!"
echo "🛠️ NEXT STEPS IN XCODE:"
echo "1. Delete missing (red) files from Xcode Project Navigator."
echo "2. Drag the new folders (Core, Features, Shared, Resources) into Xcode."
echo "3. Update Build Settings for: Bridging Header, Info.plist, and Entitlements."