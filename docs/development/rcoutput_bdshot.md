# RCOutput BDShot — Crazyflie 2.1 Brushless

The Crazyflie 2.1 Brushless drives its motors through onboard ESCs flashed with BlueJay, which expect DShot rather than the standard PWM the brushed model uses. Two hardware properties of this board make stock ArduPilot's DShot output unusable without changes.

- **Source:** `libraries/AP_HAL_ChibiOS/RCOutput_CF21.cpp`
- **Board:** `crazyflie2_bl` (defines `HAL_CF21_BRUSHLESS`)

---

## 1. The two hardware problems

### Open drain lines

The CF21 brushless ESC signal lines carry external 10 kΩ pull-up resistors. Stock ArduPilot drives its DShot pins push-pull.

A push-pull output actively driving low against an external pull-up is a short-circuit condition. In practice it prevented motor initialization entirely and the ESCs never came up.

The fix is to force the four motor GPIO pins into open-drain mode, so the external pull-ups provide the high level and the MCU only ever pulls low:

```
PAL_MODE_ALTERNATE(1) | PAL_STM32_OTYPE_OPENDRAIN | PAL_STM32_OSPEED_HIGHEST
```

Bidirectional DShot needs the same pins reconfigured for input capture between frames, so there is a matching receive mode variant that adds `PULLUP`.

The four motor lines all hang off TIM2:

| Motor line | Pin | Channel |
|---|---|---|
| M1 | PA1 | TIM2_CH2 |
| M2 | PB11 | TIM2_CH4 |
| M3 | PA15 | TIM2_CH1 |
| M4 | PB10 | TIM2_CH3 |

There is also a shared ESC reset line on PC15, pulsed as an open-drain output before bidirectional DShot starts, so all four ESCs come up in a known state.

### DMA contention on TIM2

All four motors share Timer 2, and the STM32F405 cannot allocate distinct DMA streams for every channel at once.

Specifically, TIM2_CH4 has no DMA stream of its own, and the only stream it could share is TIM2_UP, which DShot output itself needs.

That is a property of the hardware, not a software limitation:

```
define HAL_BDSHOT_NO_SHARE_UP_STREAM 1
```

**Consequence: one motor output has no bidirectional DShot telemetry.** The upstream Bitcraze discussion is [crazyflie-firmware#1556](https://github.com/bitcraze/crazyflie-firmware/pull/1556).

---

## 2. Why the code lives in its own file

The CF21 workarounds were once **11 `#ifdef` blocks and ~300 lines** threaded through `RCOutput.cpp` and `RCOutput_bdshot.cpp`.

Every one of those was a merge conflict waiting to happen on the next ArduPilot rebase, in exactly the files most likely to change upstream.

They are now:

- **One `#ifdef` in the header**, declaring the hook functions. When `HAL_CF21_BRUSHLESS` is undefined they compile to empty inlines.
- **Unconditional one line calls** at the relevant points in the upstream files.
- **All the actual logic** in `RCOutput_CF21.cpp`, which upstream never touches.

The hooks themselves are deliberately narrow: identify whether a group is the TIM2 motor group, set the lines to transmit or receive mode, and reset the ESCs.

A third quirk is that TIM2_CH4 can never do input capture. Its handled in `bdshot_setup_group_ic_DMA()` rather than here.

---

## 3. Building

The brushless variant is its own board target, distinct from the brushed `crazyflie2`, so the two builds cannot be flashed onto the wrong airframe:

```bash
./waf configure --board crazyflie2_bl BL=1 && ./waf copter
```

Both boards build from the same tree; `crazyflie2_bl` additionally defines `HAL_CF21_BRUSHLESS`.

Pre built images ship as `crazyflie2_bl-ArduSwarm-*_with_bl.hex` on the [Releases page](https://github.com/kwakurichter/ArduSwarm/releases).

The [Brushless Motor Guide](../brushless_motor_guide.md) covers the operational setup.

---

## 4. Future work

Bidirectional DShot works on three of the four outputs. Getting the fourth would mean finding a DMA arrangement that frees a stream for TIM2_CH4 without starving DShot output. The timing conflicts are worth revisiting.

---

## See also

- [Brushless Motor Guide](../brushless_motor_guide.md) — operational setup
- [Port Overview](port_overview.md) — the rebase discipline this file exists to serve