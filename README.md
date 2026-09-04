This is a basic vampire survivors clone built on the paranim stack with a focus on simplicity via paraules and composable libraries built by Zach Oakes.

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
- `patches/pararules/engine.nim` — pararules 1.4.0 with a one-line fix (`patches/pararules/engine.diff`),
  swapped in via `patchFile` in `config.nims`. Without it `fireRules` copies a rule's whole match table
  once per queued `then`, which is O(N²) per tick with N per-entity rule firings.

## Performance notes

Every entity keeps a single `Pos` fact and every per-entity rule lists `(id, Pos, pos)` first and
`DeltaTime` last: pararules re-scans all partial matches of a join's parent when a fact reaches a
non-root join, so position updates must hit root joins. `tests/bench.nim` times one tick headlessly:

    cd tests && nim c -r -d:release --hints:off --outdir:../tmp bench.nim

On the dev machine a 300-enemy tick costs ~3.5 ms of rules and ~2.5 ms of systems (release build).
`-d:perf` prints per-tick work time in the game; `-d:autoplay` skips the menus and makes the player
immortal so a `-d:fastclock` run reaches the late waves unattended.

Art: Liberated Pixel Cup contributors, see `src/assets/CREDITS.md`.
