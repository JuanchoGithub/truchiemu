I have completed the exhaustive mapping of every file in the project based on the proposed "Feature-Driven Architecture."

### 📂 Exhaustive File Mapping

#### 🏗️ Core
| Current Path | New Path |
| :--- | :--- |
| `TruchieEmu/Engine/libretro.h` | `TruchieEmu/Core/Engine/libretro.h` |
| `TruchieEmu/Engine/LibretroBridge.h` | `TruchieEmu/Core/Engine/LibretroBridge.h` |
| `TruchieEmu/Engine/LibretroBridge.mm` | `TruchieEmu/Core/Engine/LibretroBridge.mm` |
| `TruchieEmu/Engine/LibretroBridgeImpl.h` | `TruchieEmu/Core/Engine/LibretroBridgeImpl.h` |
| `TruchieEmu/Engine/LibretroBridgeImpl.mm` | `TruchieEmu/Core/Engine/LibretroBridgeImpl.mm` |
| `TruchieEmu/Engine/LibretroBridgeSwift.swift` | `TruchieEmu/Core/Engine/LibretroBridgeSwift.swift` |
| `TruchieEmu/Engine/LibretroCallbacks.h` | `TruchieEmu/Core/Engine/LibretroCallbacks.h` |
| `TruchieEmu/Engine/LibretroCallbacks.mm` | `TruchieEmu/Core/Engine/LibretroCallbacks.mm` |
| `TruchieEmu/Engine/LibretroGlobals.h` | `TruchieEmu/Core/Engine/LibretroGlobals.h` |
| `TruchieEmu/Engine/LibretroGlobals.mm` | `TruchieEmu/Core/Engine/LibretroGlobals.mm` |
| `TruchieEmu/Engine/TruchieEmu-Bridging-Header.h` | `TruchieEmu/Core/Engine/TruchieEmu-Bridging-Header.h` |
| `TruchieEmu/Engine/AudioRingBuffer.hpp` | `TruchieEmu/Core/Engine/AudioRingBuffer.hpp` |
| `TruchieEmu/Engine/Runners/BaseRunner.swift` | `TruchieEmu/Core/Engine/Runners/BaseRunner.swift` |
| `TruchieEmu/Engine/Runners/DOSRunner.swift` | `TruchieEmu/Core/Engine/Runners/DOSRunner.swift` |
| `TruchieEmu/Engine/Runners/N64Runner.swift` | `TruchieEmu/Core/Engine/Runners/N64Runner.swift` |
| `TruchieEmu/Engine/Runners/NESRunner.swift` | `TruchieEmu/Core/Engine/Runners/NESRunner.swift` |
| `TruchieEmu/Engine/Runners/SNESRunner.swift` | `TruchieEmu/Core/Engine/Runners/SNESRunner.swift` |
| `TruchieEmu/Engine/Runners/ScummVMRunner.swift` | `TruchieEmu/Core/Engine/Runners/ScummVMRunner.swift` |
| `TruchieEmu/Shaders/8bGameBoy.metal` | `TruchieEmu/Core/Shaders/8bGameBoy.metal` |
| `TruchieEmu/Shaders/CRTFilter.metal` | `TruchieEmu/Core/Shaders/CRTFilter.metal` |
| `TruchieEmu/Shaders/DotMatrixLCD.metal` | `TruchieEmu/Core/Shaders/DotMatrixLCD.metal` |
| `TruchieEmu/Shaders/LiteCRT.metal` | `TruchieEmu/Core/Shaders/LiteCRT.metal` |
| `TruchieEmu/Shaders/LottesCRT.metal` | `TruchieEmu/Core/Shaders/LottesCRT.metal` |
| `TruchieEmu/Shaders/Passthrough.metal` | `TruchieEmu/Core/Shaders/Passthrough.metal` |
| `TruchieEmu/Shaders/ScaleSmooth.metal` | `TruchieEmu/Core/Shaders/ScaleSmooth.metal` |
| `TruchieEmu/Shaders/SharpBilinear.metal` | `TruchieEmu/Core/Shaders/SharpBilinear.metal` |
| `TruchieEmu/Shaders/internal/ShaderCommon.h.metal` | `TruchieEmu/Core/Shaders/internal/ShaderCommon.h.metal` |
| `TruchieEmu/Shaders/internal/ShaderTypes.h.metal` | `TruchieEmu/Core/Shaders/internal/ShaderTypes.h.metal` |
| `TruchieEmu/Engine/LibretroCore.swift` | `TruchieEmu/Core/Models/LibretroCore.swift` |

