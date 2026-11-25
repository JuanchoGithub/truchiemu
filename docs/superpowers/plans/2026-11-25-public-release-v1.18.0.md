# TruchiEmu v1.18.0 Public Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish TruchiEmu v1.18.0 as a public GitHub release with a Release build archive and localized release notes.

**Architecture:** Follow the tagged stable release workflow in `RELEASE_PROCESS.md`. Update the four authoritative version sources, regenerate the Xcode project, add localized changelog pages, build and package the app, then commit, tag, push, and publish the GitHub release.

**Tech Stack:** XcodeGen, Xcode/xcodebuild, Git, GitHub CLI, Jekyll

**Spec:** `RELEASE_PROCESS.md`, especially "Tagged stable releases"

## Global Constraints

- The marketing version is `1.18.0`.
- The build number is `46`.
- The release date is November 25, 2026.
- The release is public. It is not a draft and not a pre-release.
- The release asset must be named `TruchiEmu-v1.18.0.zip`.
- The GitHub release title and notes must match the English changelog.
- The release archive must contain a Release configuration build.
- Do not modify the `nightly` release.

## Review Focus

- All four version sources and the built bundle must report version `1.18.0` and build `46`.
- The English, Spanish, and Portuguese changelog pages must use correct language-specific links and dates.
- The release notes must represent the changes since `v1.17.2` without unsupported claims.
- The tag must point to the release commit, and the remote branch and tag must contain that commit.
- The GitHub release must be public and must contain exactly the expected application archive.

---

### Task 1: Update the release version

**Files:**
- Modify: `project.yml`
- Modify: `TruchiEmu/Resources/Info.plist`
- Modify: `TruchiEmu/Core/XPC/Service/Info.plist`
- Modify: `docs/_config.yml`

**Interfaces:**
- Consumes: Semantic versioning and the build-number rule in `RELEASE_PROCESS.md`.
- Produces: A consistent `1.18.0` marketing version and build number `46`.

- [x] **Step 1: Set the version in all four authoritative files**

Use `1.18.0` for `CFBundleShortVersionString` and the documentation version. Use `46` for `CFBundleVersion`.

- [x] **Step 2: Verify the version values**

Run:

```bash
rg "1\.18\.0|46" project.yml TruchiEmu/Resources/Info.plist TruchiEmu/Core/XPC/Service/Info.plist docs/_config.yml
```

Expected: The app and XPC versions are `1.18.0`, both build numbers are `46`, and the documentation version is `1.18.0`.

### Task 2: Regenerate the Xcode project

