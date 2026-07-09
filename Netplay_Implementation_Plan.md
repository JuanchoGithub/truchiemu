# TruchiEmu Netplay Implementation Plan

## Locked Decisions

| Decision | Value |
|---|---|
| Scope tier | Tier 2 — full rollback (Mode 1: δ-frame ring, per-frame serialize, CRC desync detection, REQUEST/LOAD_SAVESTATE recovery) |
| Players | 4 players + spectator |
| Netplay code location | XPC service process (`CoreHostService`) |
| Wire protocol | RetroArch-compatible subset (RANP+NICK+INFO+SYNC+INPUT+NOINPUT+CRC+REQUEST/LOAD_SAVESTATE+MODE+PLAY+SPECTATE+PLAYER_CHAT+PING+STALL), no interop guarantee |
| Core gating | Savestate round-trip probe after `retro_load_game`; refuse netplay for cores without stable savestates |
| N64 in v1 | Unconditionally allowed (large savestates accepted) |
| Transport abstraction | `NetplayTransport` protocol with WebSocket and raw TCP implementations, so we can swap providers without rewriting |
| Matchmaking stages | 3 stages (see below) |

## Infrastructure

- **Relay host**: Render Free web service (750 hrs/month). Keep-alive heartbeat every 10s to prevent 15-min idle spin-down.
- **Fallback relay host**: Oracle Cloud Always-Free Ampere A1 VM (if Render limitations become problematic).
- **Lobby/match-code HTTP service**: Vercel Free (short HTTP requests, fine for 5-min timeout).
- **LAN discovery**: Apple `Network.framework` Bonjour/mDNS (`NWBrowser` + `NWListener`), no server needed.

## Matchmaking Stages

| Stage | Scope | Infra | Cost |
|---|---|---|---|
| 1 (v1 LAN+direct) | NWBrowser Bonjour auto-discovery + manual IP:port entry for port-forward power users | None | $0 |
| 2 (v1.1 Render relay + match code) | Render Free web service WebSocket relay keyed by 6‑char EFF wordlist code; both peers dial out; covers cellular/CG-NAT | Render Free WebSocket server + tiny lobby HTTP on Vercel Free | $0 with keep-alives |
| 3 (v1.2 UPnP peer-direct) | UPnP-IGD SSDP+SOAP in Swift; auto port-map on home routers; transparent fallback to relay when UPnP fails | Nothing new | $0 |

Stage 1 and Stage 2 ship within one release cycle so no user is without internet play for more than one cycle.

## Feature Module Structure

```
TruchiEmu/Features/Netplay/
  Models/
    NetplaySession.swift              — session state, role, peer list
    NetplayPeer.swift                 — per-peer: client_id, port assignments, nickname, ping, mode
    NetplayPacket.swift               — wire packet encoder/decoder (all RA commands)
    NetplayRollbackFrame.swift        — Δ-frame: resolved_input[4], real_input[4], simulated_input[4], state, CRC, frame#, have_*
    NetplayRoom.swift                 — Bonjour / lobby descriptors
    NetplayMatchCode.swift            — short word ↔ 12-byte token mapping (Stage 2)
  Services/
    NetplaySessionManager.swift       — @MainActor ObservableObject singleton; lifecycle, UI binding, transport
    NetplayTransport.swift            — protocol { connect, send, receive, close }; pluggable for raw TCP or WS
    NetplayTCPTransport.swift         — raw TCP via NWConnection (Stage 1 + Stage 3 peer-direct)
    NetplayWebSocketTransport.swift   — URLSessionWebSocketTask wrapping RA TCP frames as binary WS (Stage 2)
    NetplayRollbackBuffer.swift       — NEW dedicated ring of NetplayRollbackFrame (modelled on netplay_private.h delta_frame)
    NetplayInputState.swift           — per-port resolved/real/simulated input tables; bridge_input_state multiplexes here
    NetplayProtocol.swift             — handshake (NICK/INFO/SYNC), command dispatch, frame sync
    NetplayHostService.swift          — host-side arbiter (server = client 0); per-player unread_frame; relay-aware
    NetplayClientService.swift        — joiner side; connects to host or via relay
    NetplaySavestateGate.swift        — post-load_game probe: serialize_size>0 + serialize/unserialize round-trip
    BonjourDiscoveryService.swift     — NWBrowser `_truchinet._tcp` + NWListener with bonjourAdvertising TXT record
    RelayClientService.swift          — Stage 2: dial Render relay, RATS-style token handshake, byte-pipe
    LobbyClientService.swift         — Stage 2: POST/GET short-code ↔ 12-byte room token on Vercel
    UPnPIGDService.swift              — Stage 3: SSDP M-SEARCH + SOAP AddPortMapping/DeletePortMapping
  Views/
    NetplayLobbyView.swift            — host/join/spectate tabs
    NetplayHostSheet.swift            — get code, wait for peers
    NetplayJoinSheet.swift            — paste code or paste IP:port, or pick LAN room
    NetplayRoomBrowser.swift          — Bonjour list
    NetplayPlayerListView.swift       — in-session overlay; ping, chat
    NetplayChatOverlay.swift          — PLAYER_CHAT messages (5-line ring, 96 char cap, RA style)
    NetplaySettingsView.swift         — enable, nickname, input latency frames, check_frames, default region
```

