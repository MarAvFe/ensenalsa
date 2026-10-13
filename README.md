# ensenalsa

A lean salsa teaching tool. A dancer built from primitive shapes performs salsa basics, with footprints, a beat counter that shows all 8 counts (the tap counts 4 and 8 in gold), a weight marker, and three camera views. Built with Godot 4.7 using the Compatibility renderer, so it runs in a browser.

## Run

**In the editor / desktop:** `godot --path .` (Godot 4.7.x)

**In a browser:**

```bash
./export.sh                                   # writes build/web/
python3 -m http.server 8000 -d build/web      # any static server works
# open http://localhost:8000
```

The export uses the single-threaded web template, so it needs no special COOP/COEP headers. Browsers keep audio muted until the first click or key press.

## Export setup

1. Install Godot **4.7.2** and its export templates (Editor → Manage Export Templates, or extract `web_nothreads_release.zip` from the official `.tpz` into `~/.local/share/godot/export_templates/4.7.2.stable/`).
2. `./export.sh` runs `godot --headless --export-release Web build/web/index.html` using the `Web` preset in `export_presets.cfg`.

## Controls

| Where | Control | Action |
|---|---|---|
| bottom centre | `< Beat` / `Pause` / `Beat >` (← / Space / →) | glide one count back / play-pause / glide one count forward |
| bottom right | `Diagonal` / `Front-back` / `Sides` | queue a basic; the dancer switches on the next count 1 |
| top right | camera dropdown (1–6) | behind, front, head-down-to-feet (hips and up hidden), feet close-up from the side, behind 30°, front 30° |
| bottom left | gear | Loop (off = stop on count 8), Music (M), BPM (default 100), Speed 0.25x–1x |

## How it works

- `data/routine.json` holds **all** values: parameters (home stance, lift, tap height, pelvis height/shift/dip, BPM, music), the basics with their button `labels`, and the `start_basic`. The selected basic loops; picking another one queues it for the next count 1. Each basic is 8 counts. Each count has `weight` (`L`/`R`) and, per foot, `{target: [x, z], action}` with action `step | place | lift | tap | hold`. Coordinates are dancer-local: +X right, +Z forward (the code maps +Z to Godot −Z).
- `scripts/choreo.gd` expands the routine into one state per beat. Within each beat it orders the sub-moves so **weight always leaves a foot before that foot moves**, and a stepping foot moves before it takes weight, so the planted foot never slides. Timing is **square**: every weight change takes the last `weight_phase` of its beat and lands exactly on the count. Moves that have to wait for the weight to leave a foot (lifting it, or bringing it home on 2 and 6) happen in the first `release_phase` of the next beat. A basic always spans counts 1–8, so switches only happen on count 1.
- `scripts/dancer.gd` builds the figure (pelvis → 3 spine segments → neck/head, arms; thighs → shins → feet) and solves each leg with a two-bone IK (law of cosines, knee pole toward the dancer's front). The pelvis moves over the weighted foot, dips during weight changes, and sinks just enough in a wide stance (Sides) that both legs keep a slight bend.
- `scripts/main.gd` runs playback on an unwrapped beat clock (8 beats per basic; the queued basic takes over when the clock crosses a count 1), the HUD, footprints (one per target, labelled with its counts; tap targets carry a gold ring that pulses on the tap), the weight disc, cameras and music.

## Tests

```bash
godot --headless --path . -s res://tests/test_ik.gd       # IK reaches targets, knees bend forward
godot --headless --path . -s res://tests/test_choreo.gd   # every basic switch: no weighted-foot slide, no unreachable target, no jumps, weight lands on the beat
```

## Music

"Salsa 90 BPM" by [TheLastOneOnEarth](https://freesound.org/people/TheLastOneOnEarth/sounds/698660/) (freesound.org), licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). This is the freesound HQ MP3 preview, unmodified. It loops on its 16-beat grid and is time-stretched to the chosen BPM × speed with pitch preserved. The dance clock follows the audio, and if the music's first beat is not on count 1, set `music_offset` (seconds) in the data file.

## Licence

Code: MIT. The music is under its own CC BY 4.0 licence (see above).
