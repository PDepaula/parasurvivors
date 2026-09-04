# Parasurvivors — Design Spec

Date: 2026-09-04
Status: approved for planning (execution by Opus 5)

## 1. Goal

A small, complete Vampire Survivors clone with the feature set of the original itch.io demo
(one endless stage, a handful of characters, ~7 weapons, ~7 passives, level-up choices,
timed enemy waves, bosses, pickups, a 30-minute Reaper), built on Zach Oakes' paranim stack.

The README states the real aim: **a showcase of simplicity**. All game state lives in a
pararules session; the game is a set of small rules plus a few pure Nim procs for the
N×M hot loops. Each other concern is one composable library:

| Concern | Library | Why |
|---|---|---|
| State + logic | pararules 1.4.x (`staticRuleset`) | the point of the project |
| Window/input | paranim/glfw | already used by parakeet |
| Rendering | paranim (ImageEntity, InstancedImageEntity, TwoDEntity) | sprites + colored shapes |
| Text | paratext 0.13 | HUD, menus |
| Audio out | parasound 1.0 (miniaudio bindings) | play in-memory WAVs |
| SFX/music | paramidi 0.7 + paramidi_soundfonts 0.2 | all sound is *generated* at startup from tiny scores — no audio files |
| Image decode | stb_image 2.5 | PNG loading |

Desktop only (GLFW, OpenGL 3.3). Emscripten is a documented stretch, not in scope.

Toolchain present on this machine: Nim 2.2.10, paranim 0.12.0, pararules 1.4.0, stb_image 2.5,
ImageMagick 7 (`magick`), `gh`, `curl`. Python PIL is **not** installed; the asset script uses ImageMagick.

## 2. Reference code (read these first)

- `/home/pdp/Projects/parakeet` — Zach's minimal paranim template (GLFW loop, `core.nim` layout, `config.nims`). Our `src/parasurvivors.nim` is a near copy.
- `/home/pdp/Projects/paratry/src/core.nim` — the user's own experiment: top-down movement, `Id = distinct int` (we use plain ints instead), spawn rule using a timestamp.
- paranim_examples `super_koalio/src/core.nim` — sprite-sheet `crop`, camera via `invert(camera)`, instanced tile map.
- paranim_examples `dungeon_crawler/src/core.nim` — many enemies as dynamic int ids, `cond: id != Player.ord`, `moveEnemy` rule joining `(Player, X, px)`.
- paranim `examples/src/ex27_text.nim` — paratext usage (`initFont`, `initTextEntity`, instanced text `add`).
- parasound `tests/common.nim` — miniaudio engine/decoder/sound from memory; paramidi_starter `src/paramidi_starter.nim` — render score → WAV bytes.
- pararules README — `then = false`, `thenFinally`, `queryAll`, `retract`, int ids beyond the enum, `staticRuleset`.

Key facts verified from the installed sources:
- `session.insert(id: Id or int, attr, value)`, `session.retract(id: Id or int, attr)`, `session.contains(id, attr)`.
- In a rule, a bound `id` is an `int`. Compare with `Player.ord`.
- `session.queryAll(rules.X)` returns `seq` of named tuples; `session.query(rules.X, id = 5)` filters.
- `fireRules` raises if rules keep re-firing more than 16 passes; every mutating rule must mark
  its self-triggering inputs with `then = false`.
- paranim `InstancedImageEntity`: `instanceCount` and attribute `data` (`ref seq`) are public; `render` re-uploads
  attributes whose `disable` flag is false, and `setBuffer` recomputes `instanceCount` from the data length.
  So a batch can be rebuilt each frame: clear the two `ref seq`s, `add` each sprite, render.
- `crop(x, y, w, h)` on an ImageEntity sets the texture matrix in pixels of the source image.
- Images use `GL_NEAREST` filtering (pixel art safe).

## 3. Scope

### In scope (the "demo")
- **Stage**: one infinite grass field (LPC grass tile), 30-minute clock, Reaper at 30:00.
- **Characters (4)**, each with a starting weapon and one stat perk. Names are placeholders:
  Otto (Whip), Imma (Magic Wand), Lina (Runetracer), Gino (Knife).
