# Light and Atmosphere in Godot 4

Project files for tutorial 08 of the Godot 4 series by Phaix on YouTube (https://www.youtube.com/@Phaix).

Light the generated rooms of a game like Roblox DOORS in Godot 4.
We build an environment made for interiors, lamps that cast shadows, fog, glow and global illumination that works with rooms built while you play.

A building has no sky and no sun: the Environment gets a custom colour background, a cold trace of ambient light and the Filmic tonemap. A lamp becomes a scene of its own, placed from Marker3D nodes, with shadows on and the shadow atlas explained. Depth fog and volumetric fog give the air a body, glow makes the emissive fixture look bright, and SDFGI bounces the light in rooms that did not exist a second ago, with GI Mode Disabled for everything that moves. Every step is its own project folder.

![Screenshot](screenshot.png)

## Steps

Every step of the video is its own folder in `steps/`, the exact state at the end of that
part. Open the project in Godot 4.7, then open `steps/<step>/main.tscn` and press F6 to run
that step. The project's main scene is the final step.

| Folder | Part of the video |
|---|---|
| `steps/step_00_start` | Starting point (the final state of tutorial 07) |
| `steps/step_01_environment` | Step 1 - An environment for rooms |
| `steps/step_02_lamps` | Step 2 - Lamps that cast shadows |
| `steps/step_03_fog` | Step 3 - Fog |
| `steps/step_04_glow` | Step 4 - Glow |
| `steps/step_05_global_illumination` | Step 5 - Global illumination |

## Controls

WASD or arrow keys or the left stick to walk, mouse or right stick to look, Space to jump,
Esc gives the mouse back, a click captures it again. Further keys per tutorial are shown
in the video and in the HUD.

## Tests

```sh
godot --headless --path . -s res://tests/run_tests.gd
```

## Support

Support the channel: https://ko-fi.com/phaix or https://github.com/sponsors/schemann

## License

Code and scenes: MIT (see LICENSE).
The figure and its animations: Animated Characters Protagonists by Kenney (www.kenney.nl), CC0, see character/License.txt.
