# AP_SwarmMesh — Decentralized Peer Mesh

`AP_SwarmMesh` gives every vehicle in a swarm its own view of every other vehicle, maintained onboard, without a Ground Control Station (GCS) in the middle. Each node broadcasts a small, user-selected stream of MAVLink messages over a P2P radio, and each node keeps a peer state table built from what it hears.

Onboard Lua scripts, a companion computer, and the dataflash log read that table instead of needing to talk to a central GCS.

- **Library:** `libraries/AP_SwarmMesh/`
- **Parameter prefix:** `P2P_`
- **Upstream:** [ArduPilot PR #33881](https://github.com/ArduPilot/ardupilot/pull/33881)
  — a Google Summer of Code 2026 project (mentors: Nate Mailhot, Asif Khan)
- **Blog:** [GSoC development thread](https://discuss.ardupilot.org/t/gsoc-2026-ap-swarmmesh-resilient-mavlink-ad-hoc-swarm-networking-for-ardupilot/144105)

---

## 1. Background

Swarm coordination in ArduPilot has historically been centralized: a GCS holds a link to every vehicle and coordination happens on the ground. That has a single point of failure, needs external computation, and is finitely scalable.

The goal is that each vehicle carries enough of the swarm's state to make its own decisions:

- **Peer state table** — a bounded table of every peer's identity stored in memory, with kinematics, vehicle state and coordination state, updated as packets arrive.
- **Peer stream** — a user-configurable set of MAVLink messages broadcast to the swarm, rate-limited per hardware class.
- **Peer frame header** — a fixed 23 byte routing header carrying everything needed to deduplicate, expire and forward a packet without parsing its payload.
- **Logging and snapshots** — received peer telemetry written to the dataflash log, and the peer table snapshotted to the SD card against reboots.

---

## 2. Architecture

```
                 ┌──────────────────────────────────────────────┐
   Lua script ──▶│  AP_SwarmMesh          (frontend, singleton) │
   Companion  ──▶│    • peer_state[] table                      │
                 │    • parameters, pruning, snapshots          │
                 │    • get_peer_location() / _velocity_NED()   │
                 │    • set_coord_state() / get_peer_coord_state│
                 └───────────────────┬──────────────────────────┘
                                     │
                 ┌───────────────────▼──────────────────────────┐
                 │  AP_SwarmMesh_Backend                        │
                 │    • RX: parse_byte() → process_packet()     │
                 │    • TX: stream buckets → send_mavlink()     │
                 │    • dedup, freshness, TTL, forwarding       │
                 └───┬────────────────┬───────────────┬─────────┘
                     │                │               │
        ┌────────────▼───────┐ ┌──────▼───────┐ ┌─────▼──────────────┐
        │ _Serial            │ │ _SITL        │ │ _Syslink           │
        │ UART → P2P radio   │ │ UDP multicast│ │ nRF51 broadcast    │
        └────────────────────┘ └──────────────┘ └────────────────────┘
```

Everything protocol related lives in `AP_SwarmMesh_Backend`. A transport implements five virtual methods — `transport_ready / available / read / txspace/ write`. Adding a new radio means writing those five methods.

**On ArduSwarm the mesh rides `AP_SwarmMesh_Syslink`**, which sends each packet as one nRF51 P2P broadcast (up to 251 bytes, immediate, unacked, never split). It is modelled on `AP_SwarmMesh_SITL` rather than `_Serial`, because syslink broadcast is a datagram medium like UDP multicast, not a byte stream. A `ByteBuffer` decouples the syslink thread from the parser thread so whole datagrams are dropped rather than partially written, so a full buffer never injects a truncated frame.

### Wire format

A fixed 23 byte header followed by an unmodified MAVLink frame:

| Field | Type | Purpose |
|---|---|---|
| `stx1`, `stx2` | `uint8_t` ×2 | Sync bytes `0xAD 0xBC` |
| `version` | `uint8_t` | Header version (1); mismatches dropped |
| `type` | `uint8_t` | Payload type; `0` = MAVLink |
| `flags` | `uint8_t` | Bit 0 (`SWARMMESH_NO_RTC`): sender had no GPS synced clock |
| `origin_id` | `uint8_t` | System ID of the node that created the packet |
| `dest_id` | `uint8_t` | `0` = broadcast, otherwise targeted |
| `prev_id` | `uint8_t` | System ID of the most recent forwarding node |
| `ttl` | `uint8_t` | Hop budget, decremented on each relay |
| `seq` | `uint16_t` | Per-origin sequence number, for deduplication |
| `origin_time_us` | `uint64_t` | Creation time, GPS UTC microseconds |
| `deadline_ms` | `uint16_t` | Freshness budget; `0` = none |
| `payload_len` | `uint8_t` | Length of the MAVLink frame that follows |
| `crc` | `uint8_t` | Byte sum over `stx1`…`payload_len` |

The header is fixed length and self-validating, so the receive path rejects bad, duplicate, stale or packets not meant for us before handing bytes to the MAVLink parser. The payload keeps its own MAVLink CRC.

### RX pipeline

`process_packet()` applies these in order: version check → self-origin check → peer lookup/allocation (subject to the allowlist) → **deduplication** (32-entry sliding sequence window) → **staleness** → **TTL** → **routing** → **delivery**.

Delivery mirrors the raw frame to `P2P_FWD_PORT` if set, then feeds it to a MAVLink parser, and each decoded message updates the peer entry.

---

## 3. Design decisions worth understanding

### Freshness is per message type, not per peer

The first design had a single `last_heard` per peer. The 1 Hz heartbeat then kept a peer marked "fresh" while its position was tens of seconds old. In the leader-follower experiment this showed up as followers flying to where the leader used to be, while reporting a fresh leader the whole time.

`PeerState` now carries `last_heard_ms[]` and a `freshness` bitmask, one bit per tracked message type, with per type budgets:

| Type | Budget | Type | Budget |
|---|---|---|---|
| `HEARTBEAT` | 3 s | `EXTENDED_SYS_STATE` | 5 s |
| `SYS_STATUS` | 3 s | `ATTITUDE` | 2 s |
| `GLOBAL_POSITION_INT` | 10 s | `EKF_STATUS_REPORT` | 5 s |
| `LOCAL_POSITION_NED` | 2 s | `SCALED_IMU` | 2 s |
| `POSITION_TARGET_GLOBAL_INT` | 3 s | `COORDINATION` | 3 s |

Accessors gate on the right bit. `freshness == 0` means the peer is dead, and pruning removes it.

### Broadcast is single hop; only directed traffic is relayed

Deliberate. The primary mode is state dissemination over a shared broadcast medium where every node already hears every other node in range — relaying broadcasts would multiply the offered load by the swarm size.

Multi-hop is an additional feature: address a packet to a specific `dest_id` and intermediate nodes relay it. With *N* nodes in range a directed packet produces up to *N-1* relays, so keep `P2P_TTL` small for directed traffic.

### `deadline_ms == 0` means no budget

Originally zero meant "expires immediately", so a packet was stale the instant the receiver's clock read ahead of the sender's. Since every vehicle boots with a slightly different clock, this silently partitioned the mesh by boot order.

The check additionally requires both ends to have a GPS RTC. GPS UTC is the only clock shared across the mesh. As a result the check is effectively inert currently. It is infrastructure for latency-sensitive traffic a future sender opts into.

### Memory scales with the board

`sizeof(PeerState)` is ~168 bytes, and the table is allocated statically at its compile time max. `P2P_SWARM_SIZE` bounds how many entries are used, but does not reduce the footprint.

| `HAL_MEM_CLASS` | Max peers | Table size |
|---|---:|---:|
| ≥ 1000 (H7, SITL, Linux) | 255 | ~43 KB |
| ≥ 500 | 128 | ~21 KB |
| ≥ 300 | 64 | ~11 KB |
| ≥ 192 | 18 | ~3 KB |
| below | 8 | ~1.3 KB |

**On the Crazyflie's F4 the table holds 18 peers**, filled first come first serve, which on a busy channel may not be the 18 you want. Pin them with the `P2P_PEER_XX` allowlist. F4 boards are also forced to the Lite 10 Hz cap regardless of `P2P_HW_MASK`.

---

## 4. The bandwidth rule

> **Broadcast only what the swarm actually consumes.**

Every node's transmissions are received and parsed by every other node, so total mesh load grows as *N* × *N* × rate.

At 40 followers, leaving each follower's position stream on at 2 Hz pushed formation error from **0.81 m to ~27 m**, with followers freezing and snapping. At 254 nodes it was 0.87 m versus 19 m. Silencing one unused stream was a 22× improvement.

The default for every `P2P_SR_*` parameter is therefore `0`. Turn on one stream, confirm you need it, then consider the next.

A mesh packet is 23 bytes of header plus the MAVLink frame:

| Message | On the wire |
|---|---:|
| `HEARTBEAT` | ~46 B |
| `GLOBAL_POSITION_INT` | ~65 B |
| `LOCAL_POSITION_NED` | ~65 B |
| `POSITION` bucket tick (both) | ~130 B |

```
bytes/s ≈ N_transmitting × Σ(bucket_rate_hz × bucket_bytes) + N_nodes × 46
```

On a 57600 baud link (~5.7 kB/s usable):

| Swarm | Streams on | Load | Verdict |
|---|---|---:|---|
| 5 nodes, leader only | position @ 2 Hz | ~0.5 kB/s | comfortable |
| 5 nodes, all broadcasting | position @ 2 Hz | ~1.5 kB/s | fine |
| 10 nodes, all broadcasting | position @ 2 Hz | ~3.1 kB/s | near the limit |
| 10 nodes, all broadcasting | position @ 5 Hz | ~7.0 kB/s | over budget |
| 20 nodes, all broadcasting | position @ 5 Hz | ~13.9 kB/s | far over budget |

Plan for single digit vehicle counts with one or two streams, and lean on `P2P_DESTID` and asymmetric rates so only the nodes whose state is consumed transmit it.

---

## 5. Parameters

| Parameter | Default | Meaning |
|---|---:|---|
| `P2P_TYPE` | 0 | Backend. `0` = off, `1` = Serial, `2` = Syslink, `10` = SITL multicast |
| `P2P_SR_POSITION` | 0 | Hz — `GLOBAL_POSITION_INT`, `LOCAL_POSITION_NED` |
| `P2P_SR_EXT_STAT` | 0 | Hz — `SYS_STATUS`, `NAV_CONTROLLER_OUTPUT`, `POSITION_TARGET_GLOBAL_INT` |
| `P2P_SR_EXTRA1` | 0 | Hz — `ATTITUDE`, `EKF_STATUS_REPORT`, `SCALED_IMU`, `EXTENDED_SYS_STATE` |
| `P2P_SR_COORD` | 0 | Hz — the coordination basket |
| `P2P_SWARM_SIZE` | 0 | Max peer entries used. `0` = the board's compile-time max |
| `P2P_DESTID` | 0 | Destination for our streams. `0` = broadcast |
| `P2P_TTL` | 255 | Hop budget stamped on our packets |
| `P2P_HW_MASK` | 0 | Bit 0 = Full radio (200 Hz cap). Clear = Lite (10 Hz cap) |
| `P2P_LOG_HZ` | 50 | Combined RX dataflash write rate. `0` disables |
| `P2P_LOG_MASK` | 0x3FF | Which RX message types are logged |
| `P2P_SAVE_HZ` | 1 | Peer snapshot rate to `/APM/PEERS/peers.dat` |
| `P2P_PRUNE_SECS` | 10 | Stale entry prune interval |
| `P2P_PEER_01`…`_16` | 0 | Neighbourhood allowlist. All zero = accept any peer |
| `P2P_FWD_PORT` | -1 | Serial port to mirror received peer MAVLink to |

On ArduSwarm, set `P2P_TYPE = 2` for the syslink backend. On a generic ArduPilot vehicle with a UART radio, `P2P_TYPE = 1` and `SERIALn_PROTOCOL = 51`.

> Protocol 51 is not yet in the `SERIALn_PROTOCOL` parameter metadata, so most GCS dropdowns will not offer it by name. Set the raw value.

---

## 6. Consuming the peer table

### From Lua

`libraries/AP_Scripting/applets/swarm_follower.lua` is a complete worked example.

```lua
local leader = 1
local loc = swarm:get_peer_location(leader)      -- nil if unknown or stale
local vel = swarm:get_peer_velocity_NED(leader)
local age = swarm:get_peer_position_last_update_ms(leader)
local n   = swarm:count()
local sid = swarm:get_peer_sysid(0)              -- iterate by index
```

Accessors return `nil` rather than a stale value, so a script should cache the last good fix and fly it for a bounded hold time rather than dropping out of formation on a single missed update. Using the peer's velocity as feedforward cut steady state lag against a moving leader from ~1.4 m to ~0.17 m.

### Coordination state

The library carries `role`, `task_id`, `formation_slot`, `priority`, target position/velocity/accel, and up to 32 opaque user bytes it never interprets.

```lua
local state = SwarmCoordState()
state:role(2)
state:formation_slot(3)
state:user(0, 1)
state:user_len(1)
swarm:set_coord_state(state)
```

The basket travels as a MAVLink `TUNNEL` message, which is what makes it work from both directions: a Lua script publishes via `set_coord_state()`, and a companion computer publishes by sending the same `TUNNEL` over its ordinary telemetry link. Published state is rebroadcast at `P2P_SR_COORD` until replaced, so call it only when something changes. Nothing is transmitted until the first call.

> The coordination `TUNNEL` payload type is currently `32768`, in the experimental range.

### From a companion computer

Set `P2P_FWD_PORT`. Every accepted peer frame is written out unmodified, preserving each peer's sysid, compid, sequence and CRC, so the companion's parser sees the swarm as an ordinary multi-vehicle MAVLink stream. There is nothing to decode. See the [AI Deck Guide](ai_deck.md).

### AP_LocationDB

Every received `GLOBAL_POSITION_INT` is also pushed into `AP_LocationDB` under a MAVLink domain key, making mesh peers visible to any LocationDB consumer (following, tracking, avoidance) without those consumers knowing about the mesh. Items are dropped if the vehicle has no EKF origin.

---

## 7. Checking it works

`SMST` in the dataflash log carries the backend counters — `CRCFail`, `Stale`, `TTL`, `Dedup`, `Drop`, `TXseq`, `TXfwd`, `TXdrop`.

- Healthy: `TXseq` climbing, `TXdrop` near zero, low `CRCFail`.
- Rising `TXdrop`: the radio cannot keep up with your stream rates.
- Rising `CRCFail`: line noise or a baud mismatch.

Received peer telemetry is logged as `SMHB` (heartbeat), `SMSS` (sys status), `SMGP` (global position), `SMLP` (local position), `SMPT` (position target), `SMES` (extended sys state), `SMAT` (attitude), `SMEK` (EKF status), `SMIM` (scaled IMU), `SMCO` (coordination).

---

## 8. Limitations

In rough order of how likely they are to bite:

1. **Bandwidth is the binding constraint on hardware.** Everything else is downstream of this.
2. **No delivery guarantee.** No ACK/NACK, no retransmission, no way to know whether a critical message arrived.
3. **Broadcast is single hop.** A node out of direct range wont see a broadcaster's table.
4. **Relay is not routed.** Every node that hears a directed packet relays its first copy. Keep `P2P_TTL` low.
5. **No authentication or encryption.** Any node on the channel can inject packets under any `origin_id`. Do not deploy on a shared or contested channel.
6. **Peer allocation is first come, first serve.** Once full, new peers are rejected until pruning frees a slot.
7. **Copter only.** Other vehicles need scheduler/init/parameter integration.
8. **The staleness mechanism is inert.** All stock streams send `deadline_ms = 0` and the check needs GPS UTC on both ends.
9. **One SwarmMesh swarm per host in SITL.** The multicast group and port are fixed.
10. **Snapshot writes are not atomic.** Power loss mid write leaves a partial file, rejected on the next boot.

---

## 9. Testing status

| Layer | SITL | Hardware |
|---|---|---|
| Framing, CRC, parser | ✅ up to 254 nodes | ✅ |
| Dedup, TTL, relay | ✅ | ✅ |
| Peer table, freshness, pruning | ✅ | ✅ |
| Broadcast dissemination | ✅ 0.87 m median error @ 253 followers | ✅ |
| Lua bindings, formation control | ✅ | ✅ |
| Coordination `TUNNEL` basket | ✅ | ✅ two vehicle coordinated trajectory |
| `P2P_FWD_PORT` forwarding | ✅ | ✅ |
| `AP_LocationDB` publishing | ✅ autotest | ⚠️ not hardware tested |
| `AP_SwarmMesh_Serial` (UART) | n/a | ❌ untested |

### SITL results

Leader flying a box trajectory, followers holding a phyllotaxis formation:

| Followers | Armed & airborne | Tracking a moving leader | Median formation error |
|---:|---:|---:|---:|
| 40 | 100% | 100% | **0.36 m** |
| 253 | 253 / 254 | 236 / 252 (94%) | **0.87 m** (p90 5.3 m) |

40 Follower Experiment: https://kwakurichter.github.io/ardupilot_gsoc/formation-40-followers.html

253 Follower Experiment: https://kwakurichter.github.io/ardupilot_gsoc/formation-253-followers.html

A separate glyph formation experiment (57 instances spelling `GSoC`, with onboard CBF separation filtering) held 56/56 cells at a median 0.02 m cell error with zero sampled separations below 1 m across 15 million pair samples.

GSoC Speller Experiment: https://kwakurichter.github.io/ardupilot_gsoc/gsoc-to-cosg-replay.html

GSoC -> CoSG Speller Experiment: https://kwakurichter.github.io/ardupilot_gsoc/gsoc-swarm-replay.html

### Hardware validation

AP_SwarmMesh has flown on ArduSwarm v2.1.1, a leader-follower and a two vehicle coordinated trajectory driven by exchanged coordination baskets - see [placeholder].

---

## See also

- [AP_Syslink](ap_syslink.md) — the broadcast transport this rides on
- [Identity](identity.md) — `MAV_SYSID` as the mesh identity
- [AI Deck](ai_deck.md) — consuming the peer stream on a companion computer