- **Weapons (7)**: Whip, Magic Wand, Knife, Axe, Runetracer, Garlic, King Bible. Max level 8. Max 6 weapon slots.
- **Passives (7)**: Spinach, Armor, Hollow Heart, Pummarola, Empty Tome, Wings, Attractorb. Max level 5. Max 6 slots.
- **Enemies**: Bat, Zombie, Skeleton, Mudman (green tint), Ghost (white tint), plus bosses:
  Giant Parakeet (Zach's parakeet sprite, scaled), Koalio (Zach's koala sprite, scaled), Reaper (hooded skeleton, huge, unkillable in practice).
- **Waves**: minute-indexed table (kinds, spawn interval, minimum on-screen count), bosses at fixed minutes, enemy cap 300.
- **Pickups**: XP gems (3 values), floor chicken (heal), coin (gold), treasure chest (from bosses; levels a random owned weapon), vacuum (magnetize all gems).
- **Level-up**: pause, 3 choices (new/upgrade weapon or passive), pick with keys.
- **Screens**: Title → Character select → Run (HUD: timer, level, XP bar, kills, gold, HP bar) → Level-up overlay → Pause → Game over / Survived results → retry.
- **Audio**: SFX (hit, gem, level-up, hurt, boss) and a looping music phrase, all rendered by paramidi at startup. `-d:noaudio` disables.
- **Tests**: headless `nimble test` for rules and systems (no OpenGL needed).

### Out of scope
- Weapon evolutions, gold power-up shop, persistent unlocks/saves, multiple stages, controller input, web build.

## 4. Architecture

```
src/parasurvivors.nim   GLFW window + main loop (copy of parakeet), forwards input to core
src/core.nim            Game object, init (GL + assets + audio), tick = run rules → systems → render
src/rules.nim           Id/Attr enums, schema, staticRuleset, session helpers. NO OpenGL imports.
src/data.nim            Pure data tables: characters, weapons, passives, enemies, waves, XP curve
src/systems.nim         Pure procs on plain seqs: spatial hash, collisions, pickups, attack plans, choices
src/render.nim          Sprite sheets, per-sheet instanced batches, shapes batch, ground, HUD, menus
src/audio.nim           paramidi → WAV bytes → miniaudio sounds; play/loop
src/assets/             PNG sheets (generated by tools/fetch_assets.sh), Roboto-Regular.ttf, CREDITS.md
tools/fetch_assets.sh   Downloads LPC layers, composes characters with ImageMagick, tints enemies
tests/                  test_rules.nim, test_systems.nim, test_data.nim (+ config.nims with --path:"../src")
```

### 4.1 Facts

Ids: `enum Id = Global, Player`. Everything else (weapon slots, passives, enemies, projectiles, pickups)
is a dynamic `int` id from a counter fact `(Global, NextId, n)`. Entity *type* is signalled by
which "kind" attribute an id has: `WeaponKind`, `PassiveKind`, `EnemyKind`, `ProjKind`, `PickupKind`.
Rules that should only see enemies join on `(id, EnemyKind, kind)`, etc.

Shared attrs across entity types: `X`, `Y`, `Hp`, `Speed`, `Damage`, `Size`.

Player-only: `Character`, `Facing`, `Moving`, `MaxHp`, `Xp`, `Level`, `XpToNext`, `Gold`, `Kills`, `Stats`
(one small object: might, armor, regen, cooldownMul, speedMul, magnet, area, amount, projSpeed, duration —
recomputed by a rule whenever a passive changes).

Global-only: `DeltaTime`, `TotalTime`, `GameTime`, `WindowWidth/Height`, `WorldWidth/Height`,
`PressedKeys`, `JustPressed`, `Phase`, `SelectedIndex`, `Choices`, `NextId`, `SpawnTimer`, `EnemyCount`,
`BossesSpawned`, `NearestX`, `NearestY`, `HasNearest`, `ResultText`.

