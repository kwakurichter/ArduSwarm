# Crazyradio Dongle Guide
## Why a Custom Dongle Firmware?
The ArduSwarm radio path carries 252 byte packets, well beyond the 31 byte CRTP payload the stock Bitcraze firmware is built around. The drone side of this is handled by the custom nRF51 firmware and `AP_Syslink`, but the ground station side needs to match: a Crazyradio 2.0 running stock firmware cannot send or receive the larger packets, so it will not talk to an ArduSwarm drone.

**[crazyradio-cus](https://github.com/kwakurichter/crazyradio-cus)** is a fork of the Bitcraze Crazyradio 2.0 firmware modified to handle the new packet size. It is included in this repository as a submodule under `submodules/crazyradio-cus`.

> **Hardware note:** this is the Crazyradio 2.0 dongle, which is a different device from the older Crazyradio PA. The PA can still be used for over-the-air bootloading when flashing the nRF51 — see the [Flashing the NRF Guide](flashing_the_nrf.md).

## Flashing the Dongle
### From a release (recommended)
Download `crazyradio2.uf2` from the [Releases page](https://github.com/kwakurichter/ArduSwarm/releases).

- Put the Crazyradio 2.0 into bootloader mode (press and hold button while plugging in - LED should blink red).
- It will appear as a USB device.
- Copy `crazyradio2.uf2` onto it.
- The dongle should disconnect automatically. Unplug and plug in again (LED should flash white once).

Make sure the dongle image comes from the same release as your drone firmware. The 252 byte MTU has to be agreed on by the STM32, the nRF51, and the dongle, and mismatched versions will fail to communicate.

### Building from source
The firmware is a Zephyr application and uses [`just`](https://github.com/casey/just) as its task runner. From `submodules/crazyradio-cus`, the one time environment setup is:

```
just prepare-system
```

This fetches the system dependencies, the Zephyr SDK, and the Python dependencies. Then build and flash:

```
just build
```

```
just flash
```

`just` on its own lists all available targets. Refer to the upstream [Bitcraze build documentation](https://www.bitcraze.io/documentation/repository/crazyradio2-firmware/main/) for details on the Zephyr toolchain and for the DFU flashing path if you would rather not use a debug probe.

## Connecting to Two Drones at Once
The `nrf-firmware-cus` submodule ships a Python bridge script, `tools/mavlink_bridge.py`, that makes the dongle useful for swarm work. It polls one or more vehicles and forwards their telemetry to a ground control station over UDP:

```
.venv/bin/python tools/mavlink_bridge.py --udp 127.0.0.1:14550
```

To poll two vehicles, pass a `--uri` for each. Multiplex them onto one dongle rather than using two:

```
--uri radio://0/80/2M/E7E7E7E7E7 --uri radio://0/80/2M/E7E7E7E706
```

You can point any GCS (Mission Planner, QGroundControl, MAVProxy, etc.) at a normal UDP endpoint and see both vehicles normally. The drones appear as ordinary MAVLink vehicles distinguished by their system IDs, so make sure each drone has a unique `MAV_SYSID` before starting.

Because the script speaks plain UDP MAVLink on the GCS side, it also works with the rest of the MAVLink ecosystem.

Uplink is routed, not duplicated: each vehicle's system id is learned from its downlink, so targeted frames go only to their owner and two vehicles never both answer the same parameter or FTP request. Note that a ground station cannot use `cflib` for this link — see [AP_Syslink](development/ap_syslink.md#8-host-tooling).

See the [Custom GCS Guide](custom_gcs_guide.md) for connecting a ground station to the forwarded stream.

## Troubleshooting
**The GCS sees nothing.** Confirm the dongle, nRF51, and STM32 firmware all came from the same release.

**Only one drone appears.** Check that the two drones have different `MAV_SYSID` values. Two vehicles sharing a system ID will be merged into one by most ground stations.

**Telemetry is intermittent.** Review your mesh stream rates — see `P2P_SR_*` in the [Swarm Mesh Guide](swarm_mesh.md). Broadcasting position and attitude at high rates from every drone can saturate the channel.

## Further Reading
The dongle firmware sources are in [crazyradio-cus](https://github.com/kwakurichter/crazyradio-cus). The drone side radio path is described in the [Crazyradio Guide](crazyradio.md).
