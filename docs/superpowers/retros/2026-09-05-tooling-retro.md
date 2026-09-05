# Retro: what composed well, and what a "verification framework" would be

Date: 2026-09-05. Scope: the whole project so far (main + `sprites`, 2026-09-04 → 05).
Written after the spear-clipping fix, the first working Emscripten build and the pararules PR check.

The question this retro answers: the project was built from small, single-purpose pieces at
every layer (game libraries, build tooling, the agent's skills, the desktop-driving scripts).
Which of those compositions paid for themselves, which leaked, and what is worth extracting so the
next project gets the same loop for free? Hickey's framing applies: the pieces are *simple*
(one job, no entanglement); the work described here is what made them *easy* to use together.

## 1. The stack, and what "composable" bought

| Layer | Pieces | Contract between them |
|---|---|---|
| Game libraries | paranim (GL entities), pararules (facts + rules), paratext (font atlas), parasound (miniaudio), paramidi (MIDI → PCM), stb_image, nimgl/glfw | plain Nim procs and objects; no scene graph, no mandated ECS, no framework object |
| Build | `nim c` + `config.nims` defines, `patchFile`, nimble tasks | compile-time `-d:` switches are the only configuration surface |
| Test aids | `-d:autoplay`, `-d:fastclock`, `-d:keyscript`, `-d:perf`, `-d:noaudio` | the game is drivable from *inside* the process |
| Desktop driver | Hyprland (`hyprctl` Lua dispatch), `grim`, `tools/screenshots.sh` | `BINARY PREFIX "KEYS" "T1 T2 ..."` → `tmp/shots/PREFIX_TTT.TT.png` |
| Web driver | emsdk, headless Chromium + SwiftShader, CDP screenshot | same `-d:` seams, no compositor at all |
| Agent | superpowers skills (brainstorm → spec → plan → subagent-driven dev → review), caveman, memory files, parallel subagents | markdown files in `docs/superpowers/` and `~/.claude/.../memory/` |

### What paid off

- **Every library carried its own portability seam, so the web build was a config change.**
  nimgl emits `-sUSE_GLFW=3`, nimgl/opengl skips `dlopen` under `-d:emscripten`, paranim and
  paratext switch shaders to `300 es`, miniaudio disables threads. The first `emcc` build on
  emsdk 6.0.9 compiled clean; the only real bug was the 64 KB default wasm stack (see §3). A
  monolithic engine would have needed a port; a pile of small libraries needed a `when`.
- **State as facts made the game inspectable by scripts.** Because every piece of state is a
  `(id, attr, value)` fact, `-d:autoplay`, `-d:perf` and the tests read the same session the
  renderer reads. Nothing had to be exposed specially for testing.
- **`patchFile` is a composition seam for dependencies.** The pararules O(N²) `fireRules` fix
  ships as a one-module swap, no fork, no vendoring, and the same diff went upstream as
  [paranim/pararules#12](https://github.com/paranim/pararules/pull/12) (checked 2026-09-05:
  local patch byte-identical to the PR, upstream unmoved since 2023, fork tests green, no review
  yet).
- **Data tables over `case` statements.** `WeaponDef` rows (`motion`, `sprite`, `uiSprite`,
  `anim`) let a weaker model add a weapon without reading the renderer. The README's "Adding a
  weapon" list is deliberately honest about the steps that are *not* a table row.
- **Compile-time defines as the test surface.** When `wtype` could not reach the XWayland
  window, `-d:keyscript` put the input script inside the process, and the same seam later drove
  the browser build unchanged. Scriptability from inside beats fighting the OS from outside.
- **The agentic layer composed the same way.** Spec → plan → one subagent per plan task, each
  with a narrow prompt and a file partition, plus memory files as the resume point across
  `/clear`. Today two subagents ran in parallel (Emscripten install + build; pararules PR audit)
  while the main thread debugged the spear, with zero file overlap by construction.

### Where it leaked

- **Asset pipeline assumptions were invisible until a human looked.** `regrid 128 64` silently
  cropped the dragon-spear and longbow walk layers; every automated check passed because none
  looked at pixels. Fix: a headless test that decodes each hero sheet and asserts the left and
  right columns of every cell are transparent. Rule: any pipeline step that a human would catch
  *by eye* needs a cheap pixel assertion, not just a dimension check.
- **A first-frame smoke test is not a smoke test.** The web build rendered the title screen
  perfectly and overflowed the stack on the first *running* tick. `-d:autoplay` (skip menus)
  is the right smoke build; the first screen is the least representative frame.
- **pararules has a join-order cliff.** Position facts must sit on root joins (`Pos` first in
  every per-entity rule, `DeltaTime` last) or a fact reaching a non-root join re-scans the
  parent's partial matches. This is a property of the library, discovered by profiling, and now a
  README "Performance notes" paragraph. Composable libraries push these rules onto the user.
- **Module-name collisions in a flat namespace.** `rules` (module) vs `rules` (variable),
  `ruleset` (pararules macro): cheap to fix, annoying to discover.
- **Non-deterministic PNG output.** `magick` rewrites every sheet with fresh metadata, so
  `nimble assets` dirties 16 files when 2 changed. Pixel-compare against HEAD and restore the
  identical ones (done today by hand; should be in the script).
- **The compositor is the least portable layer.** Hyprland 0.55 moved `hyprctl` to a Lua
  dispatch API; `float` is a toggle; a window must be mapped and settled before dispatch calls
  take. `tools/screenshots.sh` is correct on this machine and nowhere else.
- **Concurrent edits confuse subagents.** The Emscripten subagent saw my in-progress test fail
  and correctly reported it as "not mine", but only because it was told which files were its own.
  Always state the partition *and* what the other party is editing.

## 2. The verification loop, as a pattern

What actually ran, for every visual change since 2026-09-04:

```
app seams                driver                        observer
-d:keyscript  ──────►  screenshots.sh (hyprctl+grim)  ──►  agent reads PNGs
-d:autoplay            or                                  and asserts
-d:fastclock           chromium --headless + CDP            (or diffs, or a test)
-d:perf
```

Three parts, three contracts:

1. **Seams** (owned by the app): a key-script grammar (`"1:enter,4:d:2"`), a menu-skip,
   a clock multiplier, a perf probe on stdout. All compile-time, all zero-cost when off.
2. **Driver** (owned by the platform): takes a binary, a script and a list of timestamps,
   returns frames named by time. Native: float + resize the window, `grim` by geometry. Web:
   serve `web/`, headless Chromium, `Page.captureScreenshot` over CDP (30 lines of Node).
3. **Observer** (owned by the agent): open the frames, compare against the intent in the plan,
   crop cells out of sheets with `magick` when the frame is ambiguous, and turn each finding that
   a human would have seen into a headless test so it never needs eyes again.

The **web driver is the portable one**. It needs no compositor, no window manager quirks, and
runs the identical wasm the user will play. After today, the Emscripten build is not just a
distribution target; it is the verification target that works on any machine with Chromium. The
Hyprland path stays for what wasm cannot show (audio, native input timing).

### What a framework would extract ("making easy from simple")

Not a library that owns the loop, but fixed contracts so the three parts stay swappable:

- A `keyscript` module for paranim games: the `PS_KEYS` grammar, the `runScript(ts)` hook and
  the `autoplay`/`fastclock` conventions, as a nimble package with a one-line include.
- `screenshots.sh` split into `drive-native.sh` and `drive-web.sh` with the same signature
  (`BINARY|URL PREFIX KEYS TIMES → frames/`), plus a `frames-diff` step that pixel-compares
  against the last committed frames and prints only the ones that changed.
- A skill for the agent that says: after any render change, run the driver with the plan's
  checkpoints, read the frames, and write a pixel test for anything you had to look at twice.
  (The spear test is the template: decode, assert on alpha, name the cell in the failure message.)
- The `patchFile` + upstream-PR move as a documented recipe: patch locally, open the PR the same
  hour, record both in memory, re-check with `gh pr view` at the start of the next session.

## 3. Today's numbers

| Item | Result |
|---|---|
| Spear/bow clipping | root cause: 128 px LPC walk layers cropped to 64 px cells; fixed with 128 px cells + renderer draws at the sheet's cell size; new pixel test |
| Emscripten | emsdk 6.0.9, `nim c -d:release -d:emscripten -d:noaudio` and `nimble build -d:emscripten -d:noaudio` both build; wasm 2.2 MB + 281 KB js |
| Web bug | default 64 KB wasm stack overflows on the first running tick; `-s STACK_SIZE=8388608` fixes it |
| pararules#12 | open, mergeable, no review, local patch identical; nothing to update |
| Tests | 57 headless tests (data, systems, rules) |
