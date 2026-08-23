# AP_Syslink — nRF51 Radio Driver

`AP_Syslink` is the ArduPilot driver for the Crazyflie's nRF51822 radio co-processor. It turns the nRF51 into a transparent MAVLink pipe so ArduPilot can talk to a ground station and to its peers, without the nRF51 needing to understand any of it.

- **Library:** `libraries/AP_Syslink/` in [ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus)
- **Parameter prefix:** `SYSL_`
- **Port:** `SERIAL2` (USART6), 1 Mbaud, `SERIAL2_PROTOCOL = 52`

---

## 1. The system

A Crazyflie 2.x carries two MCUs on one board:

```
  GCS ── USB ── Crazyradio 2.0 ──── 2.4 GHz ESB ──── nRF51822 ── UART ── STM32
                  (nRF52840)                        (radio)     1Mbaud   (ArduPilot)
                                                        │
                                          also: power, button, charging
```

ArduPilot runs on the STM32 and has no radio of its own. The nRF51822 is the radio and is accessed over a UART running a framed protocol called syslink.

Treat the nRF51 as a dumb, lossy link. It does not parse MAVLink, track frame boundaries, reassemble anything, or retry beyond what the radio hardware provides. One syslink packet becomes exactly one radio packet.

### What the driver provides

- A **virtual MAVLink port**, so telemetry, parameter download and log download work over the Crazyradio with no GCS changes.
- An **opaque broadcast transport** — `send_broadcast()`, `set_broadcast_handler()`, `broadcast_max_len()` = **251 bytes** — which is what [AP_SwarmMesh](ap_swarmmesh.md) rides on.
- **Battery and RSSI telemetry** from the nRF51's power management.

---

## 2. Why 252 bytes

The legacy Crazyflie air format caps payloads at 32 bytes, inherited from the nRF24LU1 in the original Crazyradio, whose ESB protocol is hardware limited. A MAVLink v2 frame is typically 20–100 bytes (can reach 280).

The old implementation therefore fragmented every frame on one side and reassembled it on the other, with the nRF51 parsing MAVLink to do it.

However, the nRF51822 was never the constraint. Widening the length field from 6 to 8 bits gives us access to 252 byte payloads, which fits all but the largest frames whole. So the fragmentation layer, the reassembly layer and the vendored MAVLink headers all disappear.

> **6-bit and 8-bit peers cannot decode each other.** The STM32, nRF51 and Crazyradio firmware must all come from the same release.

---

## 3. Syslink framing

Serial, **1 Mbaud, 8N1**.

```
+-----------+------+-----+=============+-----+-----+
|   START   | TYPE | LEN | DATA        |   CKSUM   |
+-----------+------+-----+=============+-----+-----+
```

- `START` — two constant bytes, `0xBC 0xCF`
- `TYPE` — one byte, packet type
- `LEN` — one byte, length of `DATA`
- `CKSUM` — two byte Fletcher-8 over `TYPE`, `LEN` and `DATA` — not the start bytes

```
for each byte b in (TYPE, LEN, DATA...):
    cksum_a = (cksum_a + b)       & 0xFF
    cksum_b = (cksum_b + cksum_a) & 0xFF
```

> **`TYPE` precedes `LEN`, and the checksum excludes the start bytes.** Transposing them yields a well formed frame that never lifts the activation gate and reports no error anywhere.

### MAVLink packet types

| Type | Name | Meaning |
| --- | --- | --- |
| `0x0C` | `SYSLINK_RADIO_MAVLINK` | opaque chunk, 1–251 bytes, unicast to the GCS |
| `0x0D` | `SYSLINK_RADIO_MAVLINK_BROADCAST` | same payload, broadcast to peers |
| `0x0E` | `SYSLINK_RADIO_MAVLINK_SPACE` | free transmit slots, backpressure |

**Unicast and broadcast are concurrent** The radio receives on both addresses at once and picks the transmit address per packet, so telemetry and peer traffic interleave freely in both directions.

On air, one syslink packet becomes exactly one radio packet, with payload `[0xE0][up to 251 bytes]`.

---

## 4. Bring up: the link starts silent

**The nRF51 sends nothing over the UART until the STM32 speaks first.** There are three independent gates:

