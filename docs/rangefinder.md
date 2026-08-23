# RangeFinder Guide
## What is ToF?
Time of flight (ToF) rangefinders like the VL53L1x work by emitting short, nanosecond scale pulses of invisible 940 nm laser light and then timing how long it takes for those pulses to bounce off a target and return to the sensor’s SPAD (single photon avalanche diode) detector.

![RangeFinder Principle](/docs/images/rangefinder/rangefinder_2.png)

*Craig, R. “Time-of-Flight Camera.” Wikipedia, Wikimedia Foundation, 16 May 2021, en.wikipedia.org/wiki/Time-of-flight_camera.*

Inside the VL53L1x module, ST’s FlightSense firmware on a tiny onboard microcontroller precisely timestamps the emission and reception events with picosecond resolution. By applying the known speed of light to the measured round trip time, the sensor computes an absolute distance (up to 4 m at rates up to 50 Hz), independent of ambient lighting or target reflectivity.

The Crazyflie 2.1 supports the Bitcraze FlowDeck, which is an external optical flow expansion deck that relies on accurate altitude estimates from the VL53L1x (https://www.bitcraze.io/products/flow-deck-v2/).

This guide will focus on getting the VL53L1x ToF sensor working in ArduPilot. To do this, we need to make a few critical changes to the ArduPilot firmware.

As mentioned in previous guides, due to the lightweight construction of the Crazyflie drones, we need to enable certain additional features that have been disabled by default to save flash storage space. This is because the main MCU on the Crazyflie (STM32) has limited onboard flash of 1 Mb which is less than the minimum 2 Mb required for the full build of ArduPilot.

## VL53L1x in ArduPilot
Previous builds of ArduPilot already contain a driver for the VL53L1x sensor however, this legacy implementation manually initializes and handles the sensor which does not work with the FlowDeck VL53L1x for some unknown reason.

Instead of attempting to fix the manual implementation, we include the API directly from the manufacturer to handle the low-level device operation. This provides a more robust, isolated driver implementation.

To do this, we need to modify the existing VL53L1x driver in the legacy base ArduPilot firmware. For more details on how this was done, see the [tof driver doc](/docs/development/tof_driver.md).

## Compiling & Flashing to the Crazyflie
Before using the new range finder driver in ArduPilot, we need to compile the custom firmware and flash it the Crazyflie. For detailed flashing instructions, please reference the [Compiling & Flashing Guide](/docs/compiling_and_flashing.md).

Range finders are not intended for lightweight MCU’s such as the STM32 found on the Crazyflie. ArduPilot only enables range finders by default on boards with at least 2 Mb of flash. As a result, we may need to free up more space to meet the 1 Mb hardware memory limitation.

If you attempt to compile your firmware and get a build failed error:
```
Build failed -> task in 'bin/arducopter' failed (exit status 1)
```
Chances are you have exceeded the memory limit. Please reference the [Freeing up Memory Guide](/docs/freeing_up_memory.md) for detailed instructions on how to minimize the build size.

## Testing and Using ToF
Once you have successfully flashed your custom firmware with range finders enabled, using the flow deck is relatively simple. Start by changing the parameter “RNGFNDX_TYPE” from 0 to 50 upon startup of your drone. Type 50 is the FlowDeck backend; do not use 16, which is the unrelated VL53L0X driver and is not compiled into this build.

After changing the parameter value and saving it to memory, restart the system by either cutting power to the drone directly or sending a reboot command through MAVLink.

Once the system has restarted, several new range finder parameters should now be available. Ensure that all new range finder parameters are set to match the following:
```
RNGFNDX_ADDR     41
RNGFNDX_FUNCTION 0
RNGFNDX_GNDCLR   0.100000
RNGFNDX_MAX      7.000000
RNGFNDX_MIN      0.200000
RNGFNDX_OFFSET   0.000000
RNGFNDX_ORIENT   25
RNGFNDX_PIN      -1
RNGFNDX_POS_X    0.000000
RNGFNDX_POS_Y    0.000000
RNGFNDX_POS_Z    0.000000
RNGFNDX_PWRRNG   0
RNGFNDX_RMETRIC  1
RNGFNDX_SCALING  3.000000
RNGFNDX_STOP_PIN -1
RNGFNDX_TYPE     16
```
After saving these new parameters, restart the system again.

The ToF sensor on the flow deck should now initialize properly upon powering the system. In your Ground Control Station of choice (ie. QGroundControl, MavProxy, etc.), verify the sensor is working properly by monitoring the live feed of the RANGEFINDER parameter.

![QGC RangeFinder](/docs/images/rangefinder/rangefinder_1.png)

If the RANGEFINDER parameter is present and the values are updated when the drone moves, the VL53L1x sensor is likely functioning properly.
