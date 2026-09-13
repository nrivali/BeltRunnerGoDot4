# Belt Runner — Godot 4 port

This is a separate project from the browser game in `C:\Users\rival\Documents\BeltRunner` (repo `nrivali/BeltRunner`).
The two are kept apart on purpose: nothing here touches the HTML game, and nothing in the HTML repo depends on this one.

- The browser game is the reference. Port its behaviour and numbers from `belt-runner-3d.html`; do not redesign systems
  while porting. `README.md` tracks what is ported and what is not.
- Godot 4.3 or newer. Godot was not installed on this machine when the port started (2026-09-13). Until it is, scripts
  cannot be run here; once it is, `godot --headless --path . --quit` parses every script and is the quickest smoke test.
- Edit files in place. Commit one task per commit with a `Co-Authored-By:` trailer naming the agent, as in the HTML repo.
- Commit `project.godot`, `scenes/`, `scripts/` and any assets. `.godot/` (the import cache) is ignored. Godot's
  `*.import` sidecar files belong in git once assets arrive.
- Units are the HTML's world units; a readout metre is half a unit (`Data.METRE`). Keep it that way so every number
  ported from the HTML stays correct.
- Multiplayer is planned: keep the belt deterministic from its seed, and keep world changes (broken rocks, pickups,
  ships) separate from generated state, so a server can replicate only the changes.