Collections stored as `ref seq` / `HashSet` per the pararules README perf note.

### 4.2 Rules (the reactive part)

Getters (no `then`): window, world, keys, phase, player, stats, weapons, passives, enemies, projectiles, pickups, choices, run.

Mutating rules, all triggered once per tick by the `DeltaTime` insert (everything else `then = false`):
`tickGameTime`, `movePlayer`, `regenPlayer`, `moveEnemies`, `decayHitFlash`, `moveProjectiles`
(per-kind motion: straight / arc with gravity / orbit around player / bounce inside the view),
`tickWeapons` (cooldown → spawn an attack plan → new projectile facts), `spawnWave`, `spawnBosses`, `movePickups` (magnetized gems).

Reactive rules: `levelUp` (Xp ≥ XpToNext → Level++, Phase=LevelUp, Choices), `playerDied` (Hp ≤ 0 → GameOver),
`recomputeStats` (any PassiveLevel change → new Stats).

Phase gating is done in `tick`: `DeltaTime`/`GameTime` are only inserted while `Phase == Running`, so
movement/spawn rules simply never fire on menus. Menu input is handled by small procs in core using `JustPressed`.

### 4.3 Systems (the plain-Nim part)

Rete joins are wrong for N×M work (every projectile vs every enemy). Each tick, after `fireRules`,
core pulls the seqs via `queryAll` and calls pure procs from `systems.nim`:

1. `collide(projs, enemies)` → hits, using a 64-px spatial hash over enemies.
2. `contactDamage(enemies, player, stats, dt)` → hp loss (sum of enemy damage per second, each reduced by armor, minimum 1).
3. `pickupsToCollect(pickups, player, magnetRadius)` → collected + newly magnetized.
4. Deaths → retract enemy, spawn gem/chicken/coin/chest, Kills++.
5. Despawn enemies far outside the view (they get respawned by `spawnWave`); nearest-enemy search → `NearestX/Y`.
6. Apply results with `session.insert`/`retract`, then `fireRules` again so `levelUp`/`playerDied` react.

Every system is a pure function of seqs → results, so tests are trivial and no OpenGL is needed.

### 4.4 Rendering

- World units = source pixels. Camera = player position; `entity.project(worldW, worldH); entity.invert(camera)` as in super_koalio. `zoom` const (default 1.0) scales worldW/H.
- One `InstancedImageEntity` per sprite sheet, rebuilt each frame from the queried seqs (clear `a_matrix`/`a_texture_matrix` data, `add` per visible sprite). Enemies are culled to the view + margin.
- LPC walk sheets: 576×256, 64×64 frames, rows = up, left, down, right; 9 columns; column 0 is the idle pose. Frame = `1 + int(t / 0.1) mod 8` while moving.
- Projectiles and pickups: one `InstancedTwoDEntity` (colored quads with rotation) — no extra art needed.
- Ground: one instanced entity of a 32×32 grass tile covering the view plus one tile margin, translated to `floor(camera / 32) * 32`.
- HUD/menus: paratext instanced text entities (Roboto 24 px) + `TwoDEntity` bars/overlays. XP bar top, timer top-center, HP bar under player.

### 4.5 Audio

At init, `audio.nim` compiles ~6 paramidi scores (e.g. gem = `(glockenspiel, 1/16, +c)`),
renders each to `cshort` samples with the bundled `generaluser.sf2`, wraps them as WAV bytes (dr_wav in memory),
and creates one miniaudio `ma_sound` per effect from a memory decoder. `play(Sfx)` seeks to frame 0 and starts;
music uses `ma_sound_set_looping`. Missing bindings (`ma_sound_seek_to_pcm_frame`, `ma_sound_set_looping`,
`ma_sound_set_volume`) are declared locally with `{.cdecl, importc.}` — the symbols exist in parasound's compiled `miniaudio.c`.
Soundfont is `staticRead` in release and read from `paramidi_soundfonts.getSoundFontPath` in dev, like paramidi_starter.

