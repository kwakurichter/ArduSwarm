# Collision Avoidance Experiment Guide
## Overview
The Collision Avoidance experiment is a two-drone proof-of-concept that validates ArduSwarm's peer-awareness and basic reactive avoidance capability. One drone (the flyer) takes off and holds a fixed hover position. A second drone (the probe) remains disarmed and is carried by hand toward the flyer. The flyer listens continuously for P2P packets from the probe, measures the received signal strength (RSSI) of those packets as a proximity proxy, and reacts when the probe enters a configurable close-approach threshold (climbing ~25 cm to avoid a potential collision). Once the probe has been absent from the vicinity for a set dwell period, the flyer descends back to its original hover altitude.

This experiment validates ArduSwarm drones aware of peers using only the existing P2P radio link, with no external positioning system required. ArduSwarm drones can execute a guard maneuver against drift-based collisions in formation control.

At a high level:
- Probe: disarmed, carried by hand, broadcasts lightweight P2P packets at ~25 Hz
- Flyer: takes off to set altitude, hovers at a fixed position, monitors peer RSSI
- Avoid: when the Probe enters ~1–2 m bubble, the flyer climbs +25 cm and holds until clear
- Recover: the Flyer descends back to normal hover altitude after the probe departs
- Failsafe: if P2P packets stop for 8 s, the flyer initiates landing

## Requirements
- Min. two ArduSwarm drones:
    - Probe drone (disarmed, handheld during experiment)
    - Flyer drone (flies autonomously)
- A Ground Control Station (GCS) of your choice (we use QGroundControl)
- The ArduSwarm Python WiFi telemetry bridge (same as [first flight](/docs/first_flight.md))
- The provided firmware from this repo:
    - [Collision Avoidance AI Deck firmware](/docs/compiled_firmware/aideck/collision_avoidance)
    - [ArduPilot firmware](/docs/compiled_firmware/ardupilot)
    - QGC [actions](/python/actions.json) file for custom actions
- Indoor flight space requirements are the same as [first flight](/docs/first_flight.md):
    - Good lighting
    - Visible floor texture for optical flow
    - Clear, open area with safety buffer

## Step 1 — Flash required firmware
### Flash the AI Deck with Collision Avoidance firmware
Flash the Flyer's AI Deck with the [Collision Avoidance experiment firmware](/docs/compiled_firmware/aideck/collision_avoidance) provided in this repository.
- Follow the repo's [Companion Computer Guide](/docs/companion_computer_guide.md).

### Flash both drones with ArduPilot firmware
Flash both the flyer and probe STM32 flight controllers with the [ArduPilot build](/docs/compiled_firmware/ardupilot) provided in this repository.
- Follow the repo's [Compiling & Flashing Guide](/docs/compiling_and_flashing.md).
- The probe only needs to broadcast P2P rssi packets, it does not fly.

## Step 2 — Configure QGC to send commands to the AI Deck
The collision avoidance mission is triggered using a custom MAVLink command sent from QGC to the Flyer's AI Deck. In our workflow, this is done through a Custom Action button in QGC.

### 2.1 Import the provided actions.json
1. Locate the [actions](/python/actions.json) file provided in this repository.
2. In QGC, configure Custom Actions using that file.
3. Confirm you now have a button/action available for:
```
Mission Go
```

If you've never configured custom actions before, follow QGC's documentation for [custom actions](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/custom_actions/custom_actions.html) import and binding.

## Step 3 — Bring up the flyer telemetry link
1. Power on the flyer drone.
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
- You see a MAVLink stream from sysID 42, showing a STATUSTEXT message with res0 = 31
- Make sure you have selected the correct parameters:
```
CF_ID = 1
CF_PEER_ID = 21
CF_HOV_TIME = 2 (default)
PILOT_TKOFF_ALT = 100 (default)
CF_P2P_STREAM = 2
```
- Power the drone on/off to enable parameter changes

## Step 4 — Power on the probe and confirm P2P reception
Power on the probe drone. Configure the following parameters:
```
CF_ID = 10
CF_PEER_ID = 20
CF_P2P_STREAM = 8 (rssi message type)
CF_RSSI_HZ = 25
```
- Power the drone on/off to enable parameter changes

Keep the probe at arm's length from the flyer for now (> 2 m).

Expected behavior:
- The probe begins broadcasting P2P packets
- The flyer should report a STATUSTEXT indicating it is receiving peer broadcasts (res0 = 31, res1 = 1)
- The flyer's proximity state should read PROX_NORMAL (31) at this range. If it reads PROX_CAUTION (79) or PROX_AVOID (143), consider moving the probe further

If you do not see peer reception status text:
- Confirm both drones are powered and within RF range
- Confirm both drones have been configured with matching peer IDs

## Step 5 — Execute the Collision Avoidance mission
### 5.1 Arm/launch via "Mission Go"
When you are ready (clear space, stable telemetry, peer reception confirmed):
1. In QGC, press the "Mission Go" custom action.
2. The flyer will:
    - Take off
    - Climb to set altitude (PILOT_TKOFF_ALT)
    - Enter a fixed hover and begin monitoring the probe's RSSI

### 5.2 Trigger the avoidance maneuver
With the flyer hovering, slowly walk the probe toward the flyer from the side:
- At ~2 m separation, the flyer transitions to **PROX_CAUTION** (no motion change — a placeholder for future speed limiting).
- At ~1 m separation, the flyer transitions to **PROX_AVOID** and climbs +25 cm to its avoidance altitude.

