# Sling Smash (Roblox)

A slingshot launch-and-smash arcade game:
1. Aim and charge the slingshot.
2. Fling yourself down a 3,000-stud lane through five biomes.
3. Smash blocks for coins and combos, and grab power-ups.
4. Spend the coins in a hex upgrade tree so the next launch goes further.

## Play it in 2 minutes

1. Download [`SlingSmash.rbxlx`](SlingSmash.rbxlx).
2. Open **Roblox Studio** → **File → Open from File…** → pick `SlingSmash.rbxlx`.
3. Press **Play** (F5).

Scripts build the whole world, the UI and the effects when the game starts, so
the edit view looks empty until you press Play. That's expected.

## Controls

| Action | Keyboard / mouse | Phone / tablet | Gamepad |
| --- | --- | --- | --- |
| Get in the slingshot | **Launch** button, or **E** at the slingshot | **Launch** button | **Launch** button |
| Aim up / down, left / right | W / S and A / D, or drag while charging | Thumbstick, or drag while charging | Left stick |
| Charge | Hold left click or Space | Press and hold the power bar | Hold A or R2 |
| Launch | Release | Release | Release |
| Steer in the air | A / D or ← / → | Thumbstick | Left stick |
| ⚡ Nitro in the air | Left click or Space | **NITRO** button | A or R2 |
| Cancel | Red **X** next to the power bar | Same | Same |

A dotted arc shows where a launch will land while you aim. Dragging works like
a real slingshot: drag down to aim higher, and drag left to aim right.

## What's in the game

### The five biomes
Each biome has its own terrain, lighting, weather, block material and rules.
The lighting blends smoothly as you fly from one biome into the next.

| Biome | Look | What's special |
| --- | --- | --- |
| 🏰 **Sky Kingdom** | Golden afternoon, floating islands, waterfalls, giant trees, ruins | **Updrafts** lift you, with a star at the top. **Bounce pads**. |
| 🌴 **Ancient Jungle** | Misty morning, huge trees with vines, a temple, swamp pools | **Swinging logs** knock you sideways. **Armored** stone foundations. |
| 🌋 **Volcanic Wasteland** | Red dusk, volcanoes, lava rivers, basalt spires, lightning | **The floor is lava**: fast landings bounce. **Geysers** erupt and launch you skywards. |
| ❄️ **Frozen Frontier** | Aurora twilight, snowy pines, ice crystals, a frozen lake | **Slippery ice** lane: you slide much further. **Ice blocks** shatter. |
| ⚡ **Neon Velocity** | Midnight neon city, holographic rings | **Laser barriers** slow you (fly over or steer round). **Accelerator gates**. |

### The slingshot
- **Aim** the angle (10–45°) and direction (±15°), with a live arc preview and landing marker.
- **Charge-up:**
  - Energy swirls in and the slingshot's core glows brighter as you pull back.
  - The bands stretch thinner, heat from orange to white-hot and shiver at high tension.
  - 100% triggers an overcharge burst.
- **Launch:**
  - A shockwave ring and speed streaks, with a flash and camera kick scaled to your power.
  - The bands snap forward and wobble after release.

### Power-ups
Fly through a glowing orb to activate it.

| Power-up | Effect | Look |
| --- | --- | --- |
| ☄️ **Meteor Breaker** (4 s) | Bigger smash radius, no slowdown, breaks armor at any speed | Fire, smoke and embers, glowing core, flame trail |
| 🌌 **Gravity Rift** (5 s) | Low gravity, so you float; pulls nearby blocks in and smashes them | Purple vortex: spinning rings, inward particles, a refracting glass lens |
| 👻 **Phase Overdrive** (4.5 s) | Pass through armor, laser barriers and logs unharmed | Energy shell, glowing outline, ghostly afterimages |
| 💥 **Devastation** (instant) | Shockwave smashes everything within 26 studs and lifts you | Layered rings, an energy bubble, dust, sparks |
| ⚡ **Nitro Overdrive** (your boost) | A kick of speed plus half a second of thrust | Cyan trail, crackling lightning, rings, FOV punch |

