# Parasurvivors — Sprites for Everything (LPC weapons, pickups, UI icons)

Date: 2026-09-04
Status: approved in brainstorming, ready for planning
Builds on: `2026-09-04-parasurvivors-design.md` (implemented on `main`)

## 1. Goal

Replace every coloured quad with a sprite and give weapons Liberated Pixel Cup art:

- Projectiles and weapon effects use LPC generator weapon layers (dragon spear, staff, bow + arrow,
  war axe, boomerang, round shield) cropped into standalone icons.
- Pickups (gems, coin, chicken, chest, vacuum) and passives use icons from Reemax's
  "[LPC] Items and game effects" and bluecarrot16's "[LPC] Food".
- Each character visibly carries their starting weapon in the walk sheet.
- Level-up cards and the HUD slot list show weapon/passive icons.
- Weapons are renamed to match the art. Mechanics do not change.

Decided in brainstorming (do not re-litigate): icons + held starter (no LPC attack animations);
one script-built atlas with a text manifest; UI icons for weapons and passives.

## 2. Weapon mapping

| Old enum   | New enum      | Display name  | Projectile sprite                     | Held by starter |
|------------|---------------|---------------|---------------------------------------|-----------------|
| Whip       | DragonSpear   | Dragon Spear  | `spear` (dragonspear thrust, steel)   | Otto            |
| MagicWand  | ArcaneStaff   | Arcane Staff  | `bolt` (effects.png blue orb)          | Imma (staff)    |
| Knife      | Longbow       | Longbow       | `arrow` (bow/arrow shoot frame)        | Gino (bow)      |
| Axe        | WarAxe        | War Axe       | `axe` (waraxe walk frame)              | —               |
| Runetracer | Boomerang     | Boomerang     | `boomerang` (boomerang frame)          | — (Lina)        |
| Garlic     | Garlic        | Garlic        | `aura` ring (effects.png) + `garlic` icon on player | — |
| KingBible  | RoundShield   | Round Shield  | `shield` (round shield walk, brown)    | —               |

