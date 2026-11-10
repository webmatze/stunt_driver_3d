# Stunt Driver 3D

A stunt racing game for [DragonRuby GTK](https://dragonruby.org/), built on the
[D3D](https://github.com/webmatze/d3d) engine (vendored in `app/d3d`). Drive 3D tracks with
bridges, loops, jumps, tunnels and curves against the clock without wrecking the car, and
build your own tracks from the same parts in the editor. The game's texts are German.

## Run

```bash
smaug run                 # DragonRuby version from Smaug.toml
# or: dragonruby .
```

## Playing

| Key | Action |
|---|---|
| Up / W | Accelerate |
| Down / S, Space | Brake, reverse at standstill |
| Left / Right, A / D | Steer |
| C | Camera: chase, far, bonnet |
| R | Restart the run |
| P | Pause |
| ESC | Back to the menu (or to the editor after a test drive) |

A gamepad works too (stick, A / R2 accelerate, B / L2 brake).

- The clock starts at "LOS!" and stops on the start/finish line once every part of the
  track has been driven in order. Leave a part out and the map shows where to go back to.
- The run ends in a crash when the car hits something fast, lands too hard or not on its
  wheels. Grass only slows it down.
- A loop needs about 80 km/h at its entrance, a jump over one empty tile about 115 km/h,
  over two about 165 km/h.
- Best times are kept per track in `data/times.txt`.

## Track editor

`E` in the menu opens the selected track ("+ Neue Strecke bauen" starts an empty one; a
track that ships with the game is edited as a copy). Up to 8 own tracks are stored as text
files in `tracks/user_N.txt`.

| Input | Action |
|---|---|
| Left mouse button / Space | Place the selected part (drag to paint) |
| Right mouse button / X | Remove the part |
| R / mouse wheel | Rotate |
| Click on the palette, Q / E | Choose a part |
| Arrow keys | Move the cursor |
| T | Test drive |
| S | Save (also saved when leaving) |

Parts: straight, start/finish, curve, wide curve (2x2 tiles), crossing, ramp, elevated road,
elevated curve, bridge (elevated road over a ground road), jump ramp, loop, tunnel, slalom
obstacle and scenery (trees, house, grandstand). The editor follows the road from the
start/finish line after every change and tells where it ends: a track can be driven once it
forms a closed circuit. A jump ramp needs a second one facing it as the landing, with at
most 2 empty tiles between them. Ground and elevated roads only connect through a ramp.

## How it works

```
app/main.rb               requires + tick
app/d3d/                  the D3D engine (unchanged copy)
app/game/
  geo.rb                  static world geometry: shared vertices, triangles with baked sun light
  pieces.rb               the track parts: connectors, centre lines, geometry, collision
  track.rb                tile grid, text format, route check
  world.rb                a track built for driving: geometry, collision grid, route centre line
  car.rb                  car physics
  race.rb                 countdown, clock, order of the parts, finish
  autopilot.rb            drives the centre line (menu demo, tests)
  builtin_tracks.rb       the three tracks that ship with the game
  gfx.rb                  renderer on top of D3D::SceneRenderer
  models.rb               car, wheels, wreckage
  map_view.rb             top-down drawings for editor, palette and minimap
  hud.rb, editor.rb, game.rb
```

- **Rendering** uses the engine's 6DOF `SceneRenderer` (camera `Pose` with free roll, needed
  in the loop) plus `StuntRenderer`: world triangles with near-plane clipping, a ground
  layer drawn unsorted before everything else, a banded sky and horizon, and haze. To keep
  the painter's algorithm from drawing road over the car, every triangle is tested against
  the car: if the car is on the camera's side of its plane it is drawn before the car,
  otherwise after it.
- **Physics** treats the car as a point with an orientation. A ray along the car's own
  "down" finds the road, so the same code drives on the flat, on ramps and upside down
  through the loop; gravity always acts, so a car that is too slow at the top falls off.
  A second ray along the velocity and two spheres against solid boxes detect crashes.
  The loop gently steers the car along its strip, like a rut.
- **Tracks** are a 20x20 grid of 30 m tiles. Every part declares connectors (tile edge and
  height level) and links between them; the route check walks these from the start line.

## Tests

```bash
ruby tests/game_test.rb                           # game logic with plain Ruby (no DragonRuby)
ruby tools/smoke.rb                               # headless DragonRuby: menu, autopilot lap, crash, editor
ruby tools/smoke.rb --eval tools/smoke_ui.rb      # input polling, new track, test drive, delete
ruby tools/gen_assets.rb                          # regenerate the sounds
```

The unit tests include the autopilot finishing every built-in track and the loop and jump
at different speeds. `tools/smoke.rb` saves screenshots and reports the Ruby time per tick
(about 2 ms on an M-series Mac without the C extension).

The optional D3D Pro C extension is picked up when a `native/` folder is present
(`D3D::Native.load`); the game doesn't need it.
