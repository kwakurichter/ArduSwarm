# ArduSwarm: A Self-Contained Micro-Aerial Vehicle Testbed for Experimental Swarm Flight Control Robotics Research
## Overview
**ArduSwarm** is a project developed as part of a Master's in Mechanical Engineering at the **University of Ottawa**, designed to provide an accessible decentralized platform for research into drone swarm dynamics and defensive algorithms for indoor test environments. The platform leverages the **Bitcraze Crazyflie** hardware platform, which are small yet highly capable micro-copters, and integrates them with the **ArduPilot** flight control software (ArduCopter).


| ![Alt1](docs/images/README/bitcraze-logo.png) | ![Alt2](docs/images/README/ArduPilot-logo.png) | ![Alt3](docs/images/README/uottawa-logo.png) |
|--------------------------|--------------------------|--------------------------|


The primary goal of this project is to create a research tool that enables the practical testing of security algorithms within a distributed drone swarm. This involves significant development to port the Crazyflie hardware onto the ArduPilot software, unlocking a wide feature set for advanced research applications.

## 🚀 The Platform
### Hardware: Bitcraze Crazyflie 2.1 and 2.1 Brushless
The **Crazyflie** platform was chosen for its unique combination of a small form factor, wide-ranging capabilities, and a fully open-source ecosystem. It is targeted at researchers and enthusiasts, offering features crucial for decentralized swarm robotics, including:

- **Peer-to-peer communication**
- **Onboard localization** for indoor test environments
- Support for expansion decks, such as the **Flow Deck** for optical flow and ranging, and the **AI Deck** for additional onboard computation.

![2.1_BL](docs/images/README/hardware.jpg)

### Software: ArduPilot (ArduCopter)
**ArduPilot** is a professional-grade, open-source flight stack. Its adaptability and extensive feature set make it an ideal choice for this research platform. Key features include:

- Support for custom controllers, including a robust **L1 adaptive controller**
- **Scripting** (Lua and companion computer) for easy customization of drone behavior
- Support for various navigation methods, including flow-based **non-GPS localization**

A significant portion of this project has been dedicated to overcoming the limited default support for the Crazyflie in ArduPilot, enabling a powerful combination of hardware and software.

## ✨ Key Features
This platform is designed to meet the demands of advanced swarm robotics research, with a focus on the following requirements:

- **Peer-to-Peer Communication**: Enables drones to relay state updates and commands directly to each other.
- **Infrastructure-free Localization**: Utilizes the Flow Deck with its optical flow and Time-of-Flight (ToF) sensors for indoor navigation.
- **Relative Positioning**: Allows drones to be aware of their peers' positions for collision avoidance and formation control.
- **Robustness & Scalability**: Designed to perform reliably in various conditions and to scale from a few drones to dozens.
- **Ease of Use**: Aims to provide a straightforward user experience, regardless of their hardware or software expertise.
- **Open Source**: Both the hardware and software are fully open-source, promoting collaboration.
- **Onboard Computation**: Capable of running higher-order algorithms directly on the drone.
- **Detailed Logging**: Flight recording enables detailed post-flight analysis using existing ArduPilot tools.

## 🛠️ Getting Started
This section provides a guide to setting up a Crazyflie drone with the custom ArduPilot and Bitcraze firmware developed for this project.

If you are not interested in modifying the ArduPilot or Bitcraze firmware yourself, please reference the [Quick Start Guide](docs/quick_start_guide.md) and skip to the [Pre-Flight Checklist](docs/pre_flight_checklist.md) afterwards.

1. **Hardware Setup**
The hardware setup defines the default configuration of the Crazyflie 2.1 drones to enable all of the functionality developed as part of the ArduSwarm project. All drones in the swarm must be configured this way.

    Please reference the [Hardware Setup Guide](docs/hardware_setup.md) to build your ArduSwarm drones.

    Note that while the setup can be done at any time, flashing of the individual components (i.e. STM32, NRF51, AI-Deck) must be done individually before final assembly.

2. **Compiling and Flashing the Firmware**
The first step is to compile the custom ArduPilot firmware and flash it onto the Crazyflie. This process requires setting up a build environment for ArduPilot on your operating system.

    For detailed instructions, please refer to the [Compiling & Flashing Guide](docs/compiling_and_flashing.md).

3. **Enabling Onboard Sensors**
For indoor navigation, you will need to enable the optical flow and rangefinder sensors on the Flow Deck.

    **Optical Flow**: For detailed instructions on enabling the PWM3901 optical flow sensor, see the [Optical Flow Guide](docs/optical_flow.md).

    **Rangefinder (ToF)**: To enable the VL53L1x Time-of-Flight sensor, follow the [RangeFinder Guide](docs/rangefinder.md).

