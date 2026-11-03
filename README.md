**WattPace**

**FTP-based pacing and heart-rate-aware fueling alerts for Garmin watches and Edge bike computers.**

A free Garmin Connect IQ data field for cycling and triathlon, written in Monkey C.

1,000+ downloads · no ads · no data collection · about 90+ Garmin device models, 150+ hardware variants

<img width="1440" height="720" alt="WattPace on a bike computer and a watch showing pace and fueling states" src="https://github.com/user-attachments/assets/56672b8d-8948-4449-b3a2-a2ffdd4e40ad" />

**Why I built it:**

I race triathlon. On long rides and triathlon bike legs I kept making two mistakes: riding 30-40 W above what I could actually sustain (I felt fine until the run), and forgetting to eat because I was focused on the effort. I couldn't find a Garmin field that handled both, so I surveyed 30+ teammates at my club to check I wasn't the only one. Most had the same problem. WattPace is my attempt to take that decision-making load off an athlete who is tired, breathing hard, and reacting to other riders.

**What it does:**

**Pacing:**
Enter your FTP and pick a race type. WattPace calculates a target power and turns the **entire field** into a pacing signal you can read at a glance.

| Race type | Target |
| Short TT / crit | 95% of FTP |
| Olympic / short fondo | 87% of FTP |
| Half-distance / medium fondo | 80% of FTP |
| Full-distance / century | 72% of FTP |

| Color | Meaning |
| Green | Within the target window |
| Red | Above the window: back off |
| Blue | Below the window: pick it up |

The window is adjustable: ±10, ±15, ±20, or ±30 W. On screens that can't show color (monochrome Edge units) or shouldn't hold a bright fill for hours (AMOLED watches), the state is carried by black/white contrast, the text label, and an up/down arrow instead.

**Fueling:**
A timer fires every 15, 20, 30, or 45 minutes. At the moment it fires, WattPace compares your current heart rate to your lactate-threshold HR:

- **Above threshold:** "H2O ONLY"
- **At or below threshold, or no HR data:** "TAKE CARBS"

The alert takes over the field for 15 seconds with a tone and a vibration pattern. The first reminder always arrives within the first 15 minutes, even on a 45-minute interval. The water-only rule is a design heuristic, not medical or nutritional advice (see Design assumptions).

**Post-ride data:**
Two custom fields are written into the activity's FIT file once per second, so they can be charted in Garmin Connect or analyzed from the exported file:

| Field | Values |
| Pacing State | 0 start · 3 no data · 4 slow down · 5 speed up · 6 on pace |
| Fuel Alert | 0 none · 1 take carbs · 2 water only |

They are separate fields so a fueling alert never overwrites the pacing record. Garmin Connect plots them as raw-value charts; it does not compute time-in-zone for developer fields, so that analysis is done from the FIT file.

**Settings:**
All configured in the Garmin Connect app: FTP (50-600 W), race type, lactate-threshold HR (100-220 bpm), fueling interval, and pacing window.

**How it works:**

`compute()` runs about once per second and `onUpdate()` draws the result.

1. **Smoothing.** Power is averaged over a 15-sample rolling window (about 15 s), so pedal-stroke noise doesn't change the color.
2. **Zones with hysteresis.** Slow/speed-up trigger at target ± window. Once triggered, a state only releases after power moves 3 W back inside the threshold, so power hovering on a boundary doesn't flicker.
3. **Dropout tolerance.** One or two missing power samples are ignored; the third consecutive miss clears the history and shows "no data". The field shows "no data" (not "0 W") until the first real reading arrives.
4. **Fuel scheduler.** The next alert is stored as an explicit timestamp, so a missed update can't skip a reminder. HR is read when the alert fires, falling back to the last good reading if the strap drops out.
5. **FIT recording.** Pacing state is captured before any fueling display override, so both signals stay clean.
6. **Adaptive rendering.** The text-fitting engine steps down through font sizes, then to a short label with an arrow, until the text fits. Round screens test the four corners of the text box against the circular bezel; rectangular screens test against the field's own box. A guard keeps text off the dividing lines in multi-field grids.

**Engineering problems I faced:**

