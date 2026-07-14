# Release Process

This document describes the exact steps to cut a new TruchiEmu release. The two channels are:

- **Nightly preview builds** — fast in-flight test builds of uncommitted work, single `TruchiEmu-nightly.zip` asset on the `nightly` pre-release tag. Documented in the next section.
- **Tagged stable releases** — version-bump + changelog + git tag + push + `gh release create v<version>`. Documented in "Tagged stable releases" below.

---

## Nightly preview builds

There is a **`nightly` GitHub pre-release** tag at `https://github.com/<owner>/<repo>/releases/tag/nightly` used to ship in-testing preview builds of uncommitted work. Persisted there as a single asset: `TruchiEmu-nightly.zip`.

**Use this channel when the user asks to:**
- "build the current state and upload it for testing"
- "upload to the nightly"
- "let other Macs download it"
- "ship a test build" without bumping versions / cutting a tagged release / merging anything

**Do NOT use this channel for:**
- Tagged stable releases — see "Tagged stable releases" below.
- Merging the working tree — nightly preview builds are explicitly not on `main`. The user keeps the changes uncommitted deliberately while testing.

### Workflow

1. **Build Release config:**
   ```bash
   xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Release -destination 'platform=macOS,arch=arm64' build
   ```
   The build output is at `~/Library/Developer/Xcode/DerivedData/TruchiEmu-<hash>/Build/Products/Release/TruchiEmu.app`.

2. **Zip the .app:**
   ```bash
   ditto -c -k --sequesterRsrc --keepParent \
     "<DerivedData path>/Build/Products/Release/TruchiEmu.app" \
     "/tmp/TruchiEmu-nightly.zip"
   ```

3. **Upload, clobbering the existing asset:**
   ```bash
   gh release upload nightly /tmp/TruchiEmu-nightly.zip --clobber
   ```

4. **Update release notes** describing what's in this preview:
   - Write the markdown to `/tmp/nightly_notes.md` (or any temp path).
   - `gh release edit nightly --notes-file /tmp/nightly_notes.md`
   - Date the notes at the top so the user can tell which version of "nightly" is live.

5. **Verify:**
   - `gh release view nightly` — confirm `assets: ["TruchiEmu-nightly.zip"]` plus the new publish timestamp.
   - The release URL is `https://github.com/<owner>/<repo>/releases/tag/nightly`. Share it back to the user.

### Conventions

- Never bump the app Version/Build number for a nightly — leave `project.yml`, `Info.plist`, `docs/_config.yml`, and the changelog HTML files untouched.
- Never `git add`, `git commit`, `git tag`, or `git push` for a nightly-only upload — the working tree stays dirty between tests.
- Never merge anything to `main` via the nightly channel. Nightly is for download-only preview deltas of in-flight work.
- If the user later asks to "make this a real release," switch to the tagged-release workflow below and follow version-bump + changelog + commit + tag + push + `gh release create v<version>` in full.

---

## Tagged stable releases

Follow the steps below in order when asked to "release", "cut a release", or "bump version".

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- `xcodegen` installed (`brew install xcodegen`)
- Write access to the repository
- Git working tree is clean (no uncommitted changes)

## Step-by-step

### Step 0 — Get changes since last release

```bash
# Find the latest tag
git describe --tags --abbrev=0

# Get log since last tag
git log --oneline --format="%h %s" <last-tag>..HEAD

# Get full log with bodies for changelog writing
git log <last-tag>..HEAD --oneline --format="%h %ai %s%n%b"
```

### Step 1 — Bump version numbers

Edit **4 files** with the new version (e.g., `1.6.0`) and incremented build number (e.g., `18`):

| File | Lines to change |
|---|---|
| `project.yml` | `CFBundleShortVersionString` (~line 40), `CFBundleVersion` (~line 39) |
| `TruchiEmu/Resources/Info.plist` | `CFBundleShortVersionString` (~line 20), `CFBundleVersion` (~line 22) |
| `TruchiEmu/Core/XPC/Service/Info.plist` | `CFBundleShortVersionString` (~line 18), `CFBundleVersion` (~line 20) |
| `docs/_config.yml` | `version:` (~line 41) |

Version pattern: `"X.Y.Z"` (marketing version). Build pattern: `'N'` (incrementing integer).

### Step 2 — Regenerate Xcode project

```bash
xcodegen generate
```

This syncs `project.yml` changes into `TruchiEmu.xcodeproj`.

### Step 3 — Create changelog HTML files

Create 3 localized changelog files following the exact HTML template from the previous release:

| Language | Path |
|---|---|
| English | `docs/changelog/v<version>.html` |
| Spanish | `docs/es/changelog/v<version>.html` |
| Portuguese | `docs/pt/changelog/v<version>.html` |

**Template structure** (copy from previous version file):