### Gate 1 — syslink transmit is disabled until a valid packet arrives

`syslinkSend()` on the nRF51 "dead" until an inbound packet has passed both checksum bytes. Until then, no battery data, no RSSI, no MAVLink, no handshake. Any valid packet lifts the gate, and it rearms only when the nRF51 powers the STM32 down, so in normal operation it is a one time handshake.

Send `SYSLINK_RADIO_READY`, zero length:

```
BC CF 0B 00 0B 16
```

**The nRF51 echoes the identical frame back.** That echo is definitive proof that the serial link, baud rate, framing and checksum are all correct.

### Gate 2 — battery *and* RSSI both need enabling

```
BC CF 14 00 14 28
```

The periodic RSSI report is emitted from inside the same `enableBatteryAutoupdate` check as the battery packet, despite being unrelated to it. Without this packet there is no RSSI either.

### Gate 3 — the radio is deaf for the first 3 seconds

After boot the nRF51 does not receive on the air until either the STM32 sends `SYSLINK_RADIO_READY` or a 3 second timeout expires. This gates radio reception only — it is not what keeps the UART quiet, and waiting it out will not start the flow.

### Boot sequence

1. `BC CF 0B 00 0B 16` — activate syslink and the radio. Expect the echo.
2. `BC CF 14 00 14 28` — enable battery and RSSI reporting.
3. Radio configuration if the defaults are wrong: channel (`0x01`), datarate (`0x02`), address (`0x05`). Each is echoed back as confirmation.

After step 1 the nRF51 sends an unsolicited `SYSLINK_RADIO_MAVLINK_SPACE` (`0x0E`, one byte, value 5). It reports on change and starts from an impossible value, so in practice it is the first packet the nRF51 ever sends.

---

## 5. Operating requirements

**Chunks cap at 251 bytes, not 252.** One byte of the payload is the `0xE0` marker that keeps MAVLink traffic from being mistaken for the radio's own control packets. The firmware still matches CRTP control packets on `(data[0] & 0xf3) == 0xf3`, and an arbitrary byte stream can easily start with such a byte. An oversized chunk is dropped, not truncated (losing the tail silently would corrupt a frame in a way the receiver could not detect).

**A MAVLink v2 frame can still exceed one chunk.** 267 bytes unsigned, 280 signed; `FILE_TRANSFER_PROTOCOL` lands near 261, and FTP is how a GCS downloads parameters and logs. Oversized frames are split, and losing either half costs the frame. This is the one place we still fragment.

**Send one whole frame per chunk where it fits.** Nothing enforces frame alignment, but a chunk spanning two frames means one lost packet damages both.

**Use the space report for backpressure, not the flow control pin.** The Crazyflie is a receiver from the radio's point of view, so downlink chunks only leave in ack payloads when the ground station polls. If polling stops, the queue fills and chunks are silently dropped. Usable depth is 5. Track free slots from `SYSLINK_RADIO_MAVLINK_SPACE` and derive `txspace()` from it. Broadcasts do not consume slots.

`NRF_FLOW_CTRL` (PA4) is the nRF51's UART RTS, driven from its UART receive FIFO. The nRF51 keeps draining syslink when the radio queue is full it just discards chunks so that line never asserts for radio backpressure. Both mechanisms are needed: the pin prevents UART overrun, the space report prevents radio queue overflow. The nRF51 drives RTS but has no CTS input, so hardware flow control is one directional.

**The link is lossy.** Unicast retries in hardware but eventually gives up; broadcast has no retry at all. MAVLink tolerates this as the parser resyncs on `STX`. Do not build anything that assumes reliable delivery.

**ArduPilot owns the radio configuration.** The nRF51's compiled defaults (channel 80, address `E7E7E7E7E7`) are not what the radio ends up using. The STM32 pushes stored channel, datarate and address over syslink at boot, and those win. A mismatch looks identical to a packet format failure.

---

## 6. Battery telemetry

`SYSLINK_PM_BATTERY_STATE` (`0x13`) is sent at 100 Hz once enabled with
`SYSLINK_PM_BATTERY_AUTOUPDATE` (`0x14`).

```
+-------+------+------+------+
| FLAGS | VBAT | ISET | TEMP |
+-------+------+------+------+
 1 byte   4       4      4
```

