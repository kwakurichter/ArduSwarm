# GCS-Based Custom Automation

## Where the scripts run

Custom Python logic runs on the GCS computer and sends MAVLink Guided commands over Crazyradio. `swarm_hub.py` owns the radio links and keeps QGC connected; `guided_swarm.py` provides mission planning, telemetry checks, and coordinated execution for one to four drones. Onboard [Lua scripting](lua_scripting.md) and [AI Deck applications](companion_computer_guide.md) remain separate options.

Complete the [GCS setup](custom_gcs_guide.md) and each drone's [first flight](first_flight.md) before using this workflow.

## Preview without connecting hardware

From the repository root, this command prints the plan and exits without opening sockets or sending commands:

```bash
.venv/bin/python python/guided_swarm.py \
    --target-systems 1 2 3 4 --pattern hover --height 1 --hover 5
```

Standalone `guided_swarm.py` previews by default. Normal flight execution is through the persistent hub below.

## Run missions from the hub

Start `swarm_hub.py` with the desired URIs from the [GCS guide](custom_gcs_guide.md), then use its `swarm>` prompt:

```text
status
preview --target-systems 1 --pattern hover --height 1 --hover 5
fly --target-systems 1 --pattern hover --height 1 --hover 5
```

`fly` prints the plan and asks for `y` before executing it. After validating individual aircraft, preview and run the group:

```text
preview --target-systems 1 2 3 4 --pattern hover --height 1 --hover 5
fly --target-systems 1 2 3 4 --pattern hover --height 1 --hover 5
```

Use explicit `--target-systems` to select the roster. If omitted, the hub selects all vehicles currently heard. QGC continues receiving telemetry during the mission and after it finishes.

| Command | Purpose |
|---|---|
| `status` | Show links, vehicle armed state, dongles, and logs |
| `preview <options>` | Show the plan without running a mission |
| `fly <options>` | Preview, confirm, and run |
| `again` | Preview and repeat the previous mission, with confirmation |
| `help fly` | Show the current mission arguments |
| `quit` / Ctrl-D | Close the hub and its GCS radio relay |

Ctrl-C during a mission requests a LAND abort and returns to the prompt; it does not force disarm the aircraft. A lost radio link can prevent delivery of LAND, so the aircraft's own configured failsafes remain necessary. QGC mode changes are treated as operator takeover by the mission logic.

## Patterns and options

Examples at the hub prompt:

```text
preview --target-systems 1 --pattern left-return --distance 0.5 --hover 3 --hold 2
preview --target-systems 1 --pattern three-axis --distance 0.5 --hover 3 --hold 1 --max-flight-time 60
preview --target-systems 1 --pattern circle --radius 0.25 --duration 12 --hover 3 --hold 2
preview --target-systems 1 --pattern diamond --radius 0.75 --duration 35 --hover 3 --hold 2 --max-flight-time 60
```

Replace `preview` with `fly` to execute a reviewed plan. Directional patterns include `forward-return`, `backward-return`, `left-return`, and `right-return`. `three-axis` visits left, right, and backward targets, returning to the captured starting point after each leg.

- `--height` is nominal height above home, not measured floor clearance.
- `--hover` is the settled hover before movement; `--hold` is the settled dwell at targets and final return.
- `--distance` must exceed the position tolerance. Fixed-target movement speed is determined by the aircraft's controller; `--speed` is not a hard movement speed cap.
- Circle radius is 0.05–0.4 m with duration 10–20 s; diamond radius is 0.05–1 m with duration 10–40 s. Both must meet the 0.35 m/s requested peak-speed limit. `--radius` is half the path width/depth; the planned excursion can reach twice that value.
- `--max-flight-time` defaults to 45 s and is limited to 60 s. It covers arming through final hover; landing takes additional time.
- Circle/diamond default arrival tolerance is 0.15 m with settled speed 0.15 m/s. Other patterns use 0.30 m and 0.40 m/s. Check `help fly` for overrides.

## Group placement and localization limits

Place drones on level marked spots facing the same forward direction.

| Count | Layout | Default `--spacing` |
|---|---|---:|
| 1 | Center | Not used |
| 2 | Side by side | 1.5 m |
| 3 | Equilateral triangle | 1.5 m side |
| 4 | Square | 1.25 m side |

The 4 drone default is 1.25 m its diagonal must also fit the planner's allowed initial pairwise distance range of 1.15–1.85 m.

The runner monitors estimated pairwise spacing within 1–2 m, using marked starting offsets and each aircraft's local position estimate. These estimates can drift; this is not measured relative localization or collision avoidance.

## Extending the scripts

The implementation is in [guided_swarm.py](../python/guided_swarm.py), with radio/GCS integration in [swarm_hub.py](../python/swarm_hub.py). These are editable application scripts, not a separately versioned SDK.

For a new pattern, trace `arguments()`, `mission_targets()`, `sweep_sample()`, `diamond_sample()`, and `SwarmFlight.run()`. Update argument validation and the printed preview along with the trajectory. Keep `SwarmFlight`'s telemetry freshness checks, command acknowledgement handling, timeouts, operator takeover handling, and landing/abort path. The hub uses the same mission parser, so a supported pattern becomes available through its prompt.

Start by running the new plan without `--execute`. Validate command sequencing and failure paths in simulation before hardware use. The hub's `--sim PORT` option can attach to a local SITL instance configured to send to that UDP port; it does not launch SITL itself.

## Logs

From this repository layout, the hub creates `python/logs/<date>/` automatically:

- `*-session.tlog`: MAVLink traffic for replay and analysis.
- `*-session.jsonl`: link statistics, failures/recoveries, and mission events.
- One `*.jsonl` per mission: plan, telemetry, commands, and outcome.

Use hub option `--log-dir PATH` to choose another location.
