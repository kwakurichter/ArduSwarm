# Freeing up Memory Guide
## Why?
One of the primary features of Crazyflie drones is their lightweight construction. The drones use the STM32 MCU as the primary flight controller which is a relatively low-power microcontroller with limited memory (1 Mb of flash). ArduPilot by contrast is primarily designed for more capable boards with a minimum of 2 Mb of onboard flash.

For these limited boards, ArduPilot by default uses its “minimize_features.inc” script which cuts out all but the most essential base ArduPilot features. For all but the most basic applications using the bare the Crazyflie hardware, we need to enable features which have been disabled by the “minimize_features” function.

Additionally, modifying the base ArduPilot firmware can quickly eat up flash storage. In these cases, selecting additional features to cut from your custom build may be required to successfully compile your firmware.
## When?
If you notice your custom build will exceed the 1 Mb memory limit, you will need to consider trimming ArduPilot to size. This limitation will most likely present itself when you attempt compiling your custom firmware and get a build failed error:
```
Build failed -> task in 'bin/arducopter' failed (exit status 1)
```
Chances are you have exceeded the memory limit. I will go over some things you can do to further reduce memory used to hopefully get your firmware compiling.

## The hwdef flash diet

Most of the trimming for this port is now done **in the board's hardware
definition file**, not in `APM_Config.h`. Building from
[ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus) you get it
automatically.

The section lives near the bottom of:

```
libraries/AP_HAL_ChibiOS/hwdef/crazyflie2/hwdef.dat
```

It runs *after* `include ../include/minimize_features.inc`, so it takes effect on
top of ArduPilot's own minimization, and it strips roughly **117 KB** of features
the Crazyflie physically cannot use. That is what makes room for the ArduSwarm
libraries on a 1 MB F405.

Every entry is commented with what it removes and roughly what it saves. **To get
a feature back, comment its line out.**

### What gets removed

| Group | Saved | Rationale |
|---|---:|---|
| Hardware with no connector | ~46 KB | FrSky telemetry, camera, precision landing, rally points, RSSI, parachute, VideoTX, relays, servo relay events, IC engine, EFI, landing gear |
| Rangefinder backends | ~18.6 KB | All backends off, then only `FLOWDECK` re-enabled |
| Compass I2C backends | ~17 KB | Drops probing for every external I2C magnetometer |
| GPS UBLOX driver | ~9.3 KB | No GPS receiver indoors; the `AP_GPS` front end stays for EKF plumbing |
| Airspeed | ~8.5 KB | No airspeed sensor |
| Proximity / avoidance | ~6.9 KB | No proximity sensor |
| Terrain database | ~5.5 KB | Needs SD card map tiles |
| Buzzer (tone alarm) | ~2.8 KB | No buzzer |
| Optical flow backends | ~2.7 KB | All backends off, then only `FLOWDECK` re-enabled |
| Unused flight modes | — | Acro, Brake, Drift, Flip, SmartRTL, Sport, Throw |

### Three things worth knowing

**Sensor backends are cut to allowlists, not trimmed individually.** The pattern is
to disable the whole family and re-enable exactly what a Crazyflie deck carries:

```
define AP_RANGEFINDER_BACKEND_DEFAULT_ENABLED 0
define AP_RANGEFINDER_FLOWDECK_ENABLED 1
```

The consequence catches people out: with the default off, **any backend you add
later must be force-enabled by name** or it silently vanishes from the build and
its `RNGFND_TYPE` value matches nothing at runtime. The sensor simply never
appears, with no build error. The same applies to optical flow.

**Airspeed needs both an `undef` and a `define`.** `minimize_common.inc`
force-enables the individual airspeed backends, so turning off just
`AP_AIRSPEED_ENABLED` leaves them compiling against a base class that no longer
exists. Each backend has to be undefined and then explicitly set to `0`. If you
add a similar family-level disable, expect to need the same treatment.

**Flight modes moved here from `APM_Config.h`.** They were previously disabled in
`ArduCopter/APM_Config.h`, which applied them to *every* board built from the
tree. Putting them in the hwdef keeps the effect on this board only, alongside the
rest of the diet. `minimize_common.inc` already covers MOUNT, OSD, ZIGZAG and
FOLLOW.

### Features deliberately re-enabled

The diet is not purely subtractive. Several features are turned back **on**
because ArduSwarm needs them, above the diet section in the same file:

```
define AP_RANGEFINDER_ENABLED 1        # FlowDeck support
define AP_OPTICALFLOW_ENABLED 1        # FlowDeck support
define AP_BATTERY_SCRIPTING_ENABLED 1  # Battery monitor support
define MODE_GUIDED_NOGPS_ENABLED 1     # AI deck support
```

`AP_SWARMMESH_MAX_PEERS` is also pinned to 8 here rather than taking the
F4-class default of 18, since the peer table is allocated statically at its
compile-time maximum — see
[AP_SwarmMesh](development/ap_swarmmesh.md#memory-scales-with-the-board).

> After editing `hwdef.dat` you must re-run `./waf configure --board crazyflie2`.
> A failed configure leaves the *previous* board configured and the next
> `./waf copter` will happily rebuild that instead, so check the exit status.

## Free up Memory
- Navigate to the ArduCopter configuration file:
```
path\...\ardupilot\ArduCopter\APM_Config.h
```
This file lists several core features which can be disabled. To re-iterate, these features are generally considered core features and thus should only be disabled if absolutely necessary.
- Any feature you wish to disable, simply uncomment the line:
```
Ex.    //#define NAV_GUIDED    0  -->  Change to:   #define NAV_GUIDED    0
```
The approximate size of each of these features is listed in the comments of the configuration file. 
If you disable all of the features that can reasonably be disabled and are still running into memory limits, you will need to find a way to reduce the space used by your custom features.

## See also

- [Port Overview](development/port_overview.md) — build system and environment hazards
- [Compiling & Flashing Guide](compiling_and_flashing.md)
