# Brushless Motor Setup
## Background
If you are using the Crazyflie 2.1 Brushless model of drones, the main difference will be to enable the brushless motors in software. The brushed motors on the standard Crazyflie 2.1 series drones use standard PWM motor control and are thus easily configurable in ArduPilot. The brushless motors are controlled by onboard ESCs (flashed with BlueJay) which need to be configured to use DSHOT. Also, the main challenge is related to the particular hardware setup on the Crazyflie.

The ESCs on the brushless variant utilize external 10kΩ pull-up resistors, while the standard ArduPilot DShot driver assumes a push-pull configuration. This mismatch caused a short-circuit condition that prevented motor initialization.

We modified the RCOutput driver to force the GPIO pins into Open Drain mode, allowing the external pull-ups to function correctly. Additionally, we identified a DMA (Direct Memory Access) conflict on the STM32F405's Timer 2, which is shared by all four motors. This hardware limitation prevents the use of Bi-Directional DShot (necessary for RPM telemetry) on this specific board revision, as distinct DMA streams could not be allocated for all channels simultaneously.

In the future, we would like to continue to investigate these timing conflicts to hopefully get Bi-Directional DShot working.

### Add New Board Target
We start by creating a new target for compilation for the Crazyflie 2.1 Brushless:

- In your development environment, navigate to the board targets file:
```
path\...\Tools\AP_Bootloader\board_types.txt
```
- Near the top of the file, find the line that defines the Crazyflie 2.1 target:
```
TARGET_HW_CRAZYFLIE21                  14
```
- Underneath this line, include the following line: 
```
TARGET_HW_CRAZYFLIEBL                  13 # Brushless Crazyflie Support
```

### Copy and Modify the HWDEF files
Next, we need to copy the existing Crazyflie 2.1 hardware definition files and modify them to work with the new brushless hardware:

- In your development environment, navigate to the hwdef folder:
```
path\...\libraries\AP_HAL_ChibiOS\hwdef
```
- Create a new folder under the hwdef directory and name it "crazyflie2_bl".
- Download and copy the modified files into the new directory:

[hwdef](../submodules/ArduPilot_cus/libraries/AP_HAL_ChibiOS/hwdef/crazyflie2_bl/hwdef.dat)

[hwdef-bl](../submodules/ArduPilot_cus/libraries/AP_HAL_ChibiOS/hwdef/crazyflie2_bl/hwdef-bl.dat)

[defaults](../submodules/ArduPilot_cus/libraries/AP_HAL_ChibiOS/hwdef/crazyflie2_bl/defaults.parm)

- The main differences between the legacy files and the modified hwdef files are the motor definitions:
```
# Brushless Motor setup
PA1   TIM2_CH2  TIM2  PWM(1)  OD  SPEED_VERYHIGH   # M1
PB11  TIM2_CH4  TIM2  PWM(2)  OD  SPEED_VERYHIGH   # M2
PA15  TIM2_CH1  TIM2  PWM(3)  OD  SPEED_VERYHIGH   # M3
PB10  TIM2_CH3  TIM2  PWM(4)  OD  SPEED_VERYHIGH   # M4
```
- We also add the following default parameters:
```
# Brushless PWM Motors
MOT_PWM_TYPE,5      #DShot300
SERVO_BLH_AUTO,1    #BLHeli_S
SERVO_BLH_MASK,15   #BLHeli_S
SERVO_BLH_DEBUG,1   #BLHeli_S
SERVO_DSHOT_ESC,2   #BLHeli_S
```
This configures ArduPilot for brushless motor support by communicating to the ESCs running BlueJay firmware.

### Modify the RC Output file
We also need to modify the RC Output file as the Crazyflie Brushless has a slightly unconventional hardware configuration.

