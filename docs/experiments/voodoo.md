# Voodoo Experiment Guide
## Overview
The Voodoo experiment is a multi-drone, leader–follower demonstration that validates ArduSwarm’s decentralized P2P command pipeline. A stationary Leader drone (disarmed, held by hand) broadcasts its attitude over the nRF51 P2P link, while flying Follower drone(s) interpret those broadcasts as discrete horizontal motion commands (RC overrides) using the AI Deck as a “virtual pilot.”

At a high level:
- Leader: disarmed, broadcasts attitude at 10 Hz over P2P
- Follower: takes off to set altitude, hovers briefly, then moves in XY based on the leader’s pitch/roll
- Failsafe: if P2P packets stop for ~1 s, the follower lands automatically

<video width="600" controls>
  <source src="/docs/images/voodoo/voodoo.mp4" type="video/mp4">
</video>

<video width="600" controls>
  <source src="/docs/images/voodoo/voodoo3.mp4" type="video/mp4">
</video>

## Requirements
- Min. Two ArduSwarm drones:
    - Leader drone (disarmed, handheld during experiment)
    - Follower drone (flies autonomously)
- A Ground Control Station (GCS) of your choice (we use QGroundControl)
- The ArduSwarm Python WiFi telemetry bridge (same as [first flight](/docs/first_flight.md))
- The provided firmware from this repo:
    - Voodoo AI Deck firmware
    - ArduPilot firmware
    - QGC [actions](/python/actions.json) file for custom actions
- Indoor flight space requirements are the same as [first flight](/docs/first_flight.md):
    - Good lighting
    - Visible floor texture for optical flow
    - Clear, open area with safety buffer

## Step 1 — Flash required firmware
### Flash the AI Deck with Voodoo firmware
Flash the AI Deck with the Voodoo experiment firmware provided in this repository.
- Follow the repo’s [Companion Computer Guide](/docs/companion_computer_guide.md).

### Flash the Leader drone with Leader ArduPilot
Flash the Leader and Follower(s) STM32 flight controller with the [ArduPilot build](/docs/compiled_firmware/ardupilot/brushless/cf2_bl.hex) provided in this repository.
- Follow the repo’s [Compiling & Flashing Guide](/docs/compiling_and_flashing.md).
- This build enables the leader to broadcast its attitude via the nRF51 P2P pipeline at ~10 Hz

## Step 2 — Configure QGC to send commands to the AI Deck
The Voodoo mission is triggered using a custom MAVLink command sent from QGC to the AI Deck. In our workflow, this is done through a Custom Action button in QGC.

### 2.1 Import the provided actions.json
1. Locate the [actions](/python/actions.json) file provided in this repository.
2. In QGC, configure Custom Actions using that file.
3. Confirm you now have a button/action available for:
```
Mission Go
```

If you’ve never configured custom actions before, follow QGC’s documentation for [custom actions](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/custom_actions/custom_actions.html) import and binding.

## Step 3 — Bring up the Follower telemetry link
1. Power on the Follower(s) drone.
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
- You see a MAVLink stream from sysID 42, showing a STATUSTEXT message with res0 = 15
- Make sure you have selected the correct parameters:
```
CF_ID = 1 (change for each additional follower)
CF_PEER_ID = 21 (22,23,...)
CF_HOV_TIME = 2 (default)
PILOT_TKOFF_ALT = 100 (default)
CF_P2P_STREAM = 2
```
- Power the drone on/off to enable parameter changes

## Step 4 — Power on the Leader and confirm P2P reception
Now power on the Leader drone. Change the following parameters:
```
CF_ID = 10
CF_PEER_ID = 20
CF_P2P_STREAM = 1
```
- Power the drone on/off to enable parameter changes

Expected behavior:
- The leader begins broadcasting attitude over P2P
- The follower should report a STATUSTEXT message indicating it is receiving peer broadcasts (res1 = 1)

If you do not see peer-reception status text:
- Confirm the leader is flashed with the Leader build
- Confirm both drones are powered and within range
- Confirm both drones have been configured correctly.

## Step 5 — Execute the Voodoo mission
### 5.1 Arm/launch via “Mission Go”
When you are ready (clear space, stable telemetry, peer reception confirmed):
1. In QGC, press the “Mission Go” custom action.
2. The follower(s) will:
    - Take off
    - Climb to set altitude (PILOT_TKOFF_ALT)
    - Enter a hover state and wait for leader commands

Important: The follower has a ~1 s timeout once it begins the hover state. If it does not continue receiving valid P2P packets, it will initiate a landing sequence.

## Step 6 — Control the follower using the leader’s attitude
With the leader disarmed, hold it in your hand and command motion by tilting it:

### 6.1 Threshold-based mapping (deadband control)
The follower uses a discrete policy with a ±20° deadband:

- Pitch forward beyond −20° → follower moves forward (1300 µs)
- Pitch backward beyond +20° → follower moves backward (1700 µs)
- Roll left beyond −20° → follower moves left (1300 µs)
- Roll right beyond +20° → follower moves right (1700 µs)
- Inside deadband → hover command (1500 µs)

### 6.2 Single-action priority
Only one axis is commanded at a time. Pitch commands take precedence over roll (single-action priority policy).

So if you’re pitching and rolling simultaneously, expect pitch-driven motion to “win.”

## Step 7 — End the experiment cleanly
When you are ready to stop:
1. Set the Leader drone down flat on a stable surface (so it returns to neutral attitude / deadband).
2. The follower should:
    - Return to hover briefly, then
    - Land automatically and disarm

## Testing Voodoo
### Safety and failsafes
Voodoo is designed to land the follower automatically under unsafe or degraded conditions:
1. P2P loss failsafe: If no P2P packets are received for ~3 s, the follower initiates landing.
2. Optical flow quality failsafe: If optical-flow quality drops below 10 (texture loss), the follower lands to prevent fly-aways.
3. Excess velocity failsafe: If estimated horizontal velocity exceeds safety thresholds continuously for 0.5 s, the follower lands.

These are intentional guardrails for indoor testing.

### What “success” looks like
A successful run typically looks like:
- Follower takes off to ~1 m and holds altitude
- You can “nudge” XY motion with clear leader tilts
- Releasing the leader back into deadband causes the follower to re-stabilize
- Setting the leader down ends the session and the follower lands and disarms

## Troubleshooting
### QGC connects but “Mission Go” does nothing
- Verify QGC is actually sending the custom action command to the vehicle system/component expected by your AI Deck handler.
- Check STATUSTEXT output from the AI Deck for command receipt/acknowledgement

### Follower takes off but lands almost immediately
- This is usually the P2P timeout (~1 s) triggering
    - Confirm leader is powered and broadcasting
    - Confirm follower shows “peer broadcasts received” status text before starting
    - Keep leader close during the first hover window

### Follower drifts or LOITER is unstable
- Improve optical flow conditions (lighting + textured floor)
- Check ToF rangefinder health and orientation
- Repeat [first flight](/docs/first_flight.md) tuning (hover throttle / notch/FFT learning) before re-running Voodoo