### Existing files that also change

| File | Change |
|---|---|
| `TruchiEmu/Core/Engine/LibretroCallbacks.mm` | Add `case RETRO_ENVIRONMENT_SET_NETPACKET_INTERFACE` to env switch (stubbed, for Mode 2 link-cable later) |
| `TruchiEmu/Core/Engine/LibretroBridgeImpl.mm` | Add `setSavestateContext()` to expose `RETRO_ENVIRONMENT_SET_SAVESTATE_CONTEXT` with `RETRO_SAVESTATE_CONTEXT_ROLLBACK_NETPLAY = 3` |
| `TruchiEmu/Core/Engine/LibretroBridgeSwift.swift` | Add `setNetplayInputSource(port:provider:)` + `setSavestateContext(_:)` |
| `TruchiEmu/Core/XPC/Service/CoreHostService.swift` | Own NetplaySessionManager + transport lifecycle; expose XPC methods: netplayHostRoom, netplayJoinWithCode, netplayJoinLanRoom, netplayLeave, netplaySendChat, netplayStateStream |
| `TruchiEmu/Core/XPC/Shared/XPCSharedMemory.h` | Add per-port "remote input source" flag (already `MAX_PLAYERS=4` arrays exist) |
| `TruchiEmu/Core/Engine/Runners/Runners/BaseRunner.swift` | Accept `NetplayConfig` parameter in launch |
| `TruchiEmu/Features/Player/Services/GameLauncher.swift` | `LaunchConfig.netplay` optional; routes through normal launch pipeline |
| `TruchiEmu/Features/Player/Services/RunningGamesTracker.swift` | Flag netplay sessions |
| `TruchiEmu/Services/HardcoreModeManager.swift` | Verify rollback-internal `retro_unserialize` is NOT a user save state (hardcore blocking check), so hardcore stays active during netplay |
| `TruchiEmu/Resources/Translations/en.json` + `es.json` + `pt.json` | All new netplay-localized strings (per AGENTS.md localization rules) |

---

## RA Wire Protocol Command Set

All commands use the RetroArch wire format:

```
uint32 cmd  | network byte order
uint32 size | network byte order (payload)
payload     | size bytes
```

### Commands to implement (protocol-compatible subset)

| Command | Direction | Payload |
|---|---|---|
| NICK | bidirectional | `nickname[32] padding` |
| INFO | bidirectional | `content_crc uint32 | core_name char[32] padding | core_version char[32] padding` |
| SYNC | server→client | `frame uint32 | paused uint8 | client_num uint32 | device_bitmap uint32[16] | share_modes uint32[4] | controller_map uint32[16] | nick[32] padding | sram_data` |
| INPUT | bidirectional | `frame uint32 | client uint32 | size uint16 | input_data` |
| NOINPUT | server→client | `frame uint32 | client uint32` |
| CRC | bidirectional | `frame uint32 | crc[8] | client uint32` |
| REQUEST_SAVESTATE | bidirectional | `frame uint32` (request state at that frame) |
| LOAD_SAVESTATE | bidirectional | `frame uint32 | state_size uint32 | state_data` (zlib-optional) |
| MODE | server→client | `mode uint32 | device uint32 | state uint32` |
| PLAY | client→server | no payload |
| SPECTATE | client→server | no payload |
| MODE_REFUSED | server→client | no payload |
| PLAYER_CHAT | bidirectional | `nickname[32] padding | message variable` |
| PING_REQUEST | bidirectional | `frame uint32` |
| PING_RESPONSE | bidirectional | `frame uint32` |
| STALL | server→client | `frame uint32 | mode uint8` |
| PAUSE | server→client | no payload |
| RESUME | server→client | no payload |
| RESET | bidirectional | no payload |
| SETTING_INPUT_LATENCY_FRAMES | bidirectional | `min uint32 | max uint32` |
| DISCONNECT | bidirectional | no payload |