## 5. Assets and licensing

- LPC character layers come straight from the generator repo's `spritesheets/` tree (raw GitHub URLs, verified 200 on 2026-09-04) and are composited with ImageMagick in `tools/fetch_assets.sh`. Layer order: body → legs → torso → head → hair (→ hat).
- Enemies: `body/bodies/skeleton/walk.png`, `body/bodies/zombie/walk/zombie.png`; Mudman/Ghost are ImageMagick tints of the zombie sheet. Bat from "LPC Base Assets" zip (`sprites/monsters/bat.png`, 96×128 = 3×4 frames of 32×32). Grass from the same zip (`tiles/grass.png`).
- Bosses: `koalio.png` (paranim_examples, public domain, 5 frames of 18×26) and `player_walk1..3.png` from `/home/pdp/Projects/parakeet/src/assets` (70×100).
- Font: `Roboto-Regular.ttf` from paranim examples (Apache 2.0).
- LPC art is CC-BY-SA 3.0 / GPL 3.0 / OGA-BY 3.0. `src/assets/CREDITS.md` must list the authors of every used layer (the generator's `CREDITS.csv` rows for those paths) plus the LPC Base Assets `CREDITS.TXT`, and the game's title screen shows "Art: Liberated Pixel Cup contributors — see CREDITS.md". Code is MIT; the composed PNGs are CC-BY-SA 3.0.

## 6. Numbers (initial balance; tune freely)

- Player base speed 160 px/s. Enemy speeds: bat 90, zombie 55, skeleton 70, mudman 45, ghost 80, parakeet 100, koalio 60, reaper 200.
- Enemy hp (× `1 + minute*0.12`): bat 1, zombie 3, skeleton 8, mudman 15, ghost 20, parakeet 150, koalio 400, reaper 65535. Contact damage: 3/4/5/6/6/12/15/999 per second.
- XP to next level: `5 + 10*(level-1)` up to level 20, then +13 per level, then +16 after 40 (VS curve).
- Gem values: 1 (blue) for bat/zombie, 3 (green) for skeleton/mudman/ghost, 5 (red) bosses give a chest instead.
- Drops: chicken 1.5 %, coin 2.5 %. Vacuum 0.5 %. Pickup radius 24 px, base magnet 48 px.
- Level-up: 3 options; a new weapon/passive can appear only if a slot is free; owned items appear as upgrades until max level.
- Weapon table (base cooldown s / damage / amount / notes) and per-level upgrades are defined in `data.nim` in the plan.
- Waves: see `data.waves` in the plan (minute → kinds, interval, min count); bosses at 3, 8, 12, 15, 20, 25 min; Reaper at 30.

## 7. Testing strategy

- `nimble test` runs `tests/test_*.nim` headless: fresh session per test via `newSession()`, drive with `insert`/`fireRules`, assert via `query`/`queryAll`.
- Rules tests: game time advances only when DeltaTime inserted; player moves on keys; enemies approach player; cooldown spawns projectiles; level-up flips phase and creates 3 choices; death flips phase.
- Systems tests: spatial hash finds hits; pierce and HitIds prevent double hits; contact damage respects armor; pickups collected within radius; choice generation respects slots and max levels; xp curve values.
- Data tests: every weapon has 8 levels, every passive 5, wave table covers minutes 0..30.
- Manual: run 30 minutes with `-d:fastclock` (game clock ×10) and watch frame time stay under 16 ms with 300 enemies.

## 8. Decisions already made (don't re-litigate)

- Plain int ids + `Id` enum for constants (pararules README style), not `distinct int`.
- Per-entity facts for enemies/projectiles/pickups (simplicity showcase) with plain-Nim systems for N×M; enemy cap 300 keeps it comfortably under budget on a native build.
- Generated audio via paramidi instead of shipping WAV/OGG files.
- Colored quads for projectiles/pickups; sprites only for characters/enemies/bosses/ground.
- No paravim dev dependency (Nim 2.2 compatibility risk and not needed).
