# OptiTrack Guard Printing Guide
## What is the OptiTrack Guard?
The OptiTrack Guard is a 3D-printed protective frame designed for the ArduSwarm platform. It serves two main purposes:

1. Hardware protection (taller-than-stock guard):
The guard extends higher than the stock Crazyflie guards to protect elevated payloads (primarily the AI Deck) from impacts, tip-overs, and handling during bench testing.

2. OptiTrack localization (rigid marker mounts):
The guard includes six rigid mounting points for OptiTrack passive markers, enabling stable 6-DoF tracking for motion-capture-based localization. These mounts are designed to keep markers well-spaced, visible from multiple angles, and mechanically stiff (minimizing vibration-induced marker motion).

![Guard](/docs/images/guard_printing_guide/guard.png)

The guard was developed in SolidWorks through multiple iterations. The workflow was:
- Measure the Crazyflie/ArduSwarm stack-up with calipers.
    - Key dimensions included standoff heights, deck stack clearance, guard clearance to props, and any protruding connectors/components.
- Reference platform schematics + real hardware measurements.
    - Measurements were cross-checked against available schematics, then verified on the physical platform to account for real-world tolerances.
- Iterate quickly. Several revisions were produced to refine:
    - Fit and alignment
    - Stiffness of the marker posts
    - Deck clearance (especially AI Deck height)
    - Ease of printing (reduced failure-prone overhangs)
    - Impact resistance (cracking during crashes or landing)

## Files included in the repository
All [printable and editable files](/docs/printing/) are provided in the repo so you can manufacture the guard using a 3D printer of your choice.

## Printing the guard
The guard is intended to print on common consumer printers using standard materials. It does not require exotic filaments.

### Recommended materials
- PLA / PLA+ (recommended for first prints): stiff, easy to print, accurate
- PETG: tougher, more ductile, can survive impacts better (but may flex more)
- ABS/ASA: possible if you have enclosure/ventilation, but not required

### Print settings used (Bambu P1S, PLA+)
These are the settings used for the reference print:
- Printer: Bambu P1S
- Material: PLA+
- Supports: Natural supports
- Infill: 15%
- Wall layers: 2
- Base adhesion: 5 mm base material

### Orientation and supports
- Print the guard in the orientation provided in the files (top up).
- Enable supports as needed for the marker posts / overhang features (natural supports worked well in practice).

### Post-processing
After printing:
- Remove supports carefully around marker mounts and propeller guards features (avoid snapping thin posts).
- Test fit on the platform.
- If necessary, use a small amount of hot glue to secure the guards to the frame.

### Mounting passive markers
Marker attachment depends on your OptiTrack marker type. The markers we used were simply friction-fit into the mounting holes which proved sufficient. If necessary, use a little hot glue to mount the markers into the mounting holes.

## Notes and troubleshooting
- Tracking jitter: If you see noisy pose estimates, the usual causes are (a) partial occlusion, (b) flexible marker posts, or (c) poor camera coverage. Consider checking your camera coverage/orientation.

- Fit too tight/loose: Printing tolerances vary. If you see consistent mismatch, adjust scaling by a small amount or modify the STEP/SolidWorks source and re print.

- Cracked posts after impact: PLA+ is stiff but can be brittle. PETG can improve survivability if you’re doing lots of crash-prone testing.