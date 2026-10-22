# VOLT — Shared AI Handoff

Last updated: 2026-10-22

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
- **Date:** 2026-10-22
- **Summary:** Upgraded the Sling Smash Roblox game (PR #2, branch `ccr-ca33681d-5emi3q`).
  - Gameplay: a mid-air rocket boost with a new Rocket Fuel upgrade branch, slow motion on TNT, and smash sparkles.
  - Progression: an Index of 12 discoveries with one-time rewards, a 7-day daily reward, redeem codes, and a global Top Launches board (OrderedDataStore).
  - Lobby and onboarding: a How to Play sign, an E-to-launch prompt and tutorial pointers.
  - Results screen: coin count-up, a discoveries list and confetti.
  - Reviewed with the `code-review` and `security-review` skills, and fixed the confirmed findings.
  - No website files changed.
- **Files changed:** `roblox/sling-smash/**` only (src/shared, src/server, src/client, tests/, README.md, SlingSmash.rbxlx), plus this file.
- **Tests run and results:**
  - `python3 roblox/sling-smash/tests/run.py`: all checks pass. It covers number formatting, the upgrade-tree layout, the course layout, Index, daily rewards, codes, and flight-physics balance.
  - `luau-lsp analyze` with the current Roblox type definitions reports no errors, both nonstrict with all lints and strict filtered for Roblox API misuse.
  - `rojo build` produces a valid place file.
- **Remaining issues / unverified behavior:**
  - Not playtested in Roblox Studio from this environment, so physics feel, UI layout on real screens, particles, the ProximityPrompt and DataStore/OrderedDataStore behaviour in a published game are unverified.
  - The server still trusts client launch reports within caps, so a forged report can inflate coins and unlock Index rewards. A full fix means simulating flights on the server.
- **Next highest-priority action:** playtest `roblox/sling-smash/SlingSmash.rbxlx` in Roblox Studio, including Test → Clients and Servers with 2 players, and note any bugs here.
