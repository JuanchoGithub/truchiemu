# Design Document: RetroAchievements Integration

## 1. Objective

To integrate the [RetroAchievements (RA)](https://retroachievements.org/) service into the frontend, allowing users to earn trophies, compete on leaderboards, and track progress for thousands of retro games.

---

## 2. Technical Foundation: `rcheevos`

Libretro does not handle the achievements internally; instead, it provides the memory access necessary for a library called **[rcheevos](https://github.com/RetroAchievements/rcheevos)** to work.

### A. The `rc_client` API

The modern way to implement this is using `rc_client`. It is a state machine that handles:

1. **Authentication:** Logging in with a username and API token.
2. **Hashing:** Identifying the game regardless of filename.
3. **Processing:** Checking memory addresses every frame to see if a condition (e.g., "Boss Health = 0") is met.
4. **Reporting:** Sending the "Unlock" command to the RA servers.

---

## 3. The Implementation Workflow

### Step 1: Authentication & Login

The user must enter their RetroAchievements credentials in your frontend settings.

* **Action:** Send credentials to the RA API to receive an `API Token`.
* **Security:** Never store the password in plain text. Store the `User Token` provided by the API.

### Step 2: Game Identification (The Hash)

RA relies on specific ROM hashes (not MD5 or SHA1 of the whole file, but specific parts of the data).

* **Logic:** When a game is loaded, use the `rc_hash_generate` function from `rcheevos`.
* **Validation:** Send this hash to the RA server to see if the game is "Recognized." If it is, the server returns a `GameID` and a list of Achievement definitions.

### Step 3: The Runtime Loop (The "Heartbeat")

Achievements work by "watching" the game's RAM.

1. **Every Frame:** Your frontend calls `rc_client_do_frame()`.
2. **Memory Access:** You must provide a callback function that allows `rcheevos` to read the Libretro Core's memory (`retro_get_memory_data`).
3. **Trigger:** When a condition is met, `rc_client` will fire a callback: `RC_CLIENT_EVENT_ACHIEVEMENT_UNLOCKED`.

---

## 4. UI/UX Requirements

### A. The "Unlock" Toast (Notification)

When an achievement is triggered, the user needs immediate visual feedback.

* **Design:** A small slide-in window (bottom-center or top-right).
* **Content:** Achievement Icon, Title, and Points value (e.g., "10 points").
* **Sound:** Play the iconic "RetroAchievement Unlock" chime (usually a short `.wav` file).

### B. Achievement List Menu

A menu accessible while the game is paused:

* **Visuals:** List of all achievements for the current game.
* **Status:** Greyed out for locked, full color for unlocked.
* **Metadata:** Display "Hardcore Mode" status (see Section 5).

### C. Rich Presence

RA allows the frontend to show exactly what the user is doing (e.g., *"Playing Super Mario World - Level 1-1 - 5 Lives"*).

* **Implementation:** `rc_client` provides a string via `rc_client_get_rich_presence()`. You should send this to your frontend's "Activity" status or Discord Rich Presence.

---

## 5. "Hardcore Mode" (The Integrity System)

RetroAchievements has a standard called **Hardcore Mode**. To earn the "Hardcore" version of a trophy (which is worth more points):

* **Forbidden:** You must disable Save States, Rewind, Slow Motion, and Cheats.
* **Frontend Logic:** If Hardcore Mode is enabled in settings, your frontend must **block** the "Load State" and "Rewind" buttons. If the user uses them, the session becomes "Softcore."

---

## 6. Leaderboards & Challenges

In addition to achievements, `rcheevos` handles Leaderboards (e.g., "Fastest time to beat Level 1").

* **Flow:**
    1. Core detects a start condition (Level starts).
    2. Core detects an end condition (Level ends).
    3. Frontend displays a "Leaderboard Submitted" notification with the user's rank.

---

## 7. Storage & Offline Mode

* **Local Cache:** Store the achievement definitions (`.json` or `.bin`) locally so the game can still track progress if the internet drops momentarily.
* **Pending Unlocks:** If a user unlocks something while offline, queue the unlock and send it to the server the next time the frontend launches with an internet connection.

---

## 8. Technical Checklist for Frontend Integration

- [ ] Include `rcheevos` headers in your build system.
* [ ] Implement the `rc_client_read_memory` callback (bridges frontend to core RAM).
* [ ] Create a `NotificationManager` class to handle achievement "Toasts."
* [ ] Implement the "Hash" logic for all supported systems (NES, SNES, Genesis, etc.).
* [ ] Add a "RetroAchievements" section to the User Settings (User/Pass/Hardcore toggle).
* [ ] Map `rc_client` events to your UI (Unlock, Leaderboard Start, Login Error).

## 9. API Reference

* **Official API Docs:** [RetroAchievements Web API](https://github.com/RetroAchievements/RAWeb/wiki/Web-API)
* **Developer Library:** [rcheevos on GitHub](https://github.com/RetroAchievements/rcheevos)
