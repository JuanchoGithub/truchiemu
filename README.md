# TruchiEmu 🕹️

<table>
<tr>
<img width="1117" height="783" alt="image" src="https://github.com/user-attachments/assets/4b6fa510-a07d-4a0a-815d-aee8da4562db" />
</tr>
</table>


# HomePage

Home page is being mantained from the repo itself, and it is here: https://juanchogithub.github.io/truchiemu/

# Download
Download and install from my releases page: https://github.com/JuanchoGithub/truchiemu/releases

# Support
- You can support TruchiEmu by subscribing to my [Patreon here](https://www.patreon.com/16201897/join)
- O si estas en Argentina o LATAM, [![Invitame un café en cafecito.app](https://cdn.cafecito.app/imgs/buttons/button_1.svg)](https://cafecito.app/truchisoft)

# TruchiEmu

**The ultimate retro gaming experience, beautifully reimagined for macOS.**

TruchiEmu is a modern, high-performance emulator built from the ground up with SwiftUI. It brings your favorite classic consoles to life with a stunning interface, immersive visuals, and effortless library management.

https://github.com/user-attachments/assets/c59b9283-b5bd-49d0-9631-f0d6bc247d60

---

## ✨ The TruchiEmu Experience

### 🎨 Beautifully Designed
Forget clunky, outdated menus. TruchiEmu features a polished, native macOS interface. Browse your collection with high-quality box art, detailed game information, and a seamless, modern navigation experience.

### 📺 Immersive Visuals

https://github.com/user-attachments/assets/46a734d8-9c25-4d94-bb81-80cb53506531

Relive the golden age of gaming with advanced Metal-powered shaders. Whether you want the warm glow of a classic CRT, the sharp look of an LCD, or custom scanline effects, TruchiEmu makes every pixel feel authentic. 14 built-in Metal shaders cover CRT, LCD, smoothing, and composite looks; hundreds of community-made Slang/RetroArch `.slangp` presets are auto-discovered and loaded via librashader.

### 🖌️ Gaming-Inspired Themes

17 accent color themes named after gaming legends, including Samus, Joker, Protoss, Kirby, and more. Each theme adapts its accent for both light and dark mode. Pick a built-in palette or choose any color with the Custom theme.

<img width="1317" height="983" alt="image" src="https://github.com/user-attachments/assets/24000983-5181-41b1-9a29-fcdb3b314eea" />

- **Gaming themes**: Mario, Sonic, Kratos, Kirby, Zelda, Pikachu, Master Chief, lots of others
- **Tinted surfaces & accent toolbars**: Subtle theme blending across every window

### 📺 TV Mode

Flip to TV Mode from **View → TV Mode** (or a button on the game-toolbar) for a couch-friendly, full-screen library experience. Browse your entire collection with just a gamepad — D-pad scrolls, A selects, B backs out — no mouse required. Animated backdrops derived from box art, box-art focus scaling, short-list mode for large libraries, and resolution-adaptive scaling for 1080p through 4K. Trigger core downloads directly from TV Mode without dropping back to the desktop.

### ⏪ Time Machine

Rewind, fast-forward, and slow-motion controls directly from the game toolbar. Time Machine captures save-state deltas in a circular buffer and replays them on demand — giving you the same "scrub" you'd expect from a video editor, all without leaving the game window. Perfect for retrying a missed jump, skipping slow cutscenes, or studying frame-perfect sequences at 0.25× speed. Hardcore-aware: automatically disabled when RetroAchievements Hardcore Mode is active.

### 🎬 Recording & Streaming

Record sessions locally (H.264/HEVC/ProRes lossless) or stream live to Twitch, YouTube, or any custom RTMP endpoint — without leaving the game. The pipeline runs in-process via HaishinKit (real RTMP handshake, AMF0 messaging, FLV mux, VideoToolbox H.264/HEVC + AAC encode) so there are no external processes, pipes, or silent frame drops. Rolling video buffer with a "save last moments" hotkey, configurable Share button (single-press reveals latest clip, long-press flushes the buffer), and per-game stream resolution from native up to 4K.

### 🥊 Move Lists & Fight Data

On-screen move notation overlay for fighting games, with directional inputs, button-glyph combinations, and special-condition markers rendered as crisp visual tokens. Ships with a curated Fight Data library covering 200+ fighting games — Street Fighter II, Mortal Kombat, KOF, Tekken, Samurai Shodown, Eternal Champions, Clay Fighter, Dragon Ball Z, Yu Yu Hakusho, TMNT Tournament Fighters, and more. MoveForest evaluator tracks inputs intelligently. Toggle move names alongside tokens, search and filter by character, input type, or name.

### 🎯 Game Guide

A built-in game guide overlay for point-and-click adventures (DOS, ScummVM) that shows contextual hints, walkthrough snippets, and clickable region maps. Auto-loads per game, toggle from the game toolbar. Captures release gracefully with Analog Mouse so you can switch between guide navigation and gameplay without losing your cursor.

### 🚀 Effortless Setup
Getting started is a breeze. Our guided setup wizard walks you through your first launch, and our automated library services handle the heavy lifting: syncing metadata and downloading beautiful box art for your entire collection.

<img width="1012" height="644" alt="Every Libretro Core supported (not all tested), including core options" src="https://github.com/user-attachments/assets/ad5d22f4-812f-4794-abbf-254c26c8fa10" />

<img width="812" height="644" alt="image" src="https://github.com/user-attachments/assets/8ba9d183-25e3-4cb1-84fb-e7b79e98bafe" />

<img width="754" height="563" alt="image" src="https://github.com/user-attachments/assets/9ef473de-610a-4a5d-bd0b-c4d1faafb4d2" />


### 🏆 RetroAchievements
Take your nostalgia to the next level. TruchiEmu supports RetroAchievements with full auth, achievement tracking/unlocking, rich presence polling, and game data caching. **Hardcore Mode** enforces achievement integrity by blocking save states, rewind, slow motion, and cheats when active — the same restrictions as official RetroAchievements clients. Games with RA support are flagged in the library and filterable via a dedicated sidebar entry; the Game Detail view shows the RA hash used for identification.

### ✨ Pure Delight
Every interaction is designed to be smooth and joyful. From polished transitions to celebratory confetti moments, TruchiEmu brings a touch of magic to your retro gaming sessions.

<img width="1112" height="814" alt="Easy interface to serach Box Art" src="https://github.com/user-attachments/assets/b68a47cd-e09e-4c22-a5ac-baec4d0c9b2a" />

---

## 🛠️ Key Features

- **Multi-System Powerhouse**: One app, countless classics. Support for NES, SNES, N64, GBA, Genesis, DOS, ScummVM, and more — virtually every system with an available LibRetro core.
- **TV Mode**: Couch-friendly, gamepad-navigable full-screen library with animated backdrops, box-art focus, and resolution-adaptive scaling.
- **Time Machine**: Rewind, fast-forward, and slow-motion controls from the game toolbar — circular save-state delta buffer, frame-perfect study, and Hardcore-aware auto-disable.
- **Recording & Streaming**: In-process local recording (H.264/HEVC/ProRes) and live RTMP streaming to Twitch/YouTube/custom endpoints via HaishinKit. Rolling video buffer, configurable Share button, native-to-4K resolution.
- **Move Lists & Fight Data**: On-screen move notation overlay with 200+ curated fighting game sets, MoveForest input evaluator, search and per-character filter.
- **Game Guide**: Contextual in-game guide overlay for DOS/ScummVM with hints, walkthrough snippets, and clickable maps.
- **Analog Mouse Support**: Use your gamepad's analog sticks to control the mouse cursor in DOS and ScummVM games, with configurable buttons for clicks and D-pad for keyboard inputs.
- **Advanced Shader System**: 14 built-in Metal shaders (CRT, LCD, smoothing, composite) plus full Slang/RetroArch `.slangp` preset support via librashader. Save your tweaks as `.truchishader` files to export, share, and re-import. Per-game and per-system shader overrides.
- **RetroAchievements + Hardcore Mode**: Full RA integration with auth, achievement tracking, rich presence, and Hardcore Mode enforcement (blocks save states, rewind, cheats).
- **Pro-Grade Controller Support**: Full gamepad mapping with per-system configurations, controller type icons, and customizable controls. Up to 4 players with multi-player keyboard support, gap-slot priority, live axis preview, and SDL-gamepad disable/reset.
- **Cheat System**: Built-in cheat library auto-downloaded from libretro-database, live toggle without restart, manual entry (Game Genie, Pro Action Replay, GameShark, raw hex), and per-ROM persistence.
- **Seamless Library Management**: Organize your games into custom categories, manage genres, and enjoy a clutter-free experience. CRC32 hardware-accelerated identification against DAT databases, LaunchBox metadata sync, multi-source box art (ScreenScraper + Libretro CDN) with region selection, iCloud placeholder materialization, and ROM-removal notifications.
- **Advanced Save States**: Visual grid of save states from the game detail view, slot-based progressive save and load functionality, auto-save on exit.
- **Bezel System**: Arcade cabinet bezels and screen framing with user > auto-match > system-default resolution cascade, per-game and per-system preferences.
- **Custom Core Options**: Per-core option persistence with a 5-layer override hierarchy (core default → app default → app system default → system override → game override). Versioned option keys for evolving libretro cores.
- **Notification System**: In-game notification pills for game actions, controller connections, and system events with full history.
- **CLI Support**: Launch games directly from the terminal: `TruchiEmu <rom-path>` for headless ROM launch.
- **Built-in Update Checker**: Automatic update checking and in-app changelog viewer to stay up to date.

---

## 🎮 Supported Systems
TruchiEmu supports virtually every system with an available LibRetro core. This includes classic consoles (NES, SNES, N64, Genesis), handhelds (Game Boy, GBA, DS), disc-based systems (PS1, PS2, Saturn, Dreamcast), DOS, ScummVM point-and-click adventures, and arcade machines via MAME.

Some cores might be a little trickier (Dreamcast I hate you) than others, but most should work. DOS and ScummVM now feature full analog mouse and keyboard capture for a complete experience.

---

## 🚀 Getting Started

1. **Download & Install**: Get the latest release from https://github.com/JuanchoGithub/truchiemu/releases
2. **Run the Setup Wizard**: Follow the on-screen instructions to configure your library.
3. **Add Your Games**: Simply drag and drop your ROM files into the app to begin your journey.
4. **Start Playing**: Pick a game, choose your favorite shader, and enjoy!

---

## 🛠️ For Developers

If you want to build TruchiEmu from source:

1. **Clone the repository**:
   ```bash
   git clone https://github.com/JuanchoGithub/truchiemu.git
   cd truchiemu
   ```

2. **Generate the project**:
   ```bash
   xcodegen generate
   ```

3. **Build in Xcode**:
   ```bash
   open TruchiEmu.xcodeproj
   ```

---

## 📜 License
MIT, etc, thanks to LibRetro and a countless other teams around the web.

© 2026 TruchiEmu

Now for some more media:



https://github.com/user-attachments/assets/8657fe30-b08d-4a3c-a907-dfc633d63afe



https://github.com/user-attachments/assets/1363458c-d316-434b-bd46-ed926ab21919



https://github.com/user-attachments/assets/480b1cc8-73d4-40fb-b8f5-062311610426