### Handshake order (from libretro docs / RA netplay README)

**Server (host) side:**
1. Send connection header (RANP magic + platform + impl magic + protocol version)
2. Receive and verify connection header from client
3. Send NICK
4. Receive NICK
5. Send INFO
6. Receive INFO (verify content CRC + core name + core version match)
7. Send SYNC (assign client number, send device bitmap, SRAM)

**Client (joiner) side:**
1. Receive and verify connection header
2. Send connection header
3. Receive NICK
4. Send NICK
5. Receive INFO
6. Send INFO (verify server info matches)
7. Receive SYNC

---

## Rollback Buffer Design (Modeled on RetroArch `netplay_private.h`)

### `NetplayRollbackFrame`

```swift
struct NetplayRollbackFrame {
    struct InputState {
        var buttons: UInt32     // bitmask of RETRO_DEVICE_ID_JOYPAD_*
        var analog: [UInt16]    // [2][2] -> left_stick_x/y, right_stick_x/y
        var haveReal: Bool      // true if real (not simulated) input arrived from peer
    }

    var frame: UInt32
    var resolvedInput: [Input]  // what the core actually sees (MAX_PLAYERS = 4)
    var realInput: [Input]      // actual input from each peer
    var simulatedInput: [Input] // predicted input when real didn't arrive
    var state: Data?            // serialized savestate *before* this frame (optional, nil until serialized)
    var crc: UInt32             // CRC-32 of serialized state, or 0
    var haveLocal: Bool
    var haveReal: [Bool]        // per-player: did real input arrive?
    var used: Bool
}
```

### `NetplayRollbackBuffer`

```swift
class NetplayRollbackBuffer {
    private var ring: [NetplayRollbackFrame]
    private var head: Int = 0
    private var count: Int = 0

    init(size: Int)   // size = latency_frames + check_frames + safety_margin

    func push(frame: UInt32) -> Int       // returns slot index
    func get(frame: UInt32) -> NetplayRollbackFrame?
    func advance(toFrame: UInt32)

    // Frame counters (from RA netplay_private.h)
    var selfFrameCount: UInt32 = 0        // local clock
    var otherFrameCount: UInt32 = 0      // last frame in perfect sync
    var unreadFrameCount: UInt32 = 0     // earliest frame missing all peers' data
    var readFrameCount: [UInt32]         // per-client read positions
}
```

### Pre-frame loop (executed before each `retro_run`)

1. `serialize()` current core state into `ring[head].state` using `RETRO_SAVESTATE_CONTEXT_ROLLBACK_NETPLAY`
2. Poll local input → store in `ring[head].resolvedInput[localPlayer]`
3. Check if remote peer input arrived for this frame:
   - If yes, copy `ring[slot].resolvedInput[remotePlayer] = received input`
   - If no, copy `ring[lastKnownFrame].resolvedInput[remotePlayer]` as simulation
4. If peer input for an earlier frame we already simulated arrives:
   - Compare simulated vs real input for that frame
   - If different → rollback to `otherFrameCount`, replay with real inputs
   - If same → advance `otherFrameCount`
5. If CRC check due (`frame % check_frames == 0`):
   - Compute `encoding_crc32(0, state, state_size)` → send `CRC` command
   - If a `REQUEST_SAVESTATE` is received, reply with `LOAD_SAVESTATE` containing fresh state

### Frame sync approach

Instead of blocking waiting for remote input (which would pin the networking and emulator together), the host runs as the clock arbiter:

- If `unreadFrameCount > selfFrameCount`: server hasn't received client input yet → simulate remote input from last known
- If `unreadFrameCount` is too far behind `selfFrameCount` (exceeds `buffer_size`): force a resync via `REQUEST_SAVESTATE` + `LOAD_SAVESTATE`
- CRC check frequency: user-adjustable (`check_frames` in settings), default every 60 frames (1 second at 60fps)

### Rollback sequence

1. Detect mismatch between simulated and real remote input
2. Call `retro_unserialize(ring[other].state)` to rewind
3. For each frame from `other` to current, re-run the core:
   - Feed real (now-arrived) input instead of simulated
   - Re-serialize state into the ring (replacing simulated state)
