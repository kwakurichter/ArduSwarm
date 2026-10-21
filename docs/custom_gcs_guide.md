# Ground Control Station Guide

## Radio and script architecture

The current GCS workflow supports simultaneous operation and telemetry for **1 to 4 drones**. Scripts run on the GCS computer. Each drone's STM32 runs ArduPilot; its nRF51 exchanges MAVLink over a Crazyradio 2.0 dongle. An AI Deck is optional.

```text
Drone STM32 ↔ nRF51 ↔ Crazyradio 2.0 ↔ swarm_hub.py ↔ QGC (UDP 14550)
                                           ↕
                                  guided_swarm.py missions
```

The hub owns the USB radios, polls the drones, reconstructs each drone's MAVLink stream, and relays complete frames to the GCS. Targeted uplink frames are routed to the vehicle identified by their MAVLink system ID. QGC remains connected while missions run and between missions.

## Install the host tools

Use the compatible [firmware versions](release_notes.md) and flash every dongle as described in the [dongle guide](crazyradio_dongle.md). Install Python 3.9 or newer, a working libusb backend for PyUSB, and the Python dependencies. From the **ArduSwarm repository root**:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install pyusb pymavlink
.venv/bin/python python/swarm_hub.py --help
```

Keep `swarm_hub.py`, `guided_swarm.py`, `mavlink_bridge.py`, and `crazyradio2_large.py` together in `python/`. The bundled bridge and USB driver match the tools in the pinned nRF submodule. Pass `--radio-tools python` explicitly so the hub loads this copy.

`cflib` is used for stock Bitcraze tools and bootloading, but does not provide this large packet GCS link. The supplied USB driver handles the full transfers. If PyUSB reports no backend or access denied, check libusb installation and [USB permissions](https://www.bitcraze.io/documentation/repository/crazyflie-lib-python/master/installation/usb_permissions/).

## Vehicle identity and radio URI

```text
radio://<dongle index>/<channel>/<rate>/<address>
```

Configure each drone individually before connecting the group:

- `MAV_SYSID`: unique for every drone. The final address byte is this ID in hexadecimal (`1` → `01`, `10` → `0A`).
- `SYSL_CHAN`: must match the URI channel.
- `SYSL_RATE=2`: 2 Mbit/s, corresponding to `2M` in the examples.
- `SYSL_ENABLE=1`, `SERIAL2_PROTOCOL=52`, `SERIAL2_BAUD=1000`: enable the Syslink transport. Reboot after configuration.

A drone with `MAV_SYSID=1` uses `E7E7E7E701`. Always supply an explicit URI: the scripts' legacy default address is `E7E7E7E7E7`. See [Identity](development/identity.md).

## One or two drones on one dongle

For one drone:

```bash
.venv/bin/python python/swarm_hub.py --radio-tools python \
    --uri radio://0/80/2M/E7E7E7E701
```

For two drones, both configured for channel 80:

```bash
.venv/bin/python python/swarm_hub.py --radio-tools python \
    --uri radio://0/80/2M/E7E7E7E701 \
    --uri radio://0/80/2M/E7E7E7E702
```

Only list drones that are powered. The hub shares each dongle's polling time between its listed vehicles.

## Four drones on two dongles

Configure this example roster, then connect both dongles:

| Drone / `MAV_SYSID` | Dongle index | `SYSL_CHAN` | URI |
|---|---:|---:|---|
| 1 | 0 | 80 | `radio://0/80/2M/E7E7E7E701` |
| 2 | 0 | 80 | `radio://0/80/2M/E7E7E7E702` |
| 3 | 1 | 100 | `radio://1/100/2M/E7E7E7E703` |
| 4 | 1 | 100 | `radio://1/100/2M/E7E7E7E704` |

```bash
.venv/bin/python python/swarm_hub.py --radio-tools python \
    --uri radio://0/80/2M/E7E7E7E701 \
    --uri radio://0/80/2M/E7E7E7E702 \
    --uri radio://1/100/2M/E7E7E7E703 \
    --uri radio://1/100/2M/E7E7E7E704
```

For three drones, omit the fourth URI. USB enumeration determines dongle indices and can change after replugging; check the hub's startup listing and `status` output.

Use one hub process for all dongles. Running another hub or bridge against the same dongle competes for its USB interface.

### Channels and peer-to-peer networking

Drones on a shared dongle use the same channel; the two dongles use different channels to avoid competing for airtime. The example above provides 4 drone GCS control and telemetry, but direct P2P traffic stays within each channel. It does not create a single four node radio mesh. A common channel P2P setup uses one multiplexed dongle and must be assessed separately for its bandwidth needs; see the [Swarm Mesh Guide](swarm_mesh.md).

## Connect QGroundControl

Configure QGC to listen for UDP on port 14550. This is the hub's default destination; change it with `--qgc HOST:PORT` if needed. QGC replies to the hub's source endpoint. There is no fixed requirement to send commands to port 14551 in this workflow.

At the `swarm>` prompt, enter `status`. Confirm all expected system IDs and fresh telemetry before selecting a mission. The hub forwards ordinary MAVLink, so other GCS applications can use the same UDP destination.

For mission previews, custom scripting, and group placement, continue to the [automation guide](using_the_api_for_custom_automation.md).

## Telemetry alternative

For a session that does not need the hub's mission prompt, run the standalone bridge instead:

```bash
.venv/bin/python python/mavlink_bridge.py \
    --uri radio://0/80/2M/E7E7E7E701 \
    --uri radio://0/80/2M/E7E7E7E702 \
    --udp 127.0.0.1:14550
```

Add the other two URIs from the table for 4 drone telemetry. Omit `--udp` to inspect radio traffic in the terminal. `--status-sec` controls status output and `--stats-jsonl PATH` saves bridge statistics.

## Troubleshooting

- **Import error for `crazyradio2_large` or `find_devices`:** use the complete current `python/` tool set. The older nRF v2.0.0 driver lacks interfaces used by the current bridge.
- **No drone or missing system ID:** check power, address, channel, data rate, and compatible firmware. Confirm `MAV_SYSID` after importing a parameter file.
- **Only one vehicle appears:** duplicated system IDs cause the GCS to merge vehicles. Assign distinct IDs and reboot.
- **USB errors or stalled telemetry:** verify Crazyradio v1.0.1, check USB access, and close other processes using the dongles. The current bridge attempts dongle recovery and polls absent vehicles more slowly; recovery does not guarantee delivery of commands during an outage.
- **Latency under load:** inspect link/queue statistics and lower unnecessary telemetry or P2P stream rates. Four vehicles share finite airtime; a single drone poll rate is not a 4 drone telemetry guarantee.