- **The fueling timer fired at the start of every activity.** The first version used a modulo on elapsed seconds, and zero is divisible by everything. It could also skip an alert if the device missed an update. Replaced with scheduled next-alert timestamps.
- **A 0 W flash at startup.** After adding dropout tolerance, the field briefly showed "0 W, speed up" before the first sensor reading. Fixed by keying the "no data" state on whether any power history exists.
- **Round vs. rectangular screens.** The original text-fit logic assumed a circular bezel. On rectangular Edge screens it shrank text needlessly. It now branches on screen shape.
- **Blank screen on the Edge 130.** The Edge 130 and 130 Plus have monochrome displays, and the blue "speed up" state rendered as an unreadable blank. I first tried detecting the device at runtime, but Garmin's device identifier is a hashed per-app value, not a model name. The fix was compile-time source folders in `monkey.jungle`: those two devices build with a black background for that state, and every other device keeps blue.
- **Older devices.** Some older Edge units cap at an earlier Connect IQ API level than the project's original minimum, so they were silently excluded from the build. Lowering the minimum API level brought them in.

**Testing and limitations:**

- Verified in the Connect IQ simulator on every device model in `manifest.xml` (90+ models, 150+ hardware variants in the export), and used in my own training and by early users since release.
- It has **not** been tested on every physical device. Simulator rendering is accurate for layout and color, but not for sensor timing, haptics, or real signal dropouts.
- Requires a power meter (or smart trainer) for pacing. A heart-rate sensor is needed for the heart-rate-aware fueling advice.
- The pacing presets and the heart-rate fueling rule are heuristics. They have not been validated in a controlled study.
- Tones and vibration depend on the device and the user's device settings.
- No automated tests. Verification was manual, per device.

**Design assumptions and sources:**

- **Pacing presets.** The percentages follow ranges commonly published by coaches and pacing tools for each event length. Published ranges vary by source, and my presets sit inside or near them. They are starting points, which is why the window is adjustable.
- **Fueling cadence.** Regular, moderate fueling is common guidance, and sources differ on when to start. An early first reminder is a conservative choice.
- **Heart-rate rule.** High-intensity exercise is one factor that slows gastric emptying, so above threshold the field suggests water. This is a design choice informed by that literature, not a clinical prescription.

Sources I consulted:
- Best Bike Split, [Ironman 70.3 bike pacing plan](https://www.bestbikesplit.com/ironman-703-bike-pacing-plan)
- Roadman Cycling, [Triathlon bike pacing: FTP percentages](https://roadmancycling.com/blog/triathlon-ftp-pacing-strategy)
- TRI247, [FTP in cycling](https://www.tri247.com/triathlon-training/ftp-in-cycling-functional-threshold-power-test-training-triathlon)
- Practical Gastro, [Fueling during endurance exercise](https://practicalgastro.com/2023/10/10/fueling-during-endurance-exercise-balancing-intake-with-gastrointestinal-tolerances/)
- Precision Hydration, [How often should athletes fuel during exercise?](https://www.precisionhydration.com/performance-advice/nutrition/how-much-and-how-often-should-you-eat-during-exercise/)

**Repository layout:**

```
source/          Shared code
  TestApp.mc       App entry point; forwards settings changes to the view
  TestView.mc      The data field: compute() logic and onUpdate() rendering
source-color/    ColorScheme.mc (blue "speed up" state): default for most devices
source-mono/     ColorScheme.mc (black "speed up" state): Edge 130 / 130 Plus
resources/       Strings, properties and settings, FIT field definitions
manifest.xml     Supported devices, permissions (FIT contributor only), min API level
monkey.jungle    Per-device source selection
```

The `Test*` class names are left over from the project scaffold.

**Build and run:**

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/), Visual Studio Code, and the Monkey C extension, and generate a developer key.
2. Clone the repository and open it in VS Code.
3. Run the project and choose a device. Use the simulator's activity-data and Data Fields menus to feed power and heart rate and try different layouts.
4. To package: run **Monkey C: Export Project**.

**Privacy:**

No network calls, no location, no accounts, no analytics. The only permission requested is FIT contributor, to write the two fields above into your own activity file.

**Development notes:**

Built over about a month of intensive work (roughly 160 logged hours across four months including research, testing, and release).

**Recognition:**

Featured in a Triathlon BC athlete profile: [From Racing to Innovation](https://www.tribc.org/news/15491-2/)

**Author:**

Advaith Iyer, competitive triathlete (Triathlon Canada Performance Pathway). Contact: contact.wattpace@gmail.com
