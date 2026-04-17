# Plan: Optimize ROM Model Performance

## Objective
The goal is to improve the performance of the `ROM` model and the overall application (especially during library scrolling and scanning) by converting several expensive computed properties into stored properties. This will eliminate redundant calculations and file system access during UI rendering.

## Technical Analysis
Currently, `TruchieEmu/Models/ROM.swift` contains several computed properties that are accessed frequently by SwiftUI views. 

### Expensive Computations Identified:
1.  **`displayName`**: Performs string manipulation (`GameNameFormatter.stripTags`) and calls `MAMEUnifiedService.shared.lookup`, which is a dictionary/service lookup. This is called every time a list cell is rendered.
2.  **`boxArtLocalPath` & `infoLocalPath`**: Perform file system operations (`FileManager.default.fileExists`) and path manipulations. File system I/O on the main thread during scrolling is a major cause of "jank".
3.  **`fileExtension`**: Repeatedly calculates the lowercase extension.
4.  **`needsAutomaticIdentification` & `needsAutomaticBoxArt`**: Perform string trimming and boolean logic repeatedly.
5.  **`shortNameForMAME` & `filenameWithoutExtension`**: Perform multiple string replacements on every access.

By moving these to stored properties, we calculate them once (during scan or identification) and read them as simple values during UI updates.

## Proposed Changes

### 1. Refactor `TruchieEmu/Models/ROM.swift`
Convert the following from computed properties to stored properties:
- `displayName: String`
- `fileExtension: String`
- `needsAutomaticIdentification: Bool`
- `needsAutomaticBoxArt: Bool`
- `boxArtLocalPath: URL`
- `infoLocalPath: URL`
- `shortNameForMAME: String`
- `filenameWithoutExtension: String`

**Synchronization Strategy:**
Since these properties depend on other fields (like `customName`, `metadata`, or `path`), we must ensure they are updated when their dependencies change. 
- I will implement a `refreshDerivedFields()` method in `ROM` (or ensure that any update logic in services calls a refresh) to maintain consistency.

### 2. Update `TruchieEmu/Services/ROMScanner.swift`
The scanner is the primary producer of `ROM` objects.
- **Update `scan(folder:...)` and `scan(urls:...)`**:
    - Calculate all new stored properties immediately after a `ROM` instance is created and its basic identity (system, name, path) is known.
    - This calculation will happen inside the concurrent `TaskGroup` to avoid blocking the main thread.

### 3. Update Automation & Sync Services
We must ensure that when a ROM is "enhanced" (metadata added, name changed, etc.), the derived properties are updated.
- **`LibraryAutomationCoordinator.swift`**: Update to refresh derived fields after identification or art fetching.
- **`MetadataSyncCoordinator.swift`**: Update to refresh derived fields after metadata sync.
- **`ROMLibrary.swift`**: Ensure that manual modifications to a `ROM` (e.g., setting a `customName`) trigger a refresh of `displayName`.

## Implementation Steps

1.  **[Model]** Modify `ROM.swift`:
    - Add stored properties.
    - Update `init`.
    - Add/update logic to keep derived fields in sync.
2.  **[Scanner]** Modify `ROMScanner.swift`:
    - Populate all new fields during the scan process.
3.  **[Services]** Update all services that modify `ROM` state:
    - `LibraryAutomationCoordinator.swift`
    - `MetadataSyncCoordinator.swift`
    - `ROMLibrary.swift`
    - `MAMEImportService.swift` (if applicable)
4.  **[Verification]**
    - Check for compiler errors.
    - Verify functionality (names, paths, and identification status).
    - Performance check (scrolling smoothness).

## Verification Plan
- **Functional**: Ensure `customName` still works and correctly overrides the `displayName`.
- **Consistency**: Ensure `boxArtLocalPath` correctly points to the right file after a scan.
- **Performance**: Verify that scrolling through a large list of ROMs is smooth and doesn't trigger heavy CPU/IO spikes.