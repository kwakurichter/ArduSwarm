# First Flight Guide
ArduSwarm is very much still in active development and thus there are some quirks with the platform which should be tested manually before attempting any of the more advanced autonomous modes.
## Purpose
Before attempting autonomous modes or swarming, every ArduSwarm drone should complete a short, controlled manual first-flight. The goal is to verify that:
- Telemetry and command links are stable (WiFi → Python bridge → GCS)
- Manual control via joystick works correctly
- Critical sensors are functioning (optical flow + ToF rangefinder)
- Logging is working (SD card deck)
- The drone can achieve a stable hover and ArduPilot can learn key unique airframe parameters

This procedure is intentionally simple: take off in STABILIZE, transition to LOITER for a short hover, then LAND.

## Requirements
- A fully assembled ArduSwarm drone with hardware + firmware setup completed
- Pre-flight checklist completed for the individual drone
- A Ground Control Station (GCS) of your choice (we use QGroundControl (QGC) in this guide)
- A joystick/gamepad supported by your GCS
- The provided ArduSwarm Python telemetry bridge script

### Step 1 - Connect to the AI Deck WiFi Access Point
1. Power on the drone.
2. Wait for the AI Deck WiFi access point to appear:
3. SSID: AiDeckDebugAP

Connect your PC to AiDeckDebugAP.

Once connected, your PC is on the same network as the AI Deck and ready to receive forwarded telemetry.

### Step 2 - Start the Python telemetry bridge
Run the Python [script](../python/mavbridge.py) provided in this repository. The script should immediately begin forwarding the drone’s telemetry stream over UDP to port 14550.

Once running, you should see messages indicating packets are being received and forwarded.

### Step 3 - Configure your GCS UDP ports (14550 / 14551)
ArduSwarm uses the following UDP pair:
- GCS listens on: 14550 (receives telemetry)
- GCS sends to: 14551 (sends commands)

In QGroundControl
Configure a UDP link so that:
- QGC listens on port 14550
- QGC sends to port 14551

Once configured, the drone should connect automatically within a few seconds.

#### If the GCS does not connect
Some setups occasionally need a clean reconnect sequence. If QGC does not connect:

- Keep the drone connected over USB, and restart the drone while QGC is running and the Python bridge is active.
- If it still fails, close/reopen the UDP link in QGC and try again.

### Step 4 — Set up joystick control and flight-mode buttons
Before arming anything, configure manual control:

1. In your GCS, enable [Joystick/Gamepad control](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/setup_view/joystick.html).
2. Verify channel mapping looks sensible (roll/pitch/yaw/throttle).
3. Configure at least two easily reachable buttons/switches for the following modes:

```
LOITER
LAND
```

LOITER is the first “assisted” indoor hold mode you’ll validate. LAND is your immediate, repeatable exit.

### Step 5 — Pre-flight checks inside the GCS
With the drone connected to the GCS, verify the essentials:

1. Sensor sanity checks
- Optical flow: verify flow data is present/healthy (not stuck / not all zeros)
- ToF rangefinder: verify distance updates when you lift/lower the drone by hand
- Estimator health: ensure no critical EKF failsafes or sensor missing warnings

2. Logging check (if SD deck installed)
- Confirm the SD card deck is detected.
- Confirm logging is enabled and that a new log will be created on arming / flight

3. Manual control check
- With props armed only when you’re ready, but before takeoff:
    - Lightly raise throttle and confirm motor response is smooth and symmetric
    - Confirm roll/pitch inputs tilt the drone in the expected direction (if you’re doing this while held, do it gently and safely)

### Step 6 — Choose a safe indoor flight space
This first flight should be done indoors, in a simple environment:

- Clear floor area with several meters of buffer
- Good lighting
- Visible floor texture for optical flow (avoid glossy, uniform, or featureless floors)
- No fans / strong drafts
- Keep people back and wear eye protection if available

Place the drone flat on the floor and let it sit still for a moment before takeoff.

### Step 7 — The first-flight sequence
1. Take off in STABILIZE
- Arm the drone.
- Take off in STABILIZE mode.
- Climb slowly to approximately 1 meter altitude.
- Hold for a moment and confirm:
    - Controls feel responsive
    - No abnormal oscillations
    - Altitude is stable enough to proceed

2. Switch to LOITER and hover
- Activate LOITER using your assigned button.
- Maintain hover for at least 5 seconds.

During this hover, ArduPilot should begin learning / refining values that matter per airframe (see below). If the hover is unstable, don't fight it, activate LAND and reassess.

3. LAND and disarm
- Activate LAND mode.
- Let the drone land completely.
- Disarm only after it has fully settled.

### Step 8 — Save parameters to your PC
After a successful first flight, immediately save parameters from the vehicle to your PC. These are per-drone and important for consistent behavior later.

You are primarily interested in:

1. Hover throttle

```
MOT_THST_HOVER
```
This value is learned/updated during stable hover and is extremely useful for consistent altitude control and later autonomous behavior.

2. FFT / notch filter parameters

FFT-based tuning and notch filtering values can differ between drones due to:

```
[Placeholder]
```

Save all relevant FFT and notch filter-related parameters for this specific airframe.

Even if two drones are identical builds, these learned parameters often differ enough that you want them saved per unit.

## If the flight was not good
If the hover was unstable or LOITER performance was poor:

- Repeat the first-flight sequence again after addressing obvious issues (props, balance, sensor mounting, lighting, flow surface).
- Be aware that ArduPilot updates learned values over time during hover states, so you may need multiple short LOITER hovers before the vehicle settles into its best behavior.

Do not proceed to autonomous or swarming modes until:

- STABILIZE takeoff is predictable
- LOITER hover is stable for multiple attempts
- LAND is reliable
- Parameters have been saved successfully

## You’re ready for autonomous flight when…
- You can repeat the above flight consistently
- MOT_THST_HOVER has converged to a stable value
- Vibration/FFT-related parameters are saved for that drone
- Flow + ToF are verified healthy in the GCS
- Logging is confirmed working

At that point, move on to the autonomous flight guides [Placeholder] and (later) swarm bring-up [Placeholder].