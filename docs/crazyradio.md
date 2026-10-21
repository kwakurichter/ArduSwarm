# Crazyradio Guide
## Communication in ArduPilot
ArduPilot’s communication stack is built around the MAVLink protocol which is a lightweight, header-based, binary framing system that defines every telemetry packet, command, and parameter exchange between the drone and Ground Control Station (GCS) or companion computers.

On startup, each enabled serial, USB or radio interface is instantiated as a “COMM_PORT” with its own send and receive buffers managed by AP_HAL (Hardware Abstraction) layer.

When the drone wants to send data (e.g. attitude, GPS, sensor readings), it calls into mavlink_msg_x_send() functions to serialize fields into a MAVLink frame (including sequence number, system/component IDs, length, and CRC), then hands that frame to the communication driver.

Incoming MAVLink data are fed into mavlink_parse_char(), which reconstructs messages, checks integrity, and sends them to the appropriate handler (parameter manager, mission planner, or scripting engine).

By decoupling message definition (in an XML) from the transport layer, ArduPilot can easily support multiple MAVLink versions, throttle bandwidth per-port, and automatically fragment large payloads, ensuring robust communication across a wide range of links and bandwidth constraints.

## Communication on Crazyflie

Stock Bitcraze applications use CRTP over the Crazyflie's radio and Syslink between the nRF51 and STM32. The current ArduSwarm application uses a custom large packet MAVLink transport instead.

The GCS tools send an ESB payload with a one byte marker and up to 251 bytes of MAVLink data. The nRF51 forwards these opaque chunks over Syslink; it does not parse MAVLink. The host and STM32 reconstruct complete MAVLink frames. Frames larger than one chunk can span packets, and the host maintains a separate receive stream for each aircraft so fragments from different drones do not mix.

Use the supplied `crazyradio2_large.py` driver and bridge/hub for this link. Stock `cflib` is still used for the legacy bootloader workflow, but not for application telemetry. See the [GCS guide](custom_gcs_guide.md) for the current 1 to 4 drone setup.

### Telemetry and P2P Together
Earlier versions of this pipeline had to choose between carrying a GCS telemetry stream and carrying peer-to-peer broadcasts, because both competed for the same radio path and the same small CRTP payload budget.

As of this release the nRF51 firmware multiplexes both streams simultaneously. Telemetry destined for the GCS and P2P broadcasts destined for peer drones are tagged with distinct Syslink packet types and interleaved on the same link, so a drone can hold a live GCS connection while participating in the swarm mesh.

### Packet Size
The original CRTP payload limit was 31 bytes, which meant every MAVLink message larger than that had to be fragmented on the STM32, reassembled on the receiving end, and reassembled again if a fragment was lost. This added latency and was a common source of dropped messages under load.

The available MTU is now 252 bytes. Most MAVLink messages fit in a single packet, which removes the fragmentation round trip for the common case and substantially reduces link latency.

This larger MTU is the reason the radio components are version dependant. The STM32 firmware, the nRF51 firmware, and the Crazyradio dongle firmware all have to agree on the packet size, so all three must come from the same release.

## The AP_Syslink Driver
**`AP_Syslink`** is a self contained ArduPilot library in the [ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus) fork which handles all communication on the ArduSwarm platform.

### What the driver does
- **Frames and deframes Syslink.** Handles the 0xBC/0xCF sync bytes, packet type, length field, and Fletcher-8 checksum in both directions, so the rest of ArduPilot only ever sees clean MAVLink.
- **Manages the radio handshake.** Sends the channel, data rate, and address configuration packets the nRF51 expects at boot, and tracks link readiness before allowing traffic.
- **Buffers outbound traffic on its own task.** Outgoing packets are queued and drained by a dedicated scheduler task rather than the main GCS loop, so radio backpressure does not stall the flight code. The buffer is written atomically per message: if a message will not fit, it is dropped whole rather than being fragmented.
- **Separates telemetry from P2P.** Telemetry is handed to the standard MAVLink parser; P2P broadcasts are routed to `AP_SwarmMesh` and, where configured, forwarded to the AI deck for onboard processing.
- **Injects nRF51 sensor data.** Battery state measured by the nRF51 arrives over the same link and is fed into ArduPilot's battery monitor. See the [Battery Monitor Guide](battery_monitor.md).

### Enabling the driver
`AP_Syslink` attaches to the serial port wired to the nRF51. Configuration is done entirely through parameters — see [Testing and Using Crazyradio](#testing-and-using-crazyradio) below.

## Flashing the NRF51
The next step to getting the Crazyradio working in ArduPilot is to flash the NRF51 with a custom version of the Bitcraze firmware. This step should be completed first before compiling and flashing the custom ArduPilot firmware.

Please reference the [Flashing the NRF Guide](/docs/flashing_the_nrf.md).

## The Crazyradio Dongle
To talk to an ArduSwarm drone from a ground station you also need a Crazyradio 2.0 running the ArduSwarm dongle firmware, which understands the larger packet size. A stock Bitcraze dongle will not decode 252 byte packets.

Please reference the [Crazyradio Dongle Guide](/docs/crazyradio_dongle.md).

## Compiling & Flashing to the Crazyflie
Before using the new Crazyradio in ArduPilot, we need to compile the custom firmware and flash it the Crazyflie. For detailed flashing instructions, please reference the [Compiling & Flashing Guide](/docs/compiling_and_flashing.md).

Prebuilt images are also published on the [Releases page](https://github.com/kwakurichter/ArduSwarm/releases) if you would rather not build from source.

If you attempt to compile your firmware and get a build failed error:
```
Build failed -> task in 'bin/arducopter' failed (exit status 1)
```
Chances are you have exceeded the memory limit. Please reference the [Freeing up Memory Guide](/docs/freeing_up_memory.md) for detailed instructions on how to reduce the build size.

## Testing and Using Crazyradio
Once you have successfully flashed your custom firmware with Crazyradio, using the custom protocol is a bit more involved than the legacy options. First, we need to change all of the serial protocols to MAVLink2 by changing the following parameters in your GCS of choice:
```
param set SERIAL2_PROTOCOL 52
```
Next, we need to change the baud rate of the NRF serial port to match what the NRF is expecting. Set the following parameter:
```
param set SERIAL2_BAUD 1000
```
After changing these parameters and saving them to memory, restart the system by either cutting power to the drone directly or sending a reboot command through MAVLink.

Once the system has restarted, the communication link should now be active. Connect to your drone from the GCS by referencing the [Custom GCS Guide](/docs/custom_gcs_guide.md).
