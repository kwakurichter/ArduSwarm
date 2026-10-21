# Crazyradio Dongle Guide
## Why a Custom Dongle Firmware?
The ArduSwarm radio path carries 252 byte packets, well beyond the 31 byte CRTP payload the stock Bitcraze firmware is built around. The drone side of this is handled by the custom nRF51 firmware and `AP_Syslink`, but the ground station side needs to match: a Crazyradio 2.0 running stock firmware cannot send or receive the larger packets, so it will not talk to an ArduSwarm drone.

**[crazyradio-cus](https://github.com/kwakurichter/crazyradio-cus)** is a fork of the Bitcraze Crazyradio 2.0 firmware modified to handle the new packet size. It is included in this repository as a submodule under `submodules/crazyradio-cus`.

> **Hardware note:** this is the Crazyradio 2.0 dongle, which is a different device from the older Crazyradio PA. The PA can still be used for over-the-air bootloading when flashing the nRF51 — see the [Flashing the NRF Guide](flashing_the_nrf.md).

## Flashing the Dongle
### From a release (recommended)
For this update, download `crazyradio2-v1.0.1.uf2` from the [Releases page](https://github.com/kwakurichter/ArduSwarm/releases).

- Put the Crazyradio 2.0 into bootloader mode (press and hold button while plugging in - LED should blink red).
- It will appear as a USB device.
- Copy `crazyradio2-v1.0.1.uf2` onto it.
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

## Connecting to 1 to 4 Drones
Use the current `python/` tools in this repository. `swarm_hub.py` combines radio polling, UDP telemetry to QGC, and an interactive mission prompt. `mavlink_bridge.py` is the telemetry only alternative.

The 4 drone configuration uses two Crazyradio 2.0 dongles, each serving two drones on a shared channel. Use different channels for the two dongles, and a distinct `MAV_SYSID` for each drone. Direct P2P traffic cannot cross these channels.

Follow the [GCS setup guide](custom_gcs_guide.md) for dependencies, the 4 drone address/channel table, and complete launch commands. Continue to the [automation guide](using_the_api_for_custom_automation.md) for GCS-based scripts.

Version **v1.0.1** fixes USB answer completion and bulk IN termination for shared radio operation. Use the current matching bridge and USB driver as well; the pinned nRF submodule now includes the current host tools required by the hub. See [version details](release_notes.md).

## Troubleshooting
**The GCS sees nothing.** Confirm the dongle, nRF51, and STM32 firmware all came from the same release.

**Only one drone appears.** Check that the two drones have different `MAV_SYSID` values. Two vehicles sharing a system ID will be merged into one by most ground stations.

**Telemetry is intermittent.** Review your mesh stream rates — see `P2P_SR_*` in the [Swarm Mesh Guide](swarm_mesh.md). Broadcasting position and attitude at high rates from every drone can saturate the channel.

## Further Reading
The dongle firmware sources are in [crazyradio-cus](https://github.com/kwakurichter/crazyradio-cus). The drone side radio path is described in the [Crazyradio Guide](crazyradio.md).
