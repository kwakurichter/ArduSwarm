# ToF Driver — VL53L1X (Flow Deck v2)

`AP_RangeFinder_FlowDeck` drives the ST VL53L1X time-of-flight rangefinder on the Bitcraze Flow Deck v2. It supplies height above ground, which is what turns the [optical flow](optical_flow_driver.md) sensor's angular rate into a usable velocity and provides an additional altitude source.

- **Source:** `libraries/AP_RangeFinder/AP_RangeFinder_FlowDeck.{cpp,h}`
- **Parameter:** `RNGFND1_TYPE = 50`
- **Bus:** I2C at 400 kHz

---

## 1. Why a custom backend

ArduPilot ships `AP_RangeFinder_VL53L1X`, a compact hand written driver. This port instead wraps ST's official VL53L1X API, vendored at `libraries/vl53l1x_api/` — roughly 51 000 lines across 49 files.

The ST API exposes the sensor's full calibration and distance mode machinery, which matters on a 27 g indoor vehicle where the useful range window and the timing budget both need tuning. The tradeoff is that the API is large and its calls are slow.

> **The hwdef sets `AP_RANGEFINDER_BACKEND_DEFAULT_ENABLED 0`.** Every rangefinder backend must be force enabled by name, or it silently vanishes from the build and `RNGFND1_TYPE = 50` matches nothing.

The API is bridged to ArduPilot's HAL by `VL53L1_set_aphal_device()`, which hands the ST platform layer an `AP_HAL::I2CDevice` to do its transfers through.

---

## 2. Distance modes and timing

The driver selects a distance mode and a matching timing budget:

| Mode | Timing budget | Inter-measurement period |
|---|---:|---:|
| Short | 20 ms | 25 ms |
| Medium | 25 ms | 30 ms |
| Long | 140 ms | 145 ms |

The inter-measurement period is derived as `timing_budget_ms + 5`, giving the sensor the minimum ~4 ms it needs between measurements plus a margin.

**Short mode is the right default indoors.** It is far more tolerant of ambient infrared and completes in 20 ms rather than 140 ms, and its reduced maximum range is irrelevant on a vehicle that flies at a metre or two. Long mode's 140 ms budget is slower than the vehicle's own dynamics.

Initialization is the standard ST sequence — `WaitDeviceBooted`, `DataInit`, `StaticInit`, `SetDistanceMode`, `SetMeasurementTimingBudget`, `SetInterMeasurementPeriod`, `StartMeasurement` — with each step's status checked and reported to the GCS on failure.

---

## 3. Threading (important)

**All ST API calls happen on a periodic bus thread callback**, registered at the inter-measurement period. Never in `update()`.

`read_rangefinder` runs with a 100 µs scheduler budget. One ST API sample is milliseconds of blocking I2C. Calling into the API from the sensor update path would blow that budget by more than an order of magnitude on every sample, and on this board the consequences compound: the IMU is also on I2C, so starving the bus threads directly degrades attitude estimation.

The callback polls `GetMeasurementDataReady`, and only when a measurement is ready does it call `GetRangingMeasurementData` and then
`ClearInterruptAndStartMeasurement` to arm the next one. `update()` simply publishes whatever the callback last stored.

---

## 4. Setup

```
param set RNGFND1_TYPE 50
```

The existing [RangeFinder Guide](../rangefinder.md) covers orientation, minimum and maximum range parameters, and the EKF configuration for height fusion.

`RFND` log messages require the CTUN bit (bit 4) in `LOG_BITMASK`.

---

## 5. Known constraints

**I2C is shared with the IMU.** Broad logging settings and heavy bus traffic measurably reduce the main loop rate. Prefer `LOG_FILE_RATEMAX` and `LOG_DARM_RATEMAX` over disabling subsystems — see the [Port Overview](port_overview.md).

---

## See also

- [Optical Flow Driver](optical_flow_driver.md) — the other half of the Flow Deck
- [RangeFinder Guide](../rangefinder.md) — operational setup