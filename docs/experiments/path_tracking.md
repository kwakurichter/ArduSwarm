# Path Tracking Experiment Guide
## Overview
The Tracking experiment is a single-drone validation flight used to benchmark infrastructure-free localization on ArduSwarm. The drone executes a repeatable, open-loop “square-like” maneuver using RC overrides, while logging its onboard EKF position estimate (from IMU + optical flow + ToF) to the SD card for later analysis against OptiTrack ground truth.

[![Path Tracking](https://img.youtube.com/vi/49ZPqF_hN3A/0.jpg)](https://www.youtube.com/watch?v=49ZPqF_hN3A)

## Requirements
- 1 ArduSwarm drone equipped with:
- A GCS of your choice (we use QGroundControl)
- The provided ArduSwarm Python WiFi telemetry bridge script
- (Optional) OptiTrack arena for ground-truth comparison

- Indoor flight space requirements are the same as [first flight](/docs/first_flight.md):
    - Good lighting
    - Visible floor texture for optical flow
    - Clear, open area with safety buffer

## Step 1 — Flash the Tracking experiment firmware (AI Deck)
To run the experiment, you first need the AI Deck firmware build that contains the Tracking experiment mission script.
1. Flash the AI Deck with the tracking firmware from this repo.
2. Follow the repo’s [Companion Computer Guide](/docs/companion_computer_guide.md) for exact flashing instructions.

The flight controller (STM32 running ArduPilot/ArduCopter) should already be on your ArduSwarm build that passed First Flight.

## Step 2 — Bring up telemetry to your GCS
1. Power on the drone.
2. Connect your PC to the AI Deck AP:
```
AiDeckDebugAP
```
3. Run the provided Python bridge script.
4. Configure your GCS UDP ports:
    - Listen: 14550
    - Send: 14551

Once connected, verify:
- You see live telemetry
- Optical flow + ToF look healthy
- Logging is enabled (SD deck, if installed)

## Step 3 — Configure QGC to trigger the experiment mission
The tracking mission is triggered using a custom MAVLink command sent from QGC to the AI Deck. In our workflow, this is done through a Custom Action button in QGC.

### 2.1 Import the provided actions.json
1. Locate the [actions](/python/actions.json) file provided in this repository.
2. In QGC, configure Custom Actions using that file.
3. Confirm you now have a button/action available for:
```
Mission Go
```

If you’ve never configured custom actions before, follow QGC’s documentation for [custom actions](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/custom_actions/custom_actions.html) import and binding.

## Step 4 — Pre-flight checks
Before starting the mission, do the same essential checks you used in First Flight:
- Optical flow is healthy (not zeroed / not stuck / reasonable quality)
- ToF rangefinder updates when you lift/lower the drone by hand
- SD logging is working (SD card detected, log created on arm/flight)
- Set parameters:
```
PILOT_TKOFF_ALT = 100 (default)
CF_LOOPS = 1 (default - how many loops you would like to perform)
```

This experiment is specifically meant to validate the onboard estimator that fuses IMU + optical flow + ToF.

## Step 5 — Run the Tracking experiment mission
Place the drone on the ground in the test area and clear the space.
1. In QGC, press your custom action (Mission Go / Start Tracking).
2. The drone will execute the mission profile:
    - Automated takeoff to the set altitude (PILOT_TKOFF_ALT)
    - Execute at least one pattern (West → South → East → North), implemented as RC override steps of approximately ±200 µs around 1500 µs 
    - Automated landing 

This produces a square trajectory driven by the platform’s position controller.

### During the flight (what gets logged)
- The drone’s onboard estimated position is logged to the SD card at 20 Hz.
- If you are running OptiTrack, the ground-truth position is recorded at 100 Hz.

## Step 6 — After the flight: pull logs and (optionally) compute tracking error
### 6.1 Retrieve the onboard log
After the drone lands and disarms:
- Download the onboard log from the SD card (method depends on your SD deck workflow / tooling in this repo).
- (Optional) Use the provided [MATLAB script](/python/path_tracking.m) to compute Root-Mean-Squared Error (RMSE) of optical flow based position estimates vs. OptiTrack Ground truth.

This experiment is meant to highlight drift accumulation in dead-reckoning and validate the stability of the optical flow driver tuning.

## Troubleshooting
- Drone lands early / unstable hover: improve lighting and floor texture; re-check ToF orientation and health.
- Flow quality low: move to a more textured surface (tape pattern / printed pattern / matte surface).
- No SD log created: confirm SD deck detection and logging settings before takeoff.
- GCS won’t connect: restart the drone after the Python bridge is running and QGC UDP ports are configured (same workaround as First Flight).