4. **Enabling Radio Communication**
To enable peer-to-peer communication and to connect to a Ground Control Station, the Crazyflie's radio system must be configured. 

    This is a two-part process involving the secondary nRF51 radio MCU and the main STM32 flight controller. 

    **First**, the nRF51 MCU must be flashed with a modified firmware. Please reference the [Flashing the NRF Guide](docs/flashing_the_nrf.md).

    **Second**, a MAVLink-to-Syslink translation driver must be enabled in the ArduPilot firmware. Please reference the [CrazyRadio Guide](docs/crazyradio.md).

    Note that this driver is still in active development. Currently, you will need to use a custom Ground Control Station to use the new radio driver ([Custom GCS Guide](docs/custom_gcs_guide.md)).

5. **Brushless Motor Support**
If you are using the newer Crazyflie 2.1 Brushless drones, you will need to update the motor driver before flying. If you are using the standard Crazyflie 2.1 hardware, skip this step.

    For detailed instructions, please refer to the [Brushless Motor Guide](docs/brushless_motor_guide.md).

6. **Using Lua Scripting for Custom Behavior**
Lua scripting allows you to add custom logic to the drone's behavior without modifying the core ArduPilot firmware. This is ideal for implementing and testing new algorithms.

    To get started with Lua scripting on the Crazyflie, please see the [Lua Scripting Guide](docs/lua_scripting.md).

7. **Logging Setup**
Logging is an essential tool for performance tuning, analyzing failures, and mission history. 

    To enable logging on the Crazyflie, please see the [Logging Guide](docs/logging_guide.md).

8. **Notch Filtering Setup**
FFT (Fast Fourier Transform) based notch filtering is a useful tool which allows us to target and attenuate unwanted IMU (Inertial Measurement Unit) disturbances to improve stability while minimizing performance loss.

    To enable notch filtering on the Crazyflie, please see the [Notch Filtering Guide](docs/notch_filtering_setup.md).

9. **Battery Monitor Setup**
Battery state updates are a critical function for autonomous flight. Without battery data, drones are at risk of catastrophic failure and unstable flight. The battery monitor driver enables battery state updates.

    Please reference the [Battery Monitor Setup Guide](docs/battery_monitor.md) for detailed instructions.

10. **Enable Companion Computer (AI Deck)**
A companion computer vastly expands the capabilities of the ArduSwarm platform. Using the AI deck, the user is able to connect to a Ground Control Station over WiFi via a full telemetry stream.
The AI deck also enables the user to write and deploy custom scripts which can facilitate autonomous missions, onboard machine learning, computer vision, etc.

    To enable the AI deck on the ArduSwarm platform, please see the [Companion Computer Guide](docs/companion_computer_guide.md).

11. **Motion Capture Localization Support**
If you have access to a motion capture system for external ground truth localization, you can enable mocap instead of flow-based localization. 
Note that this will require a constant connection to a central ground station to each drone, as well as our 3D printed custom guard to mount passive reflective markers.

    Please reference the [Motion Capture Setup Guide](docs/motion_capture_guide.md) for detailed instructions.

12. **Pre-Flight Checklist**
The pre-flight checklist is a critical final check to make sure your first flight doesn't end in disaster!

    Before attempting your first flight, be sure to check the [Pre-Flight Checklist](docs/pre_flight_checklist.md).

13. **First Flight**
Before attempting automated flight, follow the [First-Flight Guide](docs/first_flight.md) to fly each drone in manual mode to make sure you've setup the drone correctly.

14. **Using the API for Custom Automation**
[Placeholder]

## 💻 Development Notes
### Memory Optimization
The STM32 MCU on the Crazyflie has limited flash memory (1 MB). As you add features to your custom firmware, you may exceed this limit.

If you encounter a build failure, you will likely need to free up memory by disabling certain ArduPilot features. For a detailed guide on how to do this, please refer to the [Freeing up Memory Guide](docs/freeing_up_memory.md).

### Restoring the Crazyflie to Factory Firmware
If you need to revert the Crazyflie to its original Bitcraze firmware for any reason, you can follow a straightforward restoration process.

For step-by-step instructions, please see the [Restoring the Crazyflie Guide](docs/restoring_the_crazyflie.md).

### ArduPilot Support
All of the development work detailed in this project is based on ArduPilot ArduCopter version 4.6.3 (Nov 2025). This project is not yet officially supported by ArduPilot and thus is not maintained to the latest release of ArduCopter. As a result, functionality is not guaranteed for future releases.

If you attempt to port this work to more recent versions of ArduPilot and run into compilation errors due to depreciation issues, please revert back to this [repository](submodules/ArduPilot_cus).

## 🔮 Future Work
This platform provides a foundation for a wide range of swarm robotics research. Future work will include:

- Implementing and testing specific differential game-based defensive algorithms.
- Polish stability/throttle/position controller gain tune.
- Developing a user-friendly interface for managing swarm experiments.
- Implementing a relative positioning algorithm for collision avoidance.
- Enable robust L1 path following algorithm.

## ✍️ Author
**Kwaku Richter**, Masters Student in Mechanical Engineering at the University of Ottawa

📧: frich089@uottawa.ca

---

**Last Modified:** 2026-04-25