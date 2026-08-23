# AI Deck — Companion Computer Integration

How to consume swarm and ranging data on the Bitcraze AI deck (or any companion computer on the serial link).

A Crazyflie runs two independent peer-to-peer systems. [AP_SwarmMesh](ap_swarmmesh.md) shares MAVLink state between vehicles over the nRF51 radio. [AP_Ranging](ap_ranging.md) measures UWB distances to peers using the DWM1000 Loco deck. Both forward to a companion computer over a normal MAVLink serial link, but they use different mechanisms.

---

## 1. Wiring

The Ai Deck connects to **USART3** (PC10 TX / PC11 RX), which this board's `SERIAL_ORDER` maps to **`SERIAL1` — not `SERIAL3`.**

| Port | Peripheral | Use |
|---|---|---|
| `SERIAL0` | OTG1 | USB |
| `SERIAL1` | USART3 | **Ai Deck** |
| `SERIAL2` | USART6 | nRF51 radio ([AP_Syslink](ap_syslink.md)) |
| `SERIAL3` | USART2 | expansion header E_TX2 / E_RX2 |

### Required parameters

| Parameter | Value | Why |
|---|---|---|
| `SERIAL1_PROTOCOL` | `2` | MAVLink2 on the Ai Deck port |
| `P2P_FWD_PORT` | `1` | forward SwarmMesh peers there |
| `RNG_FWD_PORT` | `1` | forward UWB ranges there |
| `MAV_SYSID` | unique per vehicle | the single identity |
| `P2P_TYPE` | `2` | SwarmMesh over syslink |
| `RNG_TYPE` | `1` | DW1000 |
| `RNG_PEER_1..4` | peers' `MAV_SYSID` | who to range against |
| `SERIAL2_PROTOCOL` | `52` | Syslink |

Forwarding is driven from each library's `update()`, not from its logging path, so it does not stop when `LOG_BITMASK` is trimmed. It is independent of whether logging is enabled at all.

---

## 2. Transport 1 — SwarmMesh peers, as ordinary MAVLink

Set `P2P_FWD_PORT` to the companion port number.

Received peer frames are forwarded unmodified. Each peer appears to the Ai Deck as a separate MAVLink system, identified by that peer's `MAV_SYSID`, carrying stock messages: `HEARTBEAT`, `GLOBAL_POSITION_INT`, `ATTITUDE`, `SYS_STATUS`, etc.

**There is nothing to decode.** Point any MAVLink library at the port and treat it as a multi-vehicle stream. Route by `sysid` as normal.

---

## 3. Transport 2 — UWB ranges, as MAVLink TUNNEL

Set `RNG_FWD_PORT`. The peer table is sent at **10 Hz** as `TUNNEL` (message id **385**) with `payload_type = 220`. The payload is 36 bytes of the 128 available.

```c
struct __attribute__((packed)) PeerSlot {
    uint8_t slot;        // stable slot index, 0..3
    uint8_t peer_id;     // peer's MAV_SYSID; 0 when the slot is unused
    uint8_t healthy;     // 1 if this range is recent, else 0
    uint8_t reserved;
    float   range_m;     // metres, little endian
};

struct __attribute__((packed)) RangingPayload {
    uint8_t  version;    // currently 1
    uint8_t  node_id;    // this vehicle's MAV_SYSID
    uint8_t  count;      // slots populated
    uint8_t  reserved;
    PeerSlot peer[4];
};
```

Rules for consuming it:

- **Check `version` first.** Anything other than 1 means the layout changed.
- **Use `slot`, not array position.** A node keeps its slot for the life of the vehicle, which is what lets you difference a range over time. The explicit index stays correct if the payload is ever reordered or truncated.
- **Check `healthy` before using `range_m`.** An unhealthy slot holds the last measured value, not a current one. A range is stale after 300 ms, and a stale entry is otherwise indistinguishable from a fresh one.
- **Ignore slots where `peer_id == 0`.**

