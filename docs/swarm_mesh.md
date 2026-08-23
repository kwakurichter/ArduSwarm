# Swarm Mesh Guide
## Background
**`AP_SwarmMesh`** is a decentralized peer-to-peer mesh networking library for ArduPilot. It lets drones relay messages on each other's behalf, so a message can reach a drone that is several hops away with no central coordinator and no ground station in the loop.

This library was developed as a Google Summer of Code project and has been proposed upstream as [ArduPilot PR #33881](https://github.com/ArduPilot/ardupilot/pull/33881).

## How It Works
### Decentralized by design
There is no master node and no routing server. Every vehicle maintains its own peer table, broadcasts its own state, and independently decides whether to forward what it hears. Drones can join or leave at any time; the remaining nodes simply stop hearing from a departed peer and eventually prune it.

### Multi-hop forwarding
Each packet carries a time-to-live. When a vehicle receives a packet that is not addressed to it, it decrements the TTL and rebroadcasts it if any hops remain. This is what allows traffic to cross a swarm that is wider than a single radio link. `P2P_TTL` sets the hop budget; the default allows a message to traverse a large mesh, and lowering it is the main lever for limiting rebroadcast traffic.

### Peer table
Each vehicle tracks what it has heard from every peer — position, attitude, status, and freshness. Entries that stop being refreshed go stale and are pruned on the interval set by `P2P_PRUNE_SECS`, which frees slots for new peers.

The table is periodically written to `APM/PEERS/peers.dat` on the SD card at the rate set by `P2P_SAVE_HZ`, so a vehicle that reboots mid flight  recovers its view of the swarm instead of starting blind.

### Stream rates
Rather than flooding the mesh, each class of telemetry is broadcast at its own configurable rate, mirroring how ArduPilot throttles its GCS streams:

| Parameter | Broadcasts |
|---|---|
| `P2P_SR_POSITION` | `GLOBAL_POSITION_INT`, `LOCAL_POSITION_NED` |
| `P2P_SR_EXTRA1` | `ATTITUDE`, `EKF_STATUS_REPORT` |
| `P2P_SR_EXT_STAT` | `SYS_STATUS`, `NAV_CONTROLLER_OUTPUT`, `POSITION_TARGET_GLOBAL_INT`, `MISSION_CURRENT` |
| `P2P_SR_COORD` | This vehicle's coordination state |

All are in Hz, and setting one to `0` disables that stream. Keeping unused streams at zero is the simplest way to stay inside the radio's bandwidth budget as the swarm grows.

Note that `P2P_SR_COORD` sends nothing until a Lua script or companion computer actually populates the coordination state. It is the transport for your algorithm's data.

### Transport backends
The mesh is transport-agnostic. On the Crazyflie it runs over the Syslink backend, which carries P2P broadcasts through the nRF51 radio alongside the normal GCS telemetry stream — see the [Crazyradio Guide](crazyradio.md). A serial backend and a SITL backend are also provided, the latter allowing a mesh to be exercised in simulation before it is flown.

## Configuration
### Basic setup
Set the swarm size and give each vehicle a unique system ID. `P2P_SWARM_SIZE` counts peers plus the GCS, and is capped by a max:

```
param set P2P_TYPE 2
param set P2P_SWARM_SIZE 4
param set MAV_SYSID 1
```

`P2P_TYPE 2` selects the syslink backend, which carries the mesh over the
Crazyflie's nRF51 radio. Without it the library is compiled in but inactive, and
no peer will ever appear. (`1` is the generic UART backend and `10` is the SITL
multicast backend — neither applies on this hardware.)

`P2P_HW_MASK` describes the radio hardware attached. Bit 0 set means a full-capacity radio; clear means a Lite radio is assumed. Set this to match your hardware before tuning stream rates, since it governs the available bandwidth.

### Choosing who to track
By default a vehicle tracks every peer it hears. If you only care about a specific neighbourhood, populate the `P2P_PEER_01` through `P2P_PEER_16` slots with the system IDs you want. As soon as any slot is non-zero, only listed peers are tracked:

```
param set P2P_PEER_01 2
param set P2P_PEER_02 3
```

This is worth doing in a large swarm — it bounds both memory use and the amount of traffic each vehicle processes.

### Directed messages
`P2P_DESTID` sets the system ID that transmitted messages are addressed to, for cases where you want point-to-point delivery across the mesh rather than a broadcast.

### Forwarding to a companion computer
`P2P_FWD_PORT` names a serial port that received peer MAVLink messages are forwarded to. Point it at the AI deck and onboard scripts can consume the full peer telemetry stream directly. See the [Companion Computer Guide](companion_computer_guide.md).

### Logging
Mesh traffic can be recorded to the dataflash log for post-flight analysis. `P2P_LOG_MASK` selects which received message types are logged, and `P2P_LOG_HZ` caps the combined write rate across all peers and message types so that logging cannot saturate the log during a busy flight.

```
param set P2P_LOG_HZ 50
```

See the [Logging Guide](logging_guide.md) for retrieving and analyzing logs.

## Testing the Mesh
1. Flash at least two drones with matching firmware from the same [release](https://github.com/kwakurichter/ArduSwarm/releases).
2. Give each a unique `MAV_SYSID` and set `P2P_SWARM_SIZE` on all of them.
3. Set a position stream rate on each, then power them up together.
4. Connect to one drone with your GCS and confirm the peer entries populate.

Because peer telemetry is forwarded as standard MAVLink, peers appear as additional vehicles in most ground stations. The [Crazyradio Dongle Guide](crazyradio_dongle.md) covers connecting to two drones at once and forwarding both streams to a single GCS.

## Further Reading
The library sources live in [`libraries/AP_SwarmMesh`](https://github.com/kwakurichter/ArduPilot_cus/tree/master/libraries/AP_SwarmMesh) in the ArduPilot_cus fork. The upstream discussion in [PR #33881](https://github.com/ArduPilot/ardupilot/pull/33881) covers the design rationale in more depth.
