# AP_Ranging — UWB Peer Ranging

`AP_Ranging` measures the distance between flying nodes using ultra-wideband (UWB) Two Way Ranging (TWR) on the Bitcraze Loco Positioning Deck (a Decawave DW1000 radio) on a Crazyflie 2.x.

Unlike a fixed-anchor positioning system (`AP_Beacon`), every node is mobile and the library reports the raw range to each peer. It does not solve for absolute position; a downstream consumer (EKF, relative position controller, or companion computer) is expected to use the ranges.

- **Library:** `libraries/AP_Ranging/` in [ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus)
- **Parameter prefix:** `RNG_`
- **Status:** working end-to-end on hardware. Antenna delay needs calibration for metric accuracy.

---

## 1. Hardware

Requires a [Loco Positioning Deck](https://www.bitcraze.io/products/loco-positioning-deck/) on each drone you want to range between. No anchors are required, this is peer-to-peer ranging, not anchor positioning, so there is no Loco Positioning System to install or survey.

| Item | Detail |
|---|---|
| Board | `crazyflie2` / `crazyflie2_bl` (STM32F405, ChibiOS) |
| Bus | **SPI1**, shared with the Flow deck and SD card |
| DW1000 CS | `E_CS3` / PB8, MODE0, 2 MHz low / 20 MHz high |
| DW1000 IRQ | **PB5**, `GPIO(60)`, polled as a GPIO flag |
| DW1000 RESET | **not wired** — libdw1000 falls back to an SPI soft reset |

**PB5 was the spare deck CS `E_CS2`.** Repurposing it for the IRQ avoids sacrificing the USART3 telemetry port. An earlier design used PC11 and had to drop USART3, which was reverted. The Loco deck gives up `E_CS2` instead. That is the pin contention to be aware of when also fitting the AI deck.

The upstream DW1000 driver is a submodule at `modules/libdw1000`. Its nested `vendor/unity` and `vendor/cmock` submodules are test only, don't `git submodule update --init --recursive` that one.

---

## 2. The algorithm — Alternative DS-TWR

Decawave APS013 "Alternative Double-Sided Two-Way Ranging", equation 17:

```
Tf = (Ra*Rb - Da*Db) / (Ra + Da + Rb + Db)
distance_m = Tf_ticks * 0.00469176        // metres per DW1000 tick
```

Two nodes exchange a timed sequence of messages, each recording precise transmit and receive timestamps. The distance is calculated from the time of flight.

**Why double sided?** Every node's clock runs at a slightly different rate, and in single sided ranging that offset maps directly into a distance error. Having both nodes contribute timing information largely cancels the relative clock drift, without requiring the radios to be synchronized.

**Why the *alternative* form?** It tolerates arbitrary, asymmetric reply delays, unlike symmetric DS-TWR. The reply delays only need to be known (which they are, via delayed TX) not equal.

### The three message exchange

Frame format `[type, src, dst, seq, <payload>]`, where src/dst are `MAV_SYSID`s:

1. **A → POLL** (`0xC1`). A captures `poll_tx`.
2. B receives (`poll_rx`) → **B → RESPONSE** (`0xC2`), captures `resp_tx`.
3. A receives (`resp_rx`) → **A → FINAL** (`0xC3`) carrying A's three timestamps (3 × 40-bit).
4. B receives (`final_rx`), now holds all six timestamps → computes the range.

`Ra = resp_rx - poll_tx`, `Da = final_tx - resp_rx` (A's);
`Db = resp_tx - poll_rx`, `Rb = final_rx - resp_tx` (B's).

All differences masked `& 0xFFFFFFFFFF` for 40 bit wrap, products in `uint64`, division in `double`.

The responder computes, and there is no report back message. The responder receives last and holds all six timestamps, so a node's stored ranges come from responding to its peers' polls. Because every node polls every peer round-robin and answers incoming polls, everyone ends up with all ranges with no fourth message.

**Timestamp mechanics.** All three transmits use `dwSetDelay()` (scheduled TX), which returns the antenna-delay corrected TX timestamp before sending, so `final_tx` can be embedded in the FINAL frame. `dwSetDelay()` requires the device to already be in TX mode, so the call order is fixed:

```
dwNewTransmit → dwSetDelay → dwSetData → dwWaitForResponse → dwStartTransmit
```

---

## 3. Architecture

Standard ArduPilot frontend/backend singleton, derived from `AP_Beacon` with the fixed anchor positioning, fence/trilateration and vendor UART backends stripped out.

| Component | Role |
|---|---|
| `AP_Ranging` | Frontend: params, `NodeState[]` table, public API, logging, TUNNEL forwarding |
| `AP_Ranging_Backend` | Abstract base: param accessors, `set_node_distance()` |
| `AP_Ranging_DW1000` | SPI transport, radio config, DS-TWR state machine |

**Data model.** `NodeState { id, healthy, distance, distance_update_ms }`, one per peer, in a fixed array of `AP_RANGING_MAX_NODES` (4). `set_node_distance()` assigns each peer id a stable slot on first sight and never reassigns it, so log columns and TUNNEL slot indices refer to the same peer for the life of the vehicle. `node_healthy(i)` enforces a 300 ms timeout, so a stale peer auto drops.

**Node identity.** A node's own id is its **`MAV_SYSID`**. Peers are an explicit roster: `RNG_PEER_1..4`. There is no separate node id parameter — see [Identity](identity.md).

> **Friendship is not inherited.** `AP_Ranging` declares `friend class AP_Ranging_Backend`, but the concrete `AP_Ranging_DW1000` subclass cannot touch frontend privates. All param access goes through the base's `get_*()` accessors.

---

## 4. Parameters

Index gaps (1, 3) are retired parameters, do not reuse those indices.

| Param | Default | Applies | Meaning |
|---|---:|---|---|
| `RNG_TYPE` | 0 | reboot | 0 = None, 1 = DW1000 |
| `RNG_DEBUG` | 0 | live | 1 = verbose GCS report |
| `RNG_PEER_1..4` | 0 | live | peer `MAV_SYSID`s to range against (0 = unused) |
| `RNG_ANT_DLY` | 16384 | **reboot** | antenna delay calibration |
| `RNG_POLL_MS` | 50 | live | base poll cadence (jitter added) |
| `RNG_CHAN` | 2 | **reboot** | UWB channel; all nodes must match |
| `RNG_REPLY_US` | 3000 | live | TWR reply delay |
| `RNG_XCHG_MS` | 30 | live | stalled exchange timeout |
| `RNG_FWD_PORT` | -1 | live | serial port to forward the peer table on |

`RNG_ANT_DLY` and `RNG_CHAN` are applied in `configure_radio()`, which is why they need a reboot. `dwSetAntenaDelay()` only sets a struct field which takes effect at `dwCommitConfiguration`.

### Antenna delay calibration

This is the single most important parameter for accuracy. It compensates for the fixed delay between radio and antenna, in DW1000 device time units of roughly 15.65 ps each.

1. Place two nodes an accurately known distance apart.
2. Read the reported range with `RNG_DEBUG=1`.
3. Adjust `RNG_ANT_DLY`. **Increase to reduce the reading** and reboot.
4. Iterate. Set it on **both** nodes.

`0` gives a large offset (~155 m was observed); `16384` is the typical DWM1000 starting value. An uncalibrated delay shows up as a constant offset across the whole range, so one calibration at a known distance corrects everything.

---

## 5. Important implementation details

**IRQ gated servicing.** `service_radio()` calls `dwHandleInterrupt()` only when the IRQ pin is asserted. Earlier code blindly polled at 1 kHz, which hammered `SYS_STATUS` mid-reception and returned intermittent `0xFFFFFFFF` ("SPI busy") reads that wrecked reception. Gating on the IRQ line fixed it.

This is a polled flag and not a hardware ISR as SPI cannot run in an ISR. The polling rate must stay well inside `RNG_REPLY_US` (3000 µs default), which is why it is 300 µs.

Init fails loudly if `HAL_DW1000_IRQ_PIN` is absent from the hwdef, because `GPIO::read()` returns 0 for unmapped pins (indistinguishable from "no interrupt", which would make the driver silently fail).

**Poll jitter.** `_poll_interval = RNG_POLL_MS + get_random16() % POLL_JITTER_MS`. Two nodes on a fixed period boot in phase and livelock: each polls while the other is mid-exchange, so both drop the incoming POLL and time out forever. The range freezes while `xfail` climbs at the poll rate. Random jitter drifts them apart. Do not remove it.

**One exchange at a time.** A single half-duplex radio means a state machine (`IDLE / I_WAIT_RESP / I_SENDING_FINAL / R_WAIT_FINAL`) with one set of exchange variables. Frames arriving mid-exchange, or not addressed to us, are dropped and RX rearmed. Stalls recover via the `RNG_XCHG_MS` timeout and retry. Matching is by `(src == _peer && seq == _seq)`.

**Range sanity gate.** Results outside (-1 m, 1000 m) are rejected.

**Never take the address of a packed struct member.** It can be unaligned on ARM. Fill locals, then assign fields by value.

---

## 6. Outputs

### Onboard log — `TWR`

`TimeUS, Cnt, Hlth, ID0..ID3, D0..D3`. `Hlth` is a per node health bitmask (bit *i* = slot *i* has a recent range). `Dn` is the raw last range for slot *n* and is not zeroed when stale. Gate on `Hlth`.

`TWR` requires the CTUN bit (bit 4) in `LOG_BITMASK`.

### MAVLink TUNNEL forwarding

If `RNG_FWD_PORT >= 0`, the peer table is sent at 10 Hz as `TUNNEL` (message id 385) with `payload_type = 220`.

```c
struct __attribute__((packed)) PeerSlot {
    uint8_t slot;        // stable slot index, 0..3
    uint8_t peer_id;     // peer's MAV_SYSID; 0 when unused
    uint8_t healthy;     // 1 if this range is recent
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

TUNNEL was chosen over a custom message (a fork cannot extend the common dialect cleanly) and over `DISTANCE_SENSOR` (which ArduPilot would consume as an obstacle).

> `payload_type` 220 is unregistered. The vendor range 200–212 is allocated to STORM32 and ModalAI. 220 is unused today and could collide if the enum is extended. Filter on it, but do not assume exclusivity.

Forwarding is driven from `update()`, deliberately not the logging path, so it survives `LOG_BITMASK` being trimmed.

See the [AI Deck Guide](ai_deck.md) for consuming it.

---

## 7. Debugging

`RNG_DEBUG=1` gives a 5 second GCS report:

```
DW1000: rng=<ranges> rx=<frames> tx=<frames> irq=<IRQ assertions>
DW1000: xfail=<exchange timeouts> rxfail=<CRC/PHY errs> | <peer>=<dist>m
```

| Symptom | Cause | Fix |
|---|---|---|
| `id=0x00000000` at detect | DW1000 held in reset / not woken | check wiring and power |
| Detect ok, `rx=0`, `sys=0xFFFFFFFF` | blind polling → SPI-busy reads | IRQ-gated servicing (§5) |
| `good` climbs but `ok=0` | frames decode but are filtered | peers share a `MAV_SYSID`, or wrong `RNG_PEER_n` |
| Range freezes, `xfail ≈ tx` | mutual poll livelock | poll jitter (§5) |
| `irq=0` | IRQ pin not wired / mask not enabled | check PB5 / `GPIO(60)` in hwdef |

Note: An empty roster is not an error and produces no warning. The vehicle simply never polls anyone and every slot stays unused.

---

## 8. Known issues

- **SD card vs DW1000 SPI1 contention.** Both share SPI1 and the DW1000 periodic callback occupies the bus thread. If the SD card stops mounting, test with `RNG_TYPE=0`. Mitigations: `BRD_SD_SLOWDOWN`, lowering the callback rate.
- **Roster caps at 4 peers.**
- **Collision efficiency above 2 nodes.** An initiator currently drops an incoming POLL while mid-exchange. Letting it abandon its own poll to answer would cut collisions (not implemented).
- **Nothing in flight consumes the ranges yet.** No EKF or relative position fusion. That is the natural next milestone.

---

## See also

- [Identity](identity.md) — why `MAV_SYSID` is the UWB node id
- [AI Deck](ai_deck.md) — consuming ranges on a companion computer
- [AP_SwarmMesh](ap_swarmmesh.md) — joining ranges to peer state
