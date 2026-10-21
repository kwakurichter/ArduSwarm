# Optical Flow Guide

## Flow Deck support

The Flow Deck v2 combines a **PMW3901** optical flow sensor with a **VL53L1X** rangefinder. Flow measures angular image motion; the estimator uses height above ground and vehicle rotation to estimate horizontal movement. It supports indoor navigation over a textured, well-lit floor, but does not provide drift free absolute position.

![Optical Flow Principle](/docs/images/optical_flow/optical_flow_1.png)

*Gordon, Andrew. “Adventures in Optical Flow.” Technology, Thinking, Doing, 20 June 2021, www.andrewgordon.me/posts/Adventures-in-Optical-Flow/.*

The ArduSwarm backend is `AP_OpticalFlow_FlowDeck`, selected with `FLOW_TYPE=9`. It is included in the custom firmware; users of prebuilt images do not need to patch upstream ArduPilot. Source and implementation details are in the [driver guide](development/optical_flow_driver.md).

## Current driver changes

The v2.2.2 updates improve SPI error handling, motion status validation, configurable raw delta and surface quality filtering, and scaling. Valid zero motion samples remain in the measurement window, and gyro values are averaged over each polling interval to align rotation compensation with flow. Use the compatible firmware and tools listed in the [release notes](release_notes.md).

## Setup and calibration

Configure the [rangefinder](rangefinder.md) first. Set `FLOW_TYPE=9`, save, and reboot. The current [brushless parameter snapshot](parameters/bl_v2.2.2.params) contains:

```text
FLOW_TYPE        9
FLOW_ADDR        0
FLOW_FD_SCALE    0.0020478286
FLOW_FD_DMAX     0
FLOW_FD_SQUAL    0
FLOW_FXSCALER    -100
FLOW_FYSCALER    -100
FLOW_ORIENT_YAW  0
FLOW_POS_X       0
FLOW_POS_Y       0.01
FLOW_POS_Z       0.01
```

Measure sensor offsets for your stack and validate scale and orientation on each aircraft.

| Parameter | Meaning |
|---|---|
| `FLOW_FD_SCALE` | Radians represented by one raw PMW3901 count |
| `FLOW_FD_DMAX` | Reject absolute raw deltas at or above this threshold; `0` disables the gate (firmware default is `100`) |
| `FLOW_FD_SQUAL` | Minimum accepted surface quality; `0` disables the gate |
| `FLOW_FXSCALER`, `FLOW_FYSCALER` | Per-axis scale corrections |
| `FLOW_FD_LOG` | Only available in a custom diagnostic build; compiled out of the standard v2.2.2 release |

In the reference snapshot, EKF3 uses optical flow for horizontal velocity (`EK3_SRC1_VELXY=5`) and the rangefinder for height (`EK3_SRC1_POSZ=2`), with no absolute horizontal position source (`EK3_SRC1_POSXY=0`). Review the estimator configuration as a whole if using motion capture or another source.

## Verify before flight

With the aircraft disarmed, move it over a textured surface at a height where the rangefinder has a valid reading. Inspect `OPTICAL_FLOW` telemetry in the GCS: confirm fresh motion/quality data and the expected response to translation and rotation. `OPTICAL_FLOW` is a MAVLink message, not a parameter. Valid stationary samples can have zero motion.

![QGC Optical Flow](/docs/images/optical_flow/optical_flow_3.png)

If data is missing or inconsistent, check the selected backend, rangefinder freshness, floor texture, lighting, mounting orientation, and calibration before flight. The standard v2.2.2 board definitions compile optical flow diagnostics out, so `FLOW_FD_LOG` will not appear. In a custom diagnostic build, `FLOW_FD_LOG=1` enables `OFR`, `OFT`, `OFD`, and `OFM`; turn it off after diagnosis to reduce log load. See the [logging guide](logging_guide.md).
