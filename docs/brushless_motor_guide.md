# Brushless Motor Setup
## Background
If you are using the Crazyflie 2.1 Brushless model of drones, the main difference will be to enable the brushless motors in software. The brushed motors on the standard Crazyflie 2.1 series drones use standard PWM motor control and are thus easily configurable in ArduPilot. The brushless motors are controlled by onboard ESCs (flashed with BlueJay) which need to be configured to use DSHOT.

## Firmware Support
All of the changes described above are already applied in the [ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus) fork. Building the brushless target from that fork, or flashing `crazyflie2_bl-ArduSwarm-*_with_bl.hex` from a [release](https://github.com/kwakurichter/ArduSwarm/releases), is all that is required. For further implementation details, see [the BDSHOT doc](/docs/development/rcoutput_bdshot.md)

For reference, the brushless support consists of three pieces of work:

**A dedicated board target.** The brushless variant is registered as its own bootloader board type, distinct from the standard Crazyflie 2.1, so the two builds cannot be flashed onto the wrong airframe.

**Its own hardware definition.** The Crazyflie 2.1 hardware definition was copied and adapted for the brushless hardware, configuring the motor outputs for DShot rather than standard PWM.

## Compiling & Flashing to the Crazyflie
We now need to compile the brushless firmware and flash it the Crazyflie. For detailed flashing instructions, please reference the [Compiling & Flashing Guide](compiling_and_flashing.md).

## Testing and Using Brushless Crazyflie
Once you have successfully flashed your brushless firmware, we can use the brushless Crazyflies in the ArduSwarm platform. If you haven't yet configured the rest of the hardware, reference the [Hardware Setup Guide](hardware_setup.md) to properly assemble your ArduSwarm drone.

If you have already completed the hardware setup, you can move directly to the [Pre-Flight Checklist](pre_flight_checklist.md).