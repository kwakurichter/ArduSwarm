# ArduSwarm v2.2.2 release and migration notes

## Versions

This update follows **`master` in [kwakurichter/ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus/tree/master)**, (tag **v2.2.2**). The underlying ArduCopter version is **4.7.2**. The Flow Deck overhaul, GCS mission scripts, and brushless thrust model are included in this release.

| Component | Version / source reference | Changes |
|---|---|---|
| STM32 | ArduSwarm v2.2.2 / ArduCopter 4.7.2, `e745352bfc` | GCS mission support, Flow Deck overhaul, shared-SPI startup fix, brushless thrust model, updated board configuration |
| nRF51 | [nrf-firmware-cus v2.0.0](https://github.com/kwakurichter/nrf-firmware-cus/tree/v2.0.0), `6a34d0e` | 252-byte ESB transport, concurrent telemetry and P2P, transmit queue feedback, die-temperature reporting |
| Crazyradio 2.0 | [crazyradio-cus v1.0.1](https://github.com/kwakurichter/crazyradio-cus/tree/v1.0.1), `9b9d687` | USB answer completion and bulk IN termination fix for shared radio operation |
| GCS radio tools | nRF source `dc31d91923bd18b8000b9a43b8f4c69c4f56165c`, copied into `python/` | Per-drone frame reassembly, queue diagnostics, slow polling of absent vehicles, dongle recovery |
| Guard | `Leg_v5` | Updated design is 10% lighter than the previous guard design |

The hub and mission runner in `python/` match `companion/swarm_hub.py` and `companion/guided_swarm.py` on the verified `ArduPilot_cus` master. The nRF commits after v2.0.0 change host tools, not nRF firmware sources. Crazyradio's application release is v1.0.1 even though its USB device version remains 5.4.

Compatible image names for this update are:

- `crazyflie2-ArduSwarm-v2.2.2_with_bl.hex` — brushed aircraft.
- `crazyflie2_bl-ArduSwarm-v2.2.2_with_bl.hex` — brushless aircraft.
- `cf2_nrf.bin` / `cf2_nrf.hex` — nRF51.
- `crazyradio2-v1.0.1.uf2` — Crazyradio 2.0.

Firmware is distributed through the [ArduSwarm releases page](https://github.com/kwakurichter/ArduSwarm/releases).

## GCS scripting and 4 drone operation

`swarm_hub.py` keeps radio links and QGC telemetry alive between missions. Its prompt supports preview, execution with confirmation, repetition, link status, and automatic session/mission logging. `guided_swarm.py` supplies hover, directional out-and-back, three-axis, circle, and diamond routines for one to four vehicles. Custom logic runs on the GCS computer; an AI Deck is optional.

For four drones, use two Crazyradio 2.0 dongles with two drones on each, on separate channels. Give every drone a unique `MAV_SYSID`. This is centralized control over two radio groups: the groups cannot exchange direct `AP_SwarmMesh` traffic across channels. See the [GCS guide](custom_gcs_guide.md) and [automation guide](using_the_api_for_custom_automation.md).

## Sensor and firmware changes

- **Optical flow:** checked SPI transfers and motion status, configurable delta/quality gates and radians per count scaling, continuous measurement windows including valid zero motion intervals, and gyro averaging aligned to each polling interval.
- **Rangefinder:** validated ST range status results, bus thread sample timestamps, stale/error data reported as unavailable, and stop/start recovery after measurement timeouts.
- **Diagnostics:** `RNGFND1_FD_LOG` enables optional rangefinder records. Optical flow diagnostics (`FLOW_FD_LOG`) are compiled out of the standard v2.2.2 board definitions and require a diagnostic build. Sampling and recovery do not depend on diagnostic logging.
- **Board and scheduling:** shared SPI deck startup fix, increased brushless I2C thread priority, MMC5983MA external compass and ExternalNav support on the brushless target, plus opt-in scheduler/IMU wait profiling.
- **Brushless thrust:** calibrated cubic model selected by `MOT_THST_MODEL=1` in the brushless board defaults. The generic library default remains exponential (`0`). Model changes affect the thrust scale and require reviewing hover thrust, motor limits, and tuning.
- **Controller logging:** logs the active Guided horizontal velocity PID terms for analysis.

See the [optical flow](development/optical_flow_driver.md), [ToF](development/tof_driver.md), and [brushless motor](brushless_motor_guide.md) guides.

## Updating an existing aircraft

1. Save each aircraft's parameters and firmware revision before flashing. Use matching STM32, nRF51, and Crazyradio images; the large packet application protocol is incompatible with stock radio firmware.
2. Follow the [quick start](quick_start_guide.md) flashing order. The AI Deck is optional for GCS-based missions; retain it for onboard companion applications.
3. Use the current [brushless parameter snapshot](parameters/bl_v2.2.2.params) as a reference, not a universal calibration. It contains `MAV_SYSID=1`, `SYSL_CHAN=80`, aircraft calibration/tuning, disabled battery failsafe actions, and `MOT_THST_MODEL=1`. Review these before applying it to another aircraft.
4. Assign unique system IDs and channels using the [four-drone table](custom_gcs_guide.md#four-drones-on-two-dongles). Reboot and confirm each vehicle independently in the GCS.
5. Verify fresh optical flow and rangefinder data, logging, and manual flight on each drone. Then preview a single drone script before progressing to group missions.
6. Print the lighter guard from the current [Leg_v5 files](guard_printing_guide.md#files-included-in-the-repository), check fit and propeller clearance, and update the motion capture rigid body if needed.