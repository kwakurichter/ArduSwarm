# Battery Monitor Setup
## Background
An important parameter to keep track of during autonomous flight is the battery status of the drone. The Crazyflie 2.1 uses a small, single cell 250 mah LiPo battery to power the entire system. As a result, the Crazyflie 2.1 can only fly for around 10 to 15 minutes off of a full charge. 

This means we need to carefully monitor the state of the battery to avoid crashes during an autonomous mission.

## Implementation
Most flight controllers monitor the state of the battery directly or through a external power management unit such as an ESC. The Crazyflie 2.1 delagates all of the power management tasks to its secondary MCU (Micro-Controller Unit), the NRF51.

In the Bitcraze firmware, the NRF51 polls the battery at regular intervals for state updates (i.e. voltage, temperature, charging status, etc.) and then sends the data over serial to the main STM32 flight controller over serial.

For ArduSwarm we adopt a similar strategy, using the MAVLink protocol rather than Bitcraze's proprietary protocols.

### How It Works
The battery monitor works by using the communication infrastructure developed for the [CrazyRadio](/docs/crazyradio.md) implementation. If you have not already enabled CrazyRadio on your drone, please follow that guide before proceeding.

1. **NRF51 Battery Status**
- On boot, the NRF51 begins polling the battery for state updates as a backend task.
- The NRF51 firmware provides access to these state updates on the frontend through a user API.

2. **Uplink: STM32 → NRF51 → GCS**
- The NRF51 requests the current voltage, temperature, and charging state, then serializes the battery status into MAVLink frames.
- The frame is wrapped in Syslink and buffered until the serial port is open. A battery state packet is 13 bytes, so it always fits in a single chunk — the fragmentation the earlier implementation needed no longer applies.
- The STM32 strips the Syslink envelope and passes the frame to the MAVLink parser.
- Once parsed, battery status messages update the battery state by using the battery scripting driver.

## Firmware Support
Battery monitoring is handled by `AP_Syslink` in the [ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus) fork, together with the battery polling in the custom nRF51 firmware. Both are already in place if you build from those repositories or flash a [release](https://github.com/kwakurichter/ArduSwarm/releases).

Earlier versions of this guide walked through patching ArduPilot's receive path by hand. That work now lives in the driver, which decodes `BATTERY_STATUS` messages arriving from the nRF51 and feeds them into ArduPilot's battery monitor through the scripting backend. The backend then updates the internal battery state periodically.

The one build requirement is that the battery scripting driver is compiled in. This is enabled in the Crazyflie hardware definition, which defines `AP_BATTERY_SCRIPTING_ENABLED` so the driver survives the feature minimization applied to fit the STM32's flash budget. See the [Freeing up Memory Guide](/docs/freeing_up_memory.md) if you are managing your own build configuration.

## Compiling & Flashing to the Crazyflie
Before using the new battery monitor driver in ArduPilot, we need to compile the custom firmware and flash it the Crazyflie.

For detailed flashing instructions, please reference the [Compiling & Flashing Guide](/docs/compiling_and_flashing.md).

If you attempt to compile your firmware and get a build failed error:
```
Build failed -> task in 'bin/arducopter' failed (exit status 1)
```
Chances are you have exceeded the memory limit. Please reference the [Freeing up Memory Guide](/docs/freeing_up_memory.md) for detailed instructions on how to reduce the build size.

## Testing and Using Battery Monitor
Once you have successfully flashed both the NRF51 and the STM32 with the custom firmware, we are ready to enable the battery monitor in ArduPilot.

Start by changing the following parameters upon startup of your drone:

```
SERIAL1_PROTOCOL 2
SERIAL1_BAUD     115
SERIAL2_PROTOCOL 52
SERIAL2_BAUD     1000
SERIAL3_PROTOCOL 2
BATT_MONITOR     29
```

Changing the serial protocol and baudrate of port 2 to MAVLink and 1M respectively allows the STM32 to communicate with the NRF51. Changing the battery monitor parameter to 29 enables the scripting driver.

After changing the parameter values and saving them to memory, restart the system by either cutting power to the drone directly or sending a reboot command through MAVLink.

The battery monitor should now initialize properly upon powering the system. In your Ground Control Station of choice (ie. QGroundControl, MavProxy, etc.), verify the sensor is working properly by monitoring the live feed of the battery state:

![Battery Monitor](/docs/images/battery_monitor/battery-monitor.png)

Note that the current implementation has a bug which causes the voltage to report incorrectly in the QGC as shown in the above photo. Please check the MAVLink stream `BATTERY_STATUS` for the correct voltage.