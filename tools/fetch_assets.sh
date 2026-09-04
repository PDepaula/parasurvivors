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
  # +repage drops the PNG page offsets some layers carry (else flatten grows the canvas)
  magick "${layers[@]}" +repage -background none -layers flatten "PNG32:$OUT/$name.png"
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
  # variants like body/bodies/zombie/walk/zombie.png are credited under body/bodies/zombie/walk.png
  grep -F "\"$rel\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    grep -F "\"$(dirname "$rel").png\"" "$TMP/CREDITS.csv" >> "$OUT/CREDITS-lpc.csv" ||
    echo "WARNING: no credits row for $rel" >&2
done

echo "done. sizes:"
file "$OUT"/*.png | sed 's/PNG image data, //' | cut -d, -f1-2