Walk the probe back out past 2 m and hold it there. The flyer transitions to **PROX_RECOVER**, pauses for ~1 s, confirms the filtered RSSI is clear, then descends back to its original hover altitude.

Repeat the approach as many times as desired within the experiment window.

### 5.3 End the experiment
The experiment ends when the hover timer expires. The flyer will land and disarm automatically. You can also trigger an early land by disconnecting the P2P link (power off the probe) and waiting for the 8s leader timeout.

## RSSI Filtering and Why It Is Necessary
Raw RSSI measured from a 2.4 GHz radio in an indoor environment is highly noisy. Multipath reflections from walls, floors, furniture, and the bodies of operators cause the measured value to fluctuate by 5–10 dB on a per-packet basis, even when the two radios are stationary relative to each other. Acting on raw RSSI directly would cause the proximity state machine to oscillate rapidly between states, producing repeated avoidance climbs even when no drone is actually approaching.

To deal with this noise, the firmware runs a two-stage filter per peer at 50 Hz:

### Stage 1 — Median pre-filter
Each tick, the latest raw RSSI sample is pushed into a 5-sample circular buffer. Once the buffer is full, the median of those 5 samples is computed. The median is chosen (rather than the mean) because it completely rejects single-sample spike outliers without introducing the lag of a long averaging window. At the ~25 Hz effective packet rate the window covers approximately 0.2s of history.

Before the buffer is full (first 5 ticks), raw RSSI is used directly for classification so that the filter does not introduce a blind period on startup. On the first buffer fill, the IIR filter state is set to the median to prevent a false AVOID alarm from winding up from zero.

### Stage 2 — Asymmetric IIR low-pass filter
The median output feeds a first-order IIR filter:

```
rssi_filt += alpha * (rssi_med - rssi_filt)
```

The key design choice is that `alpha` (and therefore the filter time constant) is asymmetric:

| Direction | tau | alpha | Settling time |
|-----------|-----|-------|---------------|
| Attack (peer closing, RSSI magnitude dropping) | 0.4 s | ~0.048 | ~1–2 s |
| Release (peer departing, RSSI magnitude rising) | 2.0 s | ~0.010 | ~10 s |

A fast attack time constant ensures the filter reacts quickly when a drone is genuinely approaching, keeping the avoidance response fast. A slow release time constant prevents the filter from clearing too quickly after the peer leaves. This guards against the common case where a brief gap in packets (or a momentary RSSI recovery) would prematurely return the drone to NORMAL and trigger a descent before the peer has truly moved away.

### Proximity state machine and hysteresis
The filtered RSSI drives a 4 state machine per peer:

| RSSI magnitude | State |
|---|---|
| < 47.5 (strong signal, peer close) | `PROX_AVOID` |
| 47.5 – 50 | `PROX_CAUTION` |
| > 50 (weak signal, peer far) | `PROX_NORMAL` |

State escalation (closer) is immediate. The code jumps on the first tick that crosses the `PROX_AVOID` threshold. De-escalation (farther away) is gated by a 500 ms dwell time, and departure from `PROX_AVOID` enters a `PROX_RECOVER` state rather than jumping straight to `PROX_NORMAL`. `PROX_RECOVER` requires both a 1s timer expiry and `rssi_filt > 55` before it exits to `PROX_NORMAL`, giving the filter time to confirm the peer has genuinely cleared the area.

The global `g_proximity_state` used by the flight controller is always the worst case state across all tracked peers, so a single peer in `PROX_AVOID` holds the entire system in avoid mode regardless of what any other peer is doing.

## Troubleshooting
### Flyer never enters PROX_AVOID even at close range
- Confirm the probe is powered and broadcasting (check flyer STATUSTEXT for peer reception).
- Walk the probe closer. The RSSI threshold corresponds to roughly 1–1.5 m indoors, but this varies with environment and antenna orientation.
- Check for metal obstructions between the two drones that could attenuate the signal.

### Flyer oscillates rapidly between PROX_AVOID and PROX_RECOVER
- This usually indicates the probe is being held right at the threshold boundary. Move it clearly inside or outside the 1 m zone.
- If oscillation persists at a stable distance, the indoor RF environment may be unusually noisy. Try a different location with fewer large metal surfaces.

### Flyer does not descend after the probe is removed
- The release time constant is intentionally slow (~10 s to fully clear). Wait longer before assuming a fault.
- If the flyer is still elevated after 15 s with the probe clearly removed, check that the probe is actually powered off, a powered probe at longer range can still hold the filter elevated if the RSSI is near the threshold.

### Flyer takes off but performs an emergency land after ~8 s
- The hard leader timeout has fired. Confirm the Probe is powered on and broadcasting before pressing "Mission Go."
- Keep the Probe within RF range of the Flyer for the duration of the experiment.

### QGC connects but "Mission Go" does nothing
- Verify the flyer is healthy (res0: first 4 bits indicate EKF health and must all be true before flight).
- Check STATUSTEXT output from the AI Deck for command receipt/acknowledgement.

### Follower drifts or GUIDED is unstable
- Improve optical flow conditions (lighting + textured floor).
- Check ToF rangefinder health and orientation.
- Repeat [first flight](/docs/first_flight.md) hover tuning before re-running this experiment.