4. Advance `otherFrameCount` to the matched frame position
5. Disable frame limiter momentarily to catch up lost time

---

## Host / Client / Arbitrator Model

### Roles

- **Host** (client 0): acts as the synchronization arbiter. Manages per-player unread_frame count. Forwards input data. Controls pause, reset, mode changes.
- **Clients** (client 1..3): send per-frame INPUT to host. Send PLAY/SPECTATE requests.
- **Spectators** (client 4+): receive but send no input. They get the game stream but don't participate in lockstep; they just receive the A/V output.

### Host arbiter logic (from RA netplay_frontend.c)

- Maintains per-player unread_frame: the earliest frame for which that player's input hasn't been received.
- Global unread frame = min of all player unread frames.
- Server clock is the arbiter for all synchronization.
- Input latency frames: host specifies `SETTING_INPUT_LATENCY_FRAMES` to share the "frames behind" value.
- During frame N, the server may send its own and any number of other players' data for frame N, but never N+1.
- For CRC checking, host compares local CRC with client CRC; on mismatch, host sends `LOAD_SAVESTATE` (with current state) and both sides resume lockstep from that frame. Only sent once per `REQUEST_SAVESTATE` cycle to avoid infinite loops.

---

## Transport Abstraction

```swift
protocol NetplayTransport: AnyObject {
    var delegate: NetplayTransportDelegate? { get set }

    func connect(to endpoint: NetplayEndpoint) async throws   // host/join
    func send(data: Data) async throws
    func receive() async throws -> Data
    func close()

    var isConnected: Bool { get }
}

enum NetEndpoint {
    case direct(host: String, port: UInt16)
    case bonjour(serviceName: String)
    case relay(code: String, token: Data?)
}

protocol NetplayTransportDelegate: AnyObject {
    func transportDidConnect()
    func transportDidDisconnect(error: Error?)
    func transportDidReceive(data: Data)
}

// Raw TCP implementation (Stage 1 + Stage 3)
class TCPTransport: NetplayTransport {
    private var connection: NWConnection?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "netplay.tcp.transport")

    func connect(to endpoint: NetEndpoint) async throws {
        switch endpoint {
        case .direct(let host, let port):
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            connection = NWConnection(host: NWEndpoint.Host(host),
                                       port: NWEndpoint.Port(rawValue: port)!,
                                       using: params)
            // ... start on queue
        case .bonjour(let serviceName): // handled via NWListener, see BonjourDiscoveryService
        }
    }
}

// WebSocket transport (class for Stage 2 Render relay)
class WebSocketTransport: NetplayTransport {
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    func connect(endpoint: NetEndpoint) async throws {
        let host: String, port: UInt16, path: String
        // ... resolve from endpoint
        let url = URL(string: "wss://\(host):\(port)/\(path)")!
        task = session.webSocketTask(with: url)
        task?.resume()
        // send relay token (RATS-style magic + 12-byte unique)
        // then begin normal RA handshake (RANP + NICK + ...)
    }

    func send(data: Data) async throws {
        try await task?.send(.data(data))
    }
}
```

---

## Relay Service Protocol (Stage 2 — Render Free)

### Wire protocol on the WebSocket relay

The Render service runs a simple WebSocket byte relay (~80 lines Node.js using the `ws` library). Flow:

1. Host dials the Render relay:
   - Opens WebSocket to `wss://relay.truchiemu.ondraw.io/ws`
   - Sends first message: binary frame `[0x00, 16 bytes of zeroes]` (request new room)
   - Relay assigns a 12-byte random room token, sends back binary `[0x01, 12-byte token]`
   - Host now holds an open WebSocket for the relay, keyed by the 12-byte token
2. Match-code lobby (Vercel Free):
   - Host calls `POST /api/room` with the 12-byte token base64-encoded
   - Lobby returns a short match code from the EFF short wordlist
3. Joiner dials the relay:
   - Opens WebSocket to `wss://relay.truchiempo.ondraw.com/ws`
   - Sends binary `[0x01, 12-byte token from match code]` (request to join room)
   - Relay pairs the joiner's WebSocket with the host's WebSocket (swap buffers)
   - From this point: relay transparently forwards binary frames between the two peers
4. Both peers start the normal RA handshake (RANP + NICK + INFO + SYNC) through the relay pipe
5. Keep-alive: each side sends a ping/keep-alive message every 10 seconds to prevent Render's idle spin-down