```html
---
layout: default
title: v<version> - TruchiEmu Documentation

---

<div class="feature-docs">
    <nav class="breadcrumbs">
        <a href="{{ '/changelog.html' | relative_url }}">Changelog</a>
        <span class="separator">/</span>
        <span class="current">v<version></span>
    </nav>

    <div class="release-header">
        <h1>v<version></h1>
        <div class="release-meta">
            <span class="release-date"><Month> <Day>, <Year></span>
        </div>
    </div>

    <div class="release-description">
        <p>One-line summary of the release.</p>
    </div>

    <section id="highlights">
        <h2>Highlights</h2>
        <ul class="feature-list">
            <li><strong>Feature Name:</strong> Description</li>
        </ul>
    </section>

    <section id="details">
        <h2>Detailed Changes</h2>
        <ul>
            <li>Bullet points from git log</li>
        </ul>
    </section>

    <nav class="release-nav">
        <a href="{{ '/changelog/v<previous-version>.html' | relative_url }}" class="release-prev">&larr; v<previous-version></a>
        <a href="{{ '/changelog.html' | relative_url }}" class="release-all">All Releases</a>
    </nav>
</div>
```

For ES localization:
- `<a href="{{ '/es/changelog.html' | relative_url }}">` for breadcrumb and "All releases" link
- `<a href="{{ '/es/changelog/v<prev>.html' | relative_url }}"` for prev link
- `<a href="{{ '/es/changelog.html' | relative_url }}"` for all releases
- title: `v<version> - Documentación de TruchiEmu`
- "Registro de cambios" for breadcrumb
- "Destacados" for highlights section
- "Cambios detallados" for details section
- "Todas las versiones" for all releases link
- Date format: `<Day> de <Month> de <Year>` (e.g., "4 de julio de 2026")

For PT localization:
- `<a href="{{ '/pt/changelog.html' | relative_url }}">` for breadcrumb and "All releases" link
- `<a href="{{ '/pt/changelog/v<prev>.html' | relative_url }}"` for prev link
- `<a href="{{ '/pt/changelog.html' | relative_url }}"` for all releases
- title: `v<version> - Documentação do TruchiEmu`
- "Registro de mudanças" for breadcrumb
- "Destaques" for highlights section
- "Mudanças detalhadas" for details section
- "Todas as versões" for all releases link
- Date format: `<Day> de <Month> de <Year>` (e.g., "4 de julho de 2026")

### Step 4 — Update changelog index pages

Edit the 3 changelog index pages to add the new release at the **top** (newest first):

| Language | Path |
|---|---|
| English | `docs/changelog.html` |
| Spanish | `docs/es/changelog.html` |
| Portuguese | `docs/pt/changelog.html` |

Insert a new `.release-entry` div right after the `.changelog-timeline` opening div (before the previous top entry):

```html
<div class="release-entry">
    <div class="release-version">
        <a href="{{ '/changelog/v<version>.html' | relative_url }}">v<version></a>
    </div>
    <div class="release-date"><Month> <Day>, <Year></div>
    <div class="release-summary">
        One-line summary of changes.
    </div>
</div>
```

For ES/PT, adjust the href prefix (`/es/changelog/`, `/pt/changelog/`) and use localized date formats.

### Step 5 — Commit

```bash
git add -A
git commit -m "chore: bump version to <version>"
```

### Step 6 — Build Release

```bash
xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Release build
```

Verify build succeeds (exit code 0). Note the path of the built `.app` from the last few lines of output (look for `TruchiEmu.app` under `Build/Products/Release/`).

### Step 7 — Package the app

Zip the built `.app` bundle for distribution. Use the build output path from Step 6:

```bash
# Replace <build-dir> with the actual DerivedData path from Step 6 output
ditto -c -k --sequesterRsrc --keepParent \
  "<build-dir>/Build/Products/Release/TruchiEmu.app" \
  "/tmp/TruchiEmu-v<version>.zip"
```

### Step 8 — Tag

```bash
git tag v<version>
```

### Step 9 — Push

```bash
git push origin main --tags
```

### Step 10 — Create GitHub Release with app asset

Create a temporary changelog notes file for the GitHub release (English only). Use the Highlights and Description sections from the English changelog. Then create the release and upload the zip in a single command:

```bash
gh release create v<version> \
  --title "v<version>" \
  --notes-file <path-to-notes-file> \
  "/tmp/TruchiEmu-v<version>.zip"
```

The GitHub release title and notes should match `v<version>` with the English changelog content. The `.zip` is uploaded as a release asset so users can download the app directly from the release page.

## Version scheme

- **Marketing version** (`CFBundleShortVersionString`): `major.minor.patch` — semantic versioning
- **Build number** (`CFBundleVersion`): Simple integer, incremented by 1 each release
- **Tag format**: `v<marketing-version>` (e.g., `v1.6.0`)

## Key file locations

| Asset | Path |
|---|---|
| XcodeGen project spec | `project.yml` |
| Main app Info.plist | `TruchiEmu/Resources/Info.plist` |
| XPC service Info.plist | `TruchiEmu/Core/XPC/Service/Info.plist` |
| Docs site config | `docs/_config.yml` |
| EN changelog files | `docs/changelog/` |
| ES changelog files | `docs/es/changelog/` |
| PT changelog files | `docs/pt/changelog/` |
| EN changelog index | `docs/changelog.html` |
| ES changelog index | `docs/es/changelog.html` |
| PT changelog index | `docs/pt/changelog.html` |
