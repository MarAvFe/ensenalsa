# Dance Simulator — MVP Brief (v2)

## Goal
A lean teaching tool: one stylized dancer performs a salsa basic, with footprints, a beat counter, and multiple camera views. Target: **web export first, desktop fallback**. Must work end-to-end today. Ugly is fine. Working is not optional.

## Hard rules
- Engine: Godot 4.x (latest stable). Use the **Compatibility renderer** so web export works.
- Only free-licensed assets. For the MVP, use **none**: build the figure from primitive meshes (capsules/boxes/spheres).
- Lean. No plugins, no addons, no extra systems beyond what's listed.
- Commit after every numbered step. Each step must run before starting the next.
- If a step is blocked for more than a short attempt, stop and report instead of working around it silently.

## Out of scope (do NOT build)
Partner/follower, hands, hand connection, spins, turns, fingers, toes, skins, imported character meshes, animation files, audio/music, routine editor UI.

## Teaching principle (drives the design)
**All 8 counts are shown and counted: 1 2 3 4 5 6 7 8. Never skip 4 or 8.** Counts 4 and 8 are the tap counts. The tap is deliberate: it gives learners something visible to anchor on. Highlight 4 and 8 in the counter and make the tap clearly readable in the animation.

## Build order
0. **Web export smoke test FIRST.** Empty 3D scene with a cube, export to web, serve locally, confirm it loads in a browser. If web fails, say so and fall back to desktop for the rest of the project.
1. **Figure.** Node3D joint hierarchy built from primitives: pelvis (root), 3-segment spine, neck/head, shoulders, upper arms, forearms (arms hang relaxed, no animation needed), thighs, shins, feet (foot = one box, pitch only). No fingers, no toes.
2. **Leg IK.** Write a simple two-bone IK solver in GDScript for each leg (hip → knee → ankle) driven by a foot target position. Do not depend on Godot's built-in IK nodes. Knee bends forward.
3. **Weight and pelvis.** The weight-bearing foot is pinned to the floor. The pelvis shifts laterally over the weight-bearing foot and drops slightly on steps. The unweighted foot may lift slightly (0.04 m) or tap.
4. **Routine data format + playback.** JSON (or Godot Resource). See format below. Playback: BPM control (default 100), play/pause, step beat-by-beat (forward/back), loop, speed multiplier (0.25x to 1x).
5. **Footprints and beat counter.** Floor markers (left/right distinguishable) at each step target, a large on-screen count 1-8 (4 and 8 highlighted), and a marker for which foot carries weight.
6. **Cameras.** Three, switchable by key or button: behind the dancer, front, and head-down-to-feet (camera at head height looking down at the feet).
7. **Basic sequencer.** A routine is an ordered list of 8-count basics, looping, e.g. `["diagonal_basic","diagonal_basic","inline_basic"]`. **Switching between basics happens only on count 1.** Both basics start and end with both feet at home stance, so no blending is needed.

## Routine data format
A **basic** is 8 counts. Each count has: `count` (1-8), and per-foot `{ target:[x,z], action }`, plus `weight` (`L` or `R`).
Actions: `step` (plant and take weight), `place` (touch down, no weight), `lift` (unweighted foot raised slightly), `tap` (unweighted foot taps the floor), `hold`.
Dancer-local frame: +X right, +Y up, +Z forward (convert to Godot axes in code). **Home stance: feet at shoulder width, L foot (-0.18, 0), R foot (0.18, 0).** Step length about 0.30 m. Slight lift = 0.04 m. All values live in the data file, not in code.

## diagonal_basic (transcribed from the user's description)
Counts 1-4:
1. R steps diagonally **behind the L foot** to about (-0.10, -0.30). Weight R. L lifts slightly.
2. Weight returns to L (L is still at home, planted). R comes back under the right shoulder (0.18, 0) and touches down, no weight.
3. R steps (planted at home), weight R. L lifts slightly.
4. **L lifts and taps the floor** at home (-0.18, 0). Weight stays R.

Counts 5-8: exact mirror (swap L/R, mirror X):
5. L steps diagonally behind the R foot to about (0.10, -0.30). Weight L. R lifts slightly.
6. Weight returns to R (planted at home). L comes back under the left shoulder (-0.18, 0) and touches down, no weight.
7. L steps (planted at home), weight L. R lifts slightly.
8. **R lifts and taps the floor** at home (0.18, 0). Weight stays L.

## inline_basic (transcribed from the user's description; ASSUMPTIONS marked)
Counts 1-4:
1. L steps **forward** to (-0.18, 0.30). Weight L. R lifts slightly and taps the floor in place.
2. Weight returns to R (R at home). L comes back under the left shoulder (-0.18, 0) and touches down, no weight.
3. L steps (planted at home), weight L. R lifts slightly. *(ASSUMPTION: lift on 3, tap on 4, same pattern as the diagonal basic.)*
4. **R taps the floor** at home (0.18, 0). Weight stays L. *(ASSUMPTION, see above.)*

Counts 5-8: mirrored in L/R, and the step goes **backward** (the "front and back" structure):
5. R steps **back** to (0.18, -0.30). Weight R. L lifts slightly and taps the floor in place. *(ASSUMPTION: back step, not right-foot forward.)*
6. Weight returns to L (L at home). R comes back under the right shoulder (0.18, 0) and touches down, no weight.
7. R steps (planted at home), weight R. L lifts slightly.
8. **L taps the floor** at home (-0.18, 0). Weight stays R.

## Acceptance criteria
- Runs in a browser from a local static server (or desktop build if web failed at step 0).
- Dancer visibly performs both basics; the sequencer switches between them only on count 1 with no pops or teleporting.
- All 8 counts are displayed; counts 4 and 8 are highlighted and the tap is clearly visible.
- The weight-bearing foot does not slide.
- Pause, slow-mo, beat-step, and loop all work. All three cameras work.
- README with run and export instructions.
