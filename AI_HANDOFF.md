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
- `roblox/sling-smash/` is a separate Roblox game (a Rojo project plus a built `SlingSmash.rbxlx`). It is not part of the website and doesn't affect GitHub Pages. See `roblox/sling-smash/README.md`.
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
- **Summary:** Added a Blender slingshot model for the user's "Slingshot Phase 1" Roblox kit (uploaded as a zip, not stored in the repo).
  - `build_slingshot.py` builds the model with Blender's Python API and exports `Slingshot.fbx`, `Slingshot.obj`, `Slingshot.blend` and `preview.png`.
  - `SetupSlingshot.luau` is a Command Bar script. It names the imported model `Slingshot`, applies Roblox materials, and adds the `LaunchPoint` part and the `LeftTip`/`RightTip` attachments the kit needs.
  - No website or Sling Smash files changed.
- **Files changed:** `roblox/slingshot-model/**` (new), plus this file.
- **Tests run and results:**
  - The build script ran headless with Blender 5.2.3 (the `bpy` module): 8 pieces, 6,444 triangles.
  - Re-importing the FBX into Blender kept all 8 piece names, scale 1, an 8.7-stud height, and TipRight on +X. The OBJ is Y-up.
  - `luau-lsp analyze` (Roblox definitions, all lints) on `SetupSlingshot.luau`: no findings.
- **Remaining issues / unverified behavior:**
  - Not imported into Roblox Studio here. The importer's scale, how the pieces look with Roblox materials, and band alignment in play are unverified.
  - Earlier Sling Smash items still stand: no Studio playtest, client launch reports trusted within caps, no session locking, and redeem codes readable in the repo.
- **Next highest-priority action:** import `roblox/slingshot-model/Slingshot.fbx` into a Baseplate with the Slingshot Phase 1 kit, run `SetupSlingshot.luau`, and check the bands and launch direction. Then playtest `roblox/sling-smash/SlingSmash.rbxlx`.
