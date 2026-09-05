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
# 64->192 pads a body sheet under an oversize weapon; 128->128 only trims the sheet. Never crop
# a 128 px weapon layer down to 64: the spear and bow poke past the small cell and get cut off.
# The first crop takes just the COLSxROWS frames we want: the oversize (128 px) walk sheets are
# padded out to 13 columns, and montage would otherwise spill the extras onto a second page.
regrid() {
  local in=$1 ci=$2 co=$3 cols=$4 rows=$5 out=$6
  magick "$in" +repage -crop "$(( ci * cols ))x$(( ci * rows ))+0+0" +repage \
    -crop "${ci}x${ci}" +repage -gravity center -background none -extent "${co}x${co}" +repage miff:- |
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
regrid "$(layer weapon/polearm/dragonspear/background/walk/steel.png)" 128 128 9 4 "$TMP/spear_walk_bg.png"
regrid "$(layer weapon/polearm/dragonspear/foreground/walk/steel.png)" 128 128 9 4 "$TMP/spear_walk_fg.png"
body walk 128 9 otto "${OTTO[@]}"
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
regrid "$(layer weapon/ranged/bow/normal/walk/background/steel.png)" 128 128 9 4 "$TMP/bow_walk_bg.png"
regrid "$(layer weapon/ranged/bow/normal/walk/foreground/steel.png)" 128 128 9 4 "$TMP/bow_walk_fg.png"
body walk 128 9 gino "${GINO[@]}"
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
  magick "$@" -fuzz 20% -trim +repage -fuzz 0 -resize '64x64>' "PNG32:$TMP/icon_$name.png"
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
icon bolt $(cell "$EFFECTS" 10 0)
icon arrow "$(layer weapon/ranged/bow/arrow/shoot/arrow.png)" +repage -crop 64x64+512+192 +repage
icon axe "$(layer weapon/blunt/waraxe/behind/walk/waraxe.png)" "$(layer weapon/blunt/waraxe/walk/waraxe.png)" \
  +repage -background none -layers flatten -crop 64x64+64+192 +repage
icon boomerang $(cell "$ITEMS" 9 8)
icon shield "$(layer shield/round/walk/brown.png)" +repage -crop 64x64+0+128 +repage
icon garlic $(cell "$FOOD" 23 15)
# the garlic range marker: a soft ring drawn here rather than an effects cell, because any filled
# 32 px cell turns into a translucent square once it is scaled up to the aura's diameter
icon aura -size 64x64 xc:none -fill none -stroke '#e6ffd8' -strokewidth 4 -draw 'circle 31.5,31.5 31.5,5.5' \
  -blur 0x1.2 -channel A -evaluate multiply 0.55 +channel
icon spark $(cell "$EFFECTS" 11 0)
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
  # animation sheets (thrust.png, spellcast.png ...) are credited under the layer's walk.png row;
  # and a few (the dragon spear) are keyed by a variant name of their own (walk_128.png,
  # thrust_oversize.png), so the last resort credits the first row in the layer's directory --
  # one directory is one asset, so every row in it names the same authors and licence.
  grep -F "\"$rel\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    grep -F "\"$(dirname "$rel").png\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    grep -F "\"$(dirname "$rel")/walk.png\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    grep -F "\"$(echo "$rel" | sed -E 's#/(walk|thrust|slash|shoot|spellcast|attack_slash)/#/#; s#/(walk|thrust|slash|shoot|spellcast)\.png#.png#')\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    { grep -m1 -F "\"$(dirname "$rel")/" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" &&
      echo "note: $rel credited via its directory's first row" >&2; } ||
    echo "WARNING: no credits row for $rel" >&2
done
awk '!seen[$0]++' "$OUT/CREDITS-lpc.csv" > "$TMP/dedup.csv" && mv "$TMP/dedup.csv" "$OUT/CREDITS-lpc.csv"

echo "done. sizes:"
file "$OUT"/*.png | sed 's/PNG image data, //' | cut -d, -f1-2