Each biome opens with the power-up that suits it best. For example, Phase comes right before the Neon lasers.

### Smashing and impacts
- **Block types:**
  - Wood, stone, snow and neon blocks.
  - **Gold** pays 15× coins.
  - **TNT** chain-reacts and boosts you.
  - **Ice** shatters with almost no slowdown.
  - **Armor** only breaks above 120 studs/s, or with Meteor, TNT or a shockwave. Slower hits bounce you back.
- **Impact tiers 1–4:** effects scale with your speed and the block's durability.
  - Light impacts give a few sparks.
  - Maximum impacts add rings, an energy bubble, a brief **hit-stop** and a "DEVASTATING!" pop.
- **Material effects:**
  - Wood splinters, stone dusts, glass shatters, metal sparks and neon blocks burst with energy.
- **Ground slams:** landing very hard sends out a shockwave.
- **Combos and crits:** keep smashing to build the multiplier. 8% of smashes are **CRITICAL!** and pay triple.

### Progression
- **Upgrade tree:** 36 hex nodes in 9 branches, including Rocket Fuel for extra Nitro charges.
- **Rebirth:** a permanent coin multiplier.
- **Trail shop:** eight trails, including the new Plasma and Aurora.
- **Index:** 17 discoveries, now including every biome, Iron Breaker, Power Surge, Overcharged and Demolition.
- **Daily reward streak** and **redeem codes** (try `LAUNCH`).
- **Top Launches** board (global once published).
- **Stats** and **Settings** panels.
- A finish-line camera sequence when you reach the end.

### Performance
The game scales its effects to the device. Turn on **Performance Mode** in
Settings for the lightest version.

- **Only nearby course is drawn.** Blocks, orbs and hazards far down the lane are
  kept out of the world until you get close. Measured at the start of the lane:
  about 530 course parts drawn, where the old version always drew all ~2,480.
- **Capped debris.**
  - Smashed blocks fly with real physics only up to a budget: 80 on High, 45 on Medium, 20 on Low. Beyond that they just vanish.
  - Flying pieces don't collide with each other.
- **Pooled effects.** Rings, lightning, particles and afterimages are reused, never created every frame.
- **Quality levels.** High, Medium (phones and mid graphics settings) and Low (Performance Mode or low graphics) scale:
  - particles, debris and floating numbers;
  - speed lines, weather and afterimages;
  - hit-stop, block shadows and how far ahead the course is drawn.
- **Lighter world.** Terrain does the heavy lifting.
  - The server world has 1,228 parts and 32 text signs, versus 1,558 parts and 66 signs before.
  - Flat pieces don't cast shadows.
- **Sound.** A compressor and a cap of 10 overlapping sounds stop big chains from clipping or piling up.

### Comfort
**Camera Effects** in Settings turns off screen shake, hit-stop and camera roll, and
tones down FOV kicks and flashes for players who prefer calmer motion.

## Publishing and saving progress

DataStores only work in a published place. Until then the game runs fine but
progress resets each session. The Output window says so.

1. **File → Publish to Roblox**.
2. **Home → Game Settings → Security**, then turn on **Enable Studio Access to API Services**
   if you want saving to work while testing in Studio.

## Tweaking the game

Every balance number lives in [`src/shared/Config.luau`](src/shared/Config.luau):
- launch speed, gravity, aim limits;
- biomes, their lighting and ground rules;
- block values and durability;
- power-up durations and strengths;
- hazards;
- quality budgets;
- upgrade costs, trails and rebirth.

In Studio it's `ReplicatedStorage → Shared → Config`. The course layout (what
goes where) is in [`src/shared/CourseLayout.luau`](src/shared/CourseLayout.luau).

Redeem codes live in [`src/server/Codes.luau`](src/server/Codes.luau). Players can't
read them from inside the game, but anyone who can see this repository can, so treat
them as public promo codes. Keys must be UPPER CASE with no spaces.

To add **background music**, paste an audio asset id into `Config.Sounds.Music`,
for example `"rbxassetid://1234567890"`.