**Files:**
- Modify: `TruchiEmu.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: The updated `project.yml`.
- Produces: An Xcode project that includes the current source tree and version settings.

- [x] **Step 1: Regenerate the project**

Run:

```bash
xcodegen generate
```

Expected: XcodeGen exits with code 0.

- [x] **Step 2: Check the generated project**

Run:

```bash
git diff --check && git status --short
```

Expected: No whitespace errors. The generated project and the planned release files are the only changes.

### Task 3: Correct the RetroAchievements CDI hash order

**Files:**
- Modify: `TruchiEmu/Services/RetroAchievementsService.swift`

**Interfaces:**
- Consumes: `pending.sort(by:)` before the continuous hash task group starts.
- Produces: Non-CDI files before CDI files in the hash queue.

- [ ] **Step 1: Correct the comparator**

Return `true` only when the first file is not a CDI file and the second file is a CDI file. This matches the adjacent comment and keeps the other hash workers busy until the exclusive CDI work starts.

- [ ] **Step 2: Verify the comparator and build**

Run:

```bash
rg -n -C 2 "pending.sort" TruchiEmu/Services/RetroAchievementsService.swift
xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Release -destination 'platform=macOS,arch=arm64' build
```

Expected: The comparator places non-CDI files first. The Release build exits with code 0.

### Task 4: Add the localized changelogs

**Files:**
- Create: `docs/changelog/v1.18.0.html`
- Create: `docs/es/changelog/v1.18.0.html`
- Create: `docs/pt/changelog/v1.18.0.html`
- Modify: `docs/changelog.html`
- Modify: `docs/es/changelog.html`
- Modify: `docs/pt/changelog.html`

**Interfaces:**
- Consumes: The commit history from `v1.17.2` through `HEAD` and the v1.17.2 page templates.
- Produces: Three localized release pages and three newest-first changelog indexes.

- [ ] **Step 1: Write the English release page**

Create `docs/changelog/v1.18.0.html` from the v1.17.2 template. Describe the library redesign, offline similar-game recommendations, manual game matching, RetroAchievements speed fix, box-art improvements, input fix, and performance work.

- [ ] **Step 2: Write the Spanish release page**

Create `docs/es/changelog/v1.18.0.html`. Use Spanish headings, `/es/` links, and the date `25 de noviembre de 2026`.

- [ ] **Step 3: Write the Portuguese release page**

Create `docs/pt/changelog/v1.18.0.html`. Use Portuguese headings, `/pt/` links, and the date `25 de novembro de 2026`.

- [ ] **Step 4: Update the three changelog indexes**

Insert the v1.18.0 entry directly after each `.changelog-timeline` opening element. Keep the newest release first.

- [ ] **Step 5: Verify the changelog structure**

Run:

```bash
rg -n "v1\.18\.0|25 de noviembre de 2026|November 25, 2026" docs/changelog/v1.18.0.html docs/es/changelog/v1.18.0.html docs/pt/changelog/v1.18.0.html docs/changelog.html docs/es/changelog.html docs/pt/changelog.html
```

Expected: Each release page and index contains v1.18.0. Each page contains the correct localized date.

### Task 5: Build and package the application

**Files:**
- Create outside the repository: `/private/var/folders/vn/1bmkz4j91zs7syr7czvm3v7c0000gn/T/opencode/TruchiEmu-v1.18.0.zip`

**Interfaces:**
- Consumes: The committed source and regenerated Xcode project.
- Produces: A public Release archive containing `TruchiEmu.app`.

- [ ] **Step 1: Build the Release configuration**

Run:

```bash
xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Release -destination 'platform=macOS,arch=arm64' build
```

Expected: The build exits with code 0 and produces `TruchiEmu.app` under `Build/Products/Release/`.

- [ ] **Step 2: Verify the built bundle version**

Run `defaults read` against the built app's `Info.plist`.

Expected: `CFBundleShortVersionString` is `1.18.0` and `CFBundleVersion` is `46`.

- [ ] **Step 3: Create the release archive**

Run `ditto -c -k --sequesterRsrc --keepParent` with the built app as input and `/private/var/folders/vn/1bmkz4j91zs7syr7czvm3v7c0000gn/T/opencode/TruchiEmu-v1.18.0.zip` as output.

Expected: The archive exists and contains the top-level `TruchiEmu.app` bundle.

### Task 6: Publish the public release

**Files:**
- Create outside the repository: `/private/var/folders/vn/1bmkz4j91zs7syr7czvm3v7c0000gn/T/opencode/TruchiEmu-v1.18.0-notes.md`

**Interfaces:**
- Consumes: The release commit, tag, archive, and English changelog content.
- Produces: A public GitHub release at tag `v1.18.0`.

- [ ] **Step 1: Commit the release files**

Run:

```bash
git add -A
git commit -m "chore: bump version to 1.18.0"
```

Expected: The commit includes the version update, generated project, plan, and localized changelogs.

- [ ] **Step 2: Tag the release commit**

Run:

```bash
git tag v1.18.0
```

Expected: The tag points to the release commit.

- [ ] **Step 3: Push the branch and tag**

Run:

```bash
git push origin main --tags
```

Expected: The remote branch and tag point to the release commit.

- [ ] **Step 4: Create the GitHub release**

Run `gh release create v1.18.0` with the title `v1.18.0`, the English release notes, and `/private/var/folders/vn/1bmkz4j91zs7syr7czvm3v7c0000gn/T/opencode/TruchiEmu-v1.18.0.zip`.

Expected: GitHub creates a public release and uploads the archive.

### Task 7: Verify the published release

**Files:**
- Verify only; no file changes.

**Interfaces:**
- Consumes: The published GitHub release.
- Produces: Evidence that the public release and its asset are correct.

- [ ] **Step 1: Verify the release state and asset**

Run:

```bash
gh release view v1.18.0 --json tagName,name,isDraft,isPrerelease,publishedAt,url,assets
```

Expected: The release is not a draft, is not a pre-release, and contains `TruchiEmu-v1.18.0.zip`.

- [ ] **Step 2: Verify the remote commit and clean worktree**

Run:

```bash
git status --short --branch
git rev-parse HEAD
git rev-list -n 1 v1.18.0
git ls-remote origin refs/tags/v1.18.0
```

Expected: The worktree is clean. The local commit, local tag, and remote tag identify the same release commit.
