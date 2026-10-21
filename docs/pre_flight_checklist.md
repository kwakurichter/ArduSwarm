# Pre-Flight Checklist
If you have reached this point with your ArduSwarm drones, it means you have:

- Flashed all of the custom firmware on the:
    - [AI Deck](/docs/companion_computer_guide.md), if installed.
    - [NRF51 MCU](/docs/crazyradio.md).
    - [STM32 MCU](/docs/compiling_and_flashing.md).
- Assembled all of the required [hardware](/docs/hardware_setup.md):
    - Crazyflie 2.1.
    - Flow Deck v2.
    - SD Card Deck.
    - Micro SD card (any brand).
    - AI Deck, if using onboard companion applications.
    - One or two Crazyradio 2.0 dongles with matching firmware for the GCS workflow.

Congratulations! You are almost ready for the first flight!

This final checklist will ensure your first flight doesn't end in disaster.

## Checklist
1. Inspect the propellers on your drone.
- Make sure there the propellers are not damaged. Large bends or cracks can cause performance issues which can lead to instability.

- Ensure your propellers are correctly installed. 
    - The leading edge of each propeller (the higher edge) must be facing the same direction as the direction of travel of each motor.
    - On quadcopters like the Crazyflie, opposing motors travel in the same direction.

2. Check the position of the battery.
- Make sure the battery is positioned in the center of the drone and not hanging off to one side.

3. If an AI Deck is installed, make sure it is functioning properly. Otherwise, verify the Crazyradio link using the [GCS guide](custom_gcs_guide.md).
- Check if both green LEDs on the top of the AI Deck are blinking.
- Check if the WiFi access point from the AI Deck is visable.
- If either of these conditions are not met, check if the reset pin is touching the bottom of the AI Deck, described [here](/docs/hardware_setup.md).
- If so, push the exposed pin down and try restarting the drone.

4. Upload the parameters to the drone.
- Turn on your assembled drone and plug it into your computer via the micro USB cable.
- Open your GCS (Ground Control Station) of choice.
- Download the default ArduSwarm parameters [here](/docs/parameters).
- Navigate to the parameter tool in your GCS.

- Review and apply the brushless parameter snapshot to the matching hardware. Preserve calibration and assign a unique `MAV_SYSID` afterward. The snapshot uses `SYSL_CHAN=80`, selects `MOT_THST_MODEL=1`, and disables battery failsafe actions; review these settings for the installed firmware and test setup. See the [migration notes](release_notes.md).

- Restart your drone.

Alternatively, you can start from the [parameter file](/docs/parameters/bl_v2.2.2.params) in this repository and configure the drone manually by installing [ArduPilot Methodic Configurator](https://github.com/ArduPilot/MethodicConfigurator) on your PC and following the onscreen instructions.

5. Calibrate Sensors (i.e. accelerometer, gyroscope, barometer).
- Plug your assembled drone into your computer with the micro USB cable.
- Open your GCS (Ground Control Station) of choice.
- Navigate to the sensor settings in your GCS.

- Starting with the accelerometer, follow the onscreen instructions for the sensor calibrations offered by your GCS.

- Restart the drone as directed.

6. Test Motors
- Remove the propellers before bench motor tests.
- Plug your assembled drone into your computer with the micro USB cable.
- Open your GCS (Ground Control Station) of choice.
- Navigate to the motor settings in your GCS.
- Set the throttle to a low value (between 5 to 10%).

- Test each motor individually, ensuring each motor spins in the correct direction as described in step 1 and each motor spins at approximately the same speed.

- Test all of the motors together and ensure all motors spin at approximately the same speed.

## Telemetry Manual Mode
For manual flight over the Crazyradio GCS link (or an optional AI Deck telemetry link), set up joystick control on your GCS before proceeding:

- [QGroundControl](https://docs.qgroundcontrol.com/Stable_V4.3/en/qgc-user-guide/setup_view/joystick.html)
- [Mission Planner](https://ardupilot.org/copter/docs/common-joystick.html)
- [MavProxy](https://ardupilot.org/mavproxy/docs/modules/joystick.html)

## Before a GCS scripted group flight

- Verify all expected drones appear with distinct `MAV_SYSID` values and fresh telemetry. Check each URI against its configured channel.
- Confirm optical flow and rangefinder data update correctly on each drone. Use `FLOW_TYPE=9` and `RNGFND1_TYPE=50` for the Flow Deck backends.
- Complete individual manual flight checks before running group missions.
- Run only one hub/bridge process per dongle. For four drones, use the [two-dongle roster](custom_gcs_guide.md#four-drones-on-two-dongles).
- Preview the mission, place drones on the printed layout with matching headings, and select explicit target IDs. The default 4 drone square has 1.25 m sides.
- Check the updated guard's attachment, propeller clearance, and any motion capture marker geometry.

## Next Step, Flight!
You are now ready to begin flying ArduSwarm! Please proceed to the [First Flight Guide](/docs/first_flight.md).
