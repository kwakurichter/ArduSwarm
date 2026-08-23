# Ranging Guide
## Background
Knowing where your peers are is fundamental to collision avoidance, formation control, and most of the swarm algorithms this platform exists to test. Position estimates broadcast over the mesh get you part of the way, but they inherit every error in each drone's own state estimate so two drones with drifting flow-based position solutions can disagree about how far apart they are while both believe their own estimate.

**`AP_Ranging`** measures the distance between drones directly, using the DWM1000 ultra-wideband (UWB) radio on the Bitcraze **Loco Positioning Deck**. Because the measurement is a property of the radio link itself rather than of either drone's navigation solution, it does not drift with the EKF.

## Hardware
This feature requires a [Loco Positioning Deck](https://www.bitcraze.io/products/loco-positioning-deck/) on each drone you want to range between. No anchors are required — ArduSwarm uses the deck for peer-to-peer ranging, not for anchor-based positioning, so you do not need to install or survey a Loco Positioning System.

Mount the deck according to the [Hardware Setup Guide](hardware_setup.md), and note that it consumes deck ports and adds weight; check your thrust margin before adding it alongside the AI deck.

## How It Works
### Alternate Double-Sided Two-Way Ranging
`AP_Ranging` uses the **Alternate Double-Sided Two-Way Ranging (DS-TWR)** algorithm. Two nodes exchange a timed sequence of messages, each recording precise transmit and receive timestamps. The distance follows from the time of flight, which is derived from those timestamps.

The reason for the double sided variant is clock error. Every node's clock runs at a slightly different rate, and in single sided ranging that offset maps directly into a distance error. By having both nodes contribute timing information to the exchange, the double sided scheme largely cancels the relative clock drift, giving a usable measurement without requiring the two radios to be synchronized.

The alternate formulation reduces the number of messages needed per measurement compared to the classical double sided exchange, which matters when many drones are competing for the same channel.

### Scheduling
Each vehicle initiates a ranging exchange with each configured peer every `RNG_POLL_MS` milliseconds. Random jitter is added on top of that base interval to desynchronize the nodes. Without it, drones that power up together tend to transmit in lockstep and collide on the channel repeatedly.

An exchange that stalls is abandoned after `RNG_XCHG_MS` and retried on the next cycle, so a single lost packet does not block ranging against that peer.

For more details on the implementation, see the [AP_Ranging doc](/docs/development/ap_ranging.md).

## Configuration
### Enabling the driver
`RNG_TYPE` defaults to `0` (off), so ranging does nothing until you enable the
DW1000 backend. This one needs a reboot to take effect:

```
param set RNG_TYPE 1
```

### Selecting peers
Only configured peers are polled. Populate the peer slots with the system IDs you want to range against:

```
param set RNG_PEER_1 2
param set RNG_PEER_2 3
```

A value of `0` leaves a slot unused. Because polling is explicit, ids need to be assigned deliberately rather than discovered — decide your `MAV_SYSID` assignments across the swarm first.

### Radio channel
All nodes on the network must agree on the UWB channel:

```
param set RNG_CHAN 2
```

### Antenna delay calibration
`RNG_ANT_DLY` is the single most important parameter for accuracy. It compensates for the fixed delay between the radio and the antenna, applied to both transmit and receive, in DW1000 device time units of roughly 15.65 ps each.

Calibrate it by placing two drones at an accurately known separation and adjusting the value until the reported distance matches. An uncalibrated antenna delay shows up as a constant offset in every measurement, so a single calibration at a known distance is usually enough to correct the whole range.

### Timing
`RNG_REPLY_US` sets the delay before each TWR reply is sent. It must exceed the servicing latency of roughly 1 ms — setting it too low causes exchanges to fail because the node has not finished processing the previous message when the reply is due.

### Forwarding and debugging
`RNG_FWD_PORT` names a serial port that the peer range table is forwarded to as a MAVLink `TUNNEL` message, letting a companion computer consume live range data for onboard algorithms. See the [Companion Computer Guide](companion_computer_guide.md).

`RNG_DEBUG` enables verbose ranging diagnostics over MAVLink. It is useful when bringing up a new set of decks, but leave it off in flight — the extra traffic competes with telemetry.

## Testing
1. Fit Loco Positioning Decks to at least two drones and flash matching firmware.
2. Assign unique system IDs, then set `RNG_PEER_*` on each drone to point at the others.
3. Set the same `RNG_CHAN` on every drone.
4. Place two drones at a measured distance apart, power up, and enable `RNG_DEBUG` to watch the reported range.
5. Adjust `RNG_ANT_DLY` until the reported distance matches the true distance then disable `RNG_DEBUG`.

Range data is written to the dataflash log for post-flight analysis — see the [Logging Guide](logging_guide.md).

## Current Limitations
`AP_Ranging` reports distance, not relative position. Turning a set of inter-drone distances into a relative position solution requires fusing the ranges with the mesh position broadcasts. That fusion step is future work; see the Future Work section of the [README](../README.md).

## Further Reading
The library sources live in [`libraries/AP_Ranging`](https://github.com/kwakurichter/ArduPilot_cus/tree/master/libraries/AP_Ranging) in the ArduPilot_cus fork.