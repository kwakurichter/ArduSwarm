# Flashing the NRF Guide
## What does the NRF do?
The Crazyflie 2.1 pairs its STM32 flight controller MCU with a Nordic nRF51822 (NRF51) as a dedicated “board controller”. The nRF51 handles all 2.4 GHz radio transport (CRTP), framing and forwarding packets via Syslink to the STM32, so the flight controller stays focused on control loops.

It also manages the power system (battery measurement, regulator enable/disable, and safe power-up/down sequencing) and provides the over-the-air (and USB-bootloader) flashing interface for both itself and the STM32.

By offloading radio, power management, and bootloading tasks to this low-power SoC, the Crazyflie achieves reliable telemetry and firmware updates without burdening the main flight processor.

## Why Flash the NRF?
The main reason for flashing the NRF is to add ArduPilot communication functionality. In essence, we want to modify the NRF firmware slightly to allow the NRF to act as a telemetry forwarding radio without touching the critical underlying functionality discussed previously.

## Getting the Firmware
The modified firmware lives in [nrf-firmware-cus](https://github.com/kwakurichter/nrf-firmware-cus), which is included in this repository as a submodule under `submodules/nrf-firmware-cus`.

If you only want to flash a working image, download `cf2_nrf.bin` (or `cf2_nrf.hex`) from the [Releases page](https://github.com/kwakurichter/ArduSwarm/releases) and skip ahead to [Compiling and Flashing](#compiling-and-flashing). Remember that the nRF51, STM32, and Crazyradio images are version dependant and must come from the same release and be flashed in the correct order.

To build from source, set up a local development environment by following the Bitcraze guide:

https://www.bitcraze.io/documentation/repository/crazyflie2-nrf-firmware/master/development/starting_development/

## What the Custom Firmware Changes
Earlier versions of this guide walked through manually editing the Bitcraze sources. Those edits are now maintained in `nrf-firmware-cus`, so you no longer need to apply them yourself. For more details, see [the AP_Syslink doc](/docs/development/ap_syslink.md).

### Simultaneous telemetry and P2P
The combined effect of the new drievr is that the nRF51 can carry an ArduPilot telemetry stream and P2P broadcasts at the same time, rather than being dedicated to one or the other. The two streams are tagged with distinct Syslink types and interleaved on the same radio link.

The available MTU has also been raised to 252 bytes, up from the original 31 byte CRTP payload. Most MAVLink messages now fit in a single packet, removing the fragmentation and reassembly round trip that previously added latency and dropped messages under load.

Because the packet size is negotiated across the whole radio path, the matching [Crazyradio dongle firmware](crazyradio_dongle.md) and STM32 build are required.

## Compiling and Flashing
Once you have setup your build environment, we can move on to compiling and flashing the firmware.

Note that the Crazyflie must be flashed with the Bitcraze firmware for this to work. If you need to restore your Crazyflie to the factory firmware, please reference the [Restoring the Crazyflie Guide](restoring_the_crazyflie.md) before proceeding.

### Prepare for Flashing
- Start by inserting your CrazyRadio PA dongle into your PC.
- Put your Crazyflie into bootloader mode:
    - Disconnect all power sources (remove battery, unplug usb cable).
    - Press and hold the power button. While holding the power button:
        - Plug the usb cable into the drone.
        - The M2 LED should begin blinking slowly.
        - Release the power button.
          <video width="600" controls>
            <source src="/docs/images/quick_start_guide/bootloader-first.mp4" type="video/mp4">
          </video>

### Compile and Flash
Once you are ready to flash:
- Open a terminal.
- If you set up your build environment in a virtual environment, ensure your Python interpreter has access to the required prerequisites.
- Navigate to the NRF firmware submodule:
```
path\...\ArduSwarm\submodules\nrf-firmware-cus
```
- It is good practice to clean your build objects at this time (in case some submodules have been updated):
```
make clean
```
- Next, compile and flash the NRF over-the-air:
```
make cload
```

![Flashing the NRF](/docs/images/flashing_the_nrf/flashing.png)

- After the firmware is finished flashing, the Crazyflie should automatically reboot.

Your NRF is now flashed with your custom firmware. Note that flashing the NRF with this method does not affect the firmware that is present on the main STM32 microcontroller.

If you need to restore the NRF to the factory Bitcraze firmware for any reason, repeat the above instructions with the Bitcraze NRF repository.