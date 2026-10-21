# Rangefinder Guide

## Flow Deck support

The Flow Deck v2 uses an ST **VL53L1X** time-of-flight (ToF) sensor to measure distance below the aircraft. It supplies height above ground for optical flow scaling and can be selected as the EKF height source. Usable range and quality depend on distance mode, target, lighting, and installation.

![RangeFinder Principle](/docs/images/rangefinder/rangefinder_2.png)

*Craig, R. “Time-of-Flight Camera.” Wikipedia, Wikimedia Foundation, 16 May 2021, en.wikipedia.org/wiki/Time-of-flight_camera.*

ArduSwarm's `AP_RangeFinder_FlowDeck` wraps ST's API and is selected with **`RNGFND1_TYPE=50`**. Type `16` is the unrelated VL53L0X backend and must not be used for this setup. Prebuilt custom firmware includes the backend; source builds are covered in the [compiling guide](compiling_and_flashing.md) and [ToF driver guide](development/tof_driver.md).

## Current driver changes

The v2.2.2 overhaul validates measurement status and quality, publishes the timestamp of the actual bus thread sample, and marks stale/error data unavailable. If measurements stop arriving, it attempts a stop/start recovery on the I2C thread. Restarting the sensor does not make an old sample fresh. These changes and their source scope are listed in the [release notes](release_notes.md).

## Setup

Set `RNGFND1_TYPE=50`, save, and reboot. For the first rangefinder, the current [brushless parameter snapshot](parameters/bl_v2.2.2.params) uses:

```text
RNGFND1_TYPE     50
RNGFND1_ADDR     41
RNGFND1_MODE     1
RNGFND1_ORIENT   25
RNGFND1_MIN      0.03
RNGFND1_MAX      3
RNGFND1_GNDCLR   0.05
RNGFND1_POS_X    0
RNGFND1_POS_Y    0
RNGFND1_POS_Z    0
```

`ORIENT=25` is downward facing. Distances and offsets are in metres. Measure ground clearance and offsets for your assembled drone, especially after a guard change. The configured minimum/maximum range is an acceptance window, not a guarantee of valid measurements at every distance.

| `RNGFND1_MODE` | Mode | Timing budget | Inter-measurement period |
|---|---|---:|---:|
| `0` | Short | 20 ms | 25 ms |
| `1` | Medium (current snapshot) | 25 ms | 30 ms |
| `2` | Long | 140 ms | 145 ms |

Reboot after changing the mode. Long mode trades update rate for range. The reference estimator selects rangefinder height with `EK3_SRC1_POSZ=2`; review this if using another altitude source.

## Verify before flight

With the aircraft disarmed, raise and lower it over the intended floor and inspect `RANGEFINDER` / `DISTANCE_SENSOR` telemetry. Confirm the readings are plausible and keep updating; these are MAVLink messages, not parameters. Check estimator health as well as the displayed distance.

![QGC RangeFinder](/docs/images/rangefinder/rangefinder_1.png)

A stale last distance is not a healthy range measurement. The driver reports `NoData` on invalid/stale samples and can report `NotConnected` after sustained communication failure. Resolve repeated dropouts before relying on rangefinder height or optical flow scaling.

For diagnostics, use `RNGFND1_FD_LOG=1` when the build exposes it. This enables `RFD`, `RFS`, and `RFR` records without changing sampling or recovery. The firmware default is off. See the [logging guide](logging_guide.md).
