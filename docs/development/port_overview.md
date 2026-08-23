# Port Overview — Crazyflie → ArduPilot

- **Repo:** [kwakurichter/ArduPilot_cus](https://github.com/kwakurichter/ArduPilot_cus)
- **Base:** ArduCopter **4.7.0** · **Release:** v2.1.1 (`d99bf3b057`)
- **Hardware:** Crazyflie 2.x, STM32F405, 1 MB flash, 192 KB RAM

---

## 1. What this port is

Stock ArduPilot Copter 4.7.0 plus four new libraries and a set of board-specific changes, producing firmware for a 27 g indoor quadrotor that navigates without GPS and talks to its neighbours over its onboard radio.

| Board | Frame | Notes |
|---|---|---|
| `crazyflie2` | brushed | baseline |
| `crazyflie2_bl` | brushless | adds CF21 bdshot ESC support |

Both build from the same tree; `crazyflie2_bl` additionally defines `HAL_CF21_BRUSHLESS`.

---

## 2. Architecture

### New libraries in this fork

| Library | Files | Purpose | Guide |
|---|---:|---|---|
| `AP_Syslink` | 7 | nRF51822 radio: MAVLink over Crazyradio, peer broadcast | [→](ap_syslink.md) |
| `AP_Ranging` | 8 | DWM1000 UWB two-way ranging (Loco deck) | [→](ap_ranging.md) |
| `AP_SwarmMesh` | 23 | Decentralized peer mesh, vendored from upstream PR 33881 | [→](ap_swarmmesh.md) |
| `vl53l1x_api` | 49 | Vendored ST VL53L1X API (~51k lines) | [→](tof_driver.md) |

### Files added inside upstream libraries

```
libraries/AP_RangeFinder/AP_RangeFinder_FlowDeck.{cpp,h}
libraries/AP_OpticalFlow/AP_OpticalFlow_FlowDeck.{cpp,h}
libraries/AP_HAL_ChibiOS/RCOutput_CF21.cpp
libraries/AP_SwarmMesh/AP_SwarmMesh_Syslink.{cpp,h}
Tools/ardupilotwaf/libdw1000.py
```

Everything else in upstream files is a small hook. Keeping it that way is a deliberate design goal here — see [Rebasing](#5-rebasing).

### Parameter groups

| Group | `ParametersG2` index | Library |
|---|---|---|
| `RNG` | 47 (`var_info`) | AP_Ranging |
| `SYSL` | 29 (`var_info2`) | AP_Syslink |
| `P2P` | 23 (`var_info2`) | AP_SwarmMesh |

---

## 3. The sensor stack

The FlowDeck v2 carries both halves of GPS-denied navigation:

- **PMW3901 optical flow** — SPI1, `FLOW_TYPE = 9` → [guide](optical_flow_driver.md)
- **VL53L1X ToF** — I2C, `RNGFND1_TYPE = 50` → [guide](tof_driver.md)

Both are driven by in-tree `FlowDeck` backends, *not* upstream's `Pixart` or `VL53L1X` drivers.

> The hwdef sets `AP_RANGEFINDER_BACKEND_DEFAULT_ENABLED 0`, so every backend must be force enabled by name or it silently vanishes from the build and its `RNGFND_TYPE` matches nothing.

Both backends do their bus I/O on a periodic bus thread callback, never in `update()`. `read_rangefinder` has a 100 µs scheduler budget and one ST-API sample is milliseconds of blocking I2C.

---

## 4. Build and flash

```bash
./waf configure --board crazyflie2_bl BL=1 && ./waf copter
```

Note that `BL=1` is inert — waf parses `NAME=VALUE` into the environment and nothing reads `BL`. Bootloader embedding is automatic: `Tools/ardupilotwaf/chibios.py` embeds `Tools/bootloaders/<board>_bl.bin` whenever it exists.

Outputs:

- `arducopter.apj` — flash over an existing bootloader
- `arducopter_with_bl.hex` — full image for a bare board over SWD

> **Always check `_with_bl.hex` exists rather than trusting exit status.** If the bootloader binary is missing, waf prints `Not embedding bootloader; ...` and still succeeds.

### Environment hazards

**Silent configure failures.** `./waf configure` failing (for example on a duplicated pin) leaves the previous board configured, and `./waf copter` happily rebuilds that instead. Check exit status.

**hwdef edits need a reconfigure.** After editing `hwdef.dat`, re-run `./waf configure --board <board>`.

---

## 5. Rebasing

This is the recurring cost of the fork and the reason for several design choices.

**Keep upstream diffs tiny.** `RCOutput_CF21.cpp` exists because the CF21 brushless workarounds were once 11 `#ifdef` blocks and ~300 lines threaded through `RCOutput.cpp` and `RCOutput_bdshot.cpp`. They are now one `#ifdef` in the header declaring hooks (empty inlines elsewhere) plus unconditional one line calls. See [RCOutput BDShot](rcoutput_bdshot.md).

**Prefer expressing hardware facts in hwdef.** `HAL_BDSHOT_NO_SHARE_UP_STREAM`. TIM2_CH4 has no DMA stream of its own and its only shareable one is TIM2_UP, which DShot output needs.

---

## 6. Known behaviour and open issues

**One motor output has no bdshot telemetry** on `crazyflie2_bl`. TIM2_CH4 has no DMA stream of its own. Hardware limit — see [RCOutput BDShot](rcoutput_bdshot.md).

**Main loop runs ~350 Hz** rather than 400. SD card logging over SPI1 was measured at ~7300 transactions/s ≈ 15% of the loop. Use `LOG_FILE_RATEMAX` and `LOG_DARM_RATEMAX` rather than disabling subsystems. The IMU is on I2C, so the loop is sensitive to CPU starvation of the bus threads.

**Lua scripting fits** (~138 KB, ~85 KB free) but is not enabled. A runtime heap on a 192 KB F405 works but uses too much RAM to recommend.

**macOS SITL does not link.** Two pre existing fork issues, absent on ARM: the vendored ST API includes `<malloc.h>` (a Linux-ism), and `AP_Camera.h`'s `MOUNT` enum collides with a macOS `#define MOUNT`. Build with `-k` to compile past them when verifying that objects compile.

---

## See also

- [Identity](identity.md) — the single `MAV_SYSID` rule
- [AP_Syslink](ap_syslink.md) · [AP_SwarmMesh](ap_swarmmesh.md) · [AP_Ranging](ap_ranging.md)
- [Optical Flow](optical_flow_driver.md) · [ToF](tof_driver.md) · [RCOutput BDShot](rcoutput_bdshot.md)
- [AI Deck](ai_deck.md)