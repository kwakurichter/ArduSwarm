# Custom GCS Guide

## Why a bridge is needed

An ArduSwarm drone does not present a serial port to your ground station. Its telemetry leaves the STM32 over [syslink](development/ap_syslink.md) to the nRF51 radio, goes out over 2.4 GHz ESB, and arrives at a Crazyradio 2.0 dongle on your PC as USB traffic. No ground station speaks that natively.

[`mavlink_bridge.py`](../python/mavlink_bridge.py) is a python script which translates the data from the crazyflie to data GCS' can understand. It polls the drones through the dongle, unwraps the MAVLink out of the radio framing, and reemits it as ordinary UDP MAVLink on localhost. From your GCS's point of view it is a completely normal UDP telemetry link.

```
Drone(s) ─ ESB ─▶ Crazyradio 2.0 ─ USB ─▶ mavlink_bridge.py ─ UDP ─▶ your GCS
```

This means QGroundControl, Mission Planner, MAVProxy, or anything else that speaks MAVLink over UDP works unmodified. There is no plugin to install and no custom dialect to load.

### Why the bridge must poll

The Crazyflie is a PRX (primary receiver) in ESB terms, so it can only transmit inside an ack — it never speaks unprompted. Every downlink byte arrives as the payload of an ack to something the bridge sent.

That is why the script transmits continuously, sending a bare marker byte when it has nothing to say. Downlink latency is bounded by the poll rate, not by the radio.

---

## Prerequisites

**A Crazyradio 2.0 running the ArduSwarm dongle firmware.** A stock dongle cannot exchange 252 byte packets and will not work. See the [Crazyradio Dongle Guide](crazyradio_dongle.md).

**The drone firmware from the same release** as the dongle image. The STM32, nRF51 and dongle all have to agree on the packet size.

**Python with `pyusb`.** A copy of the script lives at `python/mavlink_bridge.py`
in this repository; the original, alongside its USB driver `crazyradio2_large.py`,
is in the `nrf-firmware-cus` submodule under `tools/`. Run it from the submodule
so it can import the driver sitting next to it:

```bash
python3 -m venv .venv && .venv/bin/pip install pyusb
```

> **`cflib` cannot be used for this link.** Its `Crazyradio.send_packet()` reads the dongle's bulk IN endpoint with a hardcoded 64 byte length, so it truncates any ack payload above that regardless of firmware. The bridge ships its own minimal driver, `crazyradio2_large.py`, which requests the full transfer.

