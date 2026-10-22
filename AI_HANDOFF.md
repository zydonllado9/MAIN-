# VOLT — Shared AI Handoff

Last updated: 2026-10-20

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
- **Date:**
- **Summary:**
- **Files changed:**
- **Tests run and results:**
- **Remaining issues / unverified behavior:**
- **Next highest-priority action:**
