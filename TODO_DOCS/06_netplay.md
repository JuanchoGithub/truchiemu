# Design Document: Netplay Subsystem (Libretro-Compatible)

## 1. Objective

To implement a high-performance multiplayer system that allows users to play retro games over the internet. This system will utilize **Rollback Networking** (similar to GGPO) to ensure a lag-free experience, even with high latency, by leveraging the Libretro serialization API.

---

## 2. Architecture: Rollback vs. Delay

Your frontend should implement **Rollback Netplay**.

* **How it works:** Instead of waiting for the other player's input to arrive (which causes "input lag"), the frontend predicts the input and runs the game immediately. If the actual input differs when it arrives, the frontend "rolls back" the game state to the point of divergence and re-simulates the frames instantly.
* **Dependency:** This requires the Core to support **Save States** (`retro_serialize`). If a core cannot save/load state, it cannot perform netplay.

---

## 3. The Discovery System (The Lobby)

To make netplay user-friendly, you should integrate with the **Libretro Lobby Server API**. This prevents users from having to manually exchange IP addresses.

### A. The Lobby API Flow

1. **Announce:** When a user hosts a game, the frontend sends a POST request to `https://lobby.libretro.com/` with the Game Name, Core Name, Game Hash, and IP.
2. **List:** The frontend fetches the JSON list from the same URL to show "Rooms" to other users.
3. **Filter:** Only show rooms that match the cores/games the user actually has installed.

---

## 4. Implementation Workflow

### Step 1: The Connection Handshake

* **Host:** Opens a TCP/UDP port (default: `55435`) and waits for a connection.
* **Client:** Connects to the Host's IP.
* **Handshake:** The Host sends the **Game Hash** and **Core Version**. If they don't match exactly, the frontend must disconnect and warn the user (to prevent desync).

### Step 2: The Sync Loop

1. **Input Exchange:** Every frame, the Host and Client exchange their controller input packets.
2. **Serialization:** The frontend takes a "Check-point" save state every $X$ frames.
3. **Correction:** If a packet arrives late, the frontend:
    * Loads the last "Clean" Save State.
    * Injects the late-arriving input.
    * Fast-forwards (runs `retro_run` without video output) until it catches up to the current frame.

---

## 5. UI/UX Requirements

### A. The Netplay Menu

* **Host Room:** Set a password, Max Players (usually 2, up to 4), and toggle "Public/Private".
* **Refresh Lobby:** A list showing:
  * Game Title + Boxart.
  * Country (determined by IP).
  * Ping (latency in ms).
  * Core version match status.

### B. In-Game Overlay

* **Latency Indicator:** A small "Signal Strength" icon.
* **Chat:** A simple text-overlay for players to communicate.
* **Pause Logic:** If one player pauses, the game must pause for both.

---

## 6. NAT Traversal (Connecting through Firewalls)

Most users cannot manually forward ports on their routers. Your frontend needs two solutions:

1. **UPnP Support:** Automatically request the router to open port `55435` using a library like `miniupnpc`.
2. **Relay Servers (MITM):** If a direct connection fails, route the traffic through a third-party server. (Note: This increases latency but ensures a connection).

---

## 7. Hardcore Mode & Integrity

* **Cheats/Rewind:** These must be **disabled** during netplay, as they would instantly cause a desync between the two machines.
* **Saves:** Only the Host's save data (SRAM) should be used. The Client's local save file should be ignored for the duration of the session.

---

## 8. Technical Implementation Checklist

### [ ] Network Protocol Implementation

Build a packet structure for:

* `NETPLAY_CMD_INPUT`: Controller data.
* `NETPLAY_CMD_SYNC`: Checksum of the current game state (to detect desyncs).
* `NETPLAY_CMD_CHAT`: Text messages.

### [ ] Serialization Buffer

Implement a circular buffer in RAM to store the last ~30 frames of save states.

* *Warning:* For PS1/N64, save states are large. You may need to limit the rollback window to 5-10 frames to save RAM.

### [ ] Input Polling Handler

Modify your `input_poll` callback to return:

* Local input for the Local Player.
* The "Last Received" or "Predicted" input for the Remote Player.

### [ ] Ping/Jitter Compensation

Add logic to dynamically adjust the "Frame Delay." If the ping is a steady 50ms, adding 1 or 2 frames of artificial delay can prevent frequent rollbacks, making the animation smoother.

---

## 9. Summary of the User Flow

1. **User A** selects "Host Netplay" on *Street Fighter II*.
2. **User B** opens the "Netplay Lobby," sees User A's room, and clicks "Join."
3. **Frontend** checks if User B has the same ROM hash.
4. **Connection** is established; User A's frontend sends the current game state to User B so they start at the exact same moment.
5. **Gameplay** begins; the two frontends stay in a constant loop of exchanging buttons and rolling back if packets are late.