#### 🚀 Features

**Library Feature**
| Current Path | New Path |
| :--- | :--- |
| `TruchieEmu/Services/ROMScanner.swift` | `TruchieEmu/Features/Library/Services/ROMScanner.swift` |
| `TruchieEmu/Services/ROMLibrary.swift` | `TruchieEmu/Features/Library/Services/ROMLibrary.swift` |
| `TruchieEmu/Services/CategoryManager.swift` | `TruchieEmu/Features/Library/Services/CategoryManager.swift` |
| `TruchieEmu/Services/LibraryAutomationCoordinator.swift` | `TruchieEmu/Features/Library/Services/LibraryAutomationCoordinator.swift` |
| `TruchieEmu/Views/Library/*` | `TruchieEmu/Features/Library/Views/*` |
| `TruchieEmu/Models/ROM.swift` | `TruchieEmu/Features/Library/Models/ROM.swift` |
| `TruchieEmu/Models/GameCategory.swift` | `TruchieEmu/Features/Library/Models/GameCategory.swift` |

**Player Feature**
| Current Path | New Path |
| :--- | :--- |
| `TruchieEmu/Services/GameLauncher.swift` | `TruchieEmu/Features/Player/Services/GameLauncher.swift` |
| `TruchieEmu/Services/RunningGamesTracker.swift` | `TruchieEmu/Features/Player/Services/RunningGamesTracker.swift` |
| `TruchieEmu/Services/CheatManagerService.swift` | `TruchieEmu/Features/Player/Services/CheatManagerService.swift` |
| `TruchieEmu/Services/ShaderManager.swift` | `TruchieEmu/Features/Player/Services/ShaderManager.swift` |
| `TruchieEmu/Services/ShaderMetadataLoader.swift` | `TruchieEmu/Features/Player/Services/ShaderMetadataLoader.swift` |
| `TruchieEmu/Services/Bezels/BezelManager.swift` | `TruchieEmu/Features/Player/Services/Bezels/BezelManager.swift` |
| `TruchieEmu/Services/Bezels/BezelStorageManager.swift` | `TruchieEmu/Features/Player/Services/Bezels/BezelStorageManager.swift` |
| `TruchieEmu/Views/Player/*` | `TruchieEmu/Features/Player/Views/*` |
| `TruchieEmu/Views/Bezels/*` | `TruchieEmu/Features/Player/Views/Bezels/*` |
| `TruchieEmu/Views/BoxArt/*` | `TruchieEmu/Features/Player/Views/BoxArt/*` |
| `TruchieEmu/Models/ShaderPreset.swift` | `TruchieEmu/Features/Player/Models/ShaderPreset.swift` |
| `TruchieEmu/Models/Achievement.swift` | `TruchieEmu/Features/Player/Models/Achievement.swift` |
| `TruchieEmu/Models/Cheat.swift` | `TruchieEmu/Features/Player/Models/Cheat.swift` |

**MAME Feature**
| Current Path | New Path |
| :--- | :--- |
| `TruchieEmu/Services/MAMEUnifiedService.swift` | `TruchieEmu/Features/MAME/Services/MAMEUnifiedService.swift` |
| `TruchieEmu/Services/MAMEImportService.swift` | `TruchieEmu/Features/MAME/Services/MAMEImportService.swift` |
| `TruchieEmu/Services/MAMEVerificationService.swift` | `TruchieEmu/Features/MAME/Services/MAMEVerificationService.swift` |
| `TruchieEmu/Services/MAMEDependencyService.swift` | `TruchieEmu/Features/MAME/Services/MAMEDependencyService.swift` |
| `TruchieEmu/Services/MAMEModels.swift` | `TruchieEmu/Features/MAME/Models/MAMEModels.swift` |
| `TruchieEmu/Services/MAMERomEntry.swift` | `TruchieEmu/Features/MAME/Models/MAMERomEntry.swift` |
| `TruchieEmu/Services/MAMEVerificationRecord.swift` | `TruchieEmu/Features/MAME/Models/MAMEVerificationRecord.swift` |
| `TruchieEmu/Views/MAME/*` | `TruchieEmu/Features/MAME/Views/*` |

