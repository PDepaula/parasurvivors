#!/usr/bin/env bash
# Captures a series of screenshots of a scripted run. Hyprland only (uses hyprctl + grim).
#
#   tools/screenshots.sh BINARY PREFIX "KEYS" "T1 T2 ..."
#
# BINARY must be built with -d:keyscript; KEYS is the PS_KEYS script it will play
# (see src/parasurvivors.nim) and T1 T2 ... are the seconds after launch at which to
# grab a frame. Frames land in tmp/shots/PREFIX_TTT.TT.png. Example, the title screen,
# the character select and the first 20 seconds of a run as Imma:
#
#   nim c -d:release -d:noaudio -d:keyscript --outdir:tmp -o:tmp/ps_shot src/parasurvivors.nim
#   tools/screenshots.sh tmp/ps_shot demo "1:enter,2.5:down,4:enter,4.5:d:2,7:s:2" "0.7 3.3 $(seq -s ' ' 5 25)"
set -u
BIN=$1; PFX=$2; KEYS=$3; TIMES=$4
cd "$(dirname "$0")/.."
OUT=tmp/shots; mkdir -p "$OUT"
T0=$(date +%s.%N)
PS_KEYS="$KEYS" "$BIN" >/dev/null 2>&1 & PID=$!
until hyprctl clients -j | jq -e --argjson pid "$PID" '.[]|select(.pid==$pid and .mapped)' >/dev/null; do sleep 0.05; done
sleep 0.5
# float it so the compositor stops tiling it into whatever shape is free
for _ in $(seq 1 20); do   # float is a toggle, so check between attempts
  hyprctl dispatch 'hl.dsp.window.float({window="pid:'"$PID"'"})' >/dev/null
  sleep 0.3
  hyprctl clients -j | jq -e --argjson pid "$PID" '.[]|select(.pid==$pid and .floating)' >/dev/null && break
done
hyprctl dispatch 'hl.dsp.window.resize({x=1024,y=768,exact=true,window="pid:'"$PID"'"})' >/dev/null
hyprctl dispatch 'hl.dsp.window.center({window="pid:'"$PID"'"})' >/dev/null
sleep 0.3
for t in $TIMES; do
  python3 -c "import time,sys; time.sleep(max(0, float(sys.argv[1]) + float(sys.argv[2]) - time.time()))" "$T0" "$t"
  G=$(hyprctl clients -j | jq -r --argjson pid "$PID" '.[] | select(.pid==$pid) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
  grim -g "$G" "$OUT/${PFX}_$(printf %06.2f "$t").png"
done
kill $PID 2>/dev/null; wait $PID 2>/dev/null
echo "done: $OUT/${PFX}_*.png"