Behaviour per kind (cooldowns, damage, motion in `moveProjectiles`, `attackPlan`) is unchanged; only
`WeaponKind` identifiers, `weaponDefs[].name/desc`, and the sprite drawn change. Descriptions are
rewritten to fit the art ("Thrusts horizontally, passes through enemies", "Fires at the nearest
enemy", "Arrows fly in the faced direction", "High damage, arcs overhead", "Bounces around the
screen", "Damages nearby enemies", "Orbits around the character").

Assumption: "enemy projectiles" in the request refers to the player's projectiles; enemies have no
ranged attacks in the base spec and none are added.

## 3. Sprite sources (all verified 2026-09-04)

| Sprite(s) | Source | File(s) | License |
|---|---|---|---|
| spear (icon), spear held layers | LPC generator `spritesheets/weapon/polearm/dragonspear/{foreground,background}/{thrust,walk}/steel.png` | thrust: 1536×768, 192 px frames; walk: 1664×512, 128 px frames | CC-BY-SA 3.0 / GPL 3.0 / OGA-BY 3.0 (rows in `CREDITS.csv` under `weapon/polearm/dragonspear`) |
| staff held layers | `weapon/magic/simple/{foreground,background}/walk/simple.png` (576×256, 64 px) | | same |
| shield | `shield/round/walk/brown.png` (576×256) | | same |
| bow held layers | `weapon/ranged/bow/normal/walk/{foreground,background}/steel.png` (1664×512, 128 px) | | same |
| arrow | `weapon/ranged/bow/arrow/shoot/arrow.png` (832×256, 64 px) | | same |
| axe | `weapon/blunt/waraxe/walk/waraxe.png` (+ `behind/walk/waraxe.png`) | | same |
| boomerang | `weapon/ranged/boomerang/boomerang.png` (1152×768, 192 px) | | same |
| gem_blue, gem_green, gem_red, coin, chicken, tome, potion, platemail, boots, leaf, apple, orb | Reemax "[LPC] Items and game effects", `ItemsAndEffects/items1.png` (512×512, 32 px cells) — https://opengameart.org/content/lpc-items-and-game-effects | `ItemsAndEffects_0.zip` | CC-BY-SA 3.0 / GPL 3.0 / GPL 2.0 |
| aura, vacuum (star burst) | same pack, `effects.png` (640×400) | | same |
| garlic | bluecarrot16 et al. "[LPC] Food" v2, `fruits-veggies.png` (1024×1536, 32 px cells) — https://opengameart.org/content/lpc-food | `lpc-food-v2.zip` | CC-BY-SA 3.0 / GPL 3.0 |
| chest | LPC Base Assets `tiles/chests.png` (64×96, top-left 32×32 = closed chest) | already downloaded | CC-BY-SA 3.0 / GPL 3.0 |

Items sheet cells (col, row, 32 px): coin (9,0), gem_red (12,3), gem_blue (12,4), gem_green (12,5),
gem_white (15,1), chicken (8,6), tome (0,9), potion_red (3,5), platemail (0,1), boots (13,3),
leaf (8,4), apple (8,5), orb (14,5). Effects: aura ring ≈ cell (16,3) of 32 px cells, star burst at
≈ (0,7); garlic ≈ cell (23,15) of the food sheet. The script uses these numbers; the plan's visual
check step confirms each before commit.

## 4. Asset pipeline

`tools/fetch_assets.sh` gains an atlas stage after the character/enemy stage:

1. Download the layer PNGs and the two zips into the temp dir (curl, unzip).
2. Weapon icons: `magick bg fg +repage -background none -layers flatten -crop FxF+X+Y +repage -trim +repage`
   for the chosen frame (fixed row/col per weapon, right-facing row 3), then `-gravity center -extent 64x64`
   for spear/boomerang/axe and `32x32` for arrow/shield/bolt. Frames chosen: spear thrust row 3 col 5,
   boomerang row 3 col 2, axe walk row 3 col 1 (+behind), arrow shoot row 3 col 9, shield walk row 3 col 1.
3. Item icons: `-crop 32x32+X+Y +repage` per cell. Effects: aura 32×32, star 32×32. Bolt = orb cell.
4. `magick montage -mode concatenate -tile 8x -background none` of all icons in a fixed order into
   `src/assets/items.png`; the script writes `src/assets/items.txt` with one `name x y w h` line per
   icon in the same order (it knows the tile size and order, so coordinates are computed, not read back).
5. Held starters: recompose `otto.png` with dragonspear walk bg (below body) and fg (above hair),
   `imma.png` with staff bg/fg, `gino.png` with bow walk bg/fg. 128 px walk layers are first
   `-crop 64x64+32+32`-style re-gridded to 64 px cells (crop each 128 px frame's centre 64×64 and
   re-tile 9×4) before flattening with the 576×256 body sheet. Lina keeps no held weapon.
6. Credits: append rows for every new generator layer path to `CREDITS-lpc.csv`; copy Reemax
   `credits.txt` as `CREDITS-lpc-items.txt` and `CREDITS-food.txt` as `CREDITS-lpc-food.txt`;
   `CREDITS.md` gets sections for both packs.

`nimble assets` remains the single entry point. Generated PNGs/manifest are committed.

## 5. Data (`src/data.nim`)

- `WeaponKind = enum DragonSpear, ArcaneStaff, Longbow, WarAxe, Boomerang, Garlic, RoundShield`.
- `Sprite = enum SprSpear, SprBolt, SprArrow, SprAxe, SprBoomerang, SprGarlic, SprShield, SprAura,
  SprGemBlue, SprGemGreen, SprGemRed, SprCoin, SprChicken, SprChest, SprVacuum, SprSpinach, SprArmor,
  SprHollowHeart, SprPummarola, SprEmptyTome, SprWings, SprAttractorb`.
- `Rect = tuple[x, y, w, h: int]`; `atlas*: array[Sprite, Rect]` built at compile time by parsing
  `staticRead("assets/items.txt")`; manifest names are the enum names without the `Spr` prefix,
  lower-cased (`spear`, `gemblue`, `emptytome`, …). A missing name is a compile-time error.
- `WeaponDef`, `PassiveDef` gain `sprite: Sprite`; `pickupSprite(kind: PickupKind): Sprite` maps
  gems/coin/chicken/chest/vacuum. Passive icons: Spinach→leaf, Armor→platemail, HollowHeart→potion_red,
  Pummarola→apple, EmptyTome→tome, Wings→boots, Attractorb→orb.
- `characterDefs` names/perks unchanged; starting weapons follow the rename.

## 6. Rendering (`src/render.nim`)

- Load `items.png` as one more sheet; `addIcon(spr: Sprite, cx, cy, w, h: float, angle = 0.0,
  alpha = 1.0, flip = false)` crops the atlas rect and applies translate → rotate → scale like `addRect`.
- Projectiles by kind: DragonSpear → `spear` icon drawn at the hitbox centre, width = hitbox size,
  flipped when the spear points left; ArcaneStaff → `bolt` 24 px rotated to `angle`; Longbow → `arrow`
  28 px rotated; WarAxe → `axe` `size*1.4` rotated (spins); Boomerang → `boomerang` `size*1.6` rotated
  by `angle + tt*12`; RoundShield → `shield` `size*1.6`; Garlic → `aura` scaled to `2r` at alpha 0.35
  plus `garlic` 20 px above the player's head.
- Pickups: gems 16 px with a 3 px bob (`sin(tt*4 + id)`), coin 18 px, chicken 22 px, chest 28 px,
  vacuum 20 px spinning.
- Hit flash, HP bar, XP bar, overlays stay quads. Draw order: ground → pickups → aura → sprites
  (enemies, player) → projectiles → flashes/bars.
- Level-up cards: 48 px icon left of the title; HUD slot lists: 24 px icon followed by the level
  number (no names). `drawCharSelect` unchanged.

## 7. Tests

- `test_data`: every `Sprite` has a non-empty atlas rect inside the atlas image bounds (the script also
  writes `size W H` as the first manifest line); every weapon and passive references a sprite;
  `weaponDefs[DragonSpear].name == "Dragon Spear"`; existing curve/upgrade tests updated for names.
- `test_rules`, `test_systems`: enum renames only (Whip→DragonSpear, MagicWand→ArcaneStaff,
  Knife→Longbow, KingBible→RoundShield, Runetracer→Boomerang, Axe→WarAxe).
- Rendering verified by screenshots from a `-d:autoplay` run (title, char select, run at ~2 min with
  every weapon added via a temporary `-d:allweapons` test aid or by editing `startRun` in a scratch
  test, level-up overlay).

## 8. Out of scope

Enemy projectiles, LPC thrust/shoot/slash attack animations on the player, weapon colour variants
per character, evolutions, new weapons.