**Settings Feature**
| Current Path | New Path |
| :--- | :--- |
| `TruchieEmu/Views/Settings/*` | `TruchieEmu/Features/Settings/Views/*` |
| `TruchieEmu/Services/CoreOptionsManager.swift` | `TruchieEmu/Features/Settings/Services/CoreOptionsManager.swift` |
| `TruchieEmu/Services/ControllerService.swift` | `TruchieEmu/Features/Settings/Services/ControllerService.swift` |

#### 🛠️ Shared (Infrastructure & Common)
| Current Path | New Path |
| :--- | :--- |
| `TruchieEmu/Services/Database/*` | `TruchieEmu/Shared/Infrastructure/Database/*` |
| `TruchieEmu/Services/Persistence/*` | `TruchieEmu/Shared/Infrastructure/Persistence/*` |
| `TruchieEmu/Services/LoggerService.swift` | `TruchieEmu/Shared/Services/LoggerService.swift` |
| `TruchieEmu/Services/LogManager.swift` | `TruchieEmu/Shared/Services/LogManager.swift` |
| `TruchieEmu/Services/ImageCache.swift` | `TruchieEmu/Shared/Services/ImageCache.swift` |
| `TruchieEmu/Services/ResourceCacheInterceptor.swift` | `TruchieEmu/Shared/Services/ResourceCacheInterceptor.swift` |
| `TruchieEmu/Models/SystemInfo.swift` | `TruchieEmu/Shared/Models/SystemInfo.swift` |
| `TruchieEmu/Models/SwiftDataModels.swift` | `TruchieEmu/Shared/Models/SwiftDataModels.swift` |
| `TruchieEmu/Design/DesignSystem.swift` | `TruchieEmu/Shared/UI/DesignSystem.swift` |
| `TruchieEmu/Extensions/*` | `TruchieEmu/Shared/Extensions/*` |
| `TruchieEmu/Utilities/*` | `TruchieEmu/Shared/Utilities/*` |

#### 📦 Resources
| Current Path | New Path |
| :--- | :--- |
| `Asset.xcassets/*` | `TruchieEmu/Resources/Assets.xcassets/*` |
| `TruchieEmu/Resources/ControllerIcons/*` | `TruchieEmu/Resources/Assets.xcassets/ControllerIcons/*` |
| `TruchieEmu/Resources/SystemIcons/*` | `TruchieEmu/Resources/Assets.xcassets/SystemIcons/*` |
| `TruchieEmu/Resources/LibretroDats/*` | `TruchieEmu/Resources/Data/LibretroDats/*` |
| `TruchieEmu/Resources/mame_unified.json` | `TruchieEmu/Resources/Data/mame_unified.json` |
| `TruchieEmu/Resources/SystemDatabase.json` | `TruchieEmu/Resources/Data/SystemDatabase.json` |
| `TruchieEmu/Resources/Info.plist` | `TruchieEmu/Resources/Plist/Info.plist` |
| `TruchieEmu/Resources/TruchieEmu.entitlements` | `TruchieEmu/Resources/Plist/TruchieEmu.entitlements` |

---
To avoid a mess, I recommend we do this in four stages. After each stage, we should "Clean Build Folder" (Cmd+Shift+K) and run the app.

Stage 1: Infrastructure & Resources (Shared, Resources, Plists). Fix the Build Settings here so the app actually launches.

Stage 2: The Core (Engine, Runners, Shaders). This handles the heavy lifting and C++ integration.

Stage 3: Features - MAME & Library. These are relatively self-contained.

Stage 4: Features - Player & Settings. These are the most interconnected and should be done last.

