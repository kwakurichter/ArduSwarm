# Optical Flow Driver — PMW3901 (Flow Deck v2)

`AP_OpticalFlow_FlowDeck` drives the PixArt PMW3901 optical flow sensor on the Bitcraze Flow Deck v2. Together with the [ToF driver](tof_driver.md) it provides the whole of the Crazyflie's GPS-denied navigation.

- **Source:** `libraries/AP_OpticalFlow/AP_OpticalFlow_FlowDeck.{cpp,h}`
- **Parameter:** `FLOW_TYPE = 9`
- **Bus:** SPI1, CS `E_CS1` / PB4, MODE3

---

## 1. Why a custom backend

The Flow Deck's wiring, chip select arrangement and initialization sequence differ enough that a dedicated backend was cleaner than conditionalising the upstream one.

> **The hwdef sets `AP_RANGEFINDER_BACKEND_DEFAULT_ENABLED 0`**, so every backend must be force enabled by name or it silently vanishes from the build and its type parameter matches nothing. The same applies here.

---

## 2. Motion burst reads

The driver reads the sensor through a motion burst (register `0x16`).

```
CS low
  write REG_MOTION_BURST (one transfer)
  read 12 bytes           (second transfer)
CS high
```

Two things matter:

**Chip select is held across both transfers.** The burst aborts if CS is released early, which is why the driver drives CS manually rather than letting the SPI layer bracket each transfer.

The burst is 12 bytes and the layout comes from the PMW3901 datasheet. A `static_assert` guards the struct size, because if packing ever changed the read length would silently disagree with the layout.

From the burst the driver takes `delta_x`, `delta_y` and `squal` (surface quality). Quality feeds ArduPilot's usual flow confidence handling.

### Register access convention

The PMW3901 distinguishes reads from writes by the top address bit:

- **Reads** send the bare register address.
- **Writes** OR in `0x80`.

Device presence is confirmed by reading `REG_ID` (`0x00`) and `REG_ID_INV` (`0x5F`) and checking they are complements.

---

## 3. Threading

All bus I/O happens on a periodic bus thread callback registered at 10 ms (100 Hz), never in `update()`.

ArduPilot's sensor update path runs inside the main loop with a tight scheduler budget, and SPI transactions on a shared bus can block for far longer than that budget allows. Doing the I/O on the bus thread keeps the main loop free; `update()` only consumes whatever the callback last produced.

The same rule governs the [ToF driver](tof_driver.md).

---

## 4. Bus sharing

SPI1 carries three devices:

| Device | CS | Mode | Notes |
|---|---|---|---|
| `optflow` (Flow deck) | `E_CS1` / PB4 | MODE3 | this driver |
| `sdcard` (SD deck) | `E_CS0` / PC12 | MODE0 | raw ChibiOS MMC-over-SPI |
| `dw1000` (Loco deck) | `E_CS3` / PB8 | MODE0 | [AP_Ranging](ap_ranging.md) |

Note the mode difference: the flow sensor runs MODE3 while the other two run MODE0. The SPI layer handles the switch per transaction, but it is worth knowing when debugging apparently corrupt reads on one device after adding another.

Contention on this bus is a recurring theme — see the SD card notes in [AP_Ranging](ap_ranging.md#8-known-issues) and the loop rate discussion in the [Port Overview](port_overview.md).

---

## 5. Setup

```
param set FLOW_TYPE 9
```

Flow-based navigation additionally needs the rangefinder working, since flow gives an angular rate that only becomes a velocity when scaled by height above ground. Configure the [ToF driver](tof_driver.md) first, confirm it reports sensible ranges, then enable flow.

The existing [Optical Flow Guide](../optical_flow.md) covers the operational setup, calibration and EKF parameters.

---

## See also

- [ToF Driver](tof_driver.md) — the other half of the Flow Deck
- [Optical Flow Guide](../optical_flow.md) — operational setup and calibration