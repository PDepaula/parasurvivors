# Parasurvivors — LPC weapons, starter attack animations, sprites for everything

Date: 2026-09-04 (revised the same day: added starter attack animations, Lina → War Axe,
spear lunge + returning boomerang, data-driven weapon table, README refresh)
Status: approved in brainstorming, ready for planning
Builds on: `2026-09-04-parasurvivors-design.md` (implemented on `main`)

## 1. Goal

Drop the Vampire Survivors weapon names and every coloured quad. Weapons get Liberated Pixel Cup
(LPC) art, each survivor visibly holds and *uses* their starting weapon, pickups and UI get icons,
and the weapon table becomes data-driven so a new weapon is a table row rather than six `case`
branches.

Decided in brainstorming (do not re-litigate):

- Only the **starter** weapon animates the body. Everything else is auto-fire icons.
- Lina's starter becomes **War Axe** (LPC has no throw animation for the boomerang). Her
  "+20% projectile speed" perk stays: axe arc height scales with speed.
- Two mechanics twists: Dragon Spear lunges in the faced direction (4-way, not horizontal-only);
  Boomerang flies out and returns to the player (replaces the screen-edge bounce).
- "Enemy projectiles" in the request meant the player's projectiles hitting enemies. Enemies get
  no ranged attacks.
- One script-built atlas with a text manifest; UI icons for weapons and passives; README refresh
  is in scope.

## 2. Weapons

| Enum          | Name          | Motion    | Projectile sprite       | Body anim (starter only)            |
|---------------|---------------|-----------|-------------------------|-------------------------------------|
| `DragonSpear` | Dragon Spear  | `Lunge`   | `spear`, rotated to dir | Otto: `AnimThrust`, 8 frames, 0.4 s |
| `ArcaneStaff` | Arcane Staff  | `Homing`  | `bolt` (blue orb)       | Imma: `AnimCast`, 7 frames, 0.35 s  |
| `Longbow`     | Longbow       | `Straight`| `arrow`, rotated        | Gino: `AnimShoot`, 13 frames, 0.5 s |
| `WarAxe`      | War Axe       | `Arc`     | `axe`, spins 10 rad/s   | Lina: `AnimSlash`, 6 frames, 0.3 s  |
| `Boomerang`   | Boomerang     | `Return`  | `boomerang`, spins 12 rad/s | none                            |
| `RoundShield` | Round Shield  | `Orbit`   | `shield`                | none                                |
| `Garlic`      | Garlic        | `Aura`    | `aura` ring α 0.35 + `garlic` icon above the player's head | none |

Descriptions: "Lunges in the faced direction, passes through enemies", "Fires at the nearest
enemy", "Arrows fly in the faced direction", "High damage, arcs overhead", "Flies out and comes
back, hits both ways", "Damages nearby enemies", "Orbits around the character".

Cooldowns are all ≥ 1 s, longer than any body animation, so animations never overlap.

### 2.1 Motions (`systems.attackPlan` spawn pattern + `rules.moveProjectiles` step)

Unchanged from today unless listed: `Homing` (was MagicWand), `Straight` (Knife), `Arc` (Axe),
`Orbit` (KingBible), `Aura` (Garlic).

**Lunge** (replaces Whip). Volley `i` direction: `i = 0` facing, `1` opposite, `2` and `3` the two
perpendiculars, then repeat. Hitbox is a rectangle of length `size` and half-width
`lungeHalfWidth = 24` along that direction, centred `size / 2` from the player. Stationary for its
`ttl`. `Angle` fact holds the direction so render rotates the spear. `hitsEnemy` tests the rotated
rectangle (project the enemy offset onto the direction and its normal).

**Return** (replaces Runetracer). Spawned at the player with velocity `speed` in a random direction
(as now). Each tick velocity gains `boomerangAccel · dt` (constant, 300 px/s²) toward the player's
current position, so at base speed it turns around ≈ 170 px out after ≈ 1.1 s and comes back even if
the player moved; speed upgrades push it farther, ttl upgrades give it the slack to return. New projectile fact `Turned: bool`; when the velocity first points toward the player
(`dot(vel, player − pos) > 0`) set `Turned = true` and clear `HitIds` so the same enemies can be
hit on the way back. Retract when `Turned` and within `boomerangCatchRadius = 20` px of the player,
or when `ttl ≤ 0`.

### 2.2 Weapon table rows