The other sounds use sounds built into the Roblox client, so they work without
uploading anything. The client checks each one loads and swaps in a fallback if
one doesn't. With only a handful of built-in sounds, most effects reuse them at
different pitches. For richer audio, swap in Creator Store sounds whose licence
allows use in your game.

## Project layout (for developers)

The source is a [Rojo](https://rojo.space) project:

```
default.project.json        Rojo project → builds SlingSmash.rbxlx
src/shared/                 ReplicatedStorage.Shared (used by server + client)
  Config.luau               all tunables: biomes, blocks, power-ups, hazards, quality
  CourseLayout.luau         deterministic layout: blocks, orbs, hazards per biome
  Physics.luau              pure flight physics + arc prediction
  RunSim.luau               the rules of a launch (smashing, power-ups, hazards)
  Daily.luau, Format.luau, Index.luau
src/server/                 ServerScriptService.Server
  init.server.luau          remotes, characters, trails, launch validation, rewards
  WorldBuilder.luau         terrain biomes, scenery, gates, slingshot, lighting
  Codes.luau, DataService.luau, Leaderboard.luau
src/client/                 StarterPlayerScripts.Client
  init.client.luau          states, aiming + arc, bands, flight loop, camera
  FlightEvents.luau         turns RunSim events into effects, sound and pops
  Course.luau               course visuals, view window, debris budget, hazard animation
  Effects.luau              impacts, rings, lightning, auras, charge-up, sound
  Atmosphere.luau           per-biome lighting blend, weather, volcanic lightning
  Quality.luau              picks the effects budget for the device
  UI.luau, UpgradeTree.luau, Widgets.luau
tests/                      logic tests and a smoke test (not part of the place)
```

Rebuild the place file after editing the source:

```bash
rojo build default.project.json -o SlingSmash.rbxlx
```

Or run `rojo serve` and connect from the Rojo Studio plugin to sync live.

### Running the tests

**Logic tests** run the real shared modules outside Roblox with small stand-ins
for `Vector3`, `Color3` and `Random`. They need the standalone
[`luau`](https://github.com/luau-lang/luau) command-line tool:

```bash
python3 tests/run.py            # uses `luau` on PATH, or $LUAU
```

They cover:
- the layout rules;
- the aim preview matching real flights;
- every power-up and hazard;
- armor bonks and breaks;
- slippery ice and lava;
- flight balance;
- 40 random flights;
- proof that honest flights never hit the server's anti-cheat limits.

The script prints `ALL CHECKS PASSED` and exits with 0.

The **smoke test** runs the real Instance-building code with
[Lune](https://lune-org.github.io/docs), which checks every property name, type and
enum against Roblox's API. It builds:
- the server world;
- the course visuals and every effect;
- the biome lighting.

It also flies five full launches through the event handlers.

```bash
lune run tests/smoke.luau
```

### How it works

- **The server** builds the world and owns all player data. When a launch
  ends, it checks the client's report against limits that depend on how long the
  launch took (`Config.LaunchLimits`, `Config.CoinCeiling`) before awarding coins.
- **The client** steps `RunSim` every frame and draws what happens.
  - The character is in `PlatformStand`, and its root part follows the simulation.
  - Other players see the flight because each client owns its own character's physics.
- `RunSim` is shared code. The tests fly the same rules the game does.

## Known limitations

- **Untested in Studio.** It hasn't been playtested in Roblox Studio yet. None of the following has been seen on screen:
  - terrain and lighting;
  - effects and power-up auras;
  - mobile controls and real frame rates.
- **Forgeable reports.** The server only sanity-checks launch reports. An exploiter could still inflate coins within those caps, including unlocking Index rewards with a forged launch. `RunSim` is shared, so the server could re-simulate launches in future to close this.
- **No music** until you add an audio id (see above).
- **Global board needs publishing.** The Top Launches board only goes global in a published game with DataStores.
- **No session locking.** If a player hops servers within a few seconds, the newer server can load data from before the last save and roll that progress back.
