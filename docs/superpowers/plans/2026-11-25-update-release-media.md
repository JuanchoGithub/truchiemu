# TruchiEmu Release Media Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Repair the images on the v1.18.0 GitHub release page and show the current app interface in the repository README.

**Architecture:** Use the corrected screenshots from commit `71e26f0096f77089f7a002f0264ec046382bd1e9`. Reference versioned repository files in the README, replace the release assets, and use raw commit URLs in the release notes so GitHub renders the images reliably.

**Tech Stack:** Markdown, GitHub CLI, Git, GitHub Releases

**Spec:** User request dated November 25, 2026

## Global Constraints

- Use the screenshots updated in the latest commit.
- Do not modify the unrelated change in `TruchiEmu/Views/Detail/GameDetailView.swift`.
- Keep the release title, notes, tag, and application archive unchanged.
- Keep the README structure and tone.

## Review Focus

- Every README image path must exist in the repository.
- Every release image must return a valid PNG.
- The release notes must use links to the corrected image files.
- The release assets must contain the corrected image files.
- The README commit must not include the unrelated Swift change.

---

### Task 1: Update the README images

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: The corrected screenshots in `docs/media/screenshots/`.
- Produces: A README that shows the current library, game details, achievements, cheats, and save states.

- [x] **Step 1: Replace image links with repository paths**

Use the eight corrected screenshots from the latest commit. Keep the existing video links and the existing README text.

- [x] **Step 2: Verify the README image paths**

Run a path check for every local image reference. Expected: all referenced files exist.

### Task 2: Update the v1.18.0 release

**Files:**
- Create outside the repository: `/private/var/folders/vn/1bmkz4j91zs7syr7czvm3v7c0000gn/T/opencode/v1.18.0-notes.md`

**Interfaces:**
- Consumes: The current release body and the corrected screenshots.
- Produces: A release page with renderable images and corrected downloadable image assets.

- [x] **Step 1: Replace the two release image URLs**

Use raw URLs for commit `71e26f0096f77089f7a002f0264ec046382bd1e9`.

- [x] **Step 2: Replace the two release image assets**

Upload the corrected files with `gh release upload --clobber`.

- [x] **Step 3: Update the release notes**

Keep all release text unchanged except for the two image URLs.

### Task 3: Verify and publish

**Files:**
- Modify: `README.md`
- Create: `docs/superpowers/plans/2026-11-25-update-release-media.md`

**Interfaces:**
- Consumes: The updated README and release.
- Produces: A published README update and a verified release page.

- [x] **Step 1: Verify the release assets and image responses**

Expected: both release images return HTTP 200 with `image/png`, and their sizes and digests match the repository files.

- [x] **Step 2: Check the final diff**

Expected: the diff contains only documentation and plan changes. The unrelated Swift change remains unstaged.

- [x] **Step 3: Commit and push the README update**

Stage only `README.md` and the plan file. Do not stage `TruchiEmu/Views/Detail/GameDetailView.swift`.