`weaponDefs` / `weaponUpgrades` keep today's numbers under the new enum names, except:
Dragon Spear `size` 100 (matches the LPC thrust reach; upgrades keep their `+size` deltas),
Boomerang `ttl` 3.0 and `speed` 320; ttl upgrades are ordered so `2·speed/boomerangAccel ≤ ttl` at
every level, Lina's +20% included (tested).

## 3. Player attack animation

- New player facts `Anim: BodyAnim` (`NoAnim, AnimThrust, AnimSlash, AnimShoot, AnimCast`) and
  `AnimStart: float` (total time). Inserted at `startRun` as `NoAnim`, `0`.
- In the weapon-cooldown rule, after `attackPlan` inserts a volley: if `kind ==
  characterDefs[hero].weapon` and `weaponDefs[kind].anim != NoAnim`, insert `Anim` and
  `AnimStart = tt`. Non-starter weapons never touch it.
- No rule expires it: render treats the animation as finished when
  `tt − AnimStart ≥ animDefs[anim].secs`; the facts stay in place (no retract churn).
- Render: while active, draw `characterDefs[hero].attackSheet` at column
  `int((tt − AnimStart) / secs · frames)` (clamped), row `facing.ord`, at the sheet's cell size in
  world pixels (192 for oversize thrust/slash, 64 for shoot/cast), centred on the player. Body
  scale is identical to the walk sheet; the weapon overflows the 64 px box. Otherwise draw the walk
  sheet as today. The player keeps moving during the animation.
- Attack sheets include the weapon layers. To avoid a doubled spear, `ProjSpec`/projectile gains
  `Held: bool`: `attackPlan` sets it on volley 0 of a `Lunge` when the weapon is the hero's starter;
  render skips the icon for held projectiles. Extra volleys and a non-starter spear draw the icon.
