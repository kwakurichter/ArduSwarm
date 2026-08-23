# Optical Flow Guide
## What is Optical Flow?
ArduPilot ArduCopter supports a variety of optical flow sensors which estimate horizontal velocity.
Optical flow velocity estimation works by analyzing successive frames from a downward facing camera to detect how small image features (edges, corners or textured patches) shift from one frame to the next. The onboard flow algorithm computes a 2D pixel displacement field by matching these features across frames at a known frame rate.

![Optical Flow Principle](/docs/images/optical_flow/optical_flow_1.png)

*Gordon, Andrew. “Adventures in Optical Flow.” Technology, Thinking, Doing, 20 June 2021, www.andrewgordon.me/posts/Adventures-in-Optical-Flow/.*

Because the physical distance each pixel represents depends on the drone’s height above ground, the system also uses a Time of Flight (ToF) sensor’s vertical distance reading to establish a scale factor (approximately height / focal length).

Multiplying the measured pixel shifts by this scale and dividing by the time between frames yields the horizontal velocity of the vehicle relative to the ground. By continuously updating with each new image and height measurement, the autopilot obtains real time, drift corrected velocity estimates even in GPS denied environments.

The Crazyflie 2.1 supports the Bitcraze Flow Deck, which is an external expansion deck with a PWM3901 optical flow sensor and a VL53L1x ToF sensor (https://www.bitcraze.io/products/flow-deck-v2/).

This guide will start with getting the PWM3901 optical flow sensor working in ArduPilot. To do this, we need to make a few critical changes to the ArduPilot firmware.

As mentioned in previous guides, due to the lightweight construction of the Crazyflie drones, we need to enable certain additional features that have been disabled by default to save flash storage space. This is because the main MCU on the Crazyflie (STM32) has limited onboard flash of 1 Mb which is less than the minimum 2 Mb required for the full build of ArduPilot.

## PWM3901 in ArduPilot
To get the FlowDeck working in ArduPilot, we need to modify the base ArduPilot firmware to include a new driver for the PWM3901 sensor. For more details on how this was done, see [the optical flow driver](/docs/development/optical_flow_driver.md).

## Testing and Using Optical Flow
Once you have successfully flashed your custom firmware with optical flow enabled, using the flow deck is relatively simple. Start by changing the new parameter FLOW_TYPE from 0 to 9 upon startup of your drone.

After changing the parameter value and saving it to memory, restart the system by either cutting power to the drone directly or sending a reboot command through MAVLink.

Once the system has restarted, several new optical flow parameters should now be available. Ensure that all new optical flow parameters are set to:
```
FLOW_ADDR        0
FLOW_FXSCALER    -600
FLOW_FYSCALER    -600
FLOW_ORIENT_YAW  0
FLOW_POS_X       0.000000
FLOW_POS_Y       0.01
FLOW_POS_Z       0.01
```
After saving these new parameters, restart the system again.

The flow deck should now initialize properly upon powering the system. In your Ground Control Station of choice (ie. QGroundControl, MavProxy, etc.), verify the sensor is working properly by monitoring the live feed of the OPTICAL_FLOW parameter.

![QGC Optical Flow](/docs/images/optical_flow/optical_flow_3.png)

If the OPTICAL_FLOW parameter is present and the values are updated when the drone moves, the PWM3901 sensor is likely functioning properly.
