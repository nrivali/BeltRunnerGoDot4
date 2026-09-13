# Belt Runner — Godot 4 port

This is a separate project from the browser game in `C:\Users\rival\Documents\BeltRunner` (repo `nrivali/BeltRunner`).
The two are kept apart on purpose: nothing here touches the HTML game, and nothing in the HTML repo depends on this one.

- The browser game is the reference. Port its behaviour and numbers from `belt-runner-3d.html`; do not redesign systems
  while porting. `README.md` tracks what is ported and what is not.
- Godot 4.7.2 is installed via winget (2026-09-13). The console build, which prints script output to the terminal, is
  `C:\Users\rival\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
  (the `godot` alias needs an admin winget run). Checks, in order of cost: `--headless --path . --quit-after 5` parses and
  runs five frames; `--path . --resolution 1280x720 -- --smoke` opens a window, runs the scripted mining pass, saves
  `%APPDATA%\Godot\app_userdata\Belt Runner\smoke.png` and quits. Read the PNG to see the result.
- GDScript gotcha that bit the first run: `var x := <expression built from a Dictionary value>` fails to parse because the
  type cannot be inferred; write `var x: float = ...` (or cast) whenever a value comes out of a Dictionary.
- Edit files in place. Commit one task per commit with a `Co-Authored-By:` trailer naming the agent, as in the HTML repo.
- Commit `project.godot`, `scenes/`, `scripts/` and any assets. `.godot/` (the import cache) is ignored. Godot's
  `*.import` sidecar files belong in git once assets arrive.
- Units are the HTML's world units; a readout metre is half a unit (`Data.METRE`). Keep it that way so every number
  ported from the HTML stays correct.
- Multiplayer is planned: keep the belt deterministic from its seed, and keep world changes (broken rocks, pickups,
  ships) separate from generated state, so a server can replicate only the changes.