- Hit flash: the white square becomes the `spark` sprite (LPC effects sheet), 24 px, shrinking to
  0 over `hitFlashSecs` (paranim's instanced image batches have no per-instance alpha).

## 4. Data (`src/data.nim`)

```nim
Motion*   = enum Lunge, Straight, Homing, Arc, Return, Orbit, Aura
BodyAnim* = enum NoAnim, AnimThrust, AnimSlash, AnimShoot, AnimCast
SheetId*  = enum ShZombie, ShSkeleton, ShMudman, ShGhost, ShReaper, ShBat, ShKoalio, ShParakeet,
                 ShOtto, ShOttoAttack, ShImma, ShImmaAttack, ShLina, ShLinaAttack,
                 ShGino, ShGinoAttack   # batches flush in this order: survivors draw on top
Sprite*   = enum SprSpear, SprBolt, SprArrow, SprAxe, SprBoomerang, SprShield, SprGarlic, SprAura,
                 SprSpark, SprGemBlue, SprGemGreen, SprGemRed, SprCoin, SprChicken, SprChest,
                 SprVacuum, SprSpinach, SprArmor, SprHollowHeart, SprPummarola, SprEmptyTome,
                 SprWings, SprAttractorb
Rect*     = tuple[x, y, w, h: int]

WeaponDef*    += sprite: Sprite, motion: Motion, anim: BodyAnim, spin: float, drawScale: float
PassiveDef*   += sprite: Sprite
CharacterDef*   sheet: SheetId (was string); += attackSheet: SheetId
EnemyDef*       sheet: SheetId (was string)

sheetDefs*: array[SheetId, tuple[file: string, cellW, cellH: int]]
animDefs*:  array[BodyAnim, tuple[frames: int, secs: float]]   # NoAnim = (1, 0)
atlas*:     array[Sprite, Rect]   # parsed at compile time from staticRead("assets/items.txt")
proc pickupSprite*(kind: PickupKind): Sprite
```

- Manifest names are the enum names without `Spr`, lower-cased (`spear`, `gemblue`, `emptytome`).
  A name missing from the manifest is a compile-time error. First manifest line is `size W H`.
- `drawScale` multiplies the projectile `size` for the icon width (spear 1.0 → icon length = hitbox
  length; bolt 2.4; arrow 3.5; axe 1.4; boomerang 1.6; shield 1.6; aura 2.0 → ring diameter).
- Passive icons: Spinach→leaf, Armor→platemail, HollowHeart→red potion, Pummarola→apple,
  EmptyTome→tome, Wings→boots, Attractorb→orb.
- `characterDefs`: Otto DragonSpear, Imma ArcaneStaff, Lina WarAxe, Gino Longbow; names, HP and
  perks unchanged.
- `systems.attackPlan`, `systems.hitsEnemy` and `rules.moveProjectiles` switch on
  `weaponDefs[kind].motion`, never on `WeaponKind`.
- `render` has one projectile path: `addIcon(def.sprite, pos, size · def.drawScale,
  angle + tt · def.spin)`; the only branches are `Aura` (ring + garlic over head) and `Held` (skip).
- `sheets` in render become `array[SheetId, Sheet]` filled from `sheetDefs` (string keys gone).

## 5. Sprite sources (all paths verified 2026-09-04 against the generator repo)

Generator root: `https://raw.githubusercontent.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator/master/spritesheets/`.
Character body layers use the same bodies/legs/torso/heads/hair as today, with the animation name
swapped (`walk` → `thrust`, `slash`, `shoot`, `spellcast`); all exist at the standard 64 px sizes
(thrust 512×256, slash 384×256, shoot 832×256, spellcast 448×256).

| Use | Files | Cell |
|---|---|---|
| Otto held spear (walk) | `weapon/polearm/dragonspear/{background,foreground}/walk/steel.png` (1664×512) | 128 → regrid to 64 |
| Otto thrust | `weapon/polearm/dragonspear/{background,foreground}/thrust/steel.png` (1536×768) | 192, 8 cols |
| Imma held staff (walk) | `weapon/magic/simple/{background,foreground}/walk/simple.png` (576×256) | 64 |
| Imma spellcast | `weapon/magic/simple/{background,foreground}/spellcast/simple.png` (448×256) | 64, 7 cols |
| Gino held bow (walk) | `weapon/ranged/bow/normal/walk/{background,foreground}/steel.png` (1664×512) | 128 → 64 |
| Gino shoot | `weapon/ranged/bow/normal/universal/{background,foreground}/shoot/steel.png` (832×256) + `weapon/ranged/bow/arrow/shoot/arrow.png` (832×256) | 64, 13 cols |
| Lina held axe (walk) | `weapon/blunt/waraxe/behind/walk/waraxe.png`, `weapon/blunt/waraxe/walk/waraxe.png` (576×256) | 64 |
| Lina slash | `weapon/blunt/waraxe/attack_slash/behind/waraxe.png`, `weapon/blunt/waraxe/attack_slash/waraxe.png` (1152×768) | 192, 6 cols |
| `spear` icon | dragonspear thrust fg+bg, right-facing row, frame 5, trimmed (93×13 → shrunk to 64 wide) | |
| `arrow` icon | arrow shoot sheet, right row, frame 8 (nocked, horizontal), trimmed | |
| `axe` icon | waraxe walk (+behind), right row, frame 1, trimmed | |
| `boomerang` icon | Reemax items sheet cell (9,8) (green boomerang; simpler than cutting the 192 px throw sheet) | 32 |
| `shield` icon | `shield/round/walk/brown.png` (576×256), down row (front view), frame 0, trimmed | |
| gems, coin, chicken, passives | Reemax "[LPC] Items and game effects" `items1.png` (32 px cells, verified): coin (9,0), gem_red (12,3), gem_blue (12,4), gem_green (12,5), chicken (8,6), tome (0,9), potion_red (3,5), platemail (0,1), boots (13,3), leaf (8,4), apple (8,5), crystal orb (2,9) — https://opengameart.org/content/lpc-items-and-game-effects | 32 |
| `bolt`, `aura`, `vacuum`, `spark` | same pack `effects.png` (verified): bolt = blue swirl orb (13,2), aura = blue ring (16,3) with alpha baked to 0.35, vacuum = purple burst (3,0), spark = blue sparkle (10,0) | 32 |
| `garlic` | bluecarrot16 "[LPC] Food" v2 `fruits-veggies.png`, cell (23,15) (verified) — https://opengameart.org/content/lpc-food | 32 |
| `chest` | LPC Base Assets `tiles/chests.png`, top-left 32×32 (already downloaded) | 32 |

Licenses: generator layers CC-BY-SA 3.0 / GPL 3.0 / OGA-BY 3.0 per `CREDITS.csv` row; Reemax
CC-BY-SA 3.0 / GPL; Food CC-BY-SA 3.0 / GPL 3.0.

## 6. Asset pipeline (`tools/fetch_assets.sh`)

1. `regrid IN cellIn cellOut cols rows OUT`: `+repage`, `-crop cellIn×cellIn +repage`, `-gravity
   center -background none -extent cellOut×cellOut`, montage back with `-mode concatenate -tile
   cols×rows`. Every LPC PNG is `+repage`d before cropping (they carry page offsets).
2. Walk sheets `<name>.png` (64 px, 9×4) as today plus held weapon: bg layer under the body, fg
   layer over the hair. 128 px walk layers (spear, bow) are regridded 128 → 64 first.
3. Attack sheets `<name>_attack.png`: bodies/legs/torso/head/hair regridded 64 → 192 for Otto
   (thrust, 8×4) and Lina (slash, 6×4), flattened between the weapon bg and fg layers; Gino (shoot,
   13×4, 64 px, arrow layer on top) and Imma (spellcast, 7×4, 64 px) flatten at native size.
4. Icons: crop frame, `-trim`, shrink with `-resize '64x64>'` if larger, centre in a 64×64 cell.
5. `magick montage -mode concatenate -tile 8x -background none` of all cells in a fixed order into
   `src/assets/items.png`; the script writes `src/assets/items.txt` (`size W H` then one
   `name x y w h` per icon: the icon's *tight* rect inside its cell, from the trimmed size and the
   cell index) so the game draws each icon at its own aspect ratio.
6. Credits: rows for every new generator layer path into `CREDITS-lpc.csv`; copy Reemax
   `credits.txt` → `CREDITS-lpc-items.txt`, Food `CREDITS-food.txt` → `CREDITS-lpc-food.txt`;
   sections in `CREDITS.md`.

`nimble assets` remains the single entry point. Generated PNGs and the manifest are committed.

## 7. Rendering (`src/render.nim`)

- `items.png` is one more sheet; `addIcon(spr: Sprite, cx, cy, w: float, angle = 0.0)` crops the
  atlas rect, derives the height from the rect's aspect, and applies translate → rotate → scale.
  No alpha/flip: instanced image batches have no per-instance colour, and rotation covers direction.
- Projectiles: §4 single path. Lunge spear: icon length `size`, rotated to `angle`, centred on the
  hitbox. Aura: ring sprite scaled to `2r` at alpha 0.35, `garlic` 20 px above the head.
- Pickups: gems 16 px with a 3 px bob (`sin(tt·4 + id)`), coin 18, chicken 22, chest 28, vacuum 20
  spinning.
- Player: walk or attack sheet per §3. HP bar, XP bar, overlays stay quads.
- Draw order: ground → pickups → aura → enemies + player → projectiles → sparks → bars.
- Level-up cards: 48 px icon left of the title. HUD slot lists: 24 px icon + level number, names
  dropped. `drawCharSelect` unchanged (the walk frame already shows the held weapon).

## 8. Tests

- `test_data`: every `Sprite` rect lies inside the manifest `size`; every weapon and passive has a
  sprite; every `SheetId` file parses as a PNG (IHDR width/height at byte 16) and
  `animDefs[anim].frames · cellW ≤ width` for each character's attack sheet; names
  (`"Dragon Spear"`, …); `characterDefs[Lina].weapon == WarAxe`; existing curve/upgrade tests under
  the new enum names.
- `test_systems`: Lunge volley 0 lies along `facing`, volley 1 opposite; rotated-rectangle hit test
  for an Up-facing lunge; Return projectile decelerates, `Turned` flips once, hit list is cleared,
  retract within the catch radius; other motions unchanged; `Held` set only for the hero's starter.
- `test_rules`: starter fire inserts `Anim`/`AnimStart`; a non-starter weapon fire leaves `NoAnim`;
  animation is inactive after `secs`.
- Visual: `tools/screenshots.sh` with `-d:autoplay` — title, select, each starter mid-attack, a run
  with every weapon, level-up card. Screenshots replace `docs/screenshots/*.png`.

## 9. README

- Survivor table: Lina → War Axe; note that the starter weapon animates.
- Weapon table: new names and behaviours (spear 4-way lunge, boomerang returns).
- New "Adding a weapon" section: the four edits (enum, `weaponDefs` row, `weaponUpgrades` row,
  icon line in `fetch_assets.sh`) plus `tools/screenshots.sh` to eyeball it.
- Credits: Reemax items, LPC Food, new generator layers.
- Every screenshot re-shot after implementation (same file names).

## 10. Out of scope

Enemy projectiles, body animations for non-starter weapons, weapon colour variants per character,
evolutions, new weapons.