- In your development environment, navigate to the RCOutput file:
```
path\...\libraries\AP_HAL_ChibiOS\RCOutput.cpp
```
- Find the DSHOT mode case:
```
case MODE_PWM_DSHOT150 ... MODE_PWM_DSHOT1200: {
...
```
- Replace the contents of this function with the following:
```
    case MODE_PWM_DSHOT150 ... MODE_PWM_DSHOT1200: {
#if HAL_DSHOT_ENABLED
        GCS_SEND_TEXT(MAV_SEVERITY_INFO, "RCOU: DShot case t=%u", (unsigned)group.timer_id);    // DEBUG
        // Crazyflie 2.1 Brushless: motor outputs are open-drain → ESC expects LOW pulses
        const uint32_t rate = protocol_bitrate(group.current_mode);
        bool active_high = is_bidir_dshot_enabled(group) ? false : true;
#ifdef HAL_CF21_BRUSHLESS         
        // CF2.1-Brushless: motor pads are OD → ESC expects LOW pulses
        const bool is_tim2 = (group.timer_id == 2);
        if (is_tim2) {
            active_high = true;
            GCS_SEND_TEXT(MAV_SEVERITY_INFO, "RCOU: ACTIVE-HIGH on TIM2");     // DEBUG
        }
#endif        
        bool at_least_freq = false;
        // calculate min time between pulses
        const uint32_t pulse_send_time_us = 1000000UL * dshot_bit_length / rate;

        // BLHeli_S (and BlueJay) appears to always want the frequency above the target
        if (_dshot_esc_type == DSHOT_ESC_BLHELI_S || _dshot_esc_type == DSHOT_ESC_BLHELI_EDT_S) {
            at_least_freq = true;
        }

        // --- CALL DMA SETUP ---
        const bool ok = setup_group_DMA(group, rate, DSHOT_BIT_WIDTH_TICKS, active_high,
                                        MAX(DSHOT_BUFFER_LENGTH, GCR_TELEMETRY_BUFFER_LEN),
                                        pulse_send_time_us, at_least_freq);

        // --- PRINT RESULT ---
        if (!ok) {
            GCS_SEND_TEXT(MAV_SEVERITY_ALERT, "RCOU: TIM%u DMA FAIL (rate=%u ah=%u)", (unsigned)group.timer_id, (unsigned)rate, (unsigned)active_high);
            group.current_mode = MODE_PWM_NORMAL;
            break;
        } else {
            GCS_SEND_TEXT(MAV_SEVERITY_INFO, "RCOU: TIM%u DMA OK (rate=%u ah=%u)", (unsigned)group.timer_id, (unsigned)rate, (unsigned)active_high);
        }  
#ifdef HAL_CF21_BRUSHLESS           
        // --- release the gate for TIM2 now ---
        if (is_tim2) {
            // 1. FORCE PINS TO OPEN DRAIN & TIM2 (AF1)
            // This fixes the Push-Pull issue seen in hwdef.h and overrides System Timer/JTAG conflicts.
            // The Pull-Up is REQUIRED for Bi-Directional DShot to work on Open Drain hardware.
            // It pulls the line High when the FC releases it, allowing the ESC to pull it Low.            
            
            // Motor 1 (PA1)
            palSetPadMode(GPIOA, 1, PAL_MODE_ALTERNATE(1) | PAL_STM32_OTYPE_OPENDRAIN | PAL_STM32_OSPEED_HIGHEST);
            
            // Motor 2 (PB11)
            palSetPadMode(GPIOB, 11, PAL_MODE_ALTERNATE(1) | PAL_STM32_OTYPE_OPENDRAIN | PAL_STM32_OSPEED_HIGHEST);
            
            // Motor 3 (PA15)
            palSetPadMode(GPIOA, 15, PAL_MODE_ALTERNATE(1) | PAL_STM32_OTYPE_OPENDRAIN | PAL_STM32_OSPEED_HIGHEST);
            
            // Motor 4 (PB10)
            palSetPadMode(GPIOB, 10, PAL_MODE_ALTERNATE(1) | PAL_STM32_OTYPE_OPENDRAIN | PAL_STM32_OSPEED_HIGHEST);

            // 2. RESET SEQUENCE
            // Ensure PC15 is Open Drain
            palSetPadMode(GPIOC, 15, PAL_MODE_OUTPUT_OPENDRAIN);            
                
            // 3. Wait briefly to ensure the Timer/DMA is outputting a clean "Idle Low" signal
            hal.scheduler->delay(100); 

            // 5. Release Reset (High) to wake up ESCs
            palWritePad(GPIOC, 15, 1);    

            // 5. Wait for ESC bootloader/init before sending commands (Bitcraze protocol detection time)
            hal.scheduler->delay(50);

            gcs().send_text(MAV_SEVERITY_ALERT, "ESC Pin Reset Sent.\n");   // DEBUG
            GCS_SEND_TEXT(MAV_SEVERITY_INFO, "ESC Pin Reset Sent.\n");   // DEBUG
         
        }    
        if (is_bidir_dshot_enabled(group)) {
            group.dshot_pulse_send_time_us = pulse_send_time_us;
            // to all intents and purposes the pulse time of send and receive are the same
            // for dshot600 this is roughly 26us + 30us + 26us = 82us
            group.dshot_pulse_time_us = pulse_send_time_us + pulse_send_time_us + 30;
        }
#endif        
#endif
        break;
    }

```

## Compiling & Flashing to the Crazyflie
We now need to compile the brushless firmware and flash it the Crazyflie. For detailed flashing instructions, please reference the [Compiling & Flashing Guide](compiling_and_flashing.md).

## Testing and Using Brushless Crazyflie
Once you have successfully flashed your brushless firmware, we can use the brushless Crazyflies in the ArduSwarm platform. If you haven't yet configured the rest of the hardware, reference the [Hardware Setup Guide](hardware_setup.md) to properly assemble your ArduSwarm drone.

If you have already completed the hardware setup, you can move directly to the [Pre-Flight Checklist](pre_flight_checklist.md).