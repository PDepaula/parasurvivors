# Parasurvivors Sprites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every coloured quad with LPC sprites, give each survivor's starter weapon a body attack animation, rename the weapons away from Vampire Survivors, and make the weapon table data-driven.

**Architecture:** `tools/fetch_assets.sh` builds every PNG (walk sheets with held weapons, oversize attack sheets, one icon atlas + text manifest). `src/data.nim` gains `Motion`, `BodyAnim`, `SheetId`, `Sprite` enums and the atlas parsed at compile time; `systems.nim` and `rules.nim` switch on `weaponDefs[kind].motion`; `render.nim` has one projectile path (`addIcon`) and picks the walk or attack sheet from two new player facts.

**Tech Stack:** Nim 2.x, paranim (instanced sprite batches), pararules, ImageMagick 7 (`magick`), bash, curl, unzip. Spec: `docs/superpowers/specs/2026-09-04-parasurvivors-sprites-design.md`.

## Global Constraints

- Only the **starter** weapon animates the body. Cooldowns ≥ 1 s so animations never overlap.
- Weapon enum and display names: `DragonSpear` "Dragon Spear", `ArcaneStaff` "Arcane Staff", `Longbow` "Longbow", `WarAxe` "War Axe", `Boomerang` "Boomerang", `Garlic` "Garlic", `RoundShield` "Round Shield".
- Starters: Otto DragonSpear, Imma ArcaneStaff, **Lina WarAxe**, Gino Longbow. Names, HP, perks unchanged.
- `systems`, `rules`, `render` never `case` on `WeaponKind`; they switch on `weaponDefs[kind].motion`.
- Manifest names = `Sprite` enum names without `Spr`, lower-cased. A missing name is a compile-time error.
- `nimble assets` is the single asset entry point; generated PNGs and `items.txt` are committed.
- Every LPC PNG is `+repage`d before cropping (they carry page offsets; without it `-crop` produces "geometry does not contain image").
- Tests run headless from the repo root: `nimble test` (= `nim c -r --hints:off --outdir:tmp tests/test_X.nim`). The game compiles with `nim c -d:noaudio --hints:off --outdir:tmp src/parasurvivors.nim`.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019VGNJYtoUzydpJzfWTW15h
  ```
- Work on branch `sprites` (already checked out).

## File map

| File | Responsibility after this plan |
|---|---|
| `tools/fetch_assets.sh` | downloads, `regrid`, walk + attack sheets, icon atlas + manifest, credits |
| `src/assets/*.png`, `src/assets/items.txt` | generated, committed |
| `src/data.nim` | enums (`Motion`, `BodyAnim`, `SheetId`, `Sprite`), `sheetDefs`, `animDefs`, `atlas`, weapon/passive/character tables with sprite fields, `pickupSprite`, `animActive`/`animFrame` |
| `src/systems.nim` | `attackPlan` by motion, `lungeDir`, `hitsEnemy` rotated rectangle, `ProjSpec.held` |
| `src/rules.nim` | facts `Held`, `Turned`, `Anim`, `AnimStart`; `moveProjectiles` by motion (incl. `Return`); starter fire sets `Anim` |
| `src/render.nim` | sheets by `SheetId`, atlas `addIcon`, attack-sheet player, icon pickups/projectiles/sparks/HUD/level-up |
| `tests/test_data.nim`, `tests/test_systems.nim`, `tests/test_rules.nim`, `tests/bench.nim` | renamed enums + new behaviour tests |
| `README.md`, `src/assets/CREDITS.md`, `docs/screenshots/*.png` | docs refresh |

---

### Task 1: Asset pipeline (sheets, atlas, manifest, credits)

**Files:**
- Modify: `tools/fetch_assets.sh` (whole file)
- Generate: `src/assets/{otto,imma,lina,gino}.png`, `src/assets/{otto,imma,lina,gino}_attack.png`, `src/assets/items.png`, `src/assets/items.txt`, `src/assets/CREDITS-lpc.csv`, `src/assets/CREDITS-lpc-items.txt`, `src/assets/CREDITS-lpc-food.txt`

**Interfaces:**
- Produces: `src/assets/items.txt` — first line `size W H`, then one `name x y w h` per icon (tight trimmed rect inside a 64×64 cell), names: `spear bolt arrow axe boomerang shield garlic aura spark gemblue gemgreen gemred coin chicken chest vacuum spinach armor hollowheart pummarola emptytome wings attractorb`.
- Produces: attack sheets — `otto_attack.png` 1536×768 (192 px cells, 8×4), `lina_attack.png` 1152×768 (192 px, 6×4), `gino_attack.png` 832×256 (64 px, 13×4), `imma_attack.png` 448×256 (64 px, 7×4). Rows are Up, Left, Down, Right (LPC order).

- [ ] **Step 1: Replace `tools/fetch_assets.sh`**

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
: > "$TMP/used.txt"   # every generator layer path we touch, for the credits rows

fetch() { curl -fsSL "$1" -o "$2"; }

# layer REL : prints the local path of one generator sheet, fetching it once.
# (Runs in a subshell via $(...), so the credit record goes through a file, not an array.)
layer() {
  local rel=$1 f="$TMP/$(echo "$1" | tr '/' '_')"
  [ -f "$f" ] || fetch "$LPC/$rel" "$f"
  echo "$rel" >> "$TMP/used.txt"
  echo "$f"
}

# flatten OUT LAYER... : bottom-to-top flatten. +repage drops the PNG page offsets LPC sheets carry.
flatten() {
  local out=$1; shift
  magick "$@" +repage -background none -layers flatten "PNG32:$out"
  echo "composed $(basename "$out")"
}

# regrid IN CELL_IN CELL_OUT COLS ROWS OUT : re-centre every frame on a different cell size.
# 64->192 pads a body sheet under an oversize weapon; 128->64 crops a 128 px walk layer to 64.
regrid() {
  local in=$1 ci=$2 co=$3 cols=$4 rows=$5 out=$6
  magick "$in" +repage -crop "${ci}x${ci}" +repage -gravity center -background none -extent "${co}x${co}" +repage miff:- |
    magick montage - -mode concatenate -tile "${cols}x${rows}" -background none "PNG32:$out"
}

# body ANIM CELL COLS NAME DIR... : sets BODY=(local files) for the character's ANIM sheets,
# regridded from 64 px frames to CELL px cells when CELL != 64.
body() {
  local anim=$1 cell=$2 cols=$3 name=$4; shift 4
  BODY=()
  for dir in "$@"; do
    local f; f=$(layer "$dir/$anim.png")
    if [ "$cell" != 64 ]; then
      local g="$TMP/${name}_${anim}_$(echo "$dir" | tr '/' '_')_$cell.png"
      regrid "$f" 64 "$cell" "$cols" 4 "$g"; f=$g
    fi
    BODY+=("$f")
  done
}

OTTO=(body/bodies/male legs/pants/male torso/clothes/longsleeve/longsleeve/male head/heads/human/male hair/bedhead/adult)
IMMA=(body/bodies/female legs/skirts/plain/thin torso/clothes/longsleeve/longsleeve/female head/heads/human/female hair/bob/adult)
LINA=(body/bodies/female legs/pantaloons/thin torso/clothes/shortsleeve/shortsleeve/female head/heads/human/female hair/bangs/adult)
GINO=(body/bodies/male legs/pants/male torso/clothes/shortsleeve/shortsleeve/male head/heads/human/male hair/balding/adult)

# --- Otto: dragon spear (walk layers are 128 px, thrust layers are 192 px oversize)
regrid "$(layer weapon/polearm/dragonspear/background/walk/steel.png)" 128 64 9 4 "$TMP/spear_walk_bg.png"
regrid "$(layer weapon/polearm/dragonspear/foreground/walk/steel.png)" 128 64 9 4 "$TMP/spear_walk_fg.png"
body walk 64 9 otto "${OTTO[@]}"
flatten "$OUT/otto.png" "$TMP/spear_walk_bg.png" "${BODY[@]}" "$TMP/spear_walk_fg.png"
body thrust 192 8 otto "${OTTO[@]}"
flatten "$OUT/otto_attack.png" "$(layer weapon/polearm/dragonspear/background/thrust/steel.png)" "${BODY[@]}" "$(layer weapon/polearm/dragonspear/foreground/thrust/steel.png)"

# --- Imma: simple staff (64 px everywhere)
body walk 64 9 imma "${IMMA[@]}"
flatten "$OUT/imma.png" "$(layer weapon/magic/simple/background/walk/simple.png)" "${BODY[@]}" "$(layer weapon/magic/simple/foreground/walk/simple.png)"
body spellcast 64 7 imma "${IMMA[@]}"
flatten "$OUT/imma_attack.png" "$(layer weapon/magic/simple/background/spellcast/simple.png)" "${BODY[@]}" "$(layer weapon/magic/simple/foreground/spellcast/simple.png)"

# --- Lina: war axe (walk 64 px, attack_slash 192 px oversize)
body walk 64 9 lina "${LINA[@]}"
flatten "$OUT/lina.png" "$(layer weapon/blunt/waraxe/behind/walk/waraxe.png)" "${BODY[@]}" "$(layer weapon/blunt/waraxe/walk/waraxe.png)"
body slash 192 6 lina "${LINA[@]}"
flatten "$OUT/lina_attack.png" "$(layer weapon/blunt/waraxe/attack_slash/behind/waraxe.png)" "${BODY[@]}" "$(layer weapon/blunt/waraxe/attack_slash/waraxe.png)"

# --- Gino: longbow (walk layers 128 px, shoot 64 px + arrow layer)
regrid "$(layer weapon/ranged/bow/normal/walk/background/steel.png)" 128 64 9 4 "$TMP/bow_walk_bg.png"
regrid "$(layer weapon/ranged/bow/normal/walk/foreground/steel.png)" 128 64 9 4 "$TMP/bow_walk_fg.png"
body walk 64 9 gino "${GINO[@]}"
flatten "$OUT/gino.png" "$TMP/bow_walk_bg.png" "${BODY[@]}" "$TMP/bow_walk_fg.png"
body shoot 64 13 gino "${GINO[@]}"
flatten "$OUT/gino_attack.png" "$(layer weapon/ranged/bow/normal/universal/background/shoot/steel.png)" "${BODY[@]}" \
  "$(layer weapon/ranged/bow/normal/universal/foreground/shoot/steel.png)" "$(layer weapon/ranged/bow/arrow/shoot/arrow.png)"

# --- enemies
flatten "$OUT/skeleton.png" "$(layer body/bodies/skeleton/walk.png)"
flatten "$OUT/zombie.png" "$(layer body/bodies/zombie/walk/zombie.png)"
flatten "$OUT/reaper_base.png" "$(layer body/bodies/skeleton/walk.png)" "$(layer hat/cloth/hood/adult/walk.png)"
magick "$OUT/reaper_base.png" -fill '#101018' -colorize 75% "PNG32:$OUT/reaper.png"
rm "$OUT/reaper_base.png"
magick "$OUT/zombie.png" -fill '#3a8f2a' -colorize 45% "PNG32:$OUT/mudman.png"
magick "$OUT/zombie.png" -fill white -colorize 70% -channel A -evaluate multiply 0.6 +channel "PNG32:$OUT/ghost.png"

# --- LPC base assets (bat, grass, chest)
fetch "https://opengameart.org/sites/default/files/LPC%20Base%20Assets.zip" "$TMP/lpc.zip"
unzip -oq "$TMP/lpc.zip" -d "$TMP"
magick "$TMP/LPC Base Assets/sprites/monsters/bat.png" "PNG32:$OUT/bat.png"
magick "$TMP/LPC Base Assets/tiles/grass.png" "PNG32:$OUT/grass.png"
cp "$TMP/LPC Base Assets/CREDITS.TXT" "$OUT/CREDITS-lpc-base.txt"

# --- item packs (Reemax items + effects, bluecarrot16 food)
fetch "https://opengameart.org/sites/default/files/ItemsAndEffects_0.zip" "$TMP/items.zip"
unzip -oq "$TMP/items.zip" -d "$TMP"
ITEMS="$TMP/ItemsAndEffects/items1.png"      # 512x512, 32 px cells
EFFECTS="$TMP/ItemsAndEffects/effects.png"   # 640x400, 32 px cells
cp "$TMP/ItemsAndEffects/credits.txt" "$OUT/CREDITS-lpc-items.txt"
fetch "https://opengameart.org/sites/default/files/lpc-food-v2.zip" "$TMP/food.zip"
unzip -oq "$TMP/food.zip" -d "$TMP"
FOOD="$TMP/lpc-food-v2/fruits-veggies.png"   # 1024x1536, 32 px cells
cp "$TMP/lpc-food-v2/CREDITS-food.txt" "$OUT/CREDITS-lpc-food.txt"

# --- icon atlas: every icon is trimmed, shrunk to fit 64x64 if larger, and centred in a 64x64 cell.
# items.txt records the tight rect of each icon inside its cell so the game can draw it scaled
# with the right aspect.
ICON_NAMES=(); ICON_SIZES=(); CELLS=()
# icon NAME MAGICK-ARGS... : the args must produce a single image (e.g. SHEET -crop WxH+X+Y +repage)
icon() {
  local name=$1; shift
  magick "$@" -trim +repage -resize '64x64>' "PNG32:$TMP/icon_$name.png"
  ICON_NAMES+=("$name")
  ICON_SIZES+=("$(magick "$TMP/icon_$name.png" -format '%w %h' info:)")
  magick "$TMP/icon_$name.png" -gravity center -background none -extent 64x64 "PNG32:$TMP/cell_$name.png"
  CELLS+=("$TMP/cell_$name.png")
}
# cell SHEET COL ROW : 32 px cell of an item sheet
cell() { echo "$1 +repage -crop 32x32+$(( $2 * 32 ))+$(( $3 * 32 )) +repage"; }

# weapons (right-facing rows of the generator sheets; row 3 = Right, row 2 = Down)
icon spear "$(layer weapon/polearm/dragonspear/background/thrust/steel.png)" "$(layer weapon/polearm/dragonspear/foreground/thrust/steel.png)" \
  +repage -background none -layers flatten -crop 192x192+960+576 +repage
icon bolt $(cell "$EFFECTS" 13 2)
icon arrow "$(layer weapon/ranged/bow/arrow/shoot/arrow.png)" +repage -crop 64x64+512+192 +repage
icon axe "$(layer weapon/blunt/waraxe/behind/walk/waraxe.png)" "$(layer weapon/blunt/waraxe/walk/waraxe.png)" \
  +repage -background none -layers flatten -crop 64x64+64+192 +repage
icon boomerang $(cell "$ITEMS" 9 8)
icon shield "$(layer shield/round/walk/brown.png)" +repage -crop 64x64+0+128 +repage
icon garlic $(cell "$FOOD" 23 15)
icon aura $(cell "$EFFECTS" 16 3) -channel A -evaluate multiply 0.35 +channel
icon spark $(cell "$EFFECTS" 10 0)
# pickups
icon gemblue $(cell "$ITEMS" 12 4)
icon gemgreen $(cell "$ITEMS" 12 5)
icon gemred $(cell "$ITEMS" 12 3)
icon coin $(cell "$ITEMS" 9 0)
icon chicken $(cell "$ITEMS" 8 6)
icon chest "$TMP/LPC Base Assets/tiles/chests.png" +repage -crop 32x32+0+0 +repage
icon vacuum $(cell "$EFFECTS" 3 0)
# passives
icon spinach $(cell "$ITEMS" 8 4)
icon armor $(cell "$ITEMS" 0 1)
icon hollowheart $(cell "$ITEMS" 3 5)
icon pummarola $(cell "$ITEMS" 8 5)
icon emptytome $(cell "$ITEMS" 0 9)
icon wings $(cell "$ITEMS" 13 3)
icon attractorb $(cell "$ITEMS" 2 9)

COLS=8
N=${#CELLS[@]}
ROWS=$(( (N + COLS - 1) / COLS ))
magick montage "${CELLS[@]}" -mode concatenate -tile "${COLS}x${ROWS}" -background none "PNG32:$OUT/items.png"
{
  echo "size $(( COLS * 64 )) $(( ROWS * 64 ))"
  for i in "${!ICON_NAMES[@]}"; do
    read -r w h <<< "${ICON_SIZES[$i]}"
    x=$(( (i % COLS) * 64 + (64 - w) / 2 ))
    y=$(( (i / COLS) * 64 + (64 - h) / 2 ))
    echo "${ICON_NAMES[$i]} $x $y $w $h"
  done
} > "$OUT/items.txt"
echo "atlas: $N icons, $(cat "$OUT/items.txt" | head -1)"

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
sort -u "$TMP/used.txt" | while read -r rel; do
  # variants like body/bodies/zombie/walk/zombie.png are credited under body/bodies/zombie/walk.png;
  # animation sheets (thrust.png, spellcast.png ...) are credited under the layer's walk.png row
  grep -F "\"$rel\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    grep -F "\"$(dirname "$rel").png\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    grep -F "\"$(dirname "$rel")/walk.png\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    grep -F "\"$(echo "$rel" | sed -E 's#/(walk|thrust|slash|shoot|spellcast|attack_slash)/#/#; s#/(walk|thrust|slash|shoot|spellcast)\.png#.png#')\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    echo "WARNING: no credits row for $rel" >&2
done
awk '!seen[$0]++' "$OUT/CREDITS-lpc.csv" > "$TMP/dedup.csv" && mv "$TMP/dedup.csv" "$OUT/CREDITS-lpc.csv"

echo "done. sizes:"
file "$OUT"/*.png | sed 's/PNG image data, //' | cut -d, -f1-2
```

- [ ] **Step 2: Run the pipeline**

Run: `nimble assets 2>&1 | tail -40`
Expected: lines `composed otto.png` … `composed gino_attack.png`, `atlas: 23 icons, size 512 192`, then a size list showing `otto_attack.png … 1536 x 768`, `lina_attack.png … 1152 x 768`, `gino_attack.png … 832 x 256`, `imma_attack.png … 448 x 256`, `items.png … 512 x 192`. Any `WARNING: no credits row` line means a grep fallback missed; find the right row name in `CREDITS.csv` and extend the sed in the credits loop.

- [ ] **Step 3: Visual check of the atlas and attack sheets**

Run:
```bash
magick src/assets/items.png -scale 300% -background '#335' -flatten tmp/atlas_check.png
for c in otto lina gino imma; do magick src/assets/${c}_attack.png -background '#335' -flatten tmp/${c}_attack_check.png; done
```
Open `tmp/atlas_check.png` (Read tool) and confirm, left to right, top to bottom: spear (horizontal, tip right), blue swirl orb, arrow, axe, green boomerang, round shield, garlic bulbs, faint blue ring, blue sparkle, blue gem, green gem, red gem, coin pile, roast chicken, closed chest, purple burst, green leaf, plate armour, red potion, apple, red book, boots, crystal ball. Open each `*_attack_check.png`: row 4 (bottom) faces right; Otto stabs a spear, Lina swings an axe, Gino draws a bow, Imma raises a staff. Fix a wrong cell coordinate in the script and re-run `nimble assets` if anything is off.

- [ ] **Step 4: Check the manifest**

Run: `cat src/assets/items.txt`
Expected: `size 512 192` then 23 lines like `spear 0 25 64 9`, every `w`/`h` between 1 and 64, `x + w ≤ 512`, `y + h ≤ 192`.

- [ ] **Step 5: Commit**

```bash
git add tools/fetch_assets.sh src/assets
git commit -m "assets: LPC held weapons, attack sheets, icon atlas

otto/imma/lina/gino walk sheets now carry their starter weapon; each
gets a <name>_attack.png (thrust/spellcast/slash/shoot). items.png +
items.txt hold every weapon, pickup, passive and effect icon."
```

---

### Task 2: Data tables and mechanical rename (everything compiles, behaviour unchanged)

**Files:**
- Modify: `src/data.nim`
- Modify: `src/systems.nim` (enum names only, `whipHalfHeight` → `lungeHalfWidth`)
- Modify: `src/rules.nim` (enum names only)
- Modify: `src/render.nim` (enum names, sheets keyed by `SheetId`)
- Modify: `tests/test_data.nim`, `tests/test_systems.nim`, `tests/test_rules.nim`, `tests/bench.nim` (enum names + new data tests)

**Interfaces:**
- Produces (in `data.nim`):
  ```nim
  WeaponKind = enum DragonSpear, ArcaneStaff, Longbow, WarAxe, Boomerang, Garlic, RoundShield
  Motion = enum Lunge, Straight, Homing, Arc, Return, Orbit, Aura
  BodyAnim = enum NoAnim, AnimThrust, AnimSlash, AnimShoot, AnimCast
  SheetId = enum ShZombie, ShSkeleton, ShMudman, ShGhost, ShReaper, ShBat, ShKoalio, ShParakeet,
                 ShOtto, ShOttoAttack, ShImma, ShImmaAttack, ShLina, ShLinaAttack, ShGino, ShGinoAttack
  Sprite = enum SprSpear, SprBolt, SprArrow, SprAxe, SprBoomerang, SprShield, SprGarlic, SprAura, SprSpark,
                SprGemBlue, SprGemGreen, SprGemRed, SprCoin, SprChicken, SprChest, SprVacuum,
                SprSpinach, SprArmor, SprHollowHeart, SprPummarola, SprEmptyTome, SprWings, SprAttractorb
  Rect = tuple[x, y, w, h: int]
  SheetDef = object; file: string; cellW, cellH: int
  AnimDef = object; frames: int; secs: float
  WeaponDef += sprite: Sprite, motion: Motion, anim: BodyAnim, spin, drawScale: float
  PassiveDef += sprite: Sprite
  CharacterDef.sheet: SheetId; += attackSheet: SheetId
  EnemyDef.sheet: SheetId
  const lungeHalfWidth = 24.0, orbitRadius = 90.0, boomerangAccel = 220.0, boomerangCatchRadius = 20.0
  const sheetDefs: array[SheetId, SheetDef]; animDefs: array[BodyAnim, AnimDef]
  const atlasSize: (int, int); atlas: array[Sprite, Rect]
  proc pickupSprite(kind: PickupKind): Sprite
  proc animActive(anim: BodyAnim, start, now: float): bool
  proc animFrame(anim: BodyAnim, start, now: float): int
  ```

- [ ] **Step 1: Write the failing data tests**

Append to `tests/test_data.nim` (inside `suite "data"`), and rename existing references: `Whip` → `DragonSpear`, `MagicWand` → `ArcaneStaff` (the `weaponAt is cumulative` test).

```nim
  test "weapon names and starters follow the LPC art":
    check weaponDefs[DragonSpear].name == "Dragon Spear"
    check weaponDefs[ArcaneStaff].name == "Arcane Staff"
    check weaponDefs[Longbow].name == "Longbow"
    check weaponDefs[WarAxe].name == "War Axe"
    check weaponDefs[Boomerang].name == "Boomerang"
    check weaponDefs[RoundShield].name == "Round Shield"
    check characterDefs[Lina].weapon == WarAxe
    check characterDefs[Otto].weapon == DragonSpear
    check weaponDefs[DragonSpear].motion == Lunge
    check weaponDefs[Boomerang].motion == Return
    for k in WeaponKind:
      check weaponDefs[k].drawScale > 0

  test "starter weapons have a body animation, others none":
    for c in CharacterKind:
      check weaponDefs[characterDefs[c].weapon].anim != NoAnim
    check weaponDefs[Boomerang].anim == NoAnim
    check weaponDefs[RoundShield].anim == NoAnim
    check weaponDefs[Garlic].anim == NoAnim

  test "atlas rects lie inside the atlas image":
    let (aw, ah) = atlasSize
    check pngSize("src/assets/items.png") == (aw, ah)
    for s in Sprite:
      let r = atlas[s]
      check r.w > 0 and r.h > 0
      check r.x >= 0 and r.y >= 0
      check r.x + r.w <= aw
      check r.y + r.h <= ah
    for k in PassiveKind:
      check atlas[passiveDefs[k].sprite].w > 0
    check pickupSprite(GemBlue) == SprGemBlue
    check pickupSprite(Chest) == SprChest

  test "sheets exist and attack sheets match their animation":
    for id in SheetId:
      let (w, h) = pngSize("src/assets/" & sheetDefs[id].file)
      check w >= sheetDefs[id].cellW
      check h >= sheetDefs[id].cellH
    for c in CharacterKind:
      let d = characterDefs[c]
      let a = animDefs[weaponDefs[d.weapon].anim]
      let sh = sheetDefs[d.attackSheet]
      check pngSize("src/assets/" & sh.file) == (a.frames * sh.cellW, 4 * sh.cellH)
      check pngSize("src/assets/" & sheetDefs[d.sheet].file) == (9 * 64, 4 * 64)

  test "animation timing":
    check not animActive(NoAnim, 0.0, 0.0)
    check animActive(AnimThrust, 1.0, 1.1)
    check not animActive(AnimThrust, 1.0, 1.0 + animDefs[AnimThrust].secs)
    check animFrame(AnimThrust, 1.0, 1.0) == 0
    check animFrame(AnimThrust, 1.0, 1.0 + animDefs[AnimThrust].secs * 0.99) == animDefs[AnimThrust].frames - 1
    check animFrame(AnimThrust, 1.0, 5.0) == animDefs[AnimThrust].frames - 1
```

Add this helper above the suite (after the imports):

```nim
proc pngSize(path: string): (int, int) =
  ## Width/height from the IHDR chunk; tests run from the repo root.
  let s = readFile(path)
  doAssert s.len > 24 and s[1 .. 3] == "PNG", path & " is not a PNG"
  proc be(i: int): int =
    (int(s[i].uint8) shl 24) or (int(s[i + 1].uint8) shl 16) or (int(s[i + 2].uint8) shl 8) or int(s[i + 3].uint8)
  (be(16), be(20))
```

- [ ] **Step 2: Run the data test to verify it fails**

Run: `nim c -r --hints:off --outdir:tmp tests/test_data.nim`
Expected: compile error, `undeclared identifier: 'DragonSpear'`.

- [ ] **Step 3: Rewrite the type section and constants of `src/data.nim`**

Replace everything from `type` down to (and including) the `characterDefs`, `weaponDefs`, `passiveDefs`, `enemyDefs` constants with the following. Keep `weaponUpgrades` (rename its keys: `Whip`→`DragonSpear`, `MagicWand`→`ArcaneStaff`, `Knife`→`Longbow`, `Axe`→`WarAxe`, `Runetracer`→`Boomerang`, `KingBible`→`RoundShield`), `waves`, `bosses` and every proc as they are.

```nim
type
  CharacterKind* = enum
    Otto, Imma, Lina, Gino
  WeaponKind* = enum
    DragonSpear, ArcaneStaff, Longbow, WarAxe, Boomerang, Garlic, RoundShield
  Motion* = enum
    ## How a weapon's projectiles spawn and move (see systems.attackPlan, rules.moveProjectiles).
    Lunge,    ## stationary hitbox along the faced direction (Dragon Spear)
    Straight, ## flies in the faced direction (Longbow)
    Homing,   ## aimed at the nearest enemy (Arcane Staff)
    Arc,      ## thrown up, falls under gravity (War Axe)
    Return,   ## flies out, curves back to the player (Boomerang)
    Orbit,    ## circles the player (Round Shield)
    Aura      ## ring centred on the player (Garlic)
  BodyAnim* = enum
    ## LPC attack animation the player's body plays when their starter weapon fires.
    NoAnim, AnimThrust, AnimSlash, AnimShoot, AnimCast
  SheetId* = enum
    ## Batches flush in this order, so enemies come first and the survivors draw on top.
    ShZombie, ShSkeleton, ShMudman, ShGhost, ShReaper, ShBat, ShKoalio, ShParakeet,
    ShOtto, ShOttoAttack, ShImma, ShImmaAttack, ShLina, ShLinaAttack, ShGino, ShGinoAttack
  Sprite* = enum
    ## Icons in assets/items.png; manifest name = enum name without "Spr", lower-cased.
    SprSpear, SprBolt, SprArrow, SprAxe, SprBoomerang, SprShield, SprGarlic, SprAura, SprSpark,
    SprGemBlue, SprGemGreen, SprGemRed, SprCoin, SprChicken, SprChest, SprVacuum,
    SprSpinach, SprArmor, SprHollowHeart, SprPummarola, SprEmptyTome, SprWings, SprAttractorb
  PassiveKind* = enum
    Spinach, Armor, HollowHeart, Pummarola, EmptyTome, Wings, Attractorb
  EnemyKind* = enum
    Bat, Zombie, Skeleton, Mudman, Ghost, Parakeet, Koalio, Reaper
  PickupKind* = enum
    GemBlue, GemGreen, GemRed, Chicken, Coin, Chest, Vacuum
  Dir* = enum
    Up, Left, Down, Right ## LPC sheet row order
  Vec2* = tuple[x, y: float] ## one position fact per entity (see rules.nim)
  Rect* = tuple[x, y, w, h: int]

  Stats* = object
    might*, armor*, regen*, cooldownMul*, speedMul*, magnet*, area*, projSpeed*, duration*: float
    amount*: int

  CharacterDef* = object
    name*, perk*: string
    sheet*, attackSheet*: SheetId
    weapon*: WeaponKind
    maxHp*: float
    base*: Stats

  WeaponDef* = object
    name*, desc*: string
    cooldown*, damage*, speed*, ttl*, size*: float
    amount*, pierce*: int
    sprite*: Sprite
    motion*: Motion
    anim*: BodyAnim      ## body animation when this is the hero's starter weapon
    spin*: float         ## icon rotation speed, rad/s
    drawScale*: float    ## icon width = size * drawScale

  WeaponUpgrade* = object ## additive deltas applied when reaching that level
    damage*, cooldown*, size*, speed*, ttl*: float
    amount*, pierce*: int
    text*: string

  PassiveDef* = object
    name*, desc*: string
    sprite*: Sprite

  EnemyDef* = object
    hp*, speed*, damage*, size*: float
    gem*: PickupKind
    sheet*: SheetId
    boss*: bool

  SheetDef* = object
    file*: string
    cellW*, cellH*: int

  AnimDef* = object
    frames*: int
    secs*: float

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
  orbitRadius* = 90.0
  lungeHalfWidth* = 24.0       ## half-width of a Lunge hitbox across its direction
  boomerangAccel* = 220.0      ## px/s² pull toward the player for Return projectiles
  boomerangCatchRadius* = 20.0 ## a returning boomerang this close to the player is caught
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

  sheetDefs*: array[SheetId, SheetDef] = [
    ShZombie: SheetDef(file: "zombie.png", cellW: 64, cellH: 64),
    ShSkeleton: SheetDef(file: "skeleton.png", cellW: 64, cellH: 64),
    ShMudman: SheetDef(file: "mudman.png", cellW: 64, cellH: 64),
    ShGhost: SheetDef(file: "ghost.png", cellW: 64, cellH: 64),
    ShReaper: SheetDef(file: "reaper.png", cellW: 64, cellH: 64),
    ShBat: SheetDef(file: "bat.png", cellW: 32, cellH: 32),
    ShKoalio: SheetDef(file: "koalio.png", cellW: 18, cellH: 26),
    ShParakeet: SheetDef(file: "parakeet.png", cellW: 70, cellH: 100),
    ShOtto: SheetDef(file: "otto.png", cellW: 64, cellH: 64),
    ShOttoAttack: SheetDef(file: "otto_attack.png", cellW: 192, cellH: 192),
    ShImma: SheetDef(file: "imma.png", cellW: 64, cellH: 64),
    ShImmaAttack: SheetDef(file: "imma_attack.png", cellW: 64, cellH: 64),
    ShLina: SheetDef(file: "lina.png", cellW: 64, cellH: 64),
    ShLinaAttack: SheetDef(file: "lina_attack.png", cellW: 192, cellH: 192),
    ShGino: SheetDef(file: "gino.png", cellW: 64, cellH: 64),
    ShGinoAttack: SheetDef(file: "gino_attack.png", cellW: 64, cellH: 64),
  ]

  animDefs*: array[BodyAnim, AnimDef] = [
    NoAnim: AnimDef(frames: 1, secs: 0.0),
    AnimThrust: AnimDef(frames: 8, secs: 0.4),
    AnimSlash: AnimDef(frames: 6, secs: 0.3),
    AnimShoot: AnimDef(frames: 13, secs: 0.5),
    AnimCast: AnimDef(frames: 7, secs: 0.35),
  ]

  characterDefs*: array[CharacterKind, CharacterDef] = [
    Otto: CharacterDef(name: "Otto", perk: "+10% Might", sheet: ShOtto, attackSheet: ShOttoAttack, weapon: DragonSpear, maxHp: 120,
      base: Stats(might: 1.1, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Imma: CharacterDef(name: "Imma", perk: "-10% Cooldown", sheet: ShImma, attackSheet: ShImmaAttack, weapon: ArcaneStaff, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 0.9, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Lina: CharacterDef(name: "Lina", perk: "+20% Projectile speed", sheet: ShLina, attackSheet: ShLinaAttack, weapon: WarAxe, maxHp: 90,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.2, duration: 1.0, amount: 0)),
    Gino: CharacterDef(name: "Gino", perk: "+1 Projectile", sheet: ShGino, attackSheet: ShGinoAttack, weapon: Longbow, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 1)),
  ]

  weaponDefs*: array[WeaponKind, WeaponDef] = [
    DragonSpear: WeaponDef(name: "Dragon Spear", desc: "Lunges in the faced direction, passes through enemies",
      cooldown: 1.35, damage: 10, speed: 0, ttl: 0.15, size: 100, amount: 1, pierce: 999,
      sprite: SprSpear, motion: Lunge, anim: AnimThrust, spin: 0, drawScale: 1.0),
    ArcaneStaff: WeaponDef(name: "Arcane Staff", desc: "Fires at the nearest enemy",
      cooldown: 1.2, damage: 10, speed: 300, ttl: 2.5, size: 10, amount: 1, pierce: 0,
      sprite: SprBolt, motion: Homing, anim: AnimCast, spin: 0, drawScale: 2.4),
    Longbow: WeaponDef(name: "Longbow", desc: "Arrows fly in the faced direction",
      cooldown: 1.0, damage: 6.5, speed: 450, ttl: 1.5, size: 8, amount: 1, pierce: 1,
      sprite: SprArrow, motion: Straight, anim: AnimShoot, spin: 0, drawScale: 3.5),
    WarAxe: WeaponDef(name: "War Axe", desc: "High damage, arcs overhead",
      cooldown: 4.0, damage: 20, speed: 300, ttl: 2.5, size: 20, amount: 1, pierce: 3,
      sprite: SprAxe, motion: Arc, anim: AnimSlash, spin: 10, drawScale: 1.4),
    Boomerang: WeaponDef(name: "Boomerang", desc: "Flies out and comes back, hits both ways",
      cooldown: 3.0, damage: 10, speed: 320, ttl: 3.0, size: 10, amount: 1, pierce: 999,
      sprite: SprBoomerang, motion: Return, anim: NoAnim, spin: 12, drawScale: 1.6),
    Garlic: WeaponDef(name: "Garlic", desc: "Damages nearby enemies",
      cooldown: 1.3, damage: 5, speed: 0, ttl: 0.05, size: 80, amount: 1, pierce: 999,
      sprite: SprAura, motion: Aura, anim: NoAnim, spin: 0, drawScale: 2.0),
    RoundShield: WeaponDef(name: "Round Shield", desc: "Orbits around the character",
      cooldown: 3.0, damage: 10, speed: 2.5, ttl: 3.0, size: 14, amount: 1, pierce: 999,
      sprite: SprShield, motion: Orbit, anim: NoAnim, spin: 0, drawScale: 1.6),
  ]
```

`passiveDefs` and `enemyDefs` become:

```nim
  passiveDefs*: array[PassiveKind, PassiveDef] = [
    Spinach: PassiveDef(name: "Spinach", desc: "+10% damage per level", sprite: SprSpinach),
    Armor: PassiveDef(name: "Armor", desc: "-1 incoming damage per level", sprite: SprArmor),
    HollowHeart: PassiveDef(name: "Hollow Heart", desc: "+20% max health per level", sprite: SprHollowHeart),
    Pummarola: PassiveDef(name: "Pummarola", desc: "+0.2 HP/s regen per level", sprite: SprPummarola),
    EmptyTome: PassiveDef(name: "Empty Tome", desc: "-8% cooldown per level", sprite: SprEmptyTome),
    Wings: PassiveDef(name: "Wings", desc: "+10% move speed per level", sprite: SprWings),
    Attractorb: PassiveDef(name: "Attractorb", desc: "+50% pickup range per level", sprite: SprAttractorb),
  ]

  enemyDefs*: array[EnemyKind, EnemyDef] = [
    Bat: EnemyDef(hp: 1, speed: 90, damage: 3, size: 32, gem: GemBlue, sheet: ShBat, boss: false),
    Zombie: EnemyDef(hp: 3, speed: 55, damage: 4, size: 64, gem: GemBlue, sheet: ShZombie, boss: false),
    Skeleton: EnemyDef(hp: 8, speed: 70, damage: 5, size: 64, gem: GemGreen, sheet: ShSkeleton, boss: false),
    Mudman: EnemyDef(hp: 15, speed: 45, damage: 6, size: 64, gem: GemGreen, sheet: ShMudman, boss: false),
    Ghost: EnemyDef(hp: 20, speed: 80, damage: 6, size: 64, gem: GemGreen, sheet: ShGhost, boss: false),
    Parakeet: EnemyDef(hp: 150, speed: 100, damage: 12, size: 150, gem: GemRed, sheet: ShParakeet, boss: true),
    Koalio: EnemyDef(hp: 400, speed: 60, damage: 15, size: 104, gem: GemRed, sheet: ShKoalio, boss: true),
    Reaper: EnemyDef(hp: 65535, speed: 200, damage: 999, size: 192, gem: GemRed, sheet: ShReaper, boss: true),
  ]
```

Then, after the `const` block (before `proc weaponAt*`), add the atlas parser and the helpers:

```nim
# ---------------------------------------------------------------- atlas (assets/items.txt)

proc spriteManifestName(s: Sprite): string =
  ## SprGemBlue -> "gemblue"
  toLowerAscii(($s)[3 .. ^1])

proc parseAtlas(manifest: string): tuple[size: (int, int), rects: array[Sprite, Rect]] =
  var seen: set[Sprite]
  for line in manifest.splitLines:
    let f = line.splitWhitespace
    if f.len == 0:
      continue
    if f[0] == "size":
      result.size = (parseInt(f[1]), parseInt(f[2]))
      continue
    doAssert f.len == 5, "bad items.txt line: " & line
    var found = false
    for s in Sprite:
      if spriteManifestName(s) == f[0]:
        result.rects[s] = (parseInt(f[1]), parseInt(f[2]), parseInt(f[3]), parseInt(f[4]))
        seen.incl s
        found = true
    doAssert found, "items.txt names an unknown sprite: " & f[0]
  for s in Sprite:
    doAssert s in seen, "sprite missing from items.txt: " & spriteManifestName(s) & " (run `nimble assets`)"

const
  atlasParsed = parseAtlas(staticRead("assets/items.txt"))
  atlasSize* = atlasParsed.size
  atlas* = atlasParsed.rects

proc pickupSprite*(kind: PickupKind): Sprite =
  case kind
  of GemBlue: SprGemBlue
  of GemGreen: SprGemGreen
  of GemRed: SprGemRed
  of Chicken: SprChicken
  of Coin: SprCoin
  of Chest: SprChest
  of Vacuum: SprVacuum

proc animActive*(anim: BodyAnim, start, now: float): bool =
  anim != NoAnim and now - start < animDefs[anim].secs

proc animFrame*(anim: BodyAnim, start, now: float): int =
  ## Column of the attack sheet for the elapsed time, clamped to the last frame.
  let a = animDefs[anim]
  if a.secs <= 0:
    return 0
  min(a.frames - 1, max(0, int((now - start) / a.secs * float(a.frames))))
```

- [ ] **Step 4: Mechanical rename in `systems.nim`, `rules.nim`, `render.nim`, tests, bench**

Apply everywhere (`grep -rn "Whip\|MagicWand\|Knife\|KingBible\|Runetracer\|\bAxe\b\|bibleOrbitRadius\|whipHalfHeight" src tests`):

| old | new |
|---|---|
| `Whip` | `DragonSpear` |
| `MagicWand` | `ArcaneStaff` |
| `Knife` | `Longbow` |
| `Axe` (the enum value; not `WarAxe`, not `axeGravity`) | `WarAxe` |
| `Runetracer` | `Boomerang` |
| `KingBible` | `RoundShield` |
| `bibleOrbitRadius` | `orbitRadius` |
| `whipHalfHeight` (systems.nim const + use) | `lungeHalfWidth` (delete the local const; it is now in data.nim) |

In `render.nim` also replace the string-keyed sheets:

```nim
const
  frameSecs = 0.1
  fontPx = 24
  tileSize = 32.0
  groundCols = 130 # covers a 4K view with margin
  groundRows = 70
  white = vec4(1f, 1f, 1f, 1f)
  yellow = vec4(1f, 0.9f, 0.3f, 1f)
  sheetPng = block:
    var a: array[SheetId, string]
    for id in SheetId:
      a[id] = staticRead("assets/" & sheetDefs[id].file)
    a
  grassPng = staticRead("assets/grass.png")
  ttf = staticRead("assets/Roboto-Regular.ttf")
```

(If the compiler rejects `staticRead` inside the block, write the array literal out instead: `ShOtto: staticRead("assets/otto.png"), ShOttoAttack: staticRead("assets/otto_attack.png"), …` for all 16 ids.)

```nim
var
  sheets: array[SheetId, Sheet]
  ...

proc initRender*[G](game: var G) =
  ...
  for id in SheetId:
    let base = loadImage(sheetPng[id])
    sheets[id] = Sheet(frameW: sheetDefs[id].cellW, frameH: sheetDefs[id].cellH, base: base,
                       batch: compile(game, initInstancedEntity(base)))
  ...

proc addSprite(id: SheetId, col, row: int, cx, cy, w, h: float, flip = false) =
  var e = sheets[id].base
  let fw = float(sheets[id].frameW)
  let fh = float(sheets[id].frameH)
  ...
  sheets[id].batch.add(e)

proc flushSprites[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat]) =
  for id in SheetId:
    if sheets[id].batch.attributes.a_matrix.data[].len == 0:
      continue
    var b = sheets[id].batch
    b.project(ww, wh)
    b.invert(camera)
    render(game, b)
    sheets[id].batch.clear()
```

`drawWorld`: `let sh = sheets[d.sheet]` and `addSprite(d.sheet, …)` already type-check once `sheet` is a `SheetId`; the player block uses `characterDefs[player.hero].sheet`. `drawCharSelect`: `addSprite(c.sheet, 0, Down.ord, …)`. Remove the `tables` import if nothing else uses it (`sequtils`, `strutils` stay).

`projColor` in render.nim keeps working with the renamed enum values (it is deleted in Task 5).

`tests/test_systems.nim` `"whip uses a wide horizontal box"` test: rename to `DragonSpear` for now (Task 3 rewrites it). `tests/bench.nim`: `s.addWeapon(ArcaneStaff); s.addWeapon(Longbow)`.

`tests/test_rules.nim` `"runetracer bounces inside the view"`: rename to Boomerang and change `s.startRun(Lina)` to `s.startRun(Otto); s.addWeapon(Boomerang)` and select the boomerang: `let r = s.queryAll(gameRules.getProjectiles).filterIt(it.kind == Boomerang)[0]`. (Task 4 replaces this test.) `"startRun creates the player with the character's weapon"`: `check ws[0].kind == DragonSpear`. `"weapon fires when its cooldown expires"`: `Longbow`. `"king bible orbits"`: `RoundShield`, `orbitRadius`. `prepareChoices and applyChoice`: `weapon: DragonSpear`. Projectile specs in the systems-step suite: `ArcaneStaff`, `Longbow`, `WarAxe`.

- [ ] **Step 5: Run all tests and compile the game**

Run: `nimble test 2>&1 | tail -30 && nim c -d:noaudio --hints:off --outdir:tmp src/parasurvivors.nim && echo COMPILED`
Expected: every suite `[OK]`, then `COMPILED`.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "data: LPC weapon names, Motion/BodyAnim/SheetId/Sprite enums, atlas manifest

Renames Whip/MagicWand/Knife/Axe/Runetracer/KingBible to
DragonSpear/ArcaneStaff/Longbow/WarAxe/Boomerang/RoundShield, moves
Lina's starter to WarAxe, keys sprite sheets by SheetId and parses
assets/items.txt into a compile-time atlas. Behaviour unchanged."
```

---

### Task 3: Motion-driven attack plans and the lunge hitbox

**Files:**
- Modify: `src/systems.nim` (`ProjSpec`, `hitsEnemy`, `attackPlan`, new `lungeDir`)
- Modify: `tests/test_systems.nim`

**Interfaces:**
- Consumes: `weaponDefs[kind].motion`, `lungeHalfWidth`, `orbitRadius` from Task 2.
- Produces:
  ```nim
  ProjSpec += held: bool
  proc lungeDir*(facing: Dir, i: int): (float, float)
  proc attackPlan*(kind: WeaponKind, level: int, st: Stats, px, py: float, facing: Dir,
                   hasNearest: bool, nx, ny: float, starter = false): seq[ProjSpec]
  ```
  `collide`'s projectile type now needs an `angle: float` field (the `getProjectiles` query already has it).

- [ ] **Step 1: Write the failing tests**

In `tests/test_systems.nim` change the `P` tuple and `proj` helper:

```nim
  P = tuple[id: int, kind: WeaponKind, pos: Vec2, size, damage: float, pierce: int, hitIds: HashSet[int], ttl, angle: float]

proc proj(id: int, x, y: float, kind = ArcaneStaff, pierce = 0, size = 10.0, angle = 0.0): P =
  (id, kind, (x, y), size, 10.0, pierce, initHashSet[int](), 1.0, angle)
```

Replace the `"whip uses a wide horizontal box"` test and the `"attack plans"` test with:

```nim
  test "lunge hits a rotated box along its direction":
    # spear pointing right, centred at (50,0), length 100, half-width lungeHalfWidth
    let right = proj(1, 50, 0, kind = DragonSpear, pierce = 999, size = 100, angle = 0.0)
    var hits = collide([right], [enemy(10, 90, 0), enemy(11, 50, 60), enemy(12, -20, 0)])
    check hits.len == 1
    check hits[0].enemyId == 10
    # same spear pointing up, centred at (0,-50)
    let up = proj(2, 0, -50, kind = DragonSpear, pierce = 999, size = 100, angle = -PI / 2)
    hits = collide([up], [enemy(10, 0, -90), enemy(11, 60, -50), enemy(12, 0, 20)])
    check hits.len == 1
    check hits[0].enemyId == 10

  test "lunge volleys: facing, opposite, then perpendiculars":
    check lungeDir(Right, 0) == (1.0, 0.0)
    check lungeDir(Right, 1) == (-1.0, 0.0)
    check lungeDir(Up, 0) == (0.0, -1.0)
    check lungeDir(Up, 1) == (0.0, 1.0)
    let (px, py) = lungeDir(Up, 2)
    check abs(px) == 1.0 and py == 0.0
    let (qx, qy) = lungeDir(Up, 3)
    check qx == -px and qy == 0.0

  test "attack plans":
    let st = defaultStats
    let spear = attackPlan(DragonSpear, 1, st, 0, 0, Up, false, 0, 0)
    check spear.len == 1
    check spear[0].y < 0                       # in front of an Up-facing player
    check abs(spear[0].angle + PI / 2) < 1e-9
    check not spear[0].held
    let held = attackPlan(DragonSpear, 2, st, 0, 0, Up, false, 0, 0, starter = true)
    check held.len == 2
    check held[0].held and not held[1].held
    check held[1].y > 0                        # volley 1 goes the other way
    let notLunge = attackPlan(Longbow, 1, st, 0, 0, Up, false, 0, 0, starter = true)
    check not notLunge[0].held                 # only lunges can be "held"
    let wand = attackPlan(ArcaneStaff, 1, st, 0, 0, Down, true, 100, 0)
    check wand.len == 1
    check wand[0].vx > 0 and abs(wand[0].vy) < 1e-6
    let arrow = attackPlan(Longbow, 1, st, 0, 0, Up, false, 0, 0)
    check arrow[0].vy < 0
    let shield = attackPlan(RoundShield, 2, st, 0, 0, Up, false, 0, 0)
    check shield.len == 2
    check abs(shield[1].angle - PI) < 1e-9
    let boom = attackPlan(Boomerang, 1, st, 0, 0, Up, false, 0, 0)
    check abs(sqrt(boom[0].vx * boom[0].vx + boom[0].vy * boom[0].vy) - weaponDefs[Boomerang].speed) < 1e-6
    var strong = defaultStats
    strong.might = 2.0
    strong.amount = 1
    let plan = attackPlan(Longbow, 1, strong, 0, 0, Right, false, 0, 0)
    check plan.len == 2
    check plan[0].damage == 13.0
```

- [ ] **Step 2: Run to verify failure**

Run: `nim c -r --hints:off --outdir:tmp tests/test_systems.nim`
Expected: compile error, `undeclared identifier: 'lungeDir'` (or "no tuple field held").

- [ ] **Step 3: Implement in `src/systems.nim`**

Replace the `ProjSpec` type, `hitsEnemy`, and `attackPlan` (add `lungeDir` above `attackPlan`):

```nim
  ProjSpec* = object
    kind*: WeaponKind
    x*, y*, vx*, vy*, size*, damage*, ttl*, angle*: float
    pierce*: int
    held*: bool ## drawn by the player's attack sheet, so render skips the icon
```

```nim
proc hitsEnemy[P, E](p: P, e: E): bool =
  let r = enemyRadius(e.size)
  if weaponDefs[p.kind].motion == Lunge:
    # rectangle of length p.size along p.angle, half-width lungeHalfWidth across it
    let dx = cos(p.angle)
    let dy = sin(p.angle)
    let ox = e.pos.x - p.pos.x
    let oy = e.pos.y - p.pos.y
    let along = ox * dx + oy * dy
    let across = -ox * dy + oy * dx
    abs(along) < p.size / 2 + r and abs(across) < lungeHalfWidth + r
  else:
    dist(p.pos.x, p.pos.y, e.pos.x, e.pos.y) < p.size + r
```

```nim
proc lungeDir*(facing: Dir, i: int): (float, float) =
  ## Direction of volley `i` of a lunge: facing, opposite, then the two perpendiculars.
  let (fx, fy) = facingVec(facing)
  case i mod 4
  of 0: (fx, fy)
  of 1: (-fx, -fy)
  of 2: (-fy, fx)
  else: (fy, -fx)

proc attackPlan*(kind: WeaponKind, level: int, st: Stats, px, py: float, facing: Dir,
                 hasNearest: bool, nx, ny: float, starter = false): seq[ProjSpec] =
  ## The projectiles one weapon activation creates. `starter` = this is the hero's own weapon,
  ## whose first lunge is drawn by the body's attack animation instead of an icon.
  let w = weaponAt(kind, level)
  let n = max(1, w.amount + st.amount)
  let dmg = w.damage * st.might
  let size = w.size * st.area
  let ttl = w.ttl * st.duration
  let speed = w.speed * st.projSpeed
  let (fx, fy) = facingVec(facing)
  case w.motion
  of Lunge:
    for i in 0 ..< n:
      let (dx, dy) = lungeDir(facing, i)
      result.add ProjSpec(kind: kind, x: px + dx * size / 2, y: py + dy * size / 2,
                          size: size, damage: dmg, ttl: ttl, angle: arctan2(dy, dx), pierce: w.pierce,
                          held: starter and i == 0)
  of Homing:
    var dx = fx
    var dy = fy
    if hasNearest:
      dx = nx - px
      dy = ny - py
    let len = max(1e-6, sqrt(dx * dx + dy * dy))
    let base = arctan2(dy / len, dx / len)
    for i in 0 ..< n:
      let a = base + (float(i) - float(n - 1) / 2) * 0.15
      result.add ProjSpec(kind: kind, x: px, y: py, vx: cos(a) * speed, vy: sin(a) * speed,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)
  of Straight:
    for i in 0 ..< n:
      let off = (float(i) - float(n - 1) / 2) * 10
      result.add ProjSpec(kind: kind, x: px - fy * off, y: py + fx * off, vx: fx * speed, vy: fy * speed,
                          size: size, damage: dmg, ttl: ttl, angle: arctan2(fy, fx), pierce: w.pierce)
  of Arc:
    for i in 0 ..< n:
      let dirx = if fx != 0: fx else: (if i mod 2 == 0: 1.0 else: -1.0)
      result.add ProjSpec(kind: kind, x: px, y: py, vx: dirx * (60 + float(i) * 30), vy: -speed * 1.5,
                          size: size, damage: dmg, ttl: ttl, pierce: w.pierce)
  of Return:
    for i in 0 ..< n:
      let a = rand(2 * PI)
      result.add ProjSpec(kind: kind, x: px, y: py, vx: cos(a) * speed, vy: sin(a) * speed,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)
  of Aura:
    result.add ProjSpec(kind: kind, x: px, y: py, size: size, damage: dmg, ttl: w.ttl, pierce: w.pierce)
  of Orbit:
    let r = orbitRadius * st.area
    for i in 0 ..< n:
      let a = float(i) * 2 * PI / float(n)
      # vx = angular speed (rad/s), vy = orbit radius; moveProjectiles reads them that way
      result.add ProjSpec(kind: kind, x: px + cos(a) * r, y: py + sin(a) * r, vx: speed, vy: r,
                          size: size, damage: dmg, ttl: ttl, angle: a, pierce: w.pierce)
```

- [ ] **Step 4: Run tests**

Run: `nimble test 2>&1 | tail -30`
Expected: all `[OK]`. (`test_rules` still compiles: `attackPlan`'s new parameter has a default.)

- [ ] **Step 5: Commit**

```bash
git add src/systems.nim tests/test_systems.nim
git commit -m "systems: attack plans by Motion, 4-way lunge hitbox, held flag"
```

---

### Task 4: Rules — motion-driven movement, returning boomerang, starter animation facts

**Files:**
- Modify: `src/rules.nim`
- Modify: `tests/test_rules.nim`

**Interfaces:**
- Consumes: `ProjSpec.held`, `attackPlan(..., starter)` from Task 3; `boomerangAccel`, `boomerangCatchRadius`, `animDefs`, `weaponDefs[].anim/motion` from Task 2.
- Produces: attrs `Held: bool`, `Turned: bool` (projectiles), `Anim: BodyAnim`, `AnimStart: float` (player); `getProjectiles` gains `held`; `getPlayer` gains `anim`, `animStart`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_rules.nim`, replace the `"runetracer bounces inside the view"` (now Boomerang) test with:

```nim
  test "boomerang turns around, forgets its hits and is caught":
    var s = newSession()
    s.startRun(Otto)
    s.addWeapon(Boomerang)
    s.step(0.25)
    let b = s.queryAll(gameRules.getProjectiles).filterIt(it.kind == Boomerang)[0]
    s.insert(b.id, Pos, (10.0, 0.0))   # already 10 px out (at the player the pull is zero)
    s.insert(b.id, VX, 100.0)
    s.insert(b.id, VY, 0.0)
    s.insert(b.id, HitIds, toHashSet([42]))
    s.step(0.1)
    var p = s.query(gameRules.getProjectiles, id = b.id)
    check p.pos.x > 10.0
    check p.vx < 100.0                 # pulled back toward the player
    check p.hitIds.contains(42)        # still outbound: hits kept
    s.insert(b.id, VX, -100.0)         # now heading home
    s.step(0.1)
    p = s.query(gameRules.getProjectiles, id = b.id)
    check p.hitIds.len == 0            # turned: can hit the same enemies again
    s.insert(b.id, Pos, (5.0, 0.0))
    s.step(0.1)
    check s.query(gameRules.getProjectiles, id = b.id).ttl <= 0   # caught → expires
```

Add to the weapons suite:

```nim
  test "the starter weapon plays the body animation and holds its first lunge":
    var s = newSession()
    s.startRun(Otto)                 # Dragon Spear → AnimThrust
    s.addWeapon(ArcaneStaff)
    var p = s.query(gameRules.getPlayer)
    check p.anim == NoAnim
    s.step(0.25)
    p = s.query(gameRules.getPlayer)
    check p.anim == AnimThrust
    check abs(p.animStart - 0.25) < 1e-9
    let projs = s.queryAll(gameRules.getProjectiles)
    check projs.filterIt(it.kind == DragonSpear and it.held).len == 1
    check projs.filterIt(it.kind == ArcaneStaff and it.held).len == 0
    check animActive(p.anim, p.animStart, 0.5)
    check not animActive(p.anim, p.animStart, 0.25 + animDefs[AnimThrust].secs)

  test "a non-starter weapon never animates the body":
    var s = newSession()
    s.startRun(Imma)                 # Arcane Staff → AnimCast
    s.addWeapon(DragonSpear)
    s.step(0.25)
    let p = s.query(gameRules.getPlayer)
    check p.anim == AnimCast
    check s.queryAll(gameRules.getProjectiles).filterIt(it.kind == DragonSpear and it.held).len == 0

  test "war axe keeps its angle fact still; render spins it":
    var s = newSession()
    s.startRun(Lina)
    s.step(0.25)
    let a = s.queryAll(gameRules.getProjectiles)[0]
    s.step(0.1)
    check s.query(gameRules.getProjectiles, id = a.id).angle == a.angle
```

Also update `"insert/retract projectile round trip"` to `check not s.contains(id, Held)` after the retract.

- [ ] **Step 2: Run to verify failure**

Run: `nim c -r --hints:off --outdir:tmp tests/test_rules.nim`
Expected: compile error, `undeclared identifier: 'Held'` / no field `anim`.

- [ ] **Step 3: Implement in `src/rules.nim`**

Attr enum and schema:

```nim
    # shared entity attrs
    Hero, Pos, Facing, Moving, Hp, MaxHp, Speed, Damage, Size,
    Xp, Level, XpToNext, Gold, Kills, PlayerStats, Anim, AnimStart,
    ...
    # projectiles
    Proj, VX, VY, Ttl, Pierce, HitIds, Angle, Held, Turned,
```

```nim
  PlayerStats: Stats
  Anim: BodyAnim
  AnimStart: float
  ...
  Angle: float
  Held: bool
  Turned: bool
```

`insertProjectile` / `retractProjectile`:

```nim
proc insertProjectile*[S](session: var S, spec: ProjSpec): int =
  result = allocId()
  session.insert(result, Pos, (spec.x, spec.y))
  session.insert(result, Proj, spec.kind)
  session.insert(result, VX, spec.vx)
  session.insert(result, VY, spec.vy)
  session.insert(result, Ttl, spec.ttl)
  session.insert(result, Pierce, spec.pierce)
  session.insert(result, HitIds, initHashSet[int]())
  session.insert(result, Angle, spec.angle)
  session.insert(result, Size, spec.size)
  session.insert(result, Damage, spec.damage)
  session.insert(result, Held, spec.held)
  session.insert(result, Turned, false)

proc retractProjectile*[S](session: var S, id: int) =
  for a in [Proj, Pos, VX, VY, Ttl, Pierce, HitIds, Angle, Size, Damage, Held, Turned]:
    session.retract(id, a)
```

Getters — add to `getPlayer`:

```nim
        (Player, Kills, kills)
        (Player, Anim, anim)
        (Player, AnimStart, animStart)
```

and to `getProjectiles`:

```nim
        (id, Damage, damage)
        (id, Held, held)
```

`tickWeapons`:

```nim
    rule tickWeapons(Fact):
      what:
        (id, Weapon, kind, then = false)
        (id, WeaponLevel, level, then = false)
        (id, Cooldown, cd, then = false)
        (Global, HasNearest, hasNearest, then = false)
        (Global, NearestX, nx, then = false)
        (Global, NearestY, ny, then = false)
        (Global, TotalTime, tt, then = false)
        (Player, Pos, ppos, then = false)
        (Player, Facing, facing, then = false)
        (Player, Hero, hero, then = false)
        (Player, PlayerStats, st, then = false)
        (Global, DeltaTime, dt)
      then:
        let cd2 = cd - dt
        if cd2 > 0:
          session.insert(id, Cooldown, cd2)
        else:
          let starter = kind == characterDefs[hero].weapon
          for spec in attackPlan(kind, level, st, ppos.x, ppos.y, facing, hasNearest, nx, ny, starter):
            discard session.insertProjectile(spec)
          if starter and weaponDefs[kind].anim != NoAnim:
            session.insert(Player, Anim, weaponDefs[kind].anim)
            session.insert(Player, AnimStart, tt)
          session.insert(id, Cooldown, weaponAt(kind, level).cooldown * st.cooldownMul)
```

`moveProjectiles`:

```nim
    rule moveProjectiles(Fact):
      what:
        (id, Pos, pos, then = false)
        (id, Proj, kind, then = false)
        (id, VX, vx, then = false)
        (id, VY, vy, then = false)
        (id, Ttl, ttl, then = false)
        (id, Angle, angle, then = false)
        (id, Turned, turned, then = false)
        (Player, Pos, ppos, then = false)
        (Global, DeltaTime, dt)
      then:
        session.insert(id, Ttl, ttl - dt)
        case weaponDefs[kind].motion
        of Lunge:
          discard # stays where it was spawned
        of Aura:
          session.insert(id, Pos, ppos)
        of Orbit:
          # vx = angular speed, vy = orbit radius (see systems.attackPlan)
          let a = angle + vx * dt
          session.insert(id, Angle, a)
          session.insert(id, Pos, (ppos.x + cos(a) * vy, ppos.y + sin(a) * vy))
        of Arc:
          let vy2 = vy + axeGravity * dt
          session.insert(id, VY, vy2)
          session.insert(id, Pos, (pos.x + vx * dt, pos.y + vy2 * dt))
        of Return:
          # constant pull toward the player: flies out, slows, comes back even if the player moved
          let tx = ppos.x - pos.x
          let ty = ppos.y - pos.y
          let d = max(1e-6, sqrt(tx * tx + ty * ty))
          let nvx = vx + tx / d * boomerangAccel * dt
          let nvy = vy + ty / d * boomerangAccel * dt
          session.insert(id, VX, nvx)
          session.insert(id, VY, nvy)
          session.insert(id, Pos, (pos.x + nvx * dt, pos.y + nvy * dt))
          let homing = nvx * tx + nvy * ty > 0
          if not turned and homing:
            session.insert(id, Turned, true)
            session.insert(id, HitIds, initHashSet[int]()) # may hit the same enemies on the way back
          elif turned and d < boomerangCatchRadius:
            session.insert(id, Ttl, 0.0) # caught; stepSystems retracts expired projectiles
        of Homing, Straight:
          session.insert(id, Pos, (pos.x + vx * dt, pos.y + vy * dt))
```

(`WorldWidth`/`WorldHeight` conditions are gone from this rule; the bounce needed them, nothing else does.)

`startRun` — after `session.insert(Player, PlayerStats, c.base)`:

```nim
  session.insert(Player, Anim, NoAnim)
  session.insert(Player, AnimStart, 0.0)
```

- [ ] **Step 4: Run tests, bench and compile**

Run: `nimble test 2>&1 | tail -30 && (cd tests && nim c -r -d:release --hints:off --outdir:../tmp bench.nim) && nim c -d:noaudio --hints:off --outdir:tmp src/parasurvivors.nim && echo COMPILED`
Expected: all `[OK]`; bench prints four lines with `rules=` under ~5 ms at 300 enemies (no regression from the extra `Held`/`Turned` facts); `COMPILED`.

- [ ] **Step 5: Commit**

```bash
git add src/rules.nim tests/test_rules.nim
git commit -m "rules: projectiles move by Motion, boomerang returns, starter sets Anim

Return motion pulls the projectile back toward the player and clears
its hit list when it turns. The hero's starter weapon inserts
Anim/AnimStart on the player; render picks the attack sheet from them."
```

---

### Task 5: Render — atlas icons, attack sheets, sprite pickups/projectiles/sparks, HUD and level-up icons

**Files:**
- Modify: `src/render.nim`

**Interfaces:**
- Consumes: `atlas`, `sheetDefs`, `animActive`, `animFrame`, `pickupSprite`, `weaponDefs[].sprite/motion/spin/drawScale`, `passiveDefs[].sprite`, `characterDefs[].attackSheet`; player facts `anim`, `animStart`; projectile `held`.
- Produces: `addIcon(spr: Sprite, cx, cy, w: float, angle = 0.0)` (height follows the icon's aspect), `flushItems`.

- [ ] **Step 1: Atlas sheet, `addIcon`, `flushItems`**

Add to the `const` block: `itemsPng = staticRead("assets/items.png")`. Add `items: Sheet` to the `var` block. In `initRender`, after the sheet loop:

```nim
  block:
    let base = loadImage(itemsPng)
    items = Sheet(frameW: 1, frameH: 1, base: base, batch: compile(game, initInstancedEntity(base)))
```

After `addRect`/`flushShapes` add:

```nim
proc addIcon*(spr: Sprite, cx, cy, w: float, angle = 0.0) =
  ## Atlas icon centred at (cx, cy), `w` wide, height from the icon's own aspect.
  let r = atlas[spr]
  let h = w * float(r.h) / float(r.w)
  var e = items.base
  e.crop(float(r.x), float(r.y), float(r.w), float(r.h))
  e.translate(cx, cy)
  e.rotate(angle)
  e.translate(-w / 2, -h / 2)
  e.scale(w, h)
  items.batch.add(e)

proc flushItems[G](game: G, ww, wh: float, camera: Mat3x3[GLfloat], useCamera: bool) =
  if items.batch.attributes.a_matrix.data[].len == 0:
    return
  var b = items.batch
  b.project(ww, wh)
  if useCamera:
    b.invert(camera)
  render(game, b)
  items.batch.clear()
```

Delete `pickupColor` and `projColor`.

- [ ] **Step 2: Rewrite `drawWorld`**

```nim
proc drawWorld[G](game: G, ww, wh, tt: float) =
  let player = session.query(gameRules.getPlayer)
  var camera = mat3f(1)
  camera.translate(player.pos.x - ww / 2, player.pos.y - wh / 2)
  let minX = player.pos.x - ww / 2 - 100
  let maxX = player.pos.x + ww / 2 + 100
  let minY = player.pos.y - wh / 2 - 100
  let maxY = player.pos.y + wh / 2 + 100

  drawGround(game, ww, wh, camera, player.pos.x, player.pos.y)

  # pickups (icons), then the garlic aura ring: both under the sprites
  for p in session.queryAll(gameRules.getPickups):
    if p.pos.x < minX or p.pos.x > maxX or p.pos.y < minY or p.pos.y > maxY:
      continue
    case p.kind
    of GemBlue, GemGreen, GemRed:
      addIcon(pickupSprite(p.kind), p.pos.x, p.pos.y + 3 * sin(tt * 4 + float(p.id)), 16)
    of Coin: addIcon(SprCoin, p.pos.x, p.pos.y, 18)
    of Chicken: addIcon(SprChicken, p.pos.x, p.pos.y, 22)
    of Chest: addIcon(SprChest, p.pos.x, p.pos.y, 28)
    of Vacuum: addIcon(SprVacuum, p.pos.x, p.pos.y, 20, tt * 3)
  let stats = session.query(gameRules.getStats).stats
  var hasGarlic = false
  for w in session.queryAll(gameRules.getWeapons):
    if weaponDefs[w.kind].motion == Aura:
      hasGarlic = true
      let r = weaponAt(w.kind, w.level).size * stats.area
      addIcon(weaponDefs[w.kind].sprite, player.pos.x, player.pos.y, r * weaponDefs[w.kind].drawScale)
  flushItems(game, ww, wh, camera, true)

  # enemies
  let enemies = session.queryAll(gameRules.getEnemies)
  for e in enemies:
    if e.pos.x < minX or e.pos.x > maxX or e.pos.y < minY or e.pos.y > maxY:
      continue
    let d = enemyDefs[e.kind]
    let sh = sheets[d.sheet]
    let h = d.size
    let w = h * float(sh.frameW) / float(sh.frameH)
    let dx = player.pos.x - e.pos.x
    let dy = player.pos.y - e.pos.y
    let phase = int(tt / frameSecs) + e.id
    case e.kind
    of Bat:
      addSprite(d.sheet, phase mod 3, 0, e.pos.x, e.pos.y, w, h)
    of Koalio:
      addSprite(d.sheet, 2 + phase mod 3, 0, e.pos.x, e.pos.y, w, h, flip = dx < 0)
    of Parakeet:
      addSprite(d.sheet, phase mod 3, 0, e.pos.x, e.pos.y, w, h, flip = dx < 0)
    else:
      addSprite(d.sheet, 1 + phase mod 8, dirRow(dx, dy), e.pos.x, e.pos.y, w, h)
  # player: attack sheet while the starter weapon's animation runs, else the walk sheet
  block:
    let c = characterDefs[player.hero]
    if animActive(player.anim, player.animStart, tt):
      let cell = float(sheetDefs[c.attackSheet].cellW)
      addSprite(c.attackSheet, animFrame(player.anim, player.animStart, tt), player.facing.ord,
                player.pos.x, player.pos.y, cell, cell)
    else:
      let col = if player.moving: 1 + int(tt / frameSecs) mod 8 else: 0
      addSprite(c.sheet, col, player.facing.ord, player.pos.x, player.pos.y, 64, 64)
  flushSprites(game, ww, wh, camera)

  # projectiles, garlic bulb, hit sparks: icons over the sprites
  for p in session.queryAll(gameRules.getProjectiles):
    let d = weaponDefs[p.kind]
    if d.motion == Aura or p.held:
      continue
    addIcon(d.sprite, p.pos.x, p.pos.y, p.size * d.drawScale, p.angle + tt * d.spin)
  if hasGarlic:
    addIcon(SprGarlic, player.pos.x, player.pos.y - 44, 20)
  for e in enemies:
    if e.hitFlash > 0 and e.pos.x >= minX and e.pos.x <= maxX and e.pos.y >= minY and e.pos.y <= maxY:
      # instanced images have no per-instance alpha, so the spark shrinks instead of fading
      addIcon(SprSpark, e.pos.x, e.pos.y, 24 * e.hitFlash / hitFlashSecs)
  flushItems(game, ww, wh, camera, true)

  # hp bar under the player
  addRect(player.pos.x, player.pos.y + 38, 40, 6, 0, vec4(0.3f, 0f, 0f, 0.9f))
  let hpFrac = max(0.0, player.hp / player.maxHp)
  addRect(player.pos.x - 20 + 20 * hpFrac, player.pos.y + 38, 40 * hpFrac, 6, 0, vec4(0.2f, 0.9f, 0.2f, 0.9f))
  flushShapes(game, ww, wh, camera, true)
```

- [ ] **Step 3: HUD and level-up icons**

Replace the weapon/passive lists at the end of `drawHud`:

```nim
  var y = wh - 30
  for w in session.queryAll(gameRules.getWeapons):
    addIcon(weaponDefs[w.kind].sprite, 22, y + 12, 24)
    drawText(game, $w.level, 40, y, ww, wh, white, 0.8)
    y -= 30
  y = wh - 30
  for p in session.queryAll(gameRules.getPassives):
    addIcon(passiveDefs[p.kind].sprite, 212, y + 12, 24)
    drawText(game, $p.level, 230, y, ww, wh, white, 0.8)
    y -= 30
  flushItems(game, ww, wh, noCam, false)
```

(`drawText` renders immediately, so the icons flushed at the end sit on top of nothing they overlap; the text is offset to the right of each icon.)

In `drawLevelUp`, inside the `for i, c in m.choices[]` loop before `drawText`:

```nim
    case c.kind
    of NewWeapon, UpgradeWeapon: addIcon(weaponDefs[c.weapon].sprite, ww / 2 - 240, y + 20, 48)
    of NewPassive, UpgradePassive: addIcon(passiveDefs[c.passive].sprite, ww / 2 - 240, y + 20, 48)
    of BonusGold: addIcon(SprCoin, ww / 2 - 240, y + 20, 48)
    of BonusHeal: addIcon(SprChicken, ww / 2 - 240, y + 20, 48)
```

and after the loop (before the hint line): `flushItems(game, ww, wh, mat3f(1), false)`.

- [ ] **Step 4: Compile, run tests, run the game**

Run: `nim c -d:noaudio --hints:off --outdir:tmp src/parasurvivors.nim && nimble test 2>&1 | tail -5`
Expected: compiles; tests `[OK]`.

Run: `nim c -d:release -d:noaudio -d:autoplay -d:fastclock --hints:off --outdir:tmp -o:tmp/ps_auto src/parasurvivors.nim && timeout 40 tmp/ps_auto; echo "exit $?"`
Expected: a window runs for 40 s without crashing (`exit 124` from `timeout`). Watch for: Otto stabbing with the spear on every fire, pickups as gems, no coloured squares anywhere, level-up cards with icons.

- [ ] **Step 5: Screenshots of every state**

Build the key-scripted binary and capture (Hyprland; see `tools/screenshots.sh` header):

```bash
nim c -d:release -d:noaudio -d:keyscript --hints:off --outdir:tmp -o:tmp/ps_shot src/parasurvivors.nim
tools/screenshots.sh tmp/ps_shot otto "1:enter,2.5:enter,3:d:1.2,4.4:s:1.2" "0.7 2.2 3.5 4.0 4.6 5.5 8 12"
tools/screenshots.sh tmp/ps_shot lina "1:enter,2:down,2.2:down,2.5:enter,3:d:1.5" "3.6 4.2 6"
tools/screenshots.sh tmp/ps_shot gino "1:enter,2:down,2.2:down,2.4:down,2.6:enter,3:a:1.5" "3.5 4.0 6"
tools/screenshots.sh tmp/ps_shot imma "1:enter,2:down,2.4:enter,3:w:1.5" "3.5 4.0 6"
```

Open the frames in `tmp/shots/` with the Read tool. Check: title, character select (each survivor holds their weapon), each starter mid-animation (spear thrust, axe swing, bow draw, staff cast), gems/coins as icons, HUD icons. Fix and rebuild if any icon is mis-sized (adjust `drawScale` in `data.nim`) or the attack sheet is misaligned with the walk sheet (the body must not jump when the animation starts — if it does, the `regrid` centring in Task 1 is off).

- [ ] **Step 6: Commit**

```bash
git add src/render.nim
git commit -m "render: atlas icons for projectiles, pickups, sparks and HUD; starter attack sheets"
```

---

### Task 6: README, credits, screenshots

**Files:**
- Modify: `README.md`
- Modify: `src/assets/CREDITS.md`
- Replace: `docs/screenshots/*.png` (same file names)

- [ ] **Step 1: README tables and text**

- Survivor table:
  ```
  | Otto | Dragon Spear | +10% might | 120 |
  | Imma | Arcane Staff | -10% cooldown | 100 |
  | Lina | War Axe | +20% projectile speed | 90 |
  | Gino | Longbow | +1 projectile | 100 |
  ```
  followed by: "Each survivor carries their starting weapon and swings, draws or casts it every time it fires. Weapons picked up later fire on their own without a body animation."
- Weapon table:
  ```
  | Dragon Spear | lunges in the direction you face, passes through everything |
  | Arcane Staff | homes in on the nearest enemy |
  | Longbow | arrows fly in the direction you face |
  | War Axe | high damage, arcs up and falls back down |
  | Boomerang | flies out, curves back to you, hits on both legs |
  | Garlic | damages everything within a ring around you |
  | Round Shield | shields orbit around you |
  ```
- After "How it is put together", add:

  ```markdown
  ### Adding a weapon

  Everything a weapon needs is data. To add one:

  1. `src/data.nim`: add the value to `WeaponKind`, a `weaponDefs` row (pick a `motion`, a `sprite`,
     `drawScale`, `spin`; `anim` only matters if a survivor starts with it) and a `weaponUpgrades` row
     for levels 2–8.
  2. If it needs new art: add an `icon NAME …` line to `tools/fetch_assets.sh`, a `SprNAME` value to
     `Sprite`, run `nimble assets`. A sprite missing from `items.txt` fails to compile.
  3. A new movement style is a new `Motion` value with a branch in `systems.attackPlan` (spawn) and
     `rules.moveProjectiles` (per tick), plus a test in `tests/test_systems.nim`.
  4. `nimble test`, then `tools/screenshots.sh` to look at it.
  ```
- Credits section: add bullets for Reemax's "[LPC] Items and game effects" (icons for weapons, pickups, passives and effects, CC-BY-SA 3.0 / GPL, `CREDITS-lpc-items.txt`) and bluecarrot16 et al. "[LPC] Food" (garlic, CC-BY-SA 3.0 / GPL 3.0, `CREDITS-lpc-food.txt`), and note that weapon layers (dragon spear, staff, bow + arrow, war axe, round shield) come from the generator like the bodies.
- "The whole game is about 2000 lines of Nim" → recount with `wc -l src/*.nim` and update.

- [ ] **Step 2: CREDITS.md**

Update the composed-file table (each survivor now lists their weapon layers and a second row for `<name>_attack.png` with the thrust/spellcast/slash/shoot layers), and add sections:

```markdown
## Icon atlas (`items.png`)

Weapon icons are single frames cut from the generator layers above (`weapon/polearm/dragonspear`,
`weapon/ranged/bow/arrow`, `weapon/blunt/waraxe`, `shield/round`). The rest:

- Reemax, "[LPC] Items and game effects" (https://opengameart.org/content/lpc-items-and-game-effects),
  CC-BY-SA 3.0 / GPL 3.0 / GPL 2.0 — gems, coin, chicken, passive icons, boomerang, bolt, aura, spark,
  vacuum burst. Full credits in `CREDITS-lpc-items.txt`.
- bluecarrot16, Daniel Eddeland, Joshua Taylor, Richard Kettering et al., "[LPC] Food"
  (https://opengameart.org/content/lpc-food), CC-BY-SA 3.0 / GPL 3.0 — garlic. Full credits in
  `CREDITS-lpc-food.txt`.
- The chest is `tiles/chests.png` from the LPC Base Assets (Lanea Zimmerman).
```

- [ ] **Step 3: Re-shoot the README screenshots**

Three builds, all Hyprland captures via `tools/screenshots.sh` (frames land in `tmp/shots/`):

```bash
# 1. menus + a normal-speed Otto run: title, character select, early game, level-up
nim c -d:release -d:noaudio -d:keyscript --hints:off --outdir:tmp -o:tmp/ps_shot src/parasurvivors.nim
tools/screenshots.sh tmp/ps_shot menu "1:enter,2.5:enter,3:d:3,7:s:3,11:a:3" "0.7 2.2 5 8 12 16 20 25 30 40"
# 2. immortal 10x clock: mid game, boss, late game, reaper (~32 min game time = ~195 s), paused (Esc)
nim c -d:release -d:noaudio -d:keyscript -d:autoplay -d:fastclock --hints:off --outdir:tmp -o:tmp/ps_fast src/parasurvivors.nim
tools/screenshots.sh tmp/ps_fast fast "2:d:200,150:esc,152:esc" "30 50 75 100 130 151 160 190 200"
# 3. mortal 10x clock, standing still: game over
tools/screenshots.sh tmp/ps_shot over "1:enter,2.5:enter" "$(seq -s ' ' 20 5 120)"
```

Pick one frame per README image and copy it over `docs/screenshots/{title,character-select,early-game,level-up,mid-game,boss,late-game,paused,reaper,game-over}.png` (same names as today). Open each with the Read tool and confirm no coloured quads remain and the survivor is visibly holding/using their weapon.

- [ ] **Step 4: Final verification**

Run: `nimble test 2>&1 | tail -5 && nimble build -d:release 2>&1 | tail -2 && git status --short`
Expected: tests `[OK]`, build succeeds, only the intended files changed.

- [ ] **Step 5: Commit**

```bash
git add README.md src/assets/CREDITS.md docs/screenshots
git commit -m "docs: LPC weapons, starter animations, adding-a-weapon guide, new screenshots"
```
