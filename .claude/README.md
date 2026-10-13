# Claude skills for this repo

Claude Code loads every folder in `.claude/skills/` as a project skill when it opens this repo. Call one with `/<name>`, or let Claude pick it from the skill's description. To use a skill in all your projects, copy its folder to `~/.claude/skills/`.

Open `claude-cheatsheet.html` in a browser for the full cheatsheet: Claude Code commands, install commands, setup tips and workflows.

These folders are copies of third-party repos (pulled 2026-10-13). Each keeps its original LICENSE. Nothing in `.claude/` is published to GitHub Pages, because Jekyll skips dot-folders.

One local change: in `ui-ux-pro-max/SKILL.md`, the search commands use `${CLAUDE_SKILL_DIR}/scripts/search.py` instead of upstream's `${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max/scripts/search.py`. Upstream wrote that file for plugin installs, and Claude Code only fills in `${CLAUDE_PLUGIN_ROOT}` for plugins. Keep this change if you update the folder. Every other file matches upstream.

| Skill (`/name`) | Source | Commit | License |
| --- | --- | --- | --- |
| `skill-creator` | [anthropics/skills](https://github.com/anthropics/skills) `skills/skill-creator` | `dbd4588` | Apache-2.0 |
| `stop-slop` | [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop) | `8da1f03` | MIT |
| `ui-ux-pro-max` | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) `.claude/skills/ui-ux-pro-max` | `7246805` | MIT |
| `design-taste-frontend` | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) `skills/taste-skill` | `d237dd3` | MIT |
| `redesign-existing-projects` | Leonxlnx/taste-skill `skills/redesign-skill` | `d237dd3` | MIT |
| `high-end-visual-design` | Leonxlnx/taste-skill `skills/soft-skill` | `d237dd3` | MIT |
| `minimalist-ui` | Leonxlnx/taste-skill `skills/minimalist-skill` | `d237dd3` | MIT |
| `industrial-brutalist-ui` | Leonxlnx/taste-skill `skills/brutalist-skill` | `d237dd3` | MIT |
| `full-output-enforcement` | Leonxlnx/taste-skill `skills/output-skill` | `d237dd3` | MIT |
| `impeccable` | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) `plugin/skills/impeccable` | `245ad82` | Apache-2.0 |
| `emil-design-eng` | [emilkowalski/skill](https://github.com/emilkowalski/skill) `skills/emil-design-eng` | `2d22863` | MIT |
| `playwright-cli` | [microsoft/playwright-cli](https://github.com/microsoft/playwright-cli) `skills/playwright-cli` | `b85c7a7` | Apache-2.0 |
| `img2threejs` | [hoainho/img2threejs](https://github.com/hoainho/img2threejs) (repo minus `.github/`, `CLAUDE.md`, sponsor logos) | `d508b59` | Apache-2.0 |

Setup some skills need:

- `playwright-cli`: `npm install -g @playwright/cli@latest`
- `ui-ux-pro-max`: Python 3
- `skill-creator`: Python 3 and PyYAML (`pip install pyyaml`) for its validate and package scripts
- `img2threejs`: Python 3.10+ (see its `forge/requirements.txt`). Its optional character tools (`scripts/character_audit.sh`, `integrations/glb_character_pipeline/`) have known upstream bugs, so stick to the main `/img2threejs` image-to-model flow.

## Plugins (install inside Claude Code)

These ship hooks, agents or dozens of skills, so they install as plugins, not copied folders.

```text
/plugin install superpowers@claude-plugins-official

/plugin marketplace add coreyhaines31/marketingskills
/plugin install marketing-skills@marketingskills

/plugin marketplace add ruvnet/ruflo
/plugin install ruflo-core@ruflo
```

To update a copied skill, replace its folder with a fresh copy from the source repo.
