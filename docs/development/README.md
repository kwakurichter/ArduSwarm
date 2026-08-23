# Development Guides

Engineering reference for the ArduSwarm port. These describe what was built and why. The operational guides live one level up in [`docs/`](../).

## Start here

**[Port Overview](port_overview.md)** — what the fork contains, how it is built.

**[Identity](identity.md)** — why every vehicle has exactly one `MAV_SYSID`, and what breaks when they collide. Short, and worth reading before the rest.

## Radio and swarm

| Guide | Covers |
|---|---|
| [AP_Syslink](ap_syslink.md) | nRF51 radio driver, syslink protocol, 252 byte packets, bring up gates |
| [AP_SwarmMesh](ap_swarmmesh.md) | Decentralized peer mesh, wire format, bandwidth budgeting |
| [AP_Ranging](ap_ranging.md) | DW1000 UWB peer ranging, Alternative DS-TWR, calibration |
| [AI Deck](ai_deck.md) | Consuming peer state and ranges on a companion computer |

## Sensors and outputs

| Guide | Covers |
|---|---|
| [Optical Flow Driver](optical_flow_driver.md) | PMW3901 motion burst reads, SPI1 sharing |
| [ToF Driver](tof_driver.md) | VL53L1X via the vendored ST API, distance modes, threading |
| [RCOutput BDShot](rcoutput_bdshot.md) | CF21 brushless open drain lines and TIM2 DMA contention |

## Operational guides

For flashing, parameters and flight setup, see the main
[documentation index](../../README.md#️-getting-started) — in particular the [Quick Start Guide](../quick_start_guide.md), [Crazyradio Guide](../crazyradio.md) and [Companion Computer Guide](../companion_computer_guide.md).