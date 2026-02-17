# OptiTrack Setup
## Background
If you have access to a motion capture system for 3D localization like an OptiTrack system, you will need to first enable its usage in software before using it within the ArduSwarm platform.

You will also need to add passive markers to each drone so the OptiTrack system can track the drones. We have designed a custom guard for the Crazyflie 2.1 Brushless which includes six marker mounting brackets. Note that our solution requires the Brushless varient over the legacy models as the guard adds around 15g in weight to the platform.

### Modify the HWDEF file
Start by enabling visual odometry in the hardware definition file:

- In your development environment, navigate to the Crazyflie hwdef file:
```
path\...\libraries\AP_HAL_ChibiOS\hwdef\crazyflie2_bl\hwdef.dat
```
- Near the bottom of the file, find the line that minimizes the ArduPilot features:
```
include ../include/minimize_features.inc
```
- Underneath this line, include the following line: 
```
define HAL_VISUALODOM_ENABLED 1        #OptiTrack Support
```
This tells the compiler to enable the visual odometry driver in our ArduPilot build regardless of any conditional statements.

## Compiling & Flashing to the Crazyflie
Before using the visual odometry driver in ArduPilot, we need to compile the custom firmware and flash it the Crazyflie.

For detailed flashing instructions, please reference the [Compiling & Flashing Guide](compiling_and_flashing.md).

If you attempt to compile your firmware and get a build failed error:
```
Build failed -> task in 'bin/arducopter' failed (exit status 1)
```
Chances are you have exceeded the memory limit. Please reference the [Freeing up Memory Guide](freeing_up_memory.md) for detailed instructions on how to reduce the build size.

## Testing and Using Motion Capture
Once you have flashed the STM32 with the custom firmware, we are ready to enable the motion capture localization in ArduPilot.

Start by changing the following parameters upon startup of your drone:

```
VISO_DELAY_MS	10
VISO_ORIENT	    0
VISO_POS_M_NSE	0.200
VISO_POS_X	    0.000
VISO_POS_Y	    0.000
VISO_POS_Z	    0.000
VISO_QUAL_MIN	0
VISO_SCALE	    1.000
VISO_TYPE	    1
VISO_VEL_M_NSE	0.100
VISO_YAW_M_NSE	0.200
[Placeholder]
```

After changing the parameter values and saving them to memory, restart the system by either cutting power to the drone directly or sending a reboot command through MAVLink.

### Hardware Setup
As mentioned previously, using OptiTrack in ArduSwarm requires several reflective trackers to be mounted on the drone. Our solution is to use a custom 3D printed guard which includes rigid mounting points for the OptiTrack markers.

Before using the OptiTrack system with ArduSwarm, please reference the [Guard Printing Guide](guard_printing_guide.md) and print yourself a guard.

### Python Script
[Placeholder]