### Lobby HTTP API (Vercel Free — Node fetch `@vercel/node`)

```
POST /api/room
  request:  { token: "<base64-12byte>" }
  response: { code: "brave-fox-42" }

GET /api/room?code=brave-fox-42
  response: { relay: "relay.truchiempo.ondraw.com", port: 443, token: "<base64-12byte>" }
```

The EFF short word list is a defined set of 1296 four-letter words (https://eff.org/files/2016/09/08/eff_short_wordlist_1.txt). Code format: `word-digit-word-digit` (e.g., "brave-42-fox-99").

---

## Savestate Gate (`NetplaySavestateGate`)

Run after `retro_load_game` succeeds in the normal launch pipeline.

```swift
class NetplaySavestateGate {
    static func probe() -> NetplayGateResult {
        let size = LibretroBridge.serializeSize()
        guard size > 0 else { return .unsupported("Core provides no serialization") }
        guard size < 10_485_760 else { return .unsupported("State too large (\(size) bytes)") }
        // Probe serialize + unserializate round-trip
        guard let state = LibretroBridge.serializeState() else { return .unsupported("serialize failed") }
        guard state.count == size else { return .unsupported("serialize size mismatch") }
        guard LibretroBridge.unserialzieState(state) else { return .unsupported("unserialize failed") }
        return .supported
    }
}
```

If the gate returns `.unsupported`, the netplay UI greys out with a tooltip explaining the core doesn't support netplay.

---

## Network.framework Primitives Used

| Primitive | Use |
|---|---|
| `NWConnection` | Dial remote TCP (joiner-to-host, host-to-relay, joiner-to-relay) |
| `NWListener` | Host listens for inbound TCP connections (direct/Stage 1 mode) |
| `NWBrowser` (bonjour descriptor) | Browse LAN `_truchinet._tcp` services (Stage 1) |
| `NWListener` with `bonjourAdvertising` descriptor | Advertise LAN session over mDNS |
| `NWPathMonitor` | Track network reachability for transport fallback decisions |
| `NWConnection.tcp` parameters | QoS on netplay traffic, TCP_NODELAY |
| `URLSessionWebSocketTask` | WebSocket transport (Stage 2) |

---

## Risk Log

1. **Determinism**: Some Beetle cores and other edge-case cores have known non-round-trippable savestates. Savestate gate catches these.
2. **ScummVM/DOSRunner**: Unsupported per gate (expected and documented)
3. **N64 bandwidth**: Large savestates per rollback (megabytes). Bandwidth usage at `check_frames=60` and 60fps rollback may be meaningful. Accepted per decision. Can be mitigated with zlib compression in future.
4. **Hardcore mode**: Rollback-internal `retro_unserialize` is NOT a user-facing save state; `HardcoreModeManager.attemptSaveState()` must allow private internal rollback calls while still blocking user save-states.
5. **XPC boundary**: All per-frame callbacks (serialize, unserialize, CRC) live in the XPC service. Main-app UI talks via XPC stream for player-list/chat/ping. `Networking.framework` primitives are safe from XPC.
6. **Render Free spin-down**: 15-min idle rule. Active 60 Hz netplay packets keep the service warm trivially. Stage 2 adds a keep-alive heartbeat every 10s to handle lobby waits. Ok with keep-alives.
7. **Render Free 750-hour/month cap**: One continuous session holds the box active. Cap is per-month; should be fine for casual usage. If needed, migrate to Oracle Always-Free VM.
8. **WebSocket framing overhead for libretro RA wire protocol**: Each binary WS frame adds 2–14 bytes of WS framing headers. Libretro's protocol is pure TCP; RA interop could eventually go through a raw TCP alternative transport. The `NetplayTransport` protocol abstracts this away.
8. **Match-code race / collision**: Lobby uses 12-byte random tokens (overflow probability negligible). EFF word codes use a short dictionary; collisions are rare. Check uniqueness at room creation.
9. **Render TOS —** The fundamental "relay that carries arbitrary game traffic" is not explicitly prohibited by Render TOS. Unlikely to be an issue for a hobby project; if it becomes one, Oracle Always-Free is the fallback.

---

## Verification Plan (manual only, no test target)

Per AGENTS.md, no test target exists. All verification:

- **Phase A+B**: deterministic-replay harness — feed identical inputs to 2 local core instances running in lockstep, assert no CRC mismatch within 5 minutes. Then test with manual simulated delay.
- **Phase C**: same-machine 2-app launch, click "Join LAN Room", play through, verify sync holds.
- **Phase D**: cross-network test (one on Wi-Fi, one on cellular), confirm match-code resolves and game runs without port-forward.
- **Phase E**: confirm UPnP creates port-map on a UPnP router; confirm relay fallback still works when UPnP fails.

---

## Phasing (Execution order)

### Phase A+B — Foundation + Wire Protocol + Loopback Transport

1. `NetplayRollbackFrame` + `NetplayRollbackBuffer` ring (dedicated, new, modelled on RA)
2. `NetplayInputState` per-port tables + `setNetplayInputSource(port:provider:)` bridge
3. Modify `LibretroCallbacks.mm` `bridge_input_state` to consult netplay input table for remote ports
4. `NetplaySavestateGate` probe (after `load_game`, before netplay UI enables)
5. `NetplayPacket` encoder/decoder for RA command subset
6. `NetplayProtocol` handshake + command dispatch on loopback `NWConnection`
7. `NetplayHostService` / `NetplayClientService` frame loop:
   - Pre-frame serialize, poll local input, send `INPUT` over transport
   - Block for peer input (with simulation fallback)
   - Post-frame CRC if `frame % check_frames == 0`
   - Rollback in simulation mismatch
   - REQUEST/LOAD_DAVESTATE on CRC mismatch
8. `NetplayTransport` protocol + `TCPTransport` implementation
9. `setSavestateContext()` in `LibretroBridgeImpl.mm` (`RETRO_ENVIRONMENT_SET_SAVESTATE_CONTEXT`, `RETRO_SAVESTATE_CONTEXT_ROLLBACK_NETPLAY = 3`)
10. `setNetplayInputSource` in `LibretroBridgeSwift.swift`
11. XPC methods in `CoreHostService.swift` (host, join, leave, chat, state stream)
12. Verification: loopback 2-instance test (SMW 5 min.)

### Phase C — Stage 1 Ship (LAN + Direct IP)

13. `BonjourDiscoveryService` (`NWBrowser` + `NWListener` bonjour advertising)
14. `NetplayJoinSheet` (paste IP:port or pick LAN room from Bonjour list)
15. `NetplayHostSheet` (host with LAN discovery)
16. `NetplayLobbyView` (tabs: Host, Join, Spectate, Settings)
17. `NetplaySettingsView` (enable netplay, nickname, input latency frames, check frames)
18. Settings group in `Features/Settings/Views/Settings/`
19. Wire into `GameLauncher.swift` `LaunchConfig.netplay` optional
20. `RunningGamesTracker` netplay flag
20. `HardcoreModeManager` verification (internal rollback does not trigger `attemptSaveState` false)
21. Localization: add all new strings to `en.json` / `es.json` / `pt.json`
22. `xcodegen generate && xcodebuild ... build` — clean

### Phase D — Stage 2 Ship (Render Relay + Match Code)

23. Stand up Render Free WebSocket relay service (Node.js `ws`, ~80 lines)
24. Build tiny lobby HTTP service (Vercel Free Node.js `@vercel/serverless`): `POST /api/room` + `GET /api/room?code=`
25. `NetplayWebSocketTransport` wrapping RA TCP frames as WS binary
26. `LobbyClientService` — fetch/create rooms
27. `RelayClientService` — RATS-style relay token handshake, byte-pipe
28. `NetplayJoinSheet` gets match-code paste box
29. Auto-preference: if Bonjour discovers a matching `_truchinet._tcp` room for the same content/crc, prefer direct LAN over relay
30. Keep-alive heartbeat (10s) in `RelayClientService`

### Phase E — Stage 3 Ship (UPnP-IGD peer-direct)

31. `UPnPIGDService` — SSDP M-SEARCH on 239.255.255.250:1900, parse IGD device XML, SOAP `GetExternalIPAddress` + `AddPortMapping` (mirroring RA `network/natt.c`)
32. When hosting: attempt UPnP map (10s timeout). If success, advertise public IP:port in lobby response; joiners prefer direct → relay fallback

### Phase F — Mode 2 Netpacket (deferred / optional)

33. `case RETRO_ENVIRONMENT_SET_NETPACKET_INTERFACE` in `LibretroCallbacks.mm`
34. Expose vtable to Swift via `LibretroBridgeSwift`: `NetpacketCallback` struct
35. mGBA / SameBoy Game Boy link wire through the same transport
36. No rollback in netpacket mode (RA disables it)