> `payload_type` 220 is unregistered. The `MAV_TUNNEL_PAYLOAD_TYPE` vendor range 200–212 is allocated to STORM32 and ModalAI; 220 is merely unused today and could collide if the enum is extended. Filter on it, but do not assume exclusivity.

---

## 4. Joining the two streams

Because both transports key on `MAV_SYSID`, a range and a peer's state are the same vehicle with no lookup table:

```python
# peer state from transport 1, ranges from transport 2
peers[msg.get_srcSystem()] = msg                 # SwarmMesh: ordinary MAVLink
for slot in ranging_payload.peer:                # TUNNEL 385 / type 220
    if slot.peer_id and slot.healthy:
        distance_to[slot.peer_id] = slot.range_m
```

A `peer_id` appearing in the ranging payload with no corresponding MAVLink system simply means that vehicle is in UWB range but its radio traffic is not reaching you.

See [Identity](identity.md) for why this works.

---

## 5. Publishing coordination state

A companion computer can drive the swarm, not just observe it. Send a coordination `TUNNEL` over the ordinary telemetry link and `GCS_MAVLink` routes it into the mesh, where it is rebroadcast at `P2P_SR_COORD` until replaced.

The basket carries `role`, `task_id`, `formation_slot`, `priority`, target position/velocity/accel, and up to 32 opaque user bytes the library never interprets. Received baskets come back out through `P2P_FWD_PORT` unmodified.

Vehicles built with different user byte limits are compatible — a receiver keeps what fits and reports how much it kept in `user_len`.

The same interface is available to onboard Lua scripts; see [AP_SwarmMesh](ap_swarmmesh.md#6-consuming-the-peer-table).

---

## 6. Available AI deck firmware

The [aideck-firmware-cus](https://github.com/kwakurichter/aideck-firmware-cus) submodule provides the GAP8 applications. Pre built images ship on the [Releases page](https://github.com/kwakurichter/ArduSwarm/releases):

| Image | Behaviour |
|---|---|
| `aideck-swarm_coordinated.img` | Coordinated swarm flight |
| `aideck-swarm_cross.img` | Cross formation manoeuvre |
| `aideck-swarm_guided_takeoff.img` | Synchronized GUIDED mode takeoff |
| `aideck-swarm_leader_follower.img` | One drone leads, the others follow |

Flashing is covered in the [Companion Computer Guide](../companion_computer_guide.md).

---

## 7. Constraints worth knowing before debugging

**UWB ranging polls only the configured roster.** `RNG_PEER_1..4` must hold the peers' `MAV_SYSID`s. An empty roster is not an error and produces no warning: the vehicle simply never polls anyone and every slot stays unused. The roster caps at 4 peers, so in a larger swarm which four you range is a deliberate choice.

**The Loco deck and the AI deck contend for pins.** `DW1000_IRQ` is on PB5 specifically so that PC10/PC11 stay available for USART3. The Loco deck gives up `E_CS2` instead.

**The nRF51 broadcast payload is 251 bytes.** SwarmMesh packets larger than that are refused and counted, never fragmented. In practice its MAVLink traffic is around 50 bytes.

**This board is CPU and bus constrained.** It is a 1 MB F405 whose IMU is on I2C and whose SD card, optical flow sensor and Loco deck all share SPI1. Broad `LOG_BITMASK` settings measurably reduce the main loop rate. Prefer `LOG_FILE_RATEMAX` / `LOG_DARM_RATEMAX` over disabling subsystems.

---

## 8. Cross checking against onboard logs

| Message | Contents |
|---|---|
| `TWR` | UWB peer table: per slot id, range, health |
| `SWSL` | SwarmMesh syslink transport counters |
| `SMST` | SwarmMesh backend counters |
| `SYSL` | Radio link statistics |

`TWR` and `RFND` both require the CTUN bit (bit 4) in `LOG_BITMASK`.

## See also

- [AP_SwarmMesh](ap_swarmmesh.md) · [AP_Ranging](ap_ranging.md) · [Identity](identity.md)
- [Companion Computer Guide](../companion_computer_guide.md) — flashing the AI deck