- `FLAGS` — bit0 charging, bit1 USB powered, bit2 can charge
- `VBAT` — float, battery volts
- `ISET` — float, charge current in mA
- `TEMP` — float, nRF51 **die** temperature in °C

**This build is 13 bytes**, with `TEMP` present (`PM_SYSLINK_INCLUDE_TEMP` enabled). Upstream defaults to 9 bytes without it. Accepting both lengths is the robust choice.

`TEMP` is the die sensor, not the battery or ambient, so it reads above room temperature. On boards where `hasCharger` is false it is never sampled and reads a constant 0.

Two nRF51 errata had to be fixed before the value was publishable: `EVENTS_DATARDY` was never cleared, so `TEMP` could be read mid conversion; and negative temperatures were not sign-extended (PAN-28), so anything below zero read as a large positive number.

See the [Battery Monitor Guide](../battery_monitor.md) for the ArduPilot side.

---

## 7. Throughput

The **UART is the bottleneck, not the radio.** At 1 Mbaud the theoretical ceiling is ~100 kB/s, but the nRF51's UART has no DMA, it is a per byte interrupt on a 16 MHz Cortex-M0.

**Budget ~50 kB/s sustained duplex**, and expect the nRF51 main loop to stall ~2.6 ms while forwarding a full size chunk.

The nRF51 radio queues are deliberately asymmetric, `RXQ_LEN 8` (usable 7), `TXQ_LEN 6` (usable 5). RX is deep because its drain side blocks; TX is shallow because it drains only when the ground station polls, and extra depth buys no throughput, only staleness. Stale attitude data is worse than dropped attitude data.

---

## 8. Host tooling

A ground station cannot use `cflib` for this link. Its `Crazyradio.send_packet()` reads the dongle's bulk IN endpoint with a hardcoded 64 byte length and truncates anything larger, regardless of firmware.

Two tools ship in the `nrf-firmware-cus` submodule under `tools/`:

**`crazyradio2_large.py`** — a minimal pyusb driver that requests the full transfer and handles the zero length packet rule in both directions. Run it directly for a self-test sweep from 4 to 252 bytes.

**`mavlink_bridge.py`** — polls one or more vehicles and forwards to a GCS over UDP:

```bash
.venv/bin/python tools/mavlink_bridge.py --udp 127.0.0.1:14550
```

**Polling is structural, not a shortcut.** The Crazyflie is a PRX and can only transmit inside an ack. Every downlink byte is the payload of an ack to something the host sent, which is why the loop transmits continuously and sends a bare `0xE0` marker when it has nothing to say. Downlink latency is bounded by the poll rate, not the radio.

For two vehicles, you can multiplex them onto one dongle:

```bash
--uri radio://0/80/2M/E7E7E7E7E7 --uri radio://0/80/2M/E7E7E7E706
```

A Crazyflie has one radio frequency for everything, so P2P peers must share a channel. Two dongles on one channel collide so ESB has no carrier sense and retries in a tight loop with no backoff, so a 252 byte ack occupying ~1 ms can swallow a whole four attempt retry burst. Multiplexing removes that by construction.

Measured: ~175 polls/s with one vehicle, ~156/s each with two multiplexed. Uplink is routed, not duplicated so each vehicle's system id is learned from downlink, so two vehicles never answer the same parameter or FTP request.

See the [Crazyradio Dongle Guide](../crazyradio_dongle.md) for the dongle side.

---

## 9. Decisions that must not be "fixed"

Each of these looks like an oversight and is not.

**The nRF51 application RAM origin is `0x20000008`.** The nRF51 is a Cortex-M0 with no VTOR, so the vector table cannot be relocated. Nordic works around this by having the MBR catch every interrupt and forward it through a pointer stored at `0x20000000` (the first word of RAM). That word is live whether or not the softdevice is enabled. Linking `.data` over it means the first interrupt after startup jumps into garbage, hanging the first `msDelay()` before the STM32 is ever started. The board looks dead while still showing a solid blue "booting firmware" LED. `sd_softdevice_enable()` must never be called in this build.

**The `0xE0` on air marker is required.** See §5.

**Oversized chunks are dropped, not truncated.** See §5.