On macOS and Linux you may need USB permissions for the dongle — see the [Bitcraze USB permissions guide](https://www.bitcraze.io/documentation/repository/crazyflie-lib-python/master/installation/usb_permissions/).

---

## Connecting one drone

From `submodules/nrf-firmware-cus`:

```bash
.venv/bin/python tools/mavlink_bridge.py --udp 127.0.0.1:14550
```

That polls the default URI, `radio://0/80/2M/E7E7E7E7E7`, and forwards everything to UDP port 14550.

Then in your GCS, add a UDP connection to `127.0.0.1:14550`. In QGroundControl this is *Application Settings → Comm Links → Add*, type UDP, port 14550. Most ground stations listen on 14550 by default and will connect on their own.

Run the script without `--udp` to watch and decode traffic in the terminal without involving a GCS at all (useful for confirming the link before adding another moving part).

### The radio URI

```
radio://<dongle index>/<channel>/<rate>/<address>
```

The address ends in the vehicle's `MAV_SYSID` as hex. A drone with `MAV_SYSID = 1` is `radio://0/80/2M/E7E7E7E701`, **not** the Crazyflie default of `...E7E7E7E7E7`. See [Identity](development/identity.md). Every vehicle needs a distinct `MAV_SYSID` before you fly more than one.

---

## Connecting two drones

Pass a `--uri` per vehicle. Both feed the same UDP endpoint, and the GCS separates them by system id:

```bash
.venv/bin/python tools/mavlink_bridge.py \
    --uri radio://0/80/2M/E7E7E7E7E7 \
    --uri radio://0/80/2M/E7E7E7E706 \
    --udp 127.0.0.1:14550
```

Both URIs share dongle index 0, so one dongle serves both, retuning between them.

### One dongle or two?

URIs sharing a dongle index are round-robined on that dongle. URIs with different indices get a dongle each:

```bash
# two dongles, separate channels — only valid if the drones do NOT use P2P
.venv/bin/python tools/mavlink_bridge.py \
    --uri radio://0/80/2M/E7E7E7E7E7 \
    --uri radio://1/90/2M/E7E7E7E706
```

**If the drones talk to each other over P2P, you must multiplex one dongle.** A Crazyflie has a single radio frequency for everything, so peers can only hear each other on a common channel. Two dongles sharing a channel collide: ESB has no carrier sense, and the dongle retries in a tight loop with no backoff, so a 252 byte ack occupying ~1 ms can use an entire retry burst. Multiplexing one dongle removes the collision by construction, at the cost of dividing the poll rate between vehicles.

Measured: **~175 polls/s** with one vehicle, **~156/s each** with two multiplexed.

### Uplink is routed, not duplicated

The bridge learns each vehicle's system id from its downlink and sends targeted frames only to their owner. Without this, two vehicles would both answer the same parameter or FTP request and corrupt each other's transfers.

---

## Reading the status line

By default the script prints a status block every 2 seconds:

```
[14:32:07]
  dongle0 [<usb id>]  retunes 41
    e7e7e7e7e7@ch80    down  1240B/31   up  180B/12  polls  312 ( 156/s) no-ack 4    err 0
                       sys1 HEARTBEAT x2, ATTITUDE x14, GLOBAL_POSITION_INT x7, SYS_STATUS x2
    e7e7e7e706@ch80    down  1198B/29   up  164B/11  polls  310 ( 155/s) no-ack 6    err 0
                       sys6 HEARTBEAT x2, ATTITUDE x13, GLOBAL_POSITION_INT x7, SYS_STATUS x2
  uplink routing: sys1->e7e7e7e7e7, sys6->e7e7e7e706
```

| Field | Meaning |
|---|---|
| `down` | bytes / packets received from the vehicle |
| `up` | bytes / chunks sent to it |
| `polls` | poll count and rate — the ceiling on downlink latency |
| `no-ack` | polls the vehicle did not answer; some is normal |
| `err` | USB errors; should stay at 0 |
| `retunes` | channel switches, shown only when a dongle serves several vehicles |
| `sysN ...` | decoded system id and the most common message types |

A healthy link shows a system id, a steady poll rate, message counts climbing, and `err` at zero.

Useful flags: `--status-sec` changes the interval, `--quiet` suppresses the block entirely, and `--idle-poll-ms` sets the pause after a polling round in which no vehicle had traffic.

---

## Troubleshooting

**`sys?` and no frames decoded.** The bridge is reaching the dongle but nothing is coming back from the drone. Check that the drone is powered and that its `MAV_SYSID` matches the address in your URI. Then confirm all three firmware images came from the same release.

**No dongle found, or USB errors.** Confirm the dongle is running the ArduSwarm firmware rather than stock, and check USB permissions. Run `tools/crazyradio2_large.py` directly for a self test sweep from 4 to 252 bytes, which checks the dongle without needing a drone.

**The GCS connects but shows one vehicle when you expect two.** Two drones sharing a `MAV_SYSID` are merged by most ground stations. Give each a distinct value.

**Telemetry is intermittent under load.** Review your mesh stream rates. Every node's broadcasts are received by every other node, so mesh load grows with the square of the swarm size — see the bandwidth rule in [AP_SwarmMesh](development/ap_swarmmesh.md#4-the-bandwidth-rule).

**Poll rate is much lower than expected.** Multiplexing divides it between vehicles by design. If you are not using P2P, a dongle per vehicle on separate channels restores the full rate.

---

## See also

- [Crazyradio Dongle Guide](crazyradio_dongle.md) — flashing the dongle
- [AP_Syslink](development/ap_syslink.md) — the protocol underneath, and host tooling notes
- [Identity](development/identity.md) — `MAV_SYSID` and radio addresses