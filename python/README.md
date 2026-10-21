# ArduSwarm Ground Control Station tools

Install Python 3.9+, libusb, `pyusb`, and `pymavlink`; run from the repository root. See the [GCS setup guide](../docs/custom_gcs_guide.md) for complete commands and the [automation guide](../docs/using_the_api_for_custom_automation.md) for mission usage.

| File | Role |
|---|---|
| `swarm_hub.py` | Persistent radio/GCS relay and mission prompt |
| `guided_swarm.py` | 1 to 4 drone Guided routines, preview, and mission checks |
| `mavlink_bridge.py` | Shared radio polling, vehicle MAVLink framing and routing |
| `crazyradio2_large.py` | PyUSB driver for the large-packet Crazyradio protocol |

Pass `--radio-tools python` when launching the hub. Keep the bridge and USB driver together.

Offline preview (no radio or network commands):

```bash
.venv/bin/python python/guided_swarm.py --target-systems 1 2 3 4 --pattern hover --height 1 --hover 5
```

Hub logs default to `python/logs/<date>/`.
