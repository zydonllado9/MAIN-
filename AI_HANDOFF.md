# VOLT — Shared AI Handoff

Last updated: 2026-10-25

## Goal
Develop a premium, cinematic, responsive product website for the fictional VOLT energy-drink concept. Keep it maintainable and compatible with static hosting on GitHub Pages.

## Current implementation
- Static HTML, CSS, and JavaScript; not currently a React application.
- Entry page: `index.html`.
- Active stylesheet linked by the page: `css/style.css`.
- Active JavaScript module linked by the page: `js/main.js`.
- Three.js is imported as an ES module from jsDelivr through an import map.
- Interactive 3D cans, three flavor concepts, scroll/motion effects, responsive sections, and accessibility/fallback behavior are described in `README.md`.
- Root-level `style.css` and `main.js` also exist. Verify which files are referenced before modifying or removing them.
- Existing Claude Code resources and skills are stored under `.claude/`; inspect `.claude/README.md` before adding or replacing skills.
- `roblox/sling-smash/` is a separate Roblox game (a Rojo project plus a built `SlingSmash.rbxlx`). It is not part of the website and doesn't affect GitHub Pages. See `roblox/sling-smash/README.md`. Its tests are `tests/run.py` (luau CLI) and `tests/smoke.luau` (Lune).
- `roblox/slingshot-model/` holds a Blender slingshot model (FBX, .blend, build script) and a Studio setup command for the user's "Slingshot Phase 1" kit. See its README.

## Constraints
- Preserve the current working site and GitHub Pages compatibility.
- Do not introduce a backend, paid APIs, or a framework migration unless explicitly requested.
- Keep API keys and secrets out of Git.
- Respect reduced-motion preferences, keyboard accessibility, and mobile performance.

## Status
- Repository structure and the entry-page asset paths were inspected on 2026-10-20.
- Existing README documents the main product features and local static-server instructions.
- A prior project note says source-level checks were performed, but live browser/console/visual QA had not been verified at that time.
- This setup change adds shared AI instructions only; it does not change website runtime code.
- Current build/test status: no new browser test has been run as part of this handoff setup.

## Workflow for ChatGPT and Claude Code
1. Treat the repository as the shared source of truth.
2. At the beginning of a task, read this file and `CLAUDE.md`, then inspect the relevant source.
3. ChatGPT can help plan work and review repository content when GitHub access is available.
4. Claude Code performs local edits and runs available checks in the developer's terminal.
5. Before merging or publishing substantial work, review the diff and test results.
6. Do not assume either assistant can see the other's live conversation or local terminal. Pass decisions and results through this file and GitHub commits.

## Update this handoff after substantial work
- **Date:** 2026-10-25
- **Summary:** Sling Smash v3 "Overdrive" (PR #2): a performance pass and a big arcade upgrade, driven by the user's long enhancement prompt.
  - **Architecture:** the rules of a launch moved into shared `RunSim.luau`, with pure physics in `Physics.luau`. The client steps it and `FlightEvents.luau` turns its events into effects, so the tests fly the same rules the game does.
  - **Five biomes** (Sky Kingdom, Ancient Jungle, Volcanic Wasteland, Frozen Frontier, Neon Velocity):
    - Roblox Terrain plus props, themed gates and per-biome block materials.
    - A client-side lighting blend with weather and volcanic lightning (`Atmosphere.luau`).
    - Biome rules: updrafts, bounce pads, swinging logs, lava floor and geysers, slippery ice, laser barriers, accelerator gates.
  - **Slingshot feel:**
    - Aim angle and direction with a predicted arc and landing marker.
    - Bands that stretch, heat up, shiver and snap back.
    - A charge-up with energy, a glowing core and an overcharge burst.
    - Launch rings and streaks scaled to power.
  - **Power-ups:** Meteor Breaker, Gravity Rift, Phase Overdrive and Devastation, each with real gameplay effects and its own aura. The mid-air boost is now Nitro Overdrive (kick plus thrust, lightning trail).
  - **Impacts:**
    - Four tiers from speed and durability, with material-specific particles and hit-stop on maximum hits.
    - Armor blocks that bounce you unless you're fast or powered up; ice blocks.
    - Ground-slam shockwaves.
  - **Performance:**
    - `Quality.luau` picks High, Medium or Low (Performance Mode setting).
    - The course is drawn only near the player.
    - The debris budget is capped per quality level, and flung debris no longer collides with itself.
    - Effects are pooled, shadows are off on flat pieces, and a compressor plus a voice cap tame the audio.
  - **Progression:** Index entries for each biome, armor, power-ups and Demolition; two new trails; a Camera Effects and Performance Mode setting.
  - **Server validation** now uses shared `Config.LaunchLimits` and `Config.CoinCeiling`, and checks the new Armor and Powerups report fields.
- **Files changed:** `roblox/sling-smash/**` (shared, server, client, tests, README, SlingSmash.rbxlx, default.project.json), plus this file. No website files.
- **Tests run and results:**
  - `python3 roblox/sling-smash/tests/run.py`: ALL CHECKS PASSED. It covers:
    - layout rules per biome;
    - the arc preview matching real physics, plus its landing flag;
    - armor bonk, break, Meteor and Phase;
    - barriers, geysers, pads, updrafts, lava and slams;
    - Shockwave and Rift, Nitro gain, and one TNT boost per blast;
    - full-flight balance and 40 random flights;
    - honest flights staying inside the server's anti-cheat limits.
  - `lune run roblox/sling-smash/tests/smoke.luau` (Lune 0.11.1): SMOKE OK. It builds the server world:
    - 1,228 parts, against 1,558 before;
    - terrain calls recorded, not executed.
    It also builds the course and every effect, blends biome lighting along the lane, and flies five full launches through the real FlightEvents handlers, with all 20 event types exercised.
  - `luau-lsp analyze` (current Roblox definitions): no findings in nonstrict mode with all lints, and no Roblox API misuse in strict mode.
  - Every property the code sets was checked against the Roblox API dump for script write access. This caught `Terrain.Decoration` (NotScriptable), which is now set in `default.project.json`.
  - `rojo build` produces valid XML with all 21 scripts.
  - The `code-review` skill (high) found 10 issues; 9 are fixed. Unverified: whether moving one emitter and calling Emit several times in a frame always spawns at each new spot.
- **Remaining issues / unverified behavior:**
  - **Not playtested in Roblox Studio** (not possible here). Nothing has been seen in a real client:
    - terrain look and joins;
    - lighting blends, effects and auras;
    - Fire/Smoke/ForceField looks;
    - mobile controls (the thumbstick aims while in the slingshot);
    - real frame rates;
    - DataStores in a published game.
  - Coin economy is faster than before (power-ups and more blocks): the first full launch pays about 1,400 coins (was about 610).
  - Built-in client sounds are few; most effects reuse them at different pitches.
  - Still true from before: client launch reports are trusted within caps, saves aren't session-locked, and redeem codes are readable in the repo.
- **Next highest-priority action:** playtest `roblox/sling-smash/SlingSmash.rbxlx` in Roblox Studio:
  - on PC and with the device emulator;
  - with Test → Clients and Servers set to 2 players;
  - checking terrain, every power-up and hazard, Performance Mode and frame rate, then recording any bugs here.
