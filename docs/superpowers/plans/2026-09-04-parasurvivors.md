# Parasurvivors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable Vampire Survivors demo clone (one stage, 4 characters, 7 weapons, 7 passives, waves, bosses, level-ups, 30-minute Reaper) on the paranim stack, with all state in pararules.

**Architecture:** `rules.nim` holds the pararules schema, rules and session helpers with no OpenGL dependency. `systems.nim` holds pure procs for N×M work (collision, pickups, attack plans, choices). `core.nim` glues input → rules → systems → `render.nim` each tick. `audio.nim` generates every sound with paramidi at startup and plays it through parasound.

**Tech Stack:** Nim 2.2, paranim 0.12, pararules 1.4, stb_image 2.5, paratext 0.13, parasound 1.0, paramidi 0.7, paramidi_soundfonts 0.2, GLFW/OpenGL 3.3, ImageMagick 7 (asset script only).

Spec: `docs/superpowers/specs/2026-09-04-parasurvivors-design.md` — read it first.

## Global Constraints

- Nim `>= 2.0.0`; verified locally with Nim 2.2.10. Use `--gc:orc` (Nim 2 default).
- `rules.nim`, `data.nim`, `systems.nim` must never import `paranim/*`, `paratext`, `parasound`, `paramidi` — tests run headless.
- Every mutating rule marks every `what` tuple except its single trigger with `then = false`. Never insert a fact a rule reads without `then = false` from inside that rule's `then`.
- Never retract facts inside a rule's `then` block; retraction happens in `stepSystems` (core-level).
- Never call `session.query(rules.getPlayer)` unless Phase is `Running`, `LevelUp`, `Paused` or `GameOver` (Player facts don't exist before `startRun`).
- Entity ids come only from `allocId()`. Never allocate ids from a fact value.
- Enemy cap `maxEnemies = 300`, pickup cap `maxPickups = 400`.
- Commit after every task with the message given in the task. Add the trailer lines:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019VGNJYtoUzydpJzfWTW15h
  ```
- Art credit: `src/assets/CREDITS.md` must exist and the title screen must show "Art: Liberated Pixel Cup contributors (CC-BY-SA 3.0), see CREDITS.md".
- Do not add paravim or emscripten support.

## Verified library facts (from installed sources on 2026-09-04)

- pararules `schema Fact(Id, Attr)` generates `insert(session, id: Id or int, attr: Attr, value)`, `retract(session, id: Id or int, attr: Attr)`, `contains(session, id, attr)`. A bound `id` in a rule is `int`; compare to `Player.ord`.
- `let (initSession, rules) = staticRuleset(Fact, FactMatch): ...` then `var s = initSession(autoFire = false); for r in rules.fields: s.add(r)`.
- `session.query(rules.r)` → one named tuple (raises if no match). `session.queryAll(rules.r)` → `seq` of named tuples. `session.query(rules.r, id = 5)` filters by binding.
- Single-binding queries destructure as `let (phase) = session.query(rules.getPhase)`.
- `fireRules` raises after 16 recursive passes.
- paranim: `initImageEntity(data, w, h): UncompiledImageEntity`; `initInstancedEntity(uncompiled): UncompiledInstancedImageEntity`; `compile(game, uncompiled)`; `add(instanced, uncompiledImage)`; `crop(e, x, y, w, h)` in source-pixel units; `project`, `invert(camera)`, `translate`, `scale`, `rotate`, `color`. Attribute data are `ref seq[GLfloat]`, `instanceCount` is public, `render` re-uploads attributes whose `disable == false` and recomputes `instanceCount` from data length.
- `initTwoDEntity(primitives.rectangle[GLfloat]())` gives a unit quad from (0,0) to (1,1). Matrix ops are applied in call order to the unit quad: translate then rotate then scale means "scale first, then rotate, then translate" in world terms.
- 2D y axis points down (super_koalio gravity is positive y).
- paratext: `initFont(ttf, fontHeight, firstChar, bitmapWidth, bitmapHeight, charCount)`, `initTextEntity(font)`, `initInstancedEntity(textEntity)`, `e.crop(bakedChar, x, font.baseline)`, `font.chars[int(ch) - font.firstChar].xadvance`.
- parasound miniaudio bindings: `ma_engine_size/init/uninit`, `ma_decoder_size/init_memory`, `ma_sound_size/init_from_data_source/start/stop/uninit`. `ma_sound_seek_to_pcm_frame`, `ma_sound_set_looping`, `ma_sound_set_volume` are NOT bound; declare them locally (symbols exist in the compiled `miniaudio.c`).
- paramidi: `compile(scoreTuple): seq[Event]`, `render[cshort](events, sf, sampleRate).data: seq[cshort]`, `tsf_load_filename`, `tsf_load_memory`, `tsf_set_output(sf, TSF_MONO, rate, 0)`, `tsf_close`. Instruments include `piano, glockenspiel, marimba, xylophone, tubular_bells, timpani, orchestra_hit, synth_bass_1, choir_aahs`.
- GLFW key codes: Left 263, Right 262, Down 264, Up 265, Enter 257, Escape 256, Space 32, A 65, D 68, P 80, R 82, S 83, W 87, `1` 49, `2` 50, `3` 51.
- LPC walk sheets: 576×256, 64×64 frames, rows Up/Left/Down/Right, 9 columns, column 0 = standing.
- Verified LPC layer URLs (all HTTP 200) are listed in Task 8.

## File Structure

```
parasurvivors.nimble          package + test task
config.nims                   release flags, linux linker flags for miniaudio
.gitignore
src/parasurvivors.nim         GLFW window, callbacks, main loop
src/core.nim                  Game type, init, tick (phase machine), input procs
src/rules.nim                 Id/Attr, schema, rules, session, entity helpers, startRun, stepSystems
src/data.nim                  enums, defs tables, curves, key codes, constants
src/systems.nim               pure procs: grid, collide, contactDamage, scanPickups, nearestEnemy,
                              offscreenPoint, tooFar, attackPlan, generateChoices, separate
src/render.nim                sheets, shapes, ground, text, drawFrame
src/audio.nim                 paramidi → wav → miniaudio
src/assets/*.png, Roboto-Regular.ttf, CREDITS.md, CREDITS-lpc.csv, CREDITS-lpc-base.txt
tools/fetch_assets.sh         builds src/assets
tests/config.nims
tests/test_data.nim
tests/test_systems.nim
tests/test_rules.nim
```

---

### Task 1: Project skeleton that opens a window

**Files:**
- Create: `parasurvivors.nimble`, `config.nims`, `.gitignore`, `src/parasurvivors.nim`, `src/core.nim`, `tests/config.nims`, `tests/test_data.nim`

**Interfaces:**
- Produces: `core.Game` (`object of RootGame` with `deltaTime`, `totalTime`), `core.init(game: var Game)`, `core.tick(game: var Game)`, `core.onKeyPress/onKeyRelease(key: int)`, `core.onWindowResize(windowWidth, windowHeight, worldWidth, worldHeight: int)`.

- [ ] **Step 1: Write the nimble file**

`parasurvivors.nimble`:
```nim
# Package

version       = "0.1.0"
author        = "Patrick"
description   = "A Vampire Survivors demo clone on the paranim stack"
license       = "MIT"
srcDir        = "src"
bin           = @["parasurvivors"]

# Dependencies

requires "nim >= 2.0.0"
requires "paranim >= 0.12.0"
requires "pararules >= 1.4.0"
requires "stb_image >= 2.5"
requires "paratext >= 0.13.0"
requires "parasound >= 1.0.0"
requires "paramidi >= 0.7.0"
requires "paramidi_soundfonts >= 0.2.0"

task test, "Run headless tests":
  for t in ["test_data", "test_systems", "test_rules"]:
    exec "nim c -r --hints:off --outdir:tmp tests/" & t & ".nim"

task assets, "Download and compose art assets":
  exec "bash tools/fetch_assets.sh"
```

- [ ] **Step 2: Write config.nims and .gitignore**

`config.nims`:
```nim
when defined(release):
  --app:gui

--gc:orc

when defined(linux) and not defined(noaudio):
  # miniaudio needs these (see parasound/config.nims)
  switch("passL", "-ldl -lm -lpthread")
```

`tests/config.nims`:
```nim
switch("path", "../src")
switch("gc", "orc")
switch("define", "noaudio")
switch("hints", "off")
```

`.gitignore`:
```
tmp/
nimcache/
parasurvivors
output.wav
*.exe
```

- [ ] **Step 3: Write the GLFW entry point (adapted from `/home/pdp/Projects/paratry/src/paratry.nim`)**

`src/parasurvivors.nim`:
```nim
import paranim/glfw
import core

proc keyCallback(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32) {.cdecl.} =
  if action == GLFW_PRESS:
    onKeyPress(key)
  elif action == GLFW_RELEASE:
    onKeyRelease(key)

var density: int

proc frameSizeCallback(window: GLFWWindow, width: int32, height: int32) {.cdecl.} =
  onWindowResize(width, height, int(width / density), int(height / density))

var
  game: Game
  window: GLFWWindow

proc mainLoop() =
  let ts = glfwGetTime()
  game.deltaTime = min(ts - game.totalTime, 0.1) # never simulate a huge step after a stall
  game.totalTime = ts
  game.tick()
  window.swapBuffers()
  glfwPollEvents()

when isMainModule:
  doAssert glfwInit()

  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE) # Used for Mac
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)

  window = glfwCreateWindow(1024, 768, "Parasurvivors")
  if window == nil:
    quit(-1)

  window.makeContextCurrent()
  glfwSwapInterval(1)

  discard window.setKeyCallback(keyCallback)
  discard window.setFramebufferSizeCallback(frameSizeCallback)

  var width, height: int32
  window.getFramebufferSize(width.addr, height.addr)

  var windowWidth, windowHeight: int32
  window.getWindowSize(windowWidth.addr, windowHeight.addr)

  density = max(1, int(width / windowWidth))
  window.frameSizeCallback(width, height)

  game.init()
  game.totalTime = glfwGetTime()

  while not window.windowShouldClose:
    mainLoop()

  window.destroyWindow()
  glfwTerminate()
```

- [ ] **Step 4: Write a stub core that clears the screen**

`src/core.nim` (temporary; replaced in Task 9/10):
```nim
import paranim/opengl
import paranim/gl

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float

var
  windowW = 1024
  windowH = 768

proc onKeyPress*(key: int) = discard
proc onKeyRelease*(key: int) = discard

proc onWindowResize*(windowWidth, windowHeight, worldWidth, worldHeight: int) =
  if windowWidth == 0 or windowHeight == 0:
    return
  windowW = windowWidth
  windowH = windowHeight

proc init*(game: var Game) =
  doAssert glInit()
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

proc tick*(game: var Game) =
  glClearColor(0.16, 0.22, 0.12, 1f)
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowW), int32(windowH))
```

- [ ] **Step 5: Write a placeholder test so `nimble test` has something to run**

`tests/test_data.nim`:
```nim
import unittest

suite "data":
  test "placeholder":
    check true
```

- [ ] **Step 6: Install deps and build**

Run: `cd /home/pdp/Projects/parasurvivors && nimble install -d -y && nimble build`
Expected: dependencies resolve (paratext, parasound, paramidi, paramidi_soundfonts are fetched from GitHub) and `parasurvivors` binary appears. If `paramidi_soundfonts` install is slow, that is normal (it ships a .sf2).

Run: `timeout 5 ./parasurvivors; echo exit=$?`
Expected: a dark green window for 5 seconds, exit=124 (killed by timeout). No crash.

Run: `nimble test`
Expected: `[OK] placeholder`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: project skeleton with GLFW window and test task"
```

---

### Task 2: Data tables

**Files:**
- Create: `src/data.nim`
- Modify: `tests/test_data.nim`

**Interfaces:**
- Produces: every enum, `Stats`, `characterDefs`, `weaponDefs`, `weaponUpgrades`, `weaponAt(kind, level): WeaponDef`, `passiveDefs`, `computeStats(hero, passives): Stats`, `maxHpFor(hero, passives): float`, `enemyDefs`, `hpScale(minute)`, `waves`, `waveFor(minute): Wave`, `bosses`, `xpForLevel(level): int`, `gemValue(kind): int`, `clockText(secs): string`, key code constants, tuning constants.

- [ ] **Step 1: Write failing tests**

Replace `tests/test_data.nim`:
```nim
import unittest
import data

suite "data":
  test "xp curve matches VS shape":
    check xpForLevel(1) == 5
    check xpForLevel(2) == 15
    check xpForLevel(19) == 185
    check xpForLevel(20) == 195
    check xpForLevel(21) == 208
    check xpForLevel(40) == 455
    check xpForLevel(41) == 471

  test "every weapon has upgrades for levels 2..8 and grows":
    for k in WeaponKind:
      let base = weaponAt(k, 1)
      let top = weaponAt(k, maxWeaponLevel)
      check top.damage + float(top.amount) + top.size + top.speed + top.ttl > base.damage + float(base.amount) + base.size + base.speed + base.ttl
      for lvl in 2 .. maxWeaponLevel:
        check weaponUpgrades[k][lvl].text.len > 0

  test "weaponAt is cumulative":
    check weaponAt(Whip, 2).amount == 2
    check weaponAt(Whip, 3).damage == 15.0
    check weaponAt(MagicWand, 3).cooldown < weaponAt(MagicWand, 1).cooldown

  test "passives change stats":
    let none = computeStats(Otto, [])
    check none.might == 1.1
    let spinach = computeStats(Otto, [(Spinach, 2)])
    check abs(spinach.might - 1.3) < 1e-9
    let tome = computeStats(Imma, [(EmptyTome, 1)])
    check tome.cooldownMul < computeStats(Imma, []).cooldownMul
    check maxHpFor(Otto, [(HollowHeart, 1)]) == 144.0

  test "waves cover the whole run":
    check waveFor(0).minute == 0
    check waveFor(2).minute == 1
    check waveFor(31).minute == 30
    for w in waves:
      check w.kinds.len > 0
      check w.interval > 0

  test "bosses are unique per minute and kind":
    var seen: seq[(int, EnemyKind)]
    for b in bosses:
      check (b.minute, b.kind) notin seen
      seen.add (b.minute, b.kind)

  test "clock text":
    check clockText(0) == "00:00"
    check clockText(65) == "01:05"
    check clockText(1800) == "30:00"
```

- [ ] **Step 2: Run to verify failure**

Run: `nimble test`
Expected: compile error `cannot open file: data`.

- [ ] **Step 3: Write data.nim**

`src/data.nim`:
```nim
## Pure data: enums, definition tables, curves, constants. No engine imports.

import strutils

type
  CharacterKind* = enum
    Otto, Imma, Lina, Gino
  WeaponKind* = enum
    Whip, MagicWand, Knife, Axe, Runetracer, Garlic, KingBible
  PassiveKind* = enum
    Spinach, Armor, HollowHeart, Pummarola, EmptyTome, Wings, Attractorb
  EnemyKind* = enum
    Bat, Zombie, Skeleton, Mudman, Ghost, Parakeet, Koalio, Reaper
  PickupKind* = enum
    GemBlue, GemGreen, GemRed, Chicken, Coin, Chest, Vacuum
  Dir* = enum
    Up, Left, Down, Right ## LPC sheet row order

  Stats* = object
    might*, armor*, regen*, cooldownMul*, speedMul*, magnet*, area*, projSpeed*, duration*: float
    amount*: int

  CharacterDef* = object
    name*, perk*, sheet*: string
    weapon*: WeaponKind
    maxHp*: float
    base*: Stats

  WeaponDef* = object
    name*, desc*: string
    cooldown*, damage*, speed*, ttl*, size*: float
    amount*, pierce*: int

  WeaponUpgrade* = object ## additive deltas applied when reaching that level
    damage*, cooldown*, size*, speed*, ttl*: float
    amount*, pierce*: int
    text*: string

  PassiveDef* = object
    name*, desc*: string

  EnemyDef* = object
    hp*, speed*, damage*, size*: float
    gem*: PickupKind
    sheet*: string
    boss*: bool

  Wave* = object
    minute*: int
    kinds*: seq[EnemyKind]
    interval*: float
    minCount*: int

  BossSpawn* = object
    minute*: int
    kind*: EnemyKind
    count*: int

const
  maxWeaponLevel* = 8
  maxPassiveLevel* = 5
  maxWeaponSlots* = 6
  maxPassiveSlots* = 6
  maxEnemies* = 300
  maxPickups* = 400
  runLengthSecs* = 30 * 60
  zoom* = 1.0 ## world units per screen pixel
  playerBaseSpeed* = 160.0
  playerRadius* = 14.0
  pickupRadius* = 24.0
  baseMagnet* = 48.0
  gemFlySpeed* = 420.0
  axeGravity* = 900.0
  bibleOrbitRadius* = 90.0
  chickenHeal* = 30.0
  coinValue* = 10
  chestGoldFallback* = 50
  chickenChance* = 0.015
  coinChance* = 0.025
  vacuumChance* = 0.005
  hitFlashSecs* = 0.12
  despawnMargin* = 400.0
  spawnMargin* = 80.0
  clockScale* = when defined(fastclock): 10.0 else: 1.0

  # GLFW key codes (kept here so rules.nim stays free of glfw)
  KeyLeft* = 263
  KeyRight* = 262
  KeyDown* = 264
  KeyUp* = 265
  KeyEnter* = 257
  KeyEscape* = 256
  KeySpace* = 32
  KeyA* = 65
  KeyD* = 68
  KeyP* = 80
  KeyR* = 82
  KeyS* = 83
  KeyW* = 87
  Key1* = 49
  Key2* = 50
  Key3* = 51

  defaultStats* = Stats(might: 1.0, armor: 0.0, regen: 0.0, cooldownMul: 1.0, speedMul: 1.0,
                        magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)

  characterDefs*: array[CharacterKind, CharacterDef] = [
    Otto: CharacterDef(name: "Otto", perk: "+10% Might", sheet: "otto", weapon: Whip, maxHp: 120,
      base: Stats(might: 1.1, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Imma: CharacterDef(name: "Imma", perk: "-10% Cooldown", sheet: "imma", weapon: MagicWand, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 0.9, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Lina: CharacterDef(name: "Lina", perk: "+20% Projectile speed", sheet: "lina", weapon: Runetracer, maxHp: 90,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.2, duration: 1.0, amount: 0)),
    Gino: CharacterDef(name: "Gino", perk: "+1 Projectile", sheet: "gino", weapon: Knife, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 1)),
  ]

  weaponDefs*: array[WeaponKind, WeaponDef] = [
    Whip: WeaponDef(name: "Whip", desc: "Attacks horizontally, passes through enemies",
      cooldown: 1.35, damage: 10, speed: 0, ttl: 0.15, size: 120, amount: 1, pierce: 999),
    MagicWand: WeaponDef(name: "Magic Wand", desc: "Fires at the nearest enemy",
      cooldown: 1.2, damage: 10, speed: 300, ttl: 2.5, size: 10, amount: 1, pierce: 0),
    Knife: WeaponDef(name: "Knife", desc: "Flies quickly in the faced direction",
      cooldown: 1.0, damage: 6.5, speed: 450, ttl: 1.5, size: 8, amount: 1, pierce: 1),
    Axe: WeaponDef(name: "Axe", desc: "High damage, arcs overhead",
      cooldown: 4.0, damage: 20, speed: 300, ttl: 2.5, size: 20, amount: 1, pierce: 3),
    Runetracer: WeaponDef(name: "Runetracer", desc: "Bounces around, passes through enemies",
      cooldown: 3.0, damage: 10, speed: 250, ttl: 4.0, size: 10, amount: 1, pierce: 999),
    Garlic: WeaponDef(name: "Garlic", desc: "Damages nearby enemies",
      cooldown: 1.3, damage: 5, speed: 0, ttl: 0.05, size: 80, amount: 1, pierce: 999),
    KingBible: WeaponDef(name: "King Bible", desc: "Orbits around the character",
      cooldown: 3.0, damage: 10, speed: 2.5, ttl: 3.0, size: 14, amount: 1, pierce: 999),
  ]

  weaponUpgrades*: array[WeaponKind, array[2 .. maxWeaponLevel, WeaponUpgrade]] = [
    Whip: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      4: WeaponUpgrade(damage: 5, size: 10, text: "Damage +5, area +10%"),
      5: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      6: WeaponUpgrade(damage: 5, size: 10, text: "Damage +5, area +10%"),
      7: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      8: WeaponUpgrade(damage: 5, text: "Base damage up by 5")],
    MagicWand: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(cooldown: -0.2, text: "Cooldown reduced by 0.2s"),
      4: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      5: WeaponUpgrade(damage: 10, text: "Base damage up by 10"),
      6: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      7: WeaponUpgrade(pierce: 1, text: "Passes through 1 more enemy"),
      8: WeaponUpgrade(damage: 10, text: "Base damage up by 10")],
    Knife: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      4: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(pierce: 1, text: "Passes through 1 more enemy"),
      7: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      8: WeaponUpgrade(damage: 5, text: "Base damage up by 5")],
    Axe: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(damage: 20, text: "Base damage up by 20"),
      4: WeaponUpgrade(pierce: 2, text: "Passes through 2 more enemies"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(damage: 20, text: "Base damage up by 20"),
      7: WeaponUpgrade(pierce: 2, text: "Passes through 2 more enemies"),
      8: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile")],
    Runetracer: [
      2: WeaponUpgrade(speed: 50, damage: 5, text: "Speed +50, damage +5"),
      3: WeaponUpgrade(ttl: 0.3, text: "Lasts 0.3s longer"),
      4: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      5: WeaponUpgrade(speed: 50, damage: 5, text: "Speed +50, damage +5"),
      6: WeaponUpgrade(ttl: 0.3, text: "Lasts 0.3s longer"),
      7: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      8: WeaponUpgrade(damage: 5, ttl: 0.5, text: "Damage +5, lasts 0.5s longer")],
    Garlic: [
      2: WeaponUpgrade(size: 20, damage: 2, text: "Area +20, damage +2"),
      3: WeaponUpgrade(cooldown: -0.1, damage: 1, text: "Faster pulse, damage +1"),
      4: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1"),
      5: WeaponUpgrade(cooldown: -0.1, damage: 2, text: "Faster pulse, damage +2"),
      6: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1"),
      7: WeaponUpgrade(cooldown: -0.1, damage: 1, text: "Faster pulse, damage +1"),
      8: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1")],
    KingBible: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(speed: 0.3, size: 3, text: "Spins faster, bigger"),
      4: WeaponUpgrade(ttl: 0.5, text: "Lasts 0.5s longer"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(speed: 0.3, size: 3, text: "Spins faster, bigger"),
      7: WeaponUpgrade(ttl: 0.5, text: "Lasts 0.5s longer"),
      8: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile")],
  ]

  passiveDefs*: array[PassiveKind, PassiveDef] = [
    Spinach: PassiveDef(name: "Spinach", desc: "+10% damage per level"),
    Armor: PassiveDef(name: "Armor", desc: "-1 incoming damage per level"),
    HollowHeart: PassiveDef(name: "Hollow Heart", desc: "+20% max health per level"),
    Pummarola: PassiveDef(name: "Pummarola", desc: "+0.2 HP/s regen per level"),
    EmptyTome: PassiveDef(name: "Empty Tome", desc: "-8% cooldown per level"),
    Wings: PassiveDef(name: "Wings", desc: "+10% move speed per level"),
    Attractorb: PassiveDef(name: "Attractorb", desc: "+50% pickup range per level"),
  ]

  enemyDefs*: array[EnemyKind, EnemyDef] = [
    Bat: EnemyDef(hp: 1, speed: 90, damage: 3, size: 32, gem: GemBlue, sheet: "bat", boss: false),
    Zombie: EnemyDef(hp: 3, speed: 55, damage: 4, size: 64, gem: GemBlue, sheet: "zombie", boss: false),
    Skeleton: EnemyDef(hp: 8, speed: 70, damage: 5, size: 64, gem: GemGreen, sheet: "skeleton", boss: false),
    Mudman: EnemyDef(hp: 15, speed: 45, damage: 6, size: 64, gem: GemGreen, sheet: "mudman", boss: false),
    Ghost: EnemyDef(hp: 20, speed: 80, damage: 6, size: 64, gem: GemGreen, sheet: "ghost", boss: false),
    Parakeet: EnemyDef(hp: 150, speed: 100, damage: 12, size: 150, gem: GemRed, sheet: "parakeet", boss: true),
    Koalio: EnemyDef(hp: 400, speed: 60, damage: 15, size: 104, gem: GemRed, sheet: "koalio", boss: true),
    Reaper: EnemyDef(hp: 65535, speed: 200, damage: 999, size: 192, gem: GemRed, sheet: "reaper", boss: true),
  ]

  waves*: seq[Wave] = @[
    Wave(minute: 0, kinds: @[Bat], interval: 1.0, minCount: 10),
    Wave(minute: 1, kinds: @[Bat, Zombie], interval: 0.8, minCount: 20),
    Wave(minute: 3, kinds: @[Skeleton, Bat], interval: 0.6, minCount: 30),
    Wave(minute: 5, kinds: @[Zombie, Mudman], interval: 0.5, minCount: 40),
    Wave(minute: 8, kinds: @[Bat, Skeleton], interval: 0.4, minCount: 60),
    Wave(minute: 12, kinds: @[Ghost, Mudman], interval: 0.35, minCount: 80),
    Wave(minute: 16, kinds: @[Skeleton, Ghost, Bat], interval: 0.3, minCount: 100),
    Wave(minute: 20, kinds: @[Zombie, Skeleton, Mudman, Ghost], interval: 0.25, minCount: 140),
    Wave(minute: 25, kinds: @[Mudman, Ghost, Skeleton, Bat], interval: 0.2, minCount: 200),
    Wave(minute: 30, kinds: @[Ghost, Bat], interval: 0.2, minCount: 200),
  ]

  bosses*: seq[BossSpawn] = @[
    BossSpawn(minute: 3, kind: Parakeet, count: 1),
    BossSpawn(minute: 8, kind: Koalio, count: 1),
    BossSpawn(minute: 12, kind: Parakeet, count: 2),
    BossSpawn(minute: 15, kind: Koalio, count: 1),
    BossSpawn(minute: 20, kind: Parakeet, count: 2),
    BossSpawn(minute: 25, kind: Koalio, count: 2),
    BossSpawn(minute: 30, kind: Reaper, count: 1),
  ]

proc weaponAt*(kind: WeaponKind, level: int): WeaponDef =
  ## Base definition plus every upgrade from level 2 up to `level`.
  result = weaponDefs[kind]
  for lvl in 2 .. min(level, maxWeaponLevel):
    let u = weaponUpgrades[kind][lvl]
    result.damage += u.damage
    result.cooldown += u.cooldown
    result.size += u.size
    result.speed += u.speed
    result.ttl += u.ttl
    result.amount += u.amount
    result.pierce += u.pierce

proc computeStats*(hero: CharacterKind, passives: openArray[(PassiveKind, int)]): Stats =
  result = characterDefs[hero].base
  for (kind, level) in passives:
    let l = float(level)
    case kind
    of Spinach: result.might += 0.1 * l
    of Armor: result.armor += 1.0 * l
    of HollowHeart: discard # handled by maxHpFor
    of Pummarola: result.regen += 0.2 * l
    of EmptyTome: result.cooldownMul *= (1.0 - 0.08 * l)
    of Wings: result.speedMul += 0.1 * l
    of Attractorb: result.magnet += 0.5 * l

proc maxHpFor*(hero: CharacterKind, passives: openArray[(PassiveKind, int)]): float =
  result = characterDefs[hero].maxHp
  for (kind, level) in passives:
    if kind == HollowHeart:
      result *= 1.0 + 0.2 * float(level)

proc hpScale*(minute: int): float =
  1.0 + 0.12 * float(minute)

proc waveFor*(minute: int): Wave =
  result = waves[0]
  for w in waves:
    if w.minute <= minute:
      result = w

proc xpForLevel*(level: int): int =
  ## XP needed to go from `level` to `level + 1` (Vampire Survivors curve).
  if level < 20:
    5 + 10 * (level - 1)
  elif level < 40:
    5 + 10 * 19 + 13 * (level - 20)
  else:
    5 + 10 * 19 + 13 * 20 + 16 * (level - 40)

proc gemValue*(kind: PickupKind): int =
  case kind
  of GemBlue: 1
  of GemGreen: 3
  of GemRed: 5
  else: 0

proc isGem*(kind: PickupKind): bool =
  kind in {GemBlue, GemGreen, GemRed}

proc clockText*(secs: float): string =
  let total = int(secs)
  align($(total div 60), 2, '0') & ":" & align($(total mod 60), 2, '0')
```

- [ ] **Step 4: Run tests**

Run: `nimble test`
Expected: all 7 `data` tests `[OK]`.

- [ ] **Step 5: Commit**

```bash
git add src/data.nim tests/test_data.nim
git commit -m "feat: data tables for characters, weapons, passives, enemies, waves"
```

---

### Task 3: Pure systems

**Files:**
- Create: `src/systems.nim`, `tests/test_systems.nim`

**Interfaces:**
- Consumes: `data`.
- Produces: `Hit`, `ProjSpec`, `ChoiceKind`, `Choice`, `PickupResult`, `dist`, `enemyRadius`, `collide[P, E](projs, enemies): seq[Hit]`, `contactDamage[E](enemies, px, py, armor, dt): float`, `scanPickups[P](pickups, px, py, magnet): PickupResult`, `nearestEnemy[E](enemies, px, py)`, `offscreenPoint(px, py, ww, wh)`, `tooFar(ex, ey, px, py, ww, wh)`, `facingVec(Dir)`, `attackPlan(...)`, `generateChoices(...)`, `separate[E](enemies): seq[(int, float, float)]`.
- Generic procs duck-type on fields: enemies need `id, kind, x, y, hp, damage, size`; projectiles need `id, kind, x, y, size, damage, pierce, hitIds, ttl`; pickups need `id, kind, x, y, magnetized`.

- [ ] **Step 1: Write failing tests**

`tests/test_systems.nim`:
```nim
import unittest, sets, math, random
import data, systems

type
  E = tuple[id: int, kind: EnemyKind, x, y, hp, damage, size: float]
  P = tuple[id: int, kind: WeaponKind, x, y, size, damage: float, pierce: int, hitIds: HashSet[int], ttl: float]
  K = tuple[id: int, kind: PickupKind, x, y: float, magnetized: bool]

proc enemy(id: int, x, y: float, kind = Bat): E =
  (id, kind, x, y, enemyDefs[kind].hp, enemyDefs[kind].damage, enemyDefs[kind].size)

proc proj(id: int, x, y: float, kind = MagicWand, pierce = 0, size = 10.0): P =
  (id, kind, x, y, size, 10.0, pierce, initHashSet[int](), 1.0)

suite "systems":
  test "collide hits overlapping enemy only":
    let hits = collide([proj(1, 0, 0)], [enemy(10, 5, 5), enemy(11, 500, 500)])
    check hits.len == 1
    check hits[0].enemyId == 10
    check hits[0].projId == 1
    check hits[0].damage == 10.0

  test "pierce limits hits per tick and hitIds are respected":
    let es = [enemy(10, 0, 0), enemy(11, 4, 0), enemy(12, -4, 0)]
    check collide([proj(1, 0, 0, pierce = 0)], es).len == 1
    check collide([proj(1, 0, 0, pierce = 1)], es).len == 2
    var p = proj(1, 0, 0, pierce = 1)
    p.hitIds.incl 10
    let hits = collide([p], es)
    check hits.len == 1
    check hits[0].enemyId != 10

  test "whip uses a wide horizontal box":
    let hits = collide([proj(1, 0, 0, kind = Whip, pierce = 999, size = 120)], [enemy(10, 50, 0), enemy(11, 0, 80)])
    check hits.len == 1
    check hits[0].enemyId == 10

  test "expired projectiles never hit":
    var p = proj(1, 0, 0)
    p.ttl = 0
    check collide([p], [enemy(10, 0, 0)]).len == 0

  test "contact damage respects armor with a floor of 1":
    let es = [enemy(10, 0, 0, Zombie)] # damage 4
    check abs(contactDamage(es, 0, 0, 0.0, 1.0) - 4.0) < 1e-9
    check abs(contactDamage(es, 0, 0, 3.0, 1.0) - 1.0) < 1e-9
    check abs(contactDamage(es, 0, 0, 10.0, 1.0) - 1.0) < 1e-9
    check contactDamage(es, 500, 500, 0.0, 1.0) == 0.0

  test "pickups: collect within radius, magnetize gems within magnet":
    let ks: seq[K] = @[(1, GemBlue, 5.0, 0.0, false), (2, GemBlue, 40.0, 0.0, false), (3, Chicken, 40.0, 0.0, false), (4, GemRed, 900.0, 0.0, false)]
    let r = scanPickups(ks, 0, 0, 60.0)
    check r.collected == @[0]
    check r.magnetize == @[1]

  test "nearest enemy":
    let n = nearestEnemy([enemy(10, 100, 0), enemy(11, 30, 40)], 0, 0)
    check n.found
    check n.x == 30.0
    check nearestEnemy(newSeq[E](), 0, 0).found == false

  test "offscreen points are outside the view":
    randomize(1)
    for i in 0 ..< 200:
      let (x, y) = offscreenPoint(0, 0, 1000, 600)
      check abs(x) >= 500 or abs(y) >= 300
      check tooFar(x, y, 0, 0, 1000, 600) == false

  test "attack plans":
    let st = defaultStats
    check attackPlan(Whip, 1, st, 0, 0, Right, false, 0, 0).len == 1
    check attackPlan(Whip, 2, st, 0, 0, Right, false, 0, 0).len == 2
    let wand = attackPlan(MagicWand, 1, st, 0, 0, Down, true, 100, 0)
    check wand.len == 1
    check wand[0].vx > 0 and abs(wand[0].vy) < 1e-6
    let knife = attackPlan(Knife, 1, st, 0, 0, Up, false, 0, 0)
    check knife[0].vy < 0
    let bible = attackPlan(KingBible, 2, st, 0, 0, Up, false, 0, 0)
    check bible.len == 2
    check abs(bible[1].angle - PI) < 1e-9
    var strong = defaultStats
    strong.might = 2.0
    strong.amount = 1
    let plan = attackPlan(Knife, 1, strong, 0, 0, Right, false, 0, 0)
    check plan.len == 2
    check plan[0].damage == 13.0

  test "choices respect slots and max levels":
    randomize(2)
    let c1 = generateChoices([(Whip, 1)], [])
    check c1.len == 3
    let maxed = generateChoices([(Whip, maxWeaponLevel), (Knife, maxWeaponLevel), (Axe, maxWeaponLevel), (Garlic, maxWeaponLevel), (MagicWand, maxWeaponLevel), (Runetracer, maxWeaponLevel)],
                                [(Spinach, maxPassiveLevel), (Armor, maxPassiveLevel), (HollowHeart, maxPassiveLevel), (Pummarola, maxPassiveLevel), (EmptyTome, maxPassiveLevel), (Wings, maxPassiveLevel)])
    check maxed.len == 2
    check maxed[0].kind == BonusGold
    for i in 0 ..< 50:
      for c in generateChoices([(Whip, 3)], [(Spinach, 1)]):
        if c.kind == UpgradeWeapon: check c.level == 4
        if c.kind == UpgradePassive: check c.level == 2
        check c.title.len > 0

  test "separate pushes overlapping enemies apart":
    let moves = separate([enemy(10, 0, 0, Zombie), enemy(11, 5, 0, Zombie), enemy(12, 400, 0, Zombie)])
    check moves.len == 2
    for (id, dx, dy) in moves:
      if id == 10: check dx < 0
      if id == 11: check dx > 0
```

- [ ] **Step 2: Run to verify failure**

Run: `nimble test`
Expected: compile error `cannot open file: systems`.

- [ ] **Step 3: Write systems.nim**

`src/systems.nim`:
```nim
## Pure procs on plain seqs. Generic over tuple/object types so both the
## pararules query results and hand-built test tuples work.

import math, tables, sets, random, algorithm, sequtils
import data

const
  gridCell* = 64.0
  whipHalfHeight = 30.0

type
  Hit* = object
    projId*, enemyId*: int
    damage*: float
  ProjSpec* = object
    kind*: WeaponKind
    x*, y*, vx*, vy*, size*, damage*, ttl*, angle*: float
    pierce*: int
  ChoiceKind* = enum
    NewWeapon, UpgradeWeapon, NewPassive, UpgradePassive, BonusGold, BonusHeal
  Choice* = object
    kind*: ChoiceKind
    weapon*: WeaponKind
    passive*: PassiveKind
    level*: int ## resulting level
    title*, desc*: string
  PickupResult* = object
    collected*: seq[int] ## indices into the pickups array
    magnetize*: seq[int]

proc dist*(x1, y1, x2, y2: float): float =
  sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))

proc enemyRadius*(size: float): float =
  size * 0.35

proc cellOf(x, y: float): (int, int) =
  (int(floor(x / gridCell)), int(floor(y / gridCell)))

proc buildGrid*[E](enemies: openArray[E]): Table[(int, int), seq[int]] =
  for i, e in enemies:
    result.mgetOrPut(cellOf(e.x, e.y), @[]).add(i)

proc hitsEnemy[P, E](p: P, e: E): bool =
  if p.kind == Whip:
    abs(e.x - p.x) < p.size / 2 + enemyRadius(e.size) and
      abs(e.y - p.y) < whipHalfHeight + enemyRadius(e.size)
  else:
    dist(p.x, p.y, e.x, e.y) < p.size + enemyRadius(e.size)

proc collide*[P, E](projs: openArray[P], enemies: openArray[E]): seq[Hit] =
  ## Every (projectile, enemy) overlap this tick, honouring pierce and hitIds.
  if enemies.len == 0:
    return
  let grid = buildGrid(enemies)
  for p in projs:
    if p.ttl <= 0:
      continue
    var allowed = p.pierce + 1 - p.hitIds.len
    if allowed <= 0:
      continue
    let reach = p.size + 40.0
    let (c0x, c0y) = cellOf(p.x - reach, p.y - reach)
    let (c1x, c1y) = cellOf(p.x + reach, p.y + reach)
    block scan:
      for cx in c0x .. c1x:
        for cy in c0y .. c1y:
          if not grid.hasKey((cx, cy)):
            continue
          for idx in grid[(cx, cy)]:
            let e = enemies[idx]
            if p.hitIds.contains(e.id):
              continue
            if hitsEnemy(p, e):
              result.add Hit(projId: p.id, enemyId: e.id, damage: p.damage)
              dec allowed
              if allowed <= 0:
                break scan

proc contactDamage*[E](enemies: openArray[E], px, py, armor, dt: float): float =
  ## Damage per tick from every enemy touching the player.
  for e in enemies:
    if dist(e.x, e.y, px, py) < enemyRadius(e.size) + playerRadius:
      result += max(1.0, e.damage - armor) * dt

proc scanPickups*[P](pickups: openArray[P], px, py, magnet: float): PickupResult =
  for i, p in pickups:
    let d = dist(p.x, p.y, px, py)
    if d < pickupRadius:
      result.collected.add i
    elif p.kind.isGem and not p.magnetized and d < magnet:
      result.magnetize.add i

proc nearestEnemy*[E](enemies: openArray[E], px, py: float): tuple[found: bool, x, y: float] =
  var best = Inf
  for e in enemies:
    let d = dist(e.x, e.y, px, py)
    if d < best:
      best = d
      result = (true, e.x, e.y)

proc offscreenPoint*(px, py, ww, wh: float): (float, float) =
  ## Random point just outside the view rectangle centred on the player.
  let hw = ww / 2 + spawnMargin
  let hh = wh / 2 + spawnMargin
  case rand(3)
  of 0: (px - hw, py + rand(hh * 2) - hh)
  of 1: (px + hw, py + rand(hh * 2) - hh)
  of 2: (px + rand(hw * 2) - hw, py - hh)
  else: (px + rand(hw * 2) - hw, py + hh)

proc tooFar*(ex, ey, px, py, ww, wh: float): bool =
  abs(ex - px) > ww / 2 + despawnMargin or abs(ey - py) > wh / 2 + despawnMargin

proc facingVec*(d: Dir): (float, float) =
  case d
  of Up: (0.0, -1.0)
  of Down: (0.0, 1.0)
  of Left: (-1.0, 0.0)
  of Right: (1.0, 0.0)

proc attackPlan*(kind: WeaponKind, level: int, st: Stats, px, py: float, facing: Dir,
                 hasNearest: bool, nx, ny: float): seq[ProjSpec] =
  ## The projectiles one weapon activation creates.
  let w = weaponAt(kind, level)
  let n = max(1, w.amount + st.amount)
  let dmg = w.damage * st.might
  let size = w.size * st.area
  let ttl = w.ttl * st.duration
  let speed = w.speed * st.projSpeed
  let (fx, fy) = facingVec(facing)
  case kind
  of Whip:
    for i in 0 ..< n:
      let side = if i mod 2 == 0: 1.0 else: -1.0
      let dirx = (if facing == Left: -1.0 else: 1.0) * side
      result.add ProjSpec(kind: Whip, x: px + dirx * size / 2, y: py - float(i div 2) * 20,
                          size: size, damage: dmg, ttl: ttl, pierce: w.pierce)
  of MagicWand:
    var dx = fx
    var dy = fy
    if hasNearest:
      dx = nx - px
      dy = ny - py
    let len = max(1e-6, sqrt(dx * dx + dy * dy))
    let base = arctan2(dy / len, dx / len)
    for i in 0 ..< n:
      let a = base + (float(i) - float(n - 1) / 2) * 0.15
      result.add ProjSpec(kind: MagicWand, x: px, y: py, vx: cos(a) * speed, vy: sin(a) * speed,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)
  of Knife:
    for i in 0 ..< n:
      let off = (float(i) - float(n - 1) / 2) * 10
      result.add ProjSpec(kind: Knife, x: px - fy * off, y: py + fx * off, vx: fx * speed, vy: fy * speed,
                          size: size, damage: dmg, ttl: ttl, angle: arctan2(fy, fx), pierce: w.pierce)
  of Axe:
    for i in 0 ..< n:
      let dirx = if fx != 0: fx else: (if i mod 2 == 0: 1.0 else: -1.0)
      result.add ProjSpec(kind: Axe, x: px, y: py, vx: dirx * (60 + float(i) * 30), vy: -speed * 1.5,
                          size: size, damage: dmg, ttl: ttl, pierce: w.pierce)
  of Runetracer:
    for i in 0 ..< n:
      let a = rand(2 * PI)
      result.add ProjSpec(kind: Runetracer, x: px, y: py, vx: cos(a) * speed, vy: sin(a) * speed,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)
  of Garlic:
    result.add ProjSpec(kind: Garlic, x: px, y: py, size: size, damage: dmg, ttl: w.ttl, pierce: w.pierce)
  of KingBible:
    let r = bibleOrbitRadius * st.area
    for i in 0 ..< n:
      let a = float(i) * 2 * PI / float(n)
      # vx = angular speed (rad/s), vy = orbit radius; moveProjectiles reads them that way
      result.add ProjSpec(kind: KingBible, x: px + cos(a) * r, y: py + sin(a) * r, vx: speed, vy: r,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)

proc generateChoices*(owned: openArray[(WeaponKind, int)],
                      ownedPassives: openArray[(PassiveKind, int)]): seq[Choice] =
  ## Up to 3 level-up options; a gold/heal fallback when everything is maxed.
  var pool: seq[Choice]
  for (k, lvl) in owned:
    if lvl < maxWeaponLevel:
      pool.add Choice(kind: UpgradeWeapon, weapon: k, level: lvl + 1,
                      title: weaponDefs[k].name & " Lv" & $(lvl + 1), desc: weaponUpgrades[k][lvl + 1].text)
  if owned.len < maxWeaponSlots:
    for k in WeaponKind:
      if not owned.anyIt(it[0] == k):
        pool.add Choice(kind: NewWeapon, weapon: k, level: 1,
                        title: "New: " & weaponDefs[k].name, desc: weaponDefs[k].desc)
  for (k, lvl) in ownedPassives:
    if lvl < maxPassiveLevel:
      pool.add Choice(kind: UpgradePassive, passive: k, level: lvl + 1,
                      title: passiveDefs[k].name & " Lv" & $(lvl + 1), desc: passiveDefs[k].desc)
  if ownedPassives.len < maxPassiveSlots:
    for k in PassiveKind:
      if not ownedPassives.anyIt(it[0] == k):
        pool.add Choice(kind: NewPassive, passive: k, level: 1,
                        title: "New: " & passiveDefs[k].name, desc: passiveDefs[k].desc)
  shuffle(pool)
  result = pool[0 ..< min(3, pool.len)]
  if result.len == 0:
    result = @[Choice(kind: BonusGold, title: "Gold +25", desc: "Nothing left to learn"),
               Choice(kind: BonusHeal, title: "Floor Chicken", desc: "Recover 30 HP")]

proc separate*[E](enemies: openArray[E]): seq[(int, float, float)] =
  ## Soft push-apart for overlapping enemies: (id, dx, dy) to add to position.
  let grid = buildGrid(enemies)
  var push = initTable[int, (float, float)]()
  for i, a in enemies:
    let (cx, cy) = cellOf(a.x, a.y)
    for ox in -1 .. 1:
      for oy in -1 .. 1:
        if not grid.hasKey((cx + ox, cy + oy)):
          continue
        for j in grid[(cx + ox, cy + oy)]:
          if j <= i:
            continue
          let b = enemies[j]
          let minD = enemyRadius(a.size) + enemyRadius(b.size)
          let d = dist(a.x, a.y, b.x, b.y)
          if d < minD and d > 1e-6:
            let overlap = (minD - d) / 2
            let nx = (a.x - b.x) / d
            let ny = (a.y - b.y) / d
            var pa = push.getOrDefault(a.id)
            pa[0] += nx * overlap
            pa[1] += ny * overlap
            push[a.id] = pa
            var pb = push.getOrDefault(b.id)
            pb[0] -= nx * overlap
            pb[1] -= ny * overlap
            push[b.id] = pb
  for id, (dx, dy) in push.pairs:
    result.add (id, dx, dy)
  result.sort(proc (a, b: (int, float, float)): int = cmp(a[0], b[0]))
```

- [ ] **Step 4: Run tests**

Run: `nimble test`
Expected: all `systems` tests `[OK]`. If `separate` order differs, the test only checks signs so it still passes.

- [ ] **Step 5: Commit**

```bash
git add src/systems.nim tests/test_systems.nim
git commit -m "feat: pure systems for collision, pickups, attacks, choices"
```

---

### Task 4: Rules — schema, getters, player movement, clock

**Files:**
- Create: `src/rules.nim`, `tests/test_rules.nim`

**Interfaces:**
- Produces: `Id`, `Attr`, `PhaseKind`, `IntSet`, `Choices`, `Fact`, `FactMatch`, `rules`, `session` (global), `newSession()`, `resetSession()`, `allocId()`, `resetIds()`, `startRun(session, hero)`, getters listed below, rule names listed below.
- Later tasks append rules inside the same `staticRuleset` block and more helper procs after it.

- [ ] **Step 1: Write failing tests**

`tests/test_rules.nim`:
```nim
import unittest, sets, math
import pararules
import data, systems, rules

proc step(s: var Session[Fact, FactMatch], dt: float) =
  s.insert(Global, DeltaTime, dt)
  s.insert(Global, TotalTime, dt)
  s.fireRules()

suite "rules: session and player":
  test "fresh session starts on the title screen":
    var s = newSession()
    let (phase) = s.query(rules.getPhase)
    check phase == Title

  test "startRun creates the player with the character's weapon":
    var s = newSession()
    s.startRun(Otto)
    let p = s.query(rules.getPlayer)
    check p.hero == Otto
    check p.hp == 120.0
    check p.level == 1
    check p.xpToNext == 5
    let ws = s.queryAll(rules.getWeapons)
    check ws.len == 1
    check ws[0].kind == Whip
    check ws[0].level == 1
    let (phase) = s.query(rules.getPhase)
    check phase == Running

  test "game time advances only with DeltaTime":
    var s = newSession()
    s.startRun(Otto)
    s.step(0.5)
    s.step(0.25)
    let (tt, gt) = s.query(rules.getTime)
    check abs(gt - 0.75 * clockScale) < 1e-9

  test "player moves with WASD and arrows and faces the direction":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Global, PressedKeys, toHashSet([KeyD]))
    s.step(0.5)
    var p = s.query(rules.getPlayer)
    check abs(p.x - playerBaseSpeed * 0.5) < 1e-6
    check p.facing == Right
    check p.moving
    s.insert(Global, PressedKeys, toHashSet([KeyUp]))
    s.step(0.5)
    p = s.query(rules.getPlayer)
    check p.y < 0
    check p.facing == Up
    s.insert(Global, PressedKeys, initHashSet[int]())
    s.step(0.5)
    p = s.query(rules.getPlayer)
    check not p.moving

  test "diagonal movement is normalised":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Global, PressedKeys, toHashSet([KeyD, KeyS]))
    s.step(1.0)
    let p = s.query(rules.getPlayer)
    check abs(sqrt(p.x * p.x + p.y * p.y) - playerBaseSpeed) < 1e-6

  test "regen heals up to max hp":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Player, Hp, 50.0)
    var st = defaultStats
    st.regen = 10.0
    s.insert(Player, PlayerStats, st)
    s.step(1.0)
    check abs(s.query(rules.getPlayer).hp - 60.0) < 1e-6
    s.insert(Player, Hp, 119.5)
    s.step(1.0)
    check s.query(rules.getPlayer).hp == 120.0

  test "resetSession keeps the window size":
    var s = newSession()
    s.insert(Global, WindowWidth, 640)
    s.insert(Global, WindowHeight, 480)
    s.insert(Global, WorldWidth, 640.0)
    s.insert(Global, WorldHeight, 480.0)
    s.startRun(Gino)
    s = s.resetSession()
    let (ww, wh) = s.query(rules.getWorld)
    check ww == 640.0
    let (phase) = s.query(rules.getPhase)
    check phase == Title
    check s.queryAll(rules.getWeapons).len == 0
```

- [ ] **Step 2: Run to verify failure**

Run: `nimble test`
Expected: compile error `cannot open file: rules`.

- [ ] **Step 3: Write rules.nim (first version)**

`src/rules.nim`:
```nim
## All game state lives in one pararules session. This module owns the schema,
## the rules, and the helper procs that create/destroy entities. No OpenGL here.

import pararules
import sets, math, random, sequtils, tables
import data, systems
export sets

type
  Id* = enum
    Global, Player
  Attr* = enum
    # time / window / input
    DeltaTime, TotalTime, GameTime,
    WindowWidth, WindowHeight, WorldWidth, WorldHeight,
    PressedKeys, JustPressed,
    # flow
    Phase, SelectedIndex, ChoiceList, PendingLevelUps, ResultText,
    # spawning / targeting
    SpawnTimer, EnemyCount, BossesSpawned, NearestX, NearestY, HasNearest,
    # shared entity attrs
    Hero, X, Y, Facing, Moving, Hp, MaxHp, Speed, Damage, Size,
    Xp, Level, XpToNext, Gold, Kills, PlayerStats,
    # weapon slots
    Weapon, WeaponLevel, Cooldown,
    # passive slots
    Passive, PassiveLevel,
    # enemies
    Enemy, HitFlash,
    # projectiles
    Proj, VX, VY, Ttl, Pierce, HitIds, Angle,
    # pickups
    Pickup, Value, Magnetized
  PhaseKind* = enum
    Title, CharSelect, Running, LevelUp, Paused, GameOver
  IntSet* = HashSet[int]
  Choices* = ref seq[Choice]

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  GameTime: float
  WindowWidth: int
  WindowHeight: int
  WorldWidth: float
  WorldHeight: float
  PressedKeys: IntSet
  JustPressed: IntSet
  Phase: PhaseKind
  SelectedIndex: int
  ChoiceList: Choices
  PendingLevelUps: int
  ResultText: string
  SpawnTimer: float
  EnemyCount: int
  BossesSpawned: IntSet
  NearestX: float
  NearestY: float
  HasNearest: bool
  Hero: CharacterKind
  X: float
  Y: float
  Facing: Dir
  Moving: bool
  Hp: float
  MaxHp: float
  Speed: float
  Damage: float
  Size: float
  Xp: int
  Level: int
  XpToNext: int
  Gold: int
  Kills: int
  PlayerStats: Stats
  Weapon: WeaponKind
  WeaponLevel: int
  Cooldown: float
  Passive: PassiveKind
  PassiveLevel: int
  Enemy: EnemyKind
  HitFlash: float
  Proj: WeaponKind
  VX: float
  VY: float
  Ttl: float
  Pierce: int
  HitIds: IntSet
  Angle: float
  Pickup: PickupKind
  Value: int
  Magnetized: bool

# ---------------------------------------------------------------- ids

var nextId = Id.high.ord + 1

proc allocId*(): int =
  result = nextId
  inc nextId

proc resetIds*() =
  nextId = Id.high.ord + 1

proc faceOf(dx, dy: float, current: Dir): Dir =
  if dx < 0: Left
  elif dx > 0: Right
  elif dy < 0: Up
  elif dy > 0: Down
  else: current

# ---------------------------------------------------------------- rules

let (initSession, rules*) =
  staticRuleset(Fact, FactMatch):
    # ---- getters
    rule getWindow(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, WindowHeight, windowHeight)
    rule getWorld(Fact):
      what:
        (Global, WorldWidth, worldWidth)
        (Global, WorldHeight, worldHeight)
    rule getKeys(Fact):
      what:
        (Global, PressedKeys, keys)
    rule getJustPressed(Fact):
      what:
        (Global, JustPressed, keys)
    rule getPhase(Fact):
      what:
        (Global, Phase, phase)
    rule getTime(Fact):
      what:
        (Global, TotalTime, totalTime)
        (Global, GameTime, gameTime)
    rule getMenu(Fact):
      what:
        (Global, SelectedIndex, selected)
        (Global, ChoiceList, choices)
        (Global, PendingLevelUps, pending)
        (Global, ResultText, resultText)
    rule getTargeting(Fact):
      what:
        (Global, HasNearest, hasNearest)
        (Global, NearestX, nearestX)
        (Global, NearestY, nearestY)
        (Global, EnemyCount, enemyCount)
    rule getPlayer(Fact):
      what:
        (Player, Hero, hero)
        (Player, X, x)
        (Player, Y, y)
        (Player, Facing, facing)
        (Player, Moving, moving)
        (Player, Hp, hp)
        (Player, MaxHp, maxHp)
        (Player, Xp, xp)
        (Player, Level, level)
        (Player, XpToNext, xpToNext)
        (Player, Gold, gold)
        (Player, Kills, kills)
    rule getStats(Fact):
      what:
        (Player, PlayerStats, stats)
    rule getWeapons(Fact):
      what:
        (id, Weapon, kind)
        (id, WeaponLevel, level)
        (id, Cooldown, cooldown)
    rule getPassives(Fact):
      what:
        (id, Passive, kind)
        (id, PassiveLevel, level)
    rule getEnemies(Fact):
      what:
        (id, Enemy, kind)
        (id, X, x)
        (id, Y, y)
        (id, Hp, hp)
        (id, Speed, speed)
        (id, Damage, damage)
        (id, Size, size)
        (id, HitFlash, hitFlash)
    rule getProjectiles(Fact):
      what:
        (id, Proj, kind)
        (id, X, x)
        (id, Y, y)
        (id, VX, vx)
        (id, VY, vy)
        (id, Ttl, ttl)
        (id, Pierce, pierce)
        (id, HitIds, hitIds)
        (id, Angle, angle)
        (id, Size, size)
        (id, Damage, damage)
    rule getPickups(Fact):
      what:
        (id, Pickup, kind)
        (id, X, x)
        (id, Y, y)
        (id, Value, value)
        (id, Magnetized, magnetized)

    # ---- per-tick rules (trigger: DeltaTime)
    rule tickGameTime(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, GameTime, t, then = false)
      then:
        session.insert(Global, GameTime, t + dt * clockScale)

    rule movePlayer(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, PressedKeys, keys, then = false)
        (Player, X, x, then = false)
        (Player, Y, y, then = false)
        (Player, Speed, speed, then = false)
        (Player, PlayerStats, st, then = false)
        (Player, Facing, facing, then = false)
      then:
        var dx = 0.0
        var dy = 0.0
        if keys.contains(KeyLeft) or keys.contains(KeyA): dx -= 1
        if keys.contains(KeyRight) or keys.contains(KeyD): dx += 1
        if keys.contains(KeyUp) or keys.contains(KeyW): dy -= 1
        if keys.contains(KeyDown) or keys.contains(KeyS): dy += 1
        let moving = dx != 0 or dy != 0
        if moving:
          let len = sqrt(dx * dx + dy * dy)
          let v = speed * st.speedMul * dt / len
          session.insert(Player, X, x + dx * v)
          session.insert(Player, Y, y + dy * v)
          session.insert(Player, Facing, faceOf(dx, dy, facing))
        session.insert(Player, Moving, moving)

    rule regenPlayer(Fact):
      what:
        (Global, DeltaTime, dt)
        (Player, Hp, hp, then = false)
        (Player, MaxHp, maxHp, then = false)
        (Player, PlayerStats, st, then = false)
      cond:
        st.regen > 0
        hp < maxHp
      then:
        session.insert(Player, Hp, min(maxHp, hp + st.regen * dt))

# ---------------------------------------------------------------- session

proc newSession*(): Session[Fact, FactMatch] =
  resetIds()
  result = initSession(autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Global, Phase, Title)
  result.insert(Global, PressedKeys, initHashSet[int]())
  result.insert(Global, JustPressed, initHashSet[int]())
  result.insert(Global, WindowWidth, 1024)
  result.insert(Global, WindowHeight, 768)
  result.insert(Global, WorldWidth, 1024.0 / zoom)
  result.insert(Global, WorldHeight, 768.0 / zoom)
  result.insert(Global, TotalTime, 0.0)
  result.insert(Global, GameTime, 0.0)
  result.insert(Global, SelectedIndex, 0)
  result.insert(Global, ChoiceList, Choices(nil))
  result.insert(Global, PendingLevelUps, 0)
  result.insert(Global, ResultText, "")
  result.insert(Global, SpawnTimer, 0.0)
  result.insert(Global, EnemyCount, 0)
  result.insert(Global, BossesSpawned, initHashSet[int]())
  result.insert(Global, NearestX, 0.0)
  result.insert(Global, NearestY, 0.0)
  result.insert(Global, HasNearest, false)

proc resetSession*(old: Session[Fact, FactMatch]): Session[Fact, FactMatch] =
  ## Brand-new session (drops every entity) that keeps the window facts.
  let (windowWidth, windowHeight) = old.query(rules.getWindow)
  let (worldWidth, worldHeight) = old.query(rules.getWorld)
  result = newSession()
  result.insert(Global, WindowWidth, windowWidth)
  result.insert(Global, WindowHeight, windowHeight)
  result.insert(Global, WorldWidth, worldWidth)
  result.insert(Global, WorldHeight, worldHeight)

var session* = newSession()

# ---------------------------------------------------------------- entity helpers

proc addWeapon*(session: var Session[Fact, FactMatch], kind: WeaponKind, level = 1) =
  let id = allocId()
  session.insert(id, Weapon, kind)
  session.insert(id, WeaponLevel, level)
  session.insert(id, Cooldown, 0.2)

proc addPassive*(session: var Session[Fact, FactMatch], kind: PassiveKind, level = 1) =
  let id = allocId()
  session.insert(id, Passive, kind)
  session.insert(id, PassiveLevel, level)

proc recomputeStats*(session: var Session[Fact, FactMatch]) =
  let p = session.query(rules.getPlayer)
  let passives = session.queryAll(rules.getPassives).mapIt((it.kind, it.level))
  session.insert(Player, PlayerStats, computeStats(p.hero, passives))
  let newMax = maxHpFor(p.hero, passives)
  if newMax != p.maxHp:
    session.insert(Player, MaxHp, newMax)
    session.insert(Player, Hp, min(newMax, p.hp + max(0.0, newMax - p.maxHp)))

proc startRun*(session: var Session[Fact, FactMatch], hero: CharacterKind) =
  let c = characterDefs[hero]
  session.insert(Player, Hero, hero)
  session.insert(Player, X, 0.0)
  session.insert(Player, Y, 0.0)
  session.insert(Player, Facing, Down)
  session.insert(Player, Moving, false)
  session.insert(Player, MaxHp, c.maxHp)
  session.insert(Player, Hp, c.maxHp)
  session.insert(Player, Speed, playerBaseSpeed)
  session.insert(Player, Xp, 0)
  session.insert(Player, Level, 1)
  session.insert(Player, XpToNext, xpForLevel(1))
  session.insert(Player, Gold, 0)
  session.insert(Player, Kills, 0)
  session.insert(Player, PlayerStats, c.base)
  session.addWeapon(c.weapon)
  session.insert(Global, GameTime, 0.0)
  session.insert(Global, SpawnTimer, 0.0)
  session.insert(Global, EnemyCount, 0)
  session.insert(Global, BossesSpawned, initHashSet[int]())
  session.insert(Global, HasNearest, false)
  session.insert(Global, PendingLevelUps, 0)
  session.insert(Global, ResultText, "")
  session.insert(Global, Phase, Running)
```

- [ ] **Step 4: Run tests**

Run: `nimble test`
Expected: all `rules: session and player` tests `[OK]`.

If the compiler complains that `rules*` cannot be exported from a tuple unpack, change the line to `let (initSession, rules) = ...` and add `export rules` is not possible for a `let`; instead keep it unexported and add below the ruleset:
```nim
template rules*: untyped = rules
```
is also invalid. The working fallback is: keep `let (initSession, rulesInternal) = staticRuleset(...)` and then `let rules* = rulesInternal`. Prefer trying `rules*` in the tuple first — Nim 2 accepts `let (a, b*) = ...`.

- [ ] **Step 5: Commit**

```bash
git add src/rules.nim tests/test_rules.nim
git commit -m "feat: pararules schema, getters, player movement and clock"
```

---

### Task 5: Rules — weapons and projectiles

**Files:**
- Modify: `src/rules.nim` (add rules inside the `staticRuleset` block after `regenPlayer`, add helpers after `addPassive`)
- Modify: `tests/test_rules.nim`

**Interfaces:**
- Produces: `insertProjectile(session, spec: ProjSpec): int`, `retractProjectile(session, id)`, rules `tickWeapons`, `moveProjectiles`.

- [ ] **Step 1: Add failing tests**

Append to `tests/test_rules.nim`:
```nim
suite "rules: weapons and projectiles":
  test "weapon fires when its cooldown expires and resets it":
    var s = newSession()
    s.startRun(Gino) # Knife, +1 amount
    check s.queryAll(rules.getProjectiles).len == 0
    s.step(0.25) # initial cooldown is 0.2
    let ps = s.queryAll(rules.getProjectiles)
    check ps.len == 2
    check ps[0].kind == Knife
    let w = s.queryAll(rules.getWeapons)[0]
    check abs(w.cooldown - weaponDefs[Knife].cooldown) < 1e-6

  test "projectiles move and age":
    var s = newSession()
    s.startRun(Gino)
    s.insert(Player, Facing, Right)
    s.step(0.25)
    let before = s.queryAll(rules.getProjectiles)[0]
    s.step(0.1)
    let after = s.query(rules.getProjectiles, id = before.id)
    check after.x > before.x
    check abs(after.ttl - (before.ttl - 0.1)) < 1e-9

  test "king bible orbits the player":
    var s = newSession()
    s.startRun(Otto)
    s.addWeapon(KingBible)
    s.step(0.25)
    let bibles = s.queryAll(rules.getProjectiles).filterIt(it.kind == KingBible)
    check bibles.len == 1
    s.insert(Player, X, 500.0)
    s.step(0.1)
    let b = s.query(rules.getProjectiles, id = bibles[0].id)
    check abs(dist(b.x, b.y, 500.0, 0.0) - bibleOrbitRadius) < 1e-6

  test "runetracer bounces inside the view":
    var s = newSession()
    s.startRun(Lina)
    s.step(0.25)
    let r = s.queryAll(rules.getProjectiles)[0]
    s.insert(r.id, X, 0.0)
    s.insert(r.id, Y, 0.0)
    s.insert(r.id, VX, -1000.0)
    s.insert(r.id, VY, 0.0)
    s.step(1.0)
    let after = s.query(rules.getProjectiles, id = r.id)
    check after.vx > 0
    check after.x >= -1024.0 / 2 / zoom

  test "insert/retract projectile round trip":
    var s = newSession()
    s.startRun(Otto)
    let id = s.insertProjectile(ProjSpec(kind: Axe, x: 1, y: 2, vx: 3, vy: 4, size: 5, damage: 6, ttl: 7, angle: 0, pierce: 8))
    check s.queryAll(rules.getProjectiles).len == 1
    s.retractProjectile(id)
    check s.queryAll(rules.getProjectiles).len == 0
```
Add `import sequtils` at the top of the test file.

- [ ] **Step 2: Run to verify failure**

Run: `nimble test`
Expected: compile error `undeclared identifier: 'insertProjectile'`.

- [ ] **Step 3: Add the rules**

Insert after `regenPlayer` inside the `staticRuleset` block:
```nim
    rule tickWeapons(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, HasNearest, hasNearest, then = false)
        (Global, NearestX, nx, then = false)
        (Global, NearestY, ny, then = false)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
        (Player, Facing, facing, then = false)
        (Player, PlayerStats, st, then = false)
        (id, Weapon, kind, then = false)
        (id, WeaponLevel, level, then = false)
        (id, Cooldown, cd, then = false)
      then:
        let cd2 = cd - dt
        if cd2 > 0:
          session.insert(id, Cooldown, cd2)
        else:
          for spec in attackPlan(kind, level, st, px, py, facing, hasNearest, nx, ny):
            let pid = allocId()
            session.insert(pid, Proj, spec.kind)
            session.insert(pid, X, spec.x)
            session.insert(pid, Y, spec.y)
            session.insert(pid, VX, spec.vx)
            session.insert(pid, VY, spec.vy)
            session.insert(pid, Ttl, spec.ttl)
            session.insert(pid, Pierce, spec.pierce)
            session.insert(pid, HitIds, initHashSet[int]())
            session.insert(pid, Angle, spec.angle)
            session.insert(pid, Size, spec.size)
            session.insert(pid, Damage, spec.damage)
          session.insert(id, Cooldown, weaponAt(kind, level).cooldown * st.cooldownMul)

    rule moveProjectiles(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, WorldWidth, ww, then = false)
        (Global, WorldHeight, wh, then = false)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
        (id, Proj, kind, then = false)
        (id, X, x, then = false)
        (id, Y, y, then = false)
        (id, VX, vx, then = false)
        (id, VY, vy, then = false)
        (id, Ttl, ttl, then = false)
        (id, Angle, angle, then = false)
      then:
        session.insert(id, Ttl, ttl - dt)
        case kind
        of Whip:
          discard # stays where it was spawned
        of Garlic:
          session.insert(id, X, px)
          session.insert(id, Y, py)
        of KingBible:
          # vx = angular speed, vy = orbit radius (see systems.attackPlan)
          let a = angle + vx * dt
          session.insert(id, Angle, a)
          session.insert(id, X, px + cos(a) * vy)
          session.insert(id, Y, py + sin(a) * vy)
        of Axe:
          let vy2 = vy + axeGravity * dt
          session.insert(id, VY, vy2)
          session.insert(id, X, x + vx * dt)
          session.insert(id, Y, y + vy2 * dt)
          session.insert(id, Angle, angle + 10 * dt)
        of Runetracer:
          var nx = x + vx * dt
          var ny = y + vy * dt
          var nvx = vx
          var nvy = vy
          let left = px - ww / 2
          let right = px + ww / 2
          let top = py - wh / 2
          let bottom = py + wh / 2
          if nx < left:
            nx = left
            nvx = abs(vx)
          elif nx > right:
            nx = right
            nvx = -abs(vx)
          if ny < top:
            ny = top
            nvy = abs(vy)
          elif ny > bottom:
            ny = bottom
            nvy = -abs(vy)
          session.insert(id, X, nx)
          session.insert(id, Y, ny)
          session.insert(id, VX, nvx)
          session.insert(id, VY, nvy)
        of MagicWand, Knife:
          session.insert(id, X, x + vx * dt)
          session.insert(id, Y, y + vy * dt)
```

Add after `addPassive`:
```nim
proc insertProjectile*(session: var Session[Fact, FactMatch], spec: ProjSpec): int =
  result = allocId()
  session.insert(result, Proj, spec.kind)
  session.insert(result, X, spec.x)
  session.insert(result, Y, spec.y)
  session.insert(result, VX, spec.vx)
  session.insert(result, VY, spec.vy)
  session.insert(result, Ttl, spec.ttl)
  session.insert(result, Pierce, spec.pierce)
  session.insert(result, HitIds, initHashSet[int]())
  session.insert(result, Angle, spec.angle)
  session.insert(result, Size, spec.size)
  session.insert(result, Damage, spec.damage)

proc retractProjectile*(session: var Session[Fact, FactMatch], id: int) =
  for a in [Proj, X, Y, VX, VY, Ttl, Pierce, HitIds, Angle, Size, Damage]:
    session.retract(id, a)
```
Then replace the 11 `session.insert(pid, ...)` lines inside `tickWeapons` with `discard session.insertProjectile(spec)` — the helper is declared after the ruleset, so if Nim reports it undeclared inside the rule body, move `insertProjectile`/`retractProjectile` *above* the `let (initSession, rules*) = ...` line (they only need the generated `Session[Fact, FactMatch]` type and `insert`, which the `schema` macro already produced). Keep whichever compiles; the inline version above is the guaranteed one.

- [ ] **Step 4: Run tests**

Run: `nimble test`
Expected: all tests `[OK]`.

- [ ] **Step 5: Commit**

```bash
git add src/rules.nim tests/test_rules.nim
git commit -m "feat: weapon cooldowns and projectile motion rules"
```

---

### Task 6: Rules — enemies, waves, bosses, pickups motion

**Files:**
- Modify: `src/rules.nim`, `tests/test_rules.nim`

**Interfaces:**
- Produces: `spawnEnemy(session, kind, x, y, minute): int`, `retractEnemy(session, id)`, `spawnPickup(session, kind, x, y, value): int`, `retractPickup(session, id)`, rules `moveEnemies`, `decayHitFlash`, `spawnWave`, `spawnBosses`, `movePickups`.

- [ ] **Step 1: Add failing tests**

Append to `tests/test_rules.nim`:
```nim
suite "rules: enemies, waves, pickups":
  test "enemies walk toward the player":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnEnemy(Zombie, 100.0, 0.0, 0)
    s.step(0.5)
    let e = s.query(rules.getEnemies, id = id)
    check e.x < 100.0
    check abs(e.x - (100.0 - enemyDefs[Zombie].speed * 0.5)) < 1e-6
    check e.hp == enemyDefs[Zombie].hp

  test "enemy hp scales with the minute":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnEnemy(Zombie, 100.0, 0.0, 10)
    check abs(s.query(rules.getEnemies, id = id).hp - enemyDefs[Zombie].hp * hpScale(10)) < 1e-9
    let boss = s.spawnEnemy(Koalio, 100.0, 0.0, 10)
    check s.query(rules.getEnemies, id = boss).hp == enemyDefs[Koalio].hp

  test "hit flash decays":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnEnemy(Bat, 100.0, 0.0, 0)
    s.insert(id, HitFlash, 0.1)
    s.step(0.05)
    check abs(s.query(rules.getEnemies, id = id).hitFlash - 0.05) < 1e-9
    s.step(0.5)
    check s.query(rules.getEnemies, id = id).hitFlash == 0.0

  test "waves keep the minimum count and spawn offscreen":
    var s = newSession()
    s.startRun(Otto)
    for i in 0 ..< 3:
      s.step(0.016)
    let es = s.queryAll(rules.getEnemies)
    check es.len >= waveFor(0).minCount
    for e in es:
      check e.kind == Bat
      check abs(e.x) >= 1024.0 / 2 or abs(e.y) >= 768.0 / 2

  test "bosses spawn once at their minute":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Global, GameTime, 3 * 60.0 - 0.1)
    s.step(0.2 / clockScale)
    check s.queryAll(rules.getEnemies).filterIt(it.kind == Parakeet).len == 1
    s.step(0.2 / clockScale)
    check s.queryAll(rules.getEnemies).filterIt(it.kind == Parakeet).len == 1

  test "magnetized gems fly to the player":
    var s = newSession()
    s.startRun(Otto)
    let id = s.spawnPickup(GemBlue, 200.0, 0.0, 1)
    s.step(0.1)
    check s.query(rules.getPickups, id = id).x == 200.0
    s.insert(id, Magnetized, true)
    s.step(0.1)
    check s.query(rules.getPickups, id = id).x < 200.0

  test "retract helpers remove every attribute":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Bat, 0, 0, 0)
    let p = s.spawnPickup(Coin, 0, 0, 10)
    s.retractEnemy(e)
    s.retractPickup(p)
    check s.queryAll(rules.getEnemies).len == 0
    check s.queryAll(rules.getPickups).len == 0
    check not s.contains(e, X)
    check not s.contains(p, X)
```

- [ ] **Step 2: Run to verify failure**

Run: `nimble test`
Expected: compile error `undeclared identifier: 'spawnEnemy'`.

- [ ] **Step 3: Add helpers above the ruleset and rules inside it**

Insert these procs **above** `let (initSession, rules*) = ...` (they are called from rule bodies):
```nim
proc spawnEnemy*(session: var Session[Fact, FactMatch], kind: EnemyKind, x, y: float, minute: int): int =
  let d = enemyDefs[kind]
  result = allocId()
  session.insert(result, Enemy, kind)
  session.insert(result, X, x)
  session.insert(result, Y, y)
  session.insert(result, Hp, if d.boss: d.hp else: d.hp * hpScale(minute))
  session.insert(result, Speed, d.speed)
  session.insert(result, Damage, d.damage)
  session.insert(result, Size, d.size)
  session.insert(result, HitFlash, 0.0)

proc retractEnemy*(session: var Session[Fact, FactMatch], id: int) =
  for a in [Enemy, X, Y, Hp, Speed, Damage, Size, HitFlash]:
    session.retract(id, a)

proc spawnPickup*(session: var Session[Fact, FactMatch], kind: PickupKind, x, y: float, value: int): int =
  result = allocId()
  session.insert(result, Pickup, kind)
  session.insert(result, X, x)
  session.insert(result, Y, y)
  session.insert(result, Value, value)
  session.insert(result, Magnetized, false)

proc retractPickup*(session: var Session[Fact, FactMatch], id: int) =
  for a in [Pickup, X, Y, Value, Magnetized]:
    session.retract(id, a)
```
If Nim rejects `Session[Fact, FactMatch]` before the ruleset exists (the `FactMatch` type is generated by `staticRuleset`), move these four procs *below* the ruleset and, inside the rules, spawn inline with the same `session.insert` lines as in `spawnEnemy`. Inline is always safe.

Insert inside the ruleset after `moveProjectiles`:
```nim
    rule moveEnemies(Fact):
      what:
        (Global, DeltaTime, dt)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
        (id, Enemy, kind, then = false)
        (id, X, x, then = false)
        (id, Y, y, then = false)
        (id, Speed, speed, then = false)
      then:
        let ddx = px - x
        let ddy = py - y
        let d = sqrt(ddx * ddx + ddy * ddy)
        if d > 1.0:
          let v = speed * dt / d
          session.insert(id, X, x + ddx * v)
          session.insert(id, Y, y + ddy * v)

    rule decayHitFlash(Fact):
      what:
        (Global, DeltaTime, dt)
        (id, HitFlash, f, then = false)
      cond:
        f > 0
      then:
        session.insert(id, HitFlash, max(0.0, f - dt))

    rule spawnWave(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, GameTime, t, then = false)
        (Global, SpawnTimer, timer, then = false)
        (Global, EnemyCount, count, then = false)
        (Global, WorldWidth, ww, then = false)
        (Global, WorldHeight, wh, then = false)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
      then:
        let minute = int(t / 60)
        let wave = waveFor(minute)
        var timer2 = timer + dt
        var toSpawn = 0
        if count < wave.minCount:
          toSpawn = min(wave.minCount - count, 10)
        elif timer2 >= wave.interval:
          toSpawn = 1
        if toSpawn > 0:
          timer2 = 0
        var spawned = 0
        for i in 0 ..< toSpawn:
          if count + spawned >= maxEnemies:
            break
          let kind = wave.kinds[rand(wave.kinds.high)]
          let (sx, sy) = offscreenPoint(px, py, ww, wh)
          discard session.spawnEnemy(kind, sx, sy, minute)
          inc spawned
        session.insert(Global, SpawnTimer, timer2)
        session.insert(Global, EnemyCount, count + spawned)

    rule spawnBosses(Fact):
      what:
        (Global, GameTime, t)
        (Global, BossesSpawned, done, then = false)
        (Global, WorldWidth, ww, then = false)
        (Global, WorldHeight, wh, then = false)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
      then:
        var done2 = done
        var changed = false
        for b in bosses:
          let key = b.minute * 100 + b.kind.ord
          if t >= float(b.minute * 60) and not done2.contains(key):
            for i in 0 ..< b.count:
              let (sx, sy) = offscreenPoint(px, py, ww, wh)
              discard session.spawnEnemy(b.kind, sx, sy, b.minute)
            done2.incl(key)
            changed = true
        if changed:
          session.insert(Global, BossesSpawned, done2)

    rule movePickups(Fact):
      what:
        (Global, DeltaTime, dt)
        (Player, X, px, then = false)
        (Player, Y, py, then = false)
        (id, Pickup, kind, then = false)
        (id, Magnetized, magnetized, then = false)
        (id, X, x, then = false)
        (id, Y, y, then = false)
      cond:
        magnetized
      then:
        let ddx = px - x
        let ddy = py - y
        let d = max(1e-6, sqrt(ddx * ddx + ddy * ddy))
        let v = min(d, gemFlySpeed * dt) / d
        session.insert(id, X, x + ddx * v)
        session.insert(id, Y, y + ddy * v)
```

- [ ] **Step 4: Run tests**

Run: `nimble test`
Expected: all tests `[OK]`. The "waves keep the minimum count" test needs three ticks because a tick spawns at most 10.

- [ ] **Step 5: Commit**

```bash
git add src/rules.nim tests/test_rules.nim
git commit -m "feat: enemy movement, wave and boss spawning, magnetized pickups"
```

---

### Task 7: stepSystems, level-up, death, choices

**Files:**
- Modify: `src/rules.nim`, `tests/test_rules.nim`

**Interfaces:**
- Produces: `StepEvents`, `stepSystems(session, dt): StepEvents`, `prepareChoices(session)`, `applyChoice(session, choice)`, rules `levelUp`, `playerDied`.

- [ ] **Step 1: Add failing tests**

Append to `tests/test_rules.nim`:
```nim
proc runTick(s: var Session[Fact, FactMatch], dt: float): StepEvents =
  s.insert(Global, DeltaTime, dt)
  s.insert(Global, TotalTime, dt)
  s.fireRules()
  result = s.stepSystems(dt)
  s.fireRules()

suite "rules: systems step, level up, death":
  test "projectile kills enemy, drops a gem, counts the kill":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Bat, 50.0, 0.0, 0)
    discard s.insertProjectile(ProjSpec(kind: MagicWand, x: 50, y: 0, size: 10, damage: 5, ttl: 1, pierce: 0))
    let ev = s.runTick(0.001)
    check ev.hits == 1
    check ev.kills == 1
    check not s.contains(e, X)
    check s.queryAll(rules.getProjectiles).len == 0 # pierce 0 → consumed
    let gems = s.queryAll(rules.getPickups)
    check gems.len >= 1
    check gems.anyIt(it.kind == GemBlue)
    check s.query(rules.getPlayer).kills == 1

  test "surviving enemy takes damage and flashes; piercing projectile survives":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Koalio, 0.0, 0.0, 0)
    let p = s.insertProjectile(ProjSpec(kind: Knife, x: 0, y: 0, size: 10, damage: 5, ttl: 1, pierce: 3))
    discard s.runTick(0.001)
    let en = s.query(rules.getEnemies, id = e)
    check abs(en.hp - (enemyDefs[Koalio].hp - 5)) < 1e-6
    check en.hitFlash > 0
    let pr = s.query(rules.getProjectiles, id = p)
    check pr.hitIds.contains(e)
    discard s.runTick(0.001)
    check abs(s.query(rules.getEnemies, id = e).hp - (enemyDefs[Koalio].hp - 5)) < 1e-6 # hit only once

  test "boss drops a chest which upgrades a weapon":
    var s = newSession()
    s.startRun(Otto)
    let e = s.spawnEnemy(Koalio, 0.0, 0.0, 0)
    s.insert(e, Hp, 1.0)
    discard s.insertProjectile(ProjSpec(kind: Knife, x: 0, y: 0, size: 10, damage: 5, ttl: 1, pierce: 3))
    let ev = s.runTick(0.001)
    check ev.bossKilled
    check s.queryAll(rules.getPickups).anyIt(it.kind == Chest)
    let ev2 = s.runTick(0.001) # chest sits on the player → collected
    check ev2.chest
    check s.queryAll(rules.getWeapons)[0].level == 2

  test "touching enemies hurts the player":
    var s = newSession()
    s.startRun(Otto)
    discard s.spawnEnemy(Zombie, 5.0, 0.0, 0)
    let ev = s.runTick(0.5)
    check ev.hurt
    check s.query(rules.getPlayer).hp < 120.0

  test "gems give xp and trigger a pending level up":
    var s = newSession()
    s.startRun(Otto)
    discard s.spawnPickup(GemRed, 0.0, 0.0, 5)
    let ev = s.runTick(0.001)
    check ev.gems == 1
    let p = s.query(rules.getPlayer)
    check p.level == 2
    check p.xp == 0
    check p.xpToNext == xpForLevel(2)
    let m = s.query(rules.getMenu)
    check m.pending == 1

  test "prepareChoices and applyChoice":
    var s = newSession()
    s.startRun(Otto)
    s.prepareChoices()
    let m = s.query(rules.getMenu)
    check m.choices != nil
    check m.choices[].len == 3
    s.applyChoice(Choice(kind: NewPassive, passive: Spinach, level: 1))
    check s.queryAll(rules.getPassives).len == 1
    check abs(s.query(rules.getStats).stats.might - 1.2) < 1e-9
    s.applyChoice(Choice(kind: UpgradeWeapon, weapon: Whip, level: 2))
    check s.queryAll(rules.getWeapons)[0].level == 2
    s.applyChoice(Choice(kind: NewPassive, passive: HollowHeart, level: 1))
    check s.query(rules.getPlayer).maxHp == 144.0

  test "player death ends the run with a result":
    var s = newSession()
    s.startRun(Otto)
    s.insert(Player, Hp, 0.0)
    s.fireRules()
    let (phase) = s.query(rules.getPhase)
    check phase == GameOver
    check s.query(rules.getMenu).resultText.len > 0

  test "far enemies despawn and the count is refreshed":
    var s = newSession()
    s.startRun(Otto)
    discard s.spawnEnemy(Bat, 5000.0, 0.0, 0)
    discard s.runTick(0.001)
    check s.queryAll(rules.getEnemies).allIt(it.x < 5000.0)
```

- [ ] **Step 2: Run to verify failure**

Run: `nimble test`
Expected: compile error `undeclared identifier: 'stepSystems'`.

- [ ] **Step 3: Add the reactive rules**

Inside the ruleset after `movePickups`:
```nim
    # ---- reactive rules
    rule levelUp(Fact):
      what:
        (Player, Xp, xp)
        (Player, XpToNext, need, then = false)
        (Player, Level, level, then = false)
        (Global, PendingLevelUps, pending, then = false)
      cond:
        xp >= need
      then:
        session.insert(Player, Level, level + 1)
        session.insert(Player, XpToNext, xpForLevel(level + 1))
        session.insert(Global, PendingLevelUps, pending + 1)
        session.insert(Player, Xp, xp - need)

    rule playerDied(Fact):
      what:
        (Player, Hp, hp)
        (Global, GameTime, t, then = false)
        (Global, Phase, phase, then = false)
      cond:
        hp <= 0
        phase == Running
      then:
        session.insert(Global, Phase, GameOver)
        session.insert(Global, ResultText,
          if t >= float(runLengthSecs): "You survived until dawn!" else: "Slain at " & clockText(t))
```

- [ ] **Step 4: Add stepSystems, prepareChoices, applyChoice at the end of rules.nim**

```nim
# ---------------------------------------------------------------- per-tick systems

type
  StepEvents* = object
    hits*, kills*, gems*: int
    hurt*, chest*, chicken*, coin*, bossKilled*: bool

proc stepSystems*(session: var Session[Fact, FactMatch], dt: float): StepEvents =
  ## Runs after fireRules: N×M work on plain seqs, then writes results back.
  let player = session.query(rules.getPlayer)
  let (st) = session.query(rules.getStats)
  let (ww, wh) = session.query(rules.getWorld)
  let (tt, gameTime) = session.query(rules.getTime)
  let enemies = session.queryAll(rules.getEnemies)
  let projs = session.queryAll(rules.getProjectiles)
  let pickups = session.queryAll(rules.getPickups)
  let minute = int(gameTime / 60)

  # 1. projectile hits
  var hpDelta = initTable[int, float]()
  var newHitIds = initTable[int, IntSet]()
  for h in collide(projs, enemies):
    hpDelta[h.enemyId] = hpDelta.getOrDefault(h.enemyId) + h.damage
    if not newHitIds.hasKey(h.projId):
      for p in projs:
        if p.id == h.projId:
          newHitIds[h.projId] = p.hitIds
          break
    newHitIds[h.projId].incl(h.enemyId)
    inc result.hits
  for p in projs:
    if p.ttl <= 0:
      session.retractProjectile(p.id)
    elif newHitIds.hasKey(p.id):
      let ids = newHitIds[p.id]
      if ids.len > p.pierce:
        session.retractProjectile(p.id)
      else:
        session.insert(p.id, HitIds, ids)

  # 2. damage, deaths, drops, despawn
  var xpGain = 0
  var goldGain = 0
  var heal = 0.0
  var alive = 0
  var gemCount = pickups.countIt(it.kind.isGem)
  for e in enemies:
    var hp = e.hp
    if hpDelta.hasKey(e.id):
      hp -= hpDelta[e.id]
      if hp > 0:
        session.insert(e.id, Hp, hp)
        session.insert(e.id, HitFlash, hitFlashSecs)
    if hp <= 0:
      session.retractEnemy(e.id)
      inc result.kills
      let d = enemyDefs[e.kind]
      if d.boss:
        discard session.spawnPickup(Chest, e.x, e.y, 1)
        result.bossKilled = true
      else:
        let r = rand(1.0)
        if r < chickenChance:
          discard session.spawnPickup(Chicken, e.x, e.y, 0)
        elif r < chickenChance + coinChance:
          discard session.spawnPickup(Coin, e.x, e.y, coinValue)
        elif r < chickenChance + coinChance + vacuumChance:
          discard session.spawnPickup(Vacuum, e.x, e.y, 0)
        if gemCount < maxPickups:
          discard session.spawnPickup(d.gem, e.x, e.y, gemValue(d.gem))
          inc gemCount
        else:
          xpGain += gemValue(d.gem)
    elif tooFar(e.x, e.y, player.x, player.y, ww, wh):
      session.retractEnemy(e.id)
    else:
      inc alive
  session.insert(Global, EnemyCount, alive)

  # 3. contact damage
  let dmg = contactDamage(enemies, player.x, player.y, st.armor, dt)
  if dmg > 0:
    result.hurt = true

  # 4. pickups
  let pr = scanPickups(pickups, player.x, player.y, baseMagnet * st.magnet)
  for i in pr.magnetize:
    session.insert(pickups[i].id, Magnetized, true)
  for i in pr.collected:
    let p = pickups[i]
    case p.kind
    of GemBlue, GemGreen, GemRed:
      xpGain += p.value
      inc result.gems
    of Chicken:
      heal += chickenHeal
      result.chicken = true
    of Coin:
      goldGain += p.value
      result.coin = true
    of Chest:
      result.chest = true
      let upgradable = session.queryAll(rules.getWeapons).filterIt(it.level < maxWeaponLevel)
      if upgradable.len > 0:
        let w = upgradable[rand(upgradable.high)]
        session.insert(w.id, WeaponLevel, w.level + 1)
      else:
        goldGain += chestGoldFallback
    of Vacuum:
      for g in pickups:
        if g.kind.isGem:
          session.insert(g.id, Magnetized, true)
    session.retractPickup(p.id)

  # 5. write player deltas
  if xpGain > 0:
    session.insert(Player, Xp, player.xp + xpGain)
  if goldGain > 0:
    session.insert(Player, Gold, player.gold + goldGain)
  if result.kills > 0:
    session.insert(Player, Kills, player.kills + result.kills)
  if dmg > 0 or heal > 0:
    session.insert(Player, Hp, min(player.maxHp, player.hp - dmg + heal))

  # 6. targeting for the magic wand
  let near = nearestEnemy(enemies, player.x, player.y)
  session.insert(Global, HasNearest, near.found)
  session.insert(Global, NearestX, near.x)
  session.insert(Global, NearestY, near.y)

# ---------------------------------------------------------------- level-up flow

proc prepareChoices*(session: var Session[Fact, FactMatch]) =
  let owned = session.queryAll(rules.getWeapons).mapIt((it.kind, it.level))
  let ownedPassives = session.queryAll(rules.getPassives).mapIt((it.kind, it.level))
  var choices: Choices
  new(choices)
  choices[] = generateChoices(owned, ownedPassives)
  session.insert(Global, ChoiceList, choices)
  session.insert(Global, SelectedIndex, 0)

proc applyChoice*(session: var Session[Fact, FactMatch], c: Choice) =
  case c.kind
  of NewWeapon:
    session.addWeapon(c.weapon)
  of UpgradeWeapon:
    for w in session.queryAll(rules.getWeapons):
      if w.kind == c.weapon:
        session.insert(w.id, WeaponLevel, c.level)
  of NewPassive:
    session.addPassive(c.passive)
  of UpgradePassive:
    for p in session.queryAll(rules.getPassives):
      if p.kind == c.passive:
        session.insert(p.id, PassiveLevel, c.level)
  of BonusGold:
    session.insert(Player, Gold, session.query(rules.getPlayer).gold + 25)
  of BonusHeal:
    let p = session.query(rules.getPlayer)
    session.insert(Player, Hp, min(p.maxHp, p.hp + chickenHeal))
  session.recomputeStats()
```

- [ ] **Step 5: Run tests**

Run: `nimble test`
Expected: all tests `[OK]`.

If `fireRules` raises the recursion-limit error in "gems give xp", the `levelUp` rule re-fired too often: confirm `Xp` is the only tuple without `then = false`.

- [ ] **Step 6: Commit**

```bash
git add src/rules.nim tests/test_rules.nim
git commit -m "feat: per-tick systems step, level-up flow, player death"
```

---

### Task 8: Assets and credits

**Files:**
- Create: `tools/fetch_assets.sh`, `src/assets/CREDITS.md`
- Generated (committed): `src/assets/{otto,imma,lina,gino,skeleton,zombie,mudman,ghost,reaper,bat,koalio,parakeet,grass}.png`, `src/assets/Roboto-Regular.ttf`, `src/assets/CREDITS-lpc.csv`, `src/assets/CREDITS-lpc-base.txt`

- [ ] **Step 1: Write the script**

`tools/fetch_assets.sh`:
```bash
#!/usr/bin/env bash
# Builds src/assets from upstream sources. Needs: curl, unzip, ImageMagick 7 (magick).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=src/assets
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

LPC_REPO=https://raw.githubusercontent.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator/master
LPC=$LPC_REPO/spritesheets
USED_LPC=()

fetch() { curl -fsSL "$1" -o "$2"; }

# compose NAME LAYER... : flattens LPC walk sheets (576x256) in the given order
compose() {
  local name=$1; shift
  local layers=()
  for rel in "$@"; do
    local f="$TMP/$(echo "$rel" | tr '/' '_')"
    [ -f "$f" ] || fetch "$LPC/$rel" "$f"
    layers+=("$f")
    USED_LPC+=("$rel")
  done
  magick "${layers[@]}" -background none -layers flatten "PNG32:$OUT/$name.png"
  echo "composed $name"
}

# --- player characters (body -> legs -> torso -> head -> hair)
compose otto body/bodies/male/walk.png legs/pants/male/walk.png torso/clothes/longsleeve/longsleeve/male/walk.png head/heads/human/male/walk.png hair/bedhead/adult/walk.png
compose imma body/bodies/female/walk.png legs/skirts/plain/thin/walk.png torso/clothes/longsleeve/longsleeve/female/walk.png head/heads/human/female/walk.png hair/bob/adult/walk.png
compose lina body/bodies/female/walk.png legs/pantaloons/thin/walk.png torso/clothes/shortsleeve/shortsleeve/female/walk.png head/heads/human/female/walk.png hair/bangs/adult/walk.png
compose gino body/bodies/male/walk.png legs/pants/male/walk.png torso/clothes/shortsleeve/shortsleeve/male/walk.png head/heads/human/male/walk.png hair/balding/adult/walk.png

# --- enemies
compose skeleton body/bodies/skeleton/walk.png
compose zombie body/bodies/zombie/walk/zombie.png
compose reaper_base body/bodies/skeleton/walk.png hat/cloth/hood/adult/walk.png
magick "$OUT/reaper_base.png" -fill '#101018' -colorize 75% "PNG32:$OUT/reaper.png"
rm "$OUT/reaper_base.png"
magick "$OUT/zombie.png" -fill '#3a8f2a' -colorize 45% "PNG32:$OUT/mudman.png"
magick "$OUT/zombie.png" -fill white -colorize 70% -channel A -evaluate multiply 0.6 +channel "PNG32:$OUT/ghost.png"

# --- LPC base assets (bat, grass)
fetch "https://opengameart.org/sites/default/files/LPC%20Base%20Assets.zip" "$TMP/lpc.zip"
unzip -oq "$TMP/lpc.zip" -d "$TMP"
magick "$TMP/LPC Base Assets/sprites/monsters/bat.png" "PNG32:$OUT/bat.png"
magick "$TMP/LPC Base Assets/tiles/grass.png" "PNG32:$OUT/grass.png"
cp "$TMP/LPC Base Assets/CREDITS.TXT" "$OUT/CREDITS-lpc-base.txt"

# --- Zach Oakes' sprites (public domain)
fetch https://raw.githubusercontent.com/paranim/paranim_examples/master/super_koalio/src/assets/koalio.png "$OUT/koalio.png"
for i in 1 2 3; do
  fetch "https://raw.githubusercontent.com/paranim/parakeet/master/src/assets/player_walk$i.png" "$TMP/parakeet$i.png"
done
magick "$TMP/parakeet1.png" "$TMP/parakeet2.png" "$TMP/parakeet3.png" +append "PNG32:$OUT/parakeet.png"

# --- font (Apache 2.0)
fetch https://raw.githubusercontent.com/paranim/paranim/master/examples/src/assets/Roboto-Regular.ttf "$OUT/Roboto-Regular.ttf"

# --- credits rows for the LPC layers actually used
fetch "$LPC_REPO/CREDITS.csv" "$TMP/CREDITS.csv"
head -1 "$TMP/CREDITS.csv" > "$OUT/CREDITS-lpc.csv"
for rel in "${USED_LPC[@]}"; do
  grep -F "\"$rel\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" || echo "WARNING: no credits row for $rel" >&2
done

echo "done. sizes:"
file "$OUT"/*.png | sed 's/PNG image data, //' | cut -d, -f1-2
```

- [ ] **Step 2: Run it**

Run: `chmod +x tools/fetch_assets.sh && nimble assets`
Expected output ends with sizes: character/enemy sheets `576 x 256`, `bat.png: 96 x 128`, `grass.png: 96 x 192`, `koalio.png: 128 x 32`, `parakeet.png: 210 x 100`. Any `WARNING: no credits row` means the CSV path format changed — open `$TMP/CREDITS.csv` (re-download it) and adjust the grep pattern; the row must end up in `CREDITS-lpc.csv`.

Visually check `src/assets/otto.png` (open it with `magick display` or the Read tool): 4 rows of a walking man, transparent background.

- [ ] **Step 3: Write CREDITS.md**

`src/assets/CREDITS.md`:
```markdown
# Art and font credits

## Liberated Pixel Cup character sprites (composed by tools/fetch_assets.sh)
- Source: https://github.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator
- License: CC-BY-SA 3.0 / GPL 3.0 / OGA-BY 3.0 (see per-file rows in CREDITS-lpc.csv)
- Sprites by: Johannes Sjölund (wulax), Michael Whitlock (bigbeargames), Matthew Krohn (makrohn), Nila122,
  David Conway Jr. (JaidynReiman), Carlo Enrico Victoria (Nemisys), Thane Brimhall (pennomi), laetissima,
  bluecarrot16, Luke Mehl, Benjamin K. Smith (BenCreating), MuffinElZangano, Durrani, kheftel,
  Stephen Challener (Redshrike), William.Thompsonj, Marcel van de Steeg (MadMarcel), TheraHedwig, Evert,
  Pierre Vigier (pvigier), Eliza Wyatt (ElizaWy), Sander Frenken (castelonia), dalonedrau,
  Lanea Zimmerman (Sharm), Manuel Riecke (MrBeast), Barbara Riviera, Joe White, Mandi Paugh, Shaun Williams,
  Daniel Eddeland (daneeklu), Emilio J. Sanchez-Sierra, drjamgo, gr3yh47, tskaufma, Fabzy, Yamilian, Skorpio,
  Tuomo Untinen (reemax), Tracy, thecilekli, LordNeo, Stafford McIntyre, PlatForge project, DCSS authors,
  DarkwallLKE, Charles Sanchez (CharlesGabriel), Radomir Dopieralski, macmanmatty,
  Cobra Hubbard (BlueVortexGames), Inboxninja, kcilds/Rocetti/Eredah, Napsio (Vitruvian Studio), The Foreman, AntumDeluge
- Sprites contributed as part of the Liberated Pixel Cup project from OpenGameArt.org: http://opengameart.org/content/lpc-collection
- The composed PNGs in this directory (otto, imma, lina, gino, skeleton, zombie, mudman, ghost, reaper) are
  derivative works released under CC-BY-SA 3.0.

## LPC Base Assets (bat.png, grass.png)
- https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles
- License: CC-BY-SA 3.0 / GPL 3.0. Authors in CREDITS-lpc-base.txt (bat by Lanea Zimmerman / Charles Sanchez et al.).

## koalio.png, parakeet.png
- Zach Oakes, from https://github.com/paranim/paranim_examples and https://github.com/paranim/parakeet (public domain / Unlicense).

## Roboto-Regular.ttf
- Google, Apache License 2.0.
```

- [ ] **Step 4: Commit**

```bash
git add tools/fetch_assets.sh src/assets
git commit -m "feat: asset pipeline for LPC sprites, tiles, font and credits"
```

---

### Task 9: Rendering the run

**Files:**
- Create: `src/render.nim`
- Modify: `src/core.nim` (replace stub)

**Interfaces:**
- Produces: `render.initRender[G](game: var G)`, `render.drawFrame[G](game: G)`.
- `core.tick` becomes: insert time → fireRules → stepSystems → fireRules → drawFrame (menus come in Task 10; for now the game auto-starts a run with Otto so this task is visually verifiable).

- [ ] **Step 1: Write render.nim**

`src/render.nim`:
```nim
## Everything that touches OpenGL. Reads state from the pararules session.

import paranim/opengl
import paranim/gl, paranim/gl/entities
import paranim/glm
import paranim/math as pmath
from paranim/primitives import nil
import paratext, paratext/gl/text
import stb_image/read as stbi
import pararules
import tables, math, strutils, sequtils
import data, systems, rules

const
  frameSecs = 0.1
  fontPx = 24
  tileSize = 32.0
  groundCols = 64
  groundRows = 40
  white = vec4(1f, 1f, 1f, 1f)
  yellow = vec4(1f, 0.9f, 0.3f, 1f)
  sheetFiles = {
    "otto": (staticRead("assets/otto.png"), 64, 64),
    "imma": (staticRead("assets/imma.png"), 64, 64),
    "lina": (staticRead("assets/lina.png"), 64, 64),
    "gino": (staticRead("assets/gino.png"), 64, 64),
    "zombie": (staticRead("assets/zombie.png"), 64, 64),
    "skeleton": (staticRead("assets/skeleton.png"), 64, 64),
    "mudman": (staticRead("assets/mudman.png"), 64, 64),
    "ghost": (staticRead("assets/ghost.png"), 64, 64),
    "reaper": (staticRead("assets/reaper.png"), 64, 64),
    "bat": (staticRead("assets/bat.png"), 32, 32),
    "koalio": (staticRead("assets/koalio.png"), 18, 26),
    "parakeet": (staticRead("assets/parakeet.png"), 70, 100),
  }
  grassPng = staticRead("assets/grass.png")
  ttf = staticRead("assets/Roboto-Regular.ttf")

type
  Sheet = object
    frameW, frameH: int
    base: UncompiledImageEntity
    batch: InstancedImageEntity

var
  sheets: Table[string, Sheet]
  shapeBase: UncompiledTwoDEntity
  shapes: InstancedTwoDEntity
  ground: InstancedImageEntity
  textBase: UncompiledTextEntity
  textBatch: InstancedTextEntity

let font = initFont(ttf = ttf, fontHeight = fontPx, firstChar = 32, bitmapWidth = 512, bitmapHeight = 512, charCount = 96)

# ---------------------------------------------------------------- loading

proc loadImage(png: string): UncompiledImageEntity =
  var width, height, channels: int
  let data = stbi.loadFromMemory(cast[seq[uint8]](png), width, height, channels, stbi.RGBA)
  initImageEntity(data, width, height)

proc initRender*[G](game: var G) =
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  for (name, entry) in sheetFiles:
    let base = loadImage(entry[0])
    sheets[name] = Sheet(frameW: entry[1], frameH: entry[2], base: base,
                         batch: compile(game, initInstancedEntity(base)))
  shapeBase = initTwoDEntity(primitives.rectangle[GLfloat]())
  shapes = compile(game, initInstancedEntity(shapeBase))
  block:
    let grass = loadImage(grassPng)
    var inst = initInstancedEntity(grass)
    for i in 0 ..< groundCols:
      for j in 0 ..< groundRows:
        var e = grass
        e.crop(tileSize, tileSize, tileSize, tileSize) # centre tile of the 3x3 grass block
        e.translate(float(i) * tileSize, float(j) * tileSize)
        e.scale(tileSize, tileSize)
        inst.add(e)
    ground = compile(game, inst)
  textBase = initTextEntity(font)
  textBatch = compile(game, initInstancedEntity(textBase))

# ---------------------------------------------------------------- batches

proc clear(b: var InstancedImageEntity) =
  b.attributes.a_matrix.data[].setLen(0)
  b.attributes.a_texture_matrix.data[].setLen(0)
  b.instanceCount = 0

proc clear(b: var InstancedTwoDEntity) =
  b.attributes.a_matrix.data[].setLen(0)
  b.attributes.a_color.data[].setLen(0)
  b.instanceCount = 0

proc clear(b: var InstancedTextEntity) =
  b.attributes.a_translate_matrix.data[].setLen(0)
  b.attributes.a_scale_matrix.data[].setLen(0)
  b.attributes.a_texture_matrix.data[].setLen(0)
  b.attributes.a_color.data[].setLen(0)
  b.instanceCount = 0

proc addSprite(name: string, col, row: int, cx, cy, w, h: float, flip = false) =
  var e = sheets[name].base
  let fw = float(sheets[name].frameW)
  let fh = float(sheets[name].frameH)
  e.crop(float(col) * fw, float(row) * fh, fw, fh)
  if flip:
    e.translate(cx + w / 2, cy - h / 2)
    e.scale(-w, h)
  else:
    e.translate(cx - w / 2, cy - h / 2)
    e.scale(w, h)
  sheets[name].batch.add(e)

proc flushSprites[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat]) =
  for name, sh in sheets.mpairs:
    if sh.batch.attributes.a_matrix.data[].len == 0:
      continue
    var b = sh.batch
    b.project(ww, wh)
    b.invert(camera)
    render(game, b)
    sh.batch.clear()

proc addRect*(cx, cy, w, h, angle: float, color: Vec4[GLfloat]) =
  var e = shapeBase
  e.translate(cx, cy)
  e.rotate(angle)
  e.translate(-w / 2, -h / 2)
  e.scale(w, h)
  e.color(color)
  shapes.add(e)

proc flushShapes[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat], useCamera: bool) =
  if shapes.attributes.a_matrix.data[].len == 0:
    return
  var s = shapes
  s.project(ww, wh)
  if useCamera:
    s.invert(camera)
  render(game, s)
  shapes.clear()

proc textWidth*(s: string, scale = 1.0): float =
  for ch in s:
    let idx = int(ch) - font.firstChar
    if idx >= 0 and idx < 96:
      result += font.chars[idx].xadvance * scale

proc drawText*[G](game: G, s: string, x, y, ww, wh: float, color = white, scale = 1.0) =
  textBatch.clear()
  var cx = 0f
  for ch in s:
    let idx = int(ch) - font.firstChar
    if idx < 0 or idx >= 96:
      continue
    let bc = font.chars[idx]
    var e = textBase
    e.crop(bc, cx, font.baseline)
    e.color(color)
    textBatch.add(e)
    cx += bc.xadvance
  if cx == 0:
    return
  var t = textBatch
  t.project(ww, wh)
  t.translate(x, y)
  t.scale(scale, scale)
  render(game, t)

proc drawTextCentered*[G](game: G, s: string, cy, ww, wh: float, color = white, scale = 1.0) =
  drawText(game, s, ww / 2 - textWidth(s, scale) / 2, cy, ww, wh, color, scale)

# ---------------------------------------------------------------- world

proc dirRow(dx, dy: float): int =
  if abs(dx) > abs(dy):
    (if dx < 0: Left.ord else: Right.ord)
  else:
    (if dy < 0: Up.ord else: Down.ord)

proc drawGround[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat], px, py: float) =
  var g = ground
  g.project(ww, wh)
  g.invert(camera)
  g.translate(floor((px - ww / 2) / tileSize) * tileSize - tileSize,
              floor((py - wh / 2) / tileSize) * tileSize - tileSize)
  render(game, g)

proc pickupColor(kind: PickupKind): Vec4[GLfloat] =
  case kind
  of GemBlue: vec4(0.3f, 0.6f, 1f, 1f)
  of GemGreen: vec4(0.3f, 1f, 0.4f, 1f)
  of GemRed: vec4(1f, 0.3f, 0.3f, 1f)
  of Chicken: vec4(1f, 0.75f, 0.4f, 1f)
  of Coin: vec4(1f, 0.85f, 0.1f, 1f)
  of Chest: vec4(0.6f, 0.35f, 0.1f, 1f)
  of Vacuum: vec4(0.8f, 0.3f, 1f, 1f)

proc projColor(kind: WeaponKind): Vec4[GLfloat] =
  case kind
  of Whip: vec4(1f, 1f, 1f, 0.7f)
  of MagicWand: vec4(0.5f, 0.7f, 1f, 1f)
  of Knife: vec4(0.85f, 0.85f, 0.9f, 1f)
  of Axe: vec4(0.7f, 0.5f, 0.3f, 1f)
  of Runetracer: vec4(0.4f, 1f, 0.6f, 1f)
  of Garlic: vec4(1f, 1f, 0.8f, 0.25f)
  of KingBible: vec4(0.9f, 0.8f, 0.5f, 1f)

proc drawWorld[G](game: G, ww, wh, tt: float) =
  let player = session.query(rules.getPlayer)
  var camera = mat3f(1)
  camera.translate(player.x - ww / 2, player.y - wh / 2)
  let minX = player.x - ww / 2 - 100
  let maxX = player.x + ww / 2 + 100
  let minY = player.y - wh / 2 - 100
  let maxY = player.y + wh / 2 + 100

  drawGround(game, ww, wh, camera, player.x, player.y)

  # pickups
  for p in session.queryAll(rules.getPickups):
    if p.x < minX or p.x > maxX or p.y < minY or p.y > maxY:
      continue
    case p.kind
    of GemBlue, GemGreen, GemRed:
      addRect(p.x, p.y, 10, 10, PI / 4, pickupColor(p.kind))
    of Chest:
      addRect(p.x, p.y, 28, 20, 0, pickupColor(p.kind))
    else:
      addRect(p.x, p.y, 16, 16, 0, pickupColor(p.kind))
  # garlic aura (drawn as two rotated squares)
  for w in session.queryAll(rules.getWeapons):
    if w.kind == Garlic:
      let r = weaponAt(Garlic, w.level).size * session.query(rules.getStats).stats.area
      addRect(player.x, player.y, r * 2, r * 2, 0, projColor(Garlic))
      addRect(player.x, player.y, r * 2, r * 2, PI / 4, projColor(Garlic))
  flushShapes(game, ww, wh, camera, true)

  # enemies
  let enemies = session.queryAll(rules.getEnemies)
  for e in enemies:
    if e.x < minX or e.x > maxX or e.y < minY or e.y > maxY:
      continue
    let d = enemyDefs[e.kind]
    let sh = sheets[d.sheet]
    let h = d.size
    let w = h * float(sh.frameW) / float(sh.frameH)
    let dx = player.x - e.x
    let dy = player.y - e.y
    let phase = int(tt / frameSecs) + e.id
    case e.kind
    of Bat:
      addSprite(d.sheet, phase mod 3, 0, e.x, e.y, w, h)
    of Koalio:
      addSprite(d.sheet, 2 + phase mod 3, 0, e.x, e.y, w, h, flip = dx < 0)
    of Parakeet:
      addSprite(d.sheet, phase mod 3, 0, e.x, e.y, w, h, flip = dx < 0)
    else:
      addSprite(d.sheet, 1 + phase mod 8, dirRow(dx, dy), e.x, e.y, w, h)
  # player
  block:
    let sheet = characterDefs[player.hero].sheet
    let col = if player.moving: 1 + int(tt / frameSecs) mod 8 else: 0
    addSprite(sheet, col, player.facing.ord, player.x, player.y, 64, 64)
  flushSprites(game, ww, wh, camera)

  # projectiles and hit flashes
  for p in session.queryAll(rules.getProjectiles):
    case p.kind
    of Whip:
      addRect(p.x, p.y, p.size, 12, 0, projColor(Whip))
    of Knife:
      addRect(p.x, p.y, 22, 6, p.angle, projColor(Knife))
    of Axe:
      addRect(p.x, p.y, p.size * 1.4, p.size * 1.4, p.angle, projColor(Axe))
    of Garlic:
      discard
    else:
      addRect(p.x, p.y, p.size * 1.6, p.size * 1.6, p.angle, projColor(p.kind))
  for e in enemies:
    if e.hitFlash > 0 and e.x >= minX and e.x <= maxX and e.y >= minY and e.y <= maxY:
      addRect(e.x, e.y, e.size * 0.6, e.size * 0.6, 0, vec4(1f, 1f, 1f, 0.6f))
  # hp bar under the player
  addRect(player.x, player.y + 38, 40, 6, 0, vec4(0.3f, 0f, 0f, 0.9f))
  let hpFrac = max(0.0, player.hp / player.maxHp)
  addRect(player.x - 20 + 20 * hpFrac, player.y + 38, 40 * hpFrac, 6, 0, vec4(0.2f, 0.9f, 0.2f, 0.9f))
  flushShapes(game, ww, wh, camera, true)

proc drawHud[G](game: G, ww, wh, gameTime: float) =
  let player = session.query(rules.getPlayer)
  let noCam = mat3f(1)
  addRect(ww / 2, 10, ww, 20, 0, vec4(0.05f, 0.05f, 0.1f, 0.9f))
  let frac = min(1.0, float(player.xp) / float(max(1, player.xpToNext)))
  addRect(ww * frac / 2, 10, ww * frac, 20, 0, vec4(0.3f, 0.5f, 1f, 1f))
  flushShapes(game, ww, wh, noCam, false)
  drawText(game, "LV " & $player.level, ww - 90, 0, ww, wh)
  drawTextCentered(game, clockText(gameTime), 24, ww, wh, scale = 1.3)
  drawText(game, "Kills " & $player.kills & "   Gold " & $player.gold, 10, 24, ww, wh, yellow)
  var y = wh - 30
  for w in session.queryAll(rules.getWeapons):
    drawText(game, weaponDefs[w.kind].name & " " & $w.level, 10, y, ww, wh, white, 0.8)
    y -= 22
  y = wh - 30
  for p in session.queryAll(rules.getPassives):
    drawText(game, passiveDefs[p.kind].name & " " & $p.level, 200, y, ww, wh, white, 0.8)
    y -= 22

proc drawOverlay[G](game: G, ww, wh: float, alpha = 0.7f) =
  addRect(ww / 2, wh / 2, ww, wh, 0, vec4(0f, 0f, 0f, alpha))
  flushShapes(game, ww, wh, mat3f(1), false)

proc drawLevelUp[G](game: G, ww, wh: float) =
  drawOverlay(game, ww, wh)
  drawTextCentered(game, "LEVEL UP!", wh / 2 - 150, ww, wh, yellow, 1.5)
  let m = session.query(rules.getMenu)
  if m.choices == nil:
    return
  for i, c in m.choices[]:
    let y = wh / 2 - 70 + float(i) * 70
    let marker = if i == m.selected: "> " else: "  "
    drawText(game, marker & c.title, ww / 2 - 200, y, ww, wh, if i == m.selected: yellow else: white)
    drawText(game, c.desc, ww / 2 - 170, y + 26, ww, wh, white, 0.8)
  drawTextCentered(game, "Up/Down + Enter, or 1/2/3", wh - 60, ww, wh, white, 0.8)

proc drawPaused[G](game: G, ww, wh: float) =
  drawOverlay(game, ww, wh, 0.5f)
  drawTextCentered(game, "PAUSED", wh / 2 - 20, ww, wh, yellow, 2.0)

proc drawGameOver[G](game: G, ww, wh: float) =
  drawOverlay(game, ww, wh)
  let m = session.query(rules.getMenu)
  let p = session.query(rules.getPlayer)
  drawTextCentered(game, m.resultText, wh / 2 - 80, ww, wh, yellow, 1.5)
  drawTextCentered(game, "Level " & $p.level & "   Kills " & $p.kills & "   Gold " & $p.gold, wh / 2, ww, wh)
  drawTextCentered(game, "Press R to retry", wh / 2 + 60, ww, wh)

proc drawTitle[G](game: G, ww, wh: float) =
  drawTextCentered(game, "PARASURVIVORS", wh / 2 - 120, ww, wh, yellow, 2.5)
  drawTextCentered(game, "Press Enter", wh / 2, ww, wh)
  drawTextCentered(game, "Art: Liberated Pixel Cup contributors (CC-BY-SA 3.0), see CREDITS.md", wh - 40, ww, wh, white, 0.7)

proc drawCharSelect[G](game: G, ww, wh: float) =
  drawTextCentered(game, "Choose your survivor", 80, ww, wh, yellow, 1.5)
  let m = session.query(rules.getMenu)
  for i, hero in [Otto, Imma, Lina, Gino]:
    let c = characterDefs[hero]
    let y = 180 + float(i) * 90
    let marker = if i == m.selected: "> " else: "  "
    drawText(game, marker & c.name & "  -  " & weaponDefs[c.weapon].name & "  -  " & c.perk, ww / 2 - 260, y, ww, wh,
             if i == m.selected: yellow else: white)
    addSprite(c.sheet, 0, Down.ord, ww / 2 - 300, y + 12, 64, 64)
  flushSprites(game, ww, wh, mat3f(1))
  drawTextCentered(game, "Up/Down + Enter", wh - 60, ww, wh, white, 0.8)

# ---------------------------------------------------------------- frame

proc drawFrame*[G](game: G) =
  let (windowWidth, windowHeight) = session.query(rules.getWindow)
  let (ww, wh) = session.query(rules.getWorld)
  let (phase) = session.query(rules.getPhase)
  let (tt, gameTime) = session.query(rules.getTime)
  glClearColor(0.16, 0.22, 0.12, 1f)
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowWidth), int32(windowHeight))
  case phase
  of Title:
    drawTitle(game, ww, wh)
  of CharSelect:
    drawCharSelect(game, ww, wh)
  of Running:
    drawWorld(game, ww, wh, tt)
    drawHud(game, ww, wh, gameTime)
  of LevelUp:
    drawWorld(game, ww, wh, tt)
    drawHud(game, ww, wh, gameTime)
    drawLevelUp(game, ww, wh)
  of Paused:
    drawWorld(game, ww, wh, tt)
    drawHud(game, ww, wh, gameTime)
    drawPaused(game, ww, wh)
  of GameOver:
    drawWorld(game, ww, wh, tt)
    drawGameOver(game, ww, wh)
```

Notes for the implementer:
- `e.crop(bc, cx, font.baseline)` is paratext's `crop` overload for `BakedChar` (see `paratext/gl/text.nim` near the bottom and `examples/src/ex27_text.nim`).
- If `for (name, entry) in sheetFiles` does not compile because the const is an array of tuples, use `for pair in sheetFiles: let name = pair[0]; let entry = pair[1]`.
- If `sheets.mpairs` complains, iterate `for name in toSeq(sheets.keys)` and index `sheets[name]`.
- The bat sheet rows may not be ordered up/left/down/right; only row 0 is used.

- [ ] **Step 2: Replace core.nim so a run starts immediately (menus in Task 10)**

`src/core.nim`:
```nim
import paranim/opengl
import paranim/gl
import pararules
import sets, random
import data, systems, rules, render

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float

proc onKeyPress*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.incl(key)
  session.insert(Global, PressedKeys, keys)
  var (just) = session.query(rules.getJustPressed)
  just.incl(key)
  session.insert(Global, JustPressed, just)

proc onKeyRelease*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.excl(key)
  session.insert(Global, PressedKeys, keys)

proc onWindowResize*(windowWidth, windowHeight, worldWidth, worldHeight: int) =
  if windowWidth == 0 or windowHeight == 0:
    return
  session.insert(Global, WindowWidth, windowWidth)
  session.insert(Global, WindowHeight, windowHeight)
  session.insert(Global, WorldWidth, float(worldWidth) / zoom)
  session.insert(Global, WorldHeight, float(worldHeight) / zoom)

proc init*(game: var Game) =
  doAssert glInit()
  randomize()
  initRender(game)
  session.startRun(Otto) # temporary: Task 10 replaces this with the title flow

proc tick*(game: var Game) =
  session.insert(Global, TotalTime, game.totalTime)
  let (phase) = session.query(rules.getPhase)
  if phase == Running:
    session.insert(Global, DeltaTime, game.deltaTime)
    session.fireRules()
    discard session.stepSystems(game.deltaTime)
    session.fireRules()
    let m = session.query(rules.getMenu)
    if m.pending > 0:
      session.prepareChoices()
      session.insert(Global, Phase, LevelUp)
  session.insert(Global, JustPressed, initHashSet[int]())
  drawFrame(game)
```

- [ ] **Step 3: Build and look**

Run: `nimble build && ./parasurvivors`
Expected: grass field, Otto in the middle walking with WASD/arrows with a 4-direction LPC walk cycle, bats flying in from the edges, whip flashes killing them, blue gems appearing and flying to the player, XP bar filling, clock ticking. After the first level the screen darkens with "LEVEL UP!" and three options (input for it comes in Task 10; kill the window with Escape from the terminal `Ctrl-C`).

Check the terminal for a pararules recursion error or a `query` failure; both mean a rule mutates without `then = false` or a fact is missing from `newSession`/`startRun`.

- [ ] **Step 4: Commit**

```bash
git add src/render.nim src/core.nim
git commit -m "feat: render ground, sprites, projectiles, pickups and HUD"
```

---

### Task 10: Screens and input flow

**Files:**
- Modify: `src/core.nim`

- [ ] **Step 1: Replace `init` and `tick` with the phase machine**

```nim
proc init*(game: var Game) =
  doAssert glInit()
  randomize()
  initRender(game)

proc pressed(just: HashSet[int], keys: varargs[int]): bool =
  for k in keys:
    if just.contains(k):
      return true
  false

proc moveSelection(just: HashSet[int], count: int) =
  let m = session.query(rules.getMenu)
  var sel = m.selected
  if just.pressed(KeyUp, KeyW): sel = (sel + count - 1) mod count
  if just.pressed(KeyDown, KeyS): sel = (sel + 1) mod count
  if sel != m.selected:
    session.insert(Global, SelectedIndex, sel)

proc finishChoice(index: int) =
  let m = session.query(rules.getMenu)
  if m.choices == nil or index >= m.choices[].len:
    return
  session.applyChoice(m.choices[][index])
  let pending = m.pending - 1
  session.insert(Global, PendingLevelUps, pending)
  if pending > 0:
    session.prepareChoices()
  else:
    session.insert(Global, Phase, Running)

proc tick*(game: var Game) =
  session.insert(Global, TotalTime, game.totalTime)
  let (phase) = session.query(rules.getPhase)
  let (just) = session.query(rules.getJustPressed)
  case phase
  of Title:
    if just.pressed(KeyEnter, KeySpace):
      session.insert(Global, SelectedIndex, 0)
      session.insert(Global, Phase, CharSelect)
  of CharSelect:
    moveSelection(just, 4)
    if just.pressed(KeyEnter, KeySpace):
      let m = session.query(rules.getMenu)
      session.startRun(CharacterKind(m.selected))
  of Running:
    if just.pressed(KeyEscape, KeyP):
      session.insert(Global, Phase, Paused)
    else:
      session.insert(Global, DeltaTime, game.deltaTime)
      session.fireRules()
      discard session.stepSystems(game.deltaTime)
      session.fireRules()
      let m = session.query(rules.getMenu)
      if m.pending > 0:
        session.prepareChoices()
        session.insert(Global, Phase, LevelUp)
  of LevelUp:
    moveSelection(just, 3)
    if just.pressed(Key1): finishChoice(0)
    elif just.pressed(Key2): finishChoice(1)
    elif just.pressed(Key3): finishChoice(2)
    elif just.pressed(KeyEnter, KeySpace): finishChoice(session.query(rules.getMenu).selected)
  of Paused:
    if just.pressed(KeyEscape, KeyP):
      session.insert(Global, Phase, Running)
  of GameOver:
    if just.pressed(KeyR, KeyEnter):
      session = session.resetSession()
      session.insert(Global, Phase, CharSelect)
  session.insert(Global, JustPressed, initHashSet[int]())
  drawFrame(game)
```

`moveSelection` with count 3 must not exceed the number of choices when the fallback offers only 2: `finishChoice` already guards `index >= len`, and the marker just won't match a row. Acceptable.

- [ ] **Step 2: Build and play**

Run: `nimble build && ./parasurvivors`
Expected flow: title → Enter → character list with sprites, Up/Down moves the marker → Enter starts → level up shows 3 options selectable by 1/2/3 or Up/Down+Enter → Escape pauses/resumes → dying shows the result and R returns to character select with a clean world.

- [ ] **Step 3: Quick 30-minute sanity run**

Run: `nim c -d:fastclock -d:release --outdir:tmp src/parasurvivors.nim && ./tmp/parasurvivors`
Expected: the clock runs 10×; bosses appear at 3, 8, 12, 15, 20, 25 min (Giant Parakeet, Koalio); the Reaper at 30:00 and death → "You survived until dawn!". Watch the terminal for any exception.

- [ ] **Step 4: Commit**

```bash
git add src/core.nim
git commit -m "feat: title, character select, level-up, pause and game-over flow"
```

---

### Task 11: Generated audio

**Files:**
- Create: `src/audio.nim`
- Modify: `src/core.nim`

**Interfaces:**
- Produces: `Sfx` enum, `initAudio()`, `play(Sfx)`, `startMusic()`, `stopMusic()`.

- [ ] **Step 1: Write audio.nim**

```nim
## All sound is synthesised at startup: paramidi scores → PCM → WAV bytes → miniaudio sounds.

type
  Sfx* = enum
    SfxHit, SfxGem, SfxLevelUp, SfxHurt, SfxBoss, SfxChest, SfxMusic

when defined(noaudio):
  proc initAudio*() = discard
  proc play*(s: Sfx) = discard
  proc startMusic*() = discard
  proc stopMusic*() = discard
else:
  import parasound/miniaudio, parasound/dr_wav
  import paramidi, paramidi/tsf, paramidi_soundfonts

  # bindings parasound does not expose; the symbols live in its compiled miniaudio.c
  proc ma_sound_seek_to_pcm_frame(pSound: pointer, frameIndex: uint64): ma_result {.cdecl, importc.}
  proc ma_sound_set_looping(pSound: pointer, isLooping: uint32) {.cdecl, importc.}
  proc ma_sound_set_volume(pSound: pointer, volume: cfloat) {.cdecl, importc.}

  const sampleRate = 44100

  var
    engine: seq[uint8]
    wavs: array[Sfx, seq[uint8]]
    decoders: array[Sfx, seq[uint8]]
    sounds: array[Sfx, seq[uint8]]
    ready = false

  proc toWav(data: var seq[cshort]): seq[uint8] =
    # same as parasound/tests/common.nim writeMemory
    var
      wav = newSeq[uint8](drwav_size())
      format: drwav_data_format
    format.container = drwav_container_riff
    format.format = DR_WAVE_FORMAT_PCM
    format.channels = 1
    format.sampleRate = sampleRate
    format.bitsPerSample = 16
    var
      outputRaw: pointer
      outputSize: csize_t
    let frames = data.len.uint32
    doAssert drwav_init_memory_write_sequential(wav[0].addr, outputRaw.addr, outputSize.addr, format.addr, frames, nil)
    doAssert frames == drwav_write_pcm_frames(wav[0].addr, frames, data[0].addr)
    result = newSeq[uint8](outputSize)
    copyMem(result[0].addr, outputRaw, outputSize)
    drwav_free(outputRaw, nil)
    discard drwav_uninit(wav[0].addr)

  proc renderScore(sf: ptr tsf, events: seq[Event]): seq[uint8] =
    var res = render[cshort](events, sf, sampleRate)
    toWav(res.data)

  proc initAudio*() =
    engine = newSeq[uint8](ma_engine_size())
    if MA_SUCCESS != ma_engine_init(nil, engine[0].addr):
      echo "audio: engine init failed, continuing silently"
      return
    when defined(release):
      const soundfont = staticRead("paramidi_soundfonts/generaluser.sf2")
      var sf = tsf_load_memory(soundfont.cstring, soundfont.len.cint)
    else:
      let path = paramidi_soundfonts.getSoundFontPath("generaluser.sf2")
      var sf = tsf_load_filename(path.cstring)
    if sf == nil:
      echo "audio: soundfont not found, continuing silently"
      return
    tsf_set_output(sf, TSF_MONO, sampleRate, 0)
    wavs[SfxHit] = renderScore(sf, compile((marimba, (octave: 5), 1/32, c)))
    wavs[SfxGem] = renderScore(sf, compile((glockenspiel, (octave: 6), 1/32, e, g)))
    wavs[SfxLevelUp] = renderScore(sf, compile((glockenspiel, (octave: 5), 1/16, c, e, g, +c)))
    wavs[SfxHurt] = renderScore(sf, compile((timpani, (octave: 2), 1/16, c)))
    wavs[SfxBoss] = renderScore(sf, compile((orchestra_hit, (octave: 3), 1/8, c)))
    wavs[SfxChest] = renderScore(sf, compile((tubular_bells, (octave: 4), 1/8, c, 1/4, g)))
    wavs[SfxMusic] = renderScore(sf, compile(
      ((mode: concurrent),
       (piano, (tempo: 150), (octave: 3), 1/8,
        a, e, +a, e, +c, e, +a, e,
        f, +c, +f, +c, +d, +c, +f, +c,
        g, +d, +g, +d, +b, +d, +g, +d,
        e, b, +e, b, +gx, b, +e, b),
       (synth_bass_1, (tempo: 150), (octave: 2), 1/4,
        a, a, f, f, g, g, e, e))))
    tsf_close(sf)
    for s in Sfx:
      decoders[s] = newSeq[uint8](ma_decoder_size())
      if MA_SUCCESS != ma_decoder_init_memory(wavs[s][0].addr, wavs[s].len.csize_t, nil, decoders[s][0].addr):
        echo "audio: decoder failed for ", s
        return
      sounds[s] = newSeq[uint8](ma_sound_size())
      if MA_SUCCESS != ma_sound_init_from_data_source(engine[0].addr, decoders[s][0].addr, 0, nil, sounds[s][0].addr):
        echo "audio: sound failed for ", s
        return
      ma_sound_set_volume(sounds[s][0].addr, if s == SfxMusic: 0.35 elif s == SfxHit: 0.4 else: 0.8)
    ma_sound_set_looping(sounds[SfxMusic][0].addr, 1)
    ready = true

  proc play*(s: Sfx) =
    if not ready:
      return
    discard ma_sound_seek_to_pcm_frame(sounds[s][0].addr, 0)
    discard ma_sound_start(sounds[s][0].addr)

  proc startMusic*() =
    if ready:
      discard ma_sound_start(sounds[SfxMusic][0].addr)

  proc stopMusic*() =
    if ready:
      discard ma_sound_stop(sounds[SfxMusic][0].addr)
```

If `(mode: concurrent)` nesting fails to compile, drop the bass line and pass only the piano tuple.
If `+c` inside the tuple is rejected, replace with `c5` style absolute octave notes (README shows both forms).

- [ ] **Step 2: Hook into core**

In `src/core.nim`: add `import audio`; in `init` call `initAudio()` after `initRender(game)`; in `tick`:
- `CharSelect` Enter → after `startRun` call `startMusic()`.
- `Running` branch: capture `let ev = session.stepSystems(game.deltaTime)` and then
  ```nim
  if ev.hits > 0: play(SfxHit)
  if ev.gems > 0: play(SfxGem)
  if ev.hurt: play(SfxHurt)
  if ev.chest: play(SfxChest)
  if ev.bossKilled: play(SfxBoss)
  ```
  and when `m.pending > 0` also `play(SfxLevelUp)`.
- `GameOver` entry: detect the transition by checking `phase == GameOver` and a module-level `var musicOn = false` toggled by `startMusic`/`stopMusic`; call `stopMusic()` once.

- [ ] **Step 3: Build and listen**

Run: `nimble build && ./parasurvivors`
Expected: startup takes a second longer (rendering the scores), music loops from the start of a run, hits click, gems chime, level-up arpeggio, low thump when hurt.

Run: `nim c -d:noaudio --outdir:tmp src/parasurvivors.nim`
Expected: compiles and runs silently.

Run: `nimble test`
Expected: still all `[OK]` (tests define `noaudio`).

- [ ] **Step 4: Commit**

```bash
git add src/audio.nim src/core.nim
git commit -m "feat: paramidi-generated sound effects and music via parasound"
```

---

### Task 12: Separation, performance check, README

**Files:**
- Modify: `src/rules.nim` (stepSystems), `README.md`

- [ ] **Step 1: Apply enemy separation in stepSystems**

After step 2 ("damage, deaths, drops, despawn") add:
```nim
  # 2b. keep enemies from stacking
  for (id, dx, dy) in separate(enemies):
    if session.contains(id, X):
      let e = session.query(rules.getEnemies, id = id)
      session.insert(id, X, e.x + dx)
      session.insert(id, Y, e.y + dy)
```
Run `nimble test` — still green.

- [ ] **Step 2: Measure frame time with 300 enemies**

Add to `core.tick` temporarily (or behind `when defined(perf)`):
```nim
  when defined(perf):
    let (tt, gameTime) = session.query(rules.getTime)
    if int(gameTime) mod 5 == 0 and game.deltaTime > 0:
      echo "t=", clockText(gameTime), " dt=", game.deltaTime * 1000, "ms enemies=", session.query(rules.getTargeting).enemyCount
```
Run: `nim c -d:release -d:fastclock -d:perf --outdir:tmp src/parasurvivors.nim && ./tmp/parasurvivors`
Expected: at 25+ minutes with ~200–300 enemies, `dt` stays under 16 ms. If it doesn't: (a) confirm `-d:release`; (b) reduce `maxEnemies` to 200; (c) as a last resort skip `separate` when `enemies.len > 150`.

- [ ] **Step 3: README**

Append to `README.md`:
```markdown
## Run

    nimble install -d -y
    nimble assets      # downloads and composes sprites (needs curl, unzip, ImageMagick)
    nimble build && ./parasurvivors

Controls: WASD/arrows move, Enter/Space confirm, 1/2/3 pick a level-up, Esc/P pause, R retry.

Flags: `-d:noaudio` (silent), `-d:fastclock` (10× game clock for testing waves), `-d:release`.

## Tests

    nimble test

## How it is put together

- `src/rules.nim` — every piece of game state is a `(id, attribute, value)` fact in a pararules session;
  movement, cooldowns, spawning and level-ups are rules that react to `DeltaTime` and `Xp` changes.
- `src/systems.nim` — the few N×M loops (collision, pickups) as pure procs on plain seqs.
- `src/render.nim` — paranim instanced sprite batches, paratext HUD.
- `src/audio.nim` — paramidi renders every sound effect at startup, parasound plays them.

Art: Liberated Pixel Cup contributors, see `src/assets/CREDITS.md`.
```

- [ ] **Step 4: Commit**

```bash
git add src/rules.nim src/core.nim README.md
git commit -m "feat: enemy separation, perf probe, README"
```

---

## Self-review against the spec

- Stage / clock / Reaper: Task 2 waves+bosses, Task 6 spawnBosses, Task 7 playerDied result text. ✓
- 4 characters, 7 weapons, 7 passives with levels: Task 2, choices Task 3/7. ✓
- Enemies incl. Parakeet/Koalio/Reaper sprites: Task 8 assets, Task 9 frames. ✓
- Pickups (gems, chicken, coin, chest, vacuum): Task 7 stepSystems, Task 6 movePickups. ✓
- Level-up UI / pause / game over / title / char select: Tasks 9–10. ✓
- Audio generated by paramidi, `-d:noaudio`: Task 11. ✓
- Headless tests: Tasks 2–7. ✓
- Credits on title screen: Task 9 `drawTitle`, file in Task 8. ✓
- Not in scope (evolutions, shop, saves, web): none planned. ✓

## Known risks and their fallbacks

| Risk | Fallback |
|---|---|
| `let (initSession, rules*) = ...` export syntax | `let (initSession, rulesInternal) = ...; let rules* = rulesInternal` |
| Helper procs referencing `Session[Fact, FactMatch]` before the ruleset | Move them below the ruleset and inline the inserts inside rule bodies |
| `then` blocks retracting facts | Not done anywhere; all retracts are in `stepSystems` |
| pararules recursion limit | Every rule's non-trigger tuples carry `then = false`; `levelUp` chains at most a few times |
| LPC URL 404 | All URLs in Task 8 verified 2026-09-04; if one breaks, browse the `spritesheets/` tree on GitHub and swap a same-category layer |
| `staticRead("paramidi_soundfonts/generaluser.sf2")` in release | Same line paramidi_starter uses; if it fails, fall back to `getSoundFontPath` at runtime for release too |
| Frame time with 300 enemies | `-d:release`; lower `maxEnemies`; skip `separate` at high counts |
