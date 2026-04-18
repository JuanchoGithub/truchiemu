# Plan: Core Options View Implementation (V1 & V2 Support)

## Objective
Implement a functional Core Options View that allows users to view, load, and modify core configuration options (both V1 and V2) without interfering with the actual execution of the emulator cores.

## Technical Requirements

### 1. Environment Callback Implementation
The frontend must handle specific Libretro environment constants to capture options "on the fly":
- **`RETRO_ENVIRONMENT_GET_VARIABLE` (15)**: Used to retrieve the current value.
- **`RETRO_ENVIRONMENT_SET_VARIABLES` (16)**: Used by V1 cores to deliver the full list of options via an array of `retro_variable` structs.
- **`RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2` (67)**: Used by modern cores to deliver structured options via `retro_core_options_v2`.
- **`RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE` (17)**: Notifies the host if something changed.

### 2. Parsing Logic

#### V1 Parsing (Legacy)
When `RETRO_ENVIRONMENT_SET_VARIABLES` is received, parse the `retro_variable` array.
Each variable follows this string format:
`"Name; Option1|Option2|Option3"`
- **Name**: The human-readable description.
- **Delimiter**: `;` separates the name from the options.
- **Options**: Separated by `|`.

#### V2 Parsing (Modern)
When `RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2` is received, iterate through the `definitions` array.
Each definition contains:
- `key`: Internal identifier.
- `desc`: Human-readable description.
- `values`: An array of possible values and their labels.

### 3. Persistence (File Management)
- **Reading**: Before calling `retro_load_game`, look for a configuration file (e.g., `.cfg` or `.opt`) named after the game or core.
- **Injection**: When the core calls `RETRO_ENVIRONMENT_GET_VARIABLE`, the host must return the value stored in the local database/file.
- **Writing**: When a user modifies an option in the UI, save the new value to the configuration file.

## Implementation Steps

### 1. [Model] Update Data Structures
- Modify `CoreOption` to include a `version` property (to distinguish V1 from V2).
- Update `CoreOptionCategory` to support versioning if necessary.

### 2. [Manager] Enhance `CoreOptionsManager`
- Update the manager to handle and store multiple versions of options for the same core key.
- Ensure the manager correctly loads definitions from the JSON cache and applies user overrides from `.cfg` files.

### 3. [UI] Develop `CoreOptionsView`
- Update the existing `CoreOptionsView.swift` to:
    - Display version badges (e.g., "[V1]" or "[V2]") next to options/categories.
    - Implement a "Load Options" mechanism that pulls from the local JSON definitions.
    - Bind UI controls (like Pickers) to `CoreOptionsManager` for real-time updates.

### 4. [Verification] Testing & Persistence
- Verify that changing a value in the UI correctly updates the `CoreOptionsManager`.
- Confirm that changes are successfully persisted to the core's `.cfg` file.
- Ensure that the view correctly handles and displays both V1 and V2 options simultaneously if a core provides both.

## Verification Plan
- **Functional**: Verify that "Load Options" successfully populates the view from JSON.
- **Visual**: Confirm that V1 and V2 options are clearly distinguished by labels.
- **Persistence**: Change an option, restart the view (or simulate reload), and verify the value remains changed.