**The bootloader stays on the legacy 6-bit format.** It is a separate flash image, deliberately left alone, and that is what keeps OTA recovery working: a stock Crazyradio can always reach the bootloader even when the firmware speaks a format nothing else understands. **MUST** flash the Crazyflie with a stock dongle, not the large packet one.

**`SYSLINK_RADIO_MAVLINK_SPACE` is not redundant with the flow control pin.** See §5.

---

## 10. Debugging

**There is no debug output to look for.** `DEBUG_PRINT` on the nRF51 expands to nothing unless built with `DEBUG_PRINT_ON_SEGGER_RTT`, and even then goes to RTT over SWD, not the UART. Adding a printf path would corrupt syslink since they share the port. Use the gate 1 echo instead.

| Symptom | Likely cause |
|---|---|
| nRF51 completely silent | Gate 1 — send `BC CF 0B 00 0B 16`, expect the echo |
| No RSSI and no battery | Gate 2 — battery autoupdate not enabled |
| Looks like a packet-format failure | Channel/address mismatch; ArduPilot pushes stored config at boot |
| Frames arrive corrupt | 6-bit vs 8-bit format mismatch — check all three firmware versions |
| Transmit stalls under load | Space report ignored; queue full and dropping |

`ESB_MAX_PAYLOAD` is overridable at build time (`make ESB_MAX_PAYLOAD=32`) to drop back to the legacy format, which is useful for bisecting whether a fault is the packet format or something else.

**Count bytes after `_uart->write()`, not before.** Counting queued rather than written bytes once hid a transmit problem in this driver.

Log messages: `SYSL` carries radio link statistics.

---

## 11. Known issues

- **`esbSendBroadcast()` races the receive path.** It hijacks the radio mid cycle rather than going through the TX queue, so it can cut short an in flight receive. Inherited from `esbSendP2PPacket()`, documented in `esb.h`, not fixed. It will matter more as P2P traffic becomes continuous.
- **Idle polls forward as zero length syslink packets** — roughly 6% of the syslink budget. Upstream Bitcraze commit `429e189` handles null CRTP packets in the radio ISR and should be merged.
- **An upstream flags byte change is pending.** Bitcraze `8542609` adds an over temp status flag and changes the flags byte on the wire (`usbPluggedIn` → `powerGood`, new `overTemp` at bit 3). Both this document and the driver need updating when it lands, and it will conflict with the temperature fixes in §6.

---

---
## 12. NRF Firmware edits

The work touches four areas of the stock Bitcraze firmware:

### Syslink layer (`syslink.c` / `syslink.h`)
A buffered send path was added alongside the original blocking one. It assembles the complete Syslink frame — sync bytes, type, length, payload, and Fletcher-8 checksum — into a single buffer and hands it to the non blocking UART writer in one call, instead of writing byte by byte while holding the link.

A new Syslink packet type was also defined to carry MAVLink traffic, so MAVLink telemetry and the existing P2P broadcast types can be distinguished on the same link and demultiplexed by the receiver.

### Serial layer (`uart.c` / `uart.h`)
A dedicated receive buffer stores data arriving from the STM32, decoupling the UART interrupt from packet processing.

The matching send path masks interrupts while a packet is being handled, which prevents the corruption that occurred when a radio event fired mid write. It also tracks whether the link was previously idle, so transmission can be restarted cleanly after a quiet period rather than stalling.

### Main loop (`main.c`)
Radio packets are now stored in their own structure in separate memory rather than sharing the buffer the radio ISR writes into. Together with interrupt masking around the critical section, this removes the race conditions that previously caused intermittent packet loss under sustained traffic.

A dedicated case handles MAVLink data arriving from the GCS over the radio and routes it to the STM32, and the legacy Syslink send calls throughout the loop were switched over to the buffered send path described above.

### Radio layer (`esb.c` / `esb.h`)
A send function wraps outgoing Syslink payloads in a CRTP header before queueing them for radio transmission, which is what allows the GCS to receive them as ordinary CRTP traffic.

---

## See also

- [AP_SwarmMesh](ap_swarmmesh.md) — rides the broadcast transport
- [Crazyradio Dongle Guide](../crazyradio_dongle.md) — the ground-station side
- [Flashing the NRF Guide](../flashing_the_nrf.md) — building and flashing the nRF51