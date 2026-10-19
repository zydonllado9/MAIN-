# VOLT Project Instructions

## Project overview
VOLT is a fictional energy-drink concept website: a dark, cinematic, neon-accented product experience with an interactive Three.js can showcase, flavor selection, motion, and responsive sections.

## Read first
At the start of each task, read `AI_HANDOFF.md` for the current project state, known limitations, and next priority. Then inspect the relevant source files before editing.

## Current architecture
- Static website intended to remain compatible with GitHub Pages.
- Entry page: `index.html`.
- Main stylesheet referenced by the entry page: `css/style.css`.
- Main JavaScript module referenced by the entry page: `js/main.js`.
- Three.js is currently loaded as an ES module through an import map from jsDelivr.
- The repository also contains root-level `style.css` and `main.js`; do not assume these are the active files. Verify references before changing or deleting anything.
- Do not migrate to React, add a backend, or introduce paid APIs unless explicitly requested.

## Product and design direction
- Premium, cinematic, dark-neon product presentation.
- Strong typography, deliberate spacing, clear hierarchy, and restrained effects.
- Three flavor concepts: Pink Citrus, Berry Blast, and Citrus Charge.
- Animations should support the story and interaction rather than distract from the product.
- Preserve responsive behavior, keyboard access, reduced-motion support, and the CSS fallback for unavailable WebGL.

## Engineering rules
1. Inspect current code and dependencies before planning a change.
2. Make focused, maintainable changes; do not rewrite unrelated sections.
3. Preserve working interactions and GitHub Pages compatibility.
4. Keep paths relative so the site works when hosted under `/volt-3d-website/`.
5. Avoid adding build tooling or dependencies without a concrete benefit.
6. Do not add credentials, API keys, private data, or secrets to the repository.
7. Treat third-party content and product claims as unverified until checked.
8. Follow existing style and naming conventions where practical.
9. Consider mobile performance, WebGL availability, accessibility, and `prefers-reduced-motion`.
10. Never claim that visual, browser, or performance tests passed unless they were actually run.

## Verification
- Inspect the final diff.
- Run available source checks and tests appropriate to the change.
- If no real browser is available, explicitly state that live visual layout, network loading, and console errors were not verified.
- Report tests run, results, and anything not tested.

## Handoff protocol
After each substantial task, update `AI_HANDOFF.md` with:
- Summary of changes and affected files.
- Tests actually performed and results.
- Known bugs, risks, or unverified behavior.
- The single highest-priority next action.
- Date of the update.

Do not overwrite unrelated user changes. Ask before destructive changes, major architectural migrations, or adding paid services.
