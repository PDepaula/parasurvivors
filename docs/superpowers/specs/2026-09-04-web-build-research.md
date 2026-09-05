# Web build (Emscripten) — research findings

Date: 2026-09-04. Research only; no source changes made.

Legend: **[V]** = verified by reading the actual file named. **[I]** = inferred, not run.

## 1. Verdict

A web build is **feasible and unusually cheap**: the whole stack is already
Emscripten-aware upstream. paranim advertises Emscripten support, `paranim/glfw` is
`nimgl/glfw` which emits `-sUSE_GLFW=3`, `nimgl/opengl` has a static (non-`dlopen`) path
under `-d:emscripten`, and both paranim's and paratext's shaders switch to `#version 300 es`
on that define. `src/parasurvivors.nim` is a near-verbatim copy of parakeet's
`src/parakeet.nim` — the upstream reference project with a documented working web build.
Shortest path: copy parakeet's `config.nims` emscripten block + `shell_minimal.html`, add
`emscripten_set_main_loop` to `src/parasurvivors.nim`, build with `-d:noaudio`.
Biggest blocker: **audio payload size** — `src/audio.nim` `staticRead`s `generaluser.sf2`
(31 MB) in release builds (the native binary is 35 MB), and that would become the wasm
download. Audio is *not* an API blocker (miniaudio has a WebAudio backend and explicitly
disables its threads on Emscripten); it is a **size** blocker.

## 2. Findings

### Q1 — Does paranim support Emscripten? Yes, officially.

- paranim README line 141, "**_How do I build games for the web?_**": *"Paranim supports
  Emscripten. See the README in the [parakeet example game](https://github.com/paranim/parakeet)
  for more on how to build with it. Nim is particularly great for this because its C backend
  fits Emscripten's tools like a glove."* **[V]**
- parakeet README: *"Or to make a release build for the web: `nimble build -d:release -d:emscripten`"*,
  prerequisites `git clone emsdk; ./emsdk install 3.1.0; ./emsdk activate 3.1.0`. **[V]**
- The **identical** emscripten `config.nims` block appears in four upstream repos, verbatim:
  `paranim/parakeet/config.nims`, `paranim/paranim/examples/config.nims`,
  `paranim/paranim_examples/{dungeon_crawler,super_koalio,voxel_explorer}/config.nims`. **[V]**
  Quoted in full in §3.
- Crucially, `paranim/paranim/examples/examples.nimble` requires **`paratext >= 0.13.0`**
  (parasurvivors' exact version) *and* `stb_image >= 2.5`, and that directory carries the
  emscripten `config.nims` + `shell_minimal.html` — so paranim + paratext + stb_image on the
  web is upstream-exercised. Its `ex27_text.nim` even uses
  `const ttf = staticRead("assets/Roboto-Regular.ttf")` + `initFont(...)`, the exact pattern
  in `src/render.nim`. **[V]**

### Q2 — GLFW + OpenGL under Emscripten: already handled, no shader work needed.

- `~/.nimble/pkgs2/nimgl-1.3.2-.../nimgl/glfw.nim` lines 26–29: `when defined(emscripten):
  {.passL: "-s USE_GLFW=3".}`, and lines 24 + 84–89 skip compiling GLFW's own
  `vulkan.c/context.c/init.c/input.c/monitor.c/window.c`. The Emscripten GLFW3 shim is
  therefore linked in automatically — nothing to add. **[V]**
- All GLFW procs are `{.importc.}` with **no `header:` pragma** (`{.push cdecl.}`, line 1503),
  so no GLFW headers are needed at compile time. **[V]**
- `nimgl/opengl.nim` line 20: `when not defined(glCustomLoader) and not defined(emscripten):`
  guards the whole `dynlib`/`libGL.so.1` loader. Under `-d:emscripten` the other branch is
  used: direct `{.stdcall, importc.}` procs and `proc glInit*(): bool = true` (line 6801). **[V]**
  `src/core.nim`'s `doAssert glInit()` therefore still passes.
- Shaders: **paranim already does the GLSL switch.** `paranim/gl/entities.nim` lines 7–11 are
  `const version = when defined(emscripten): "300 es" else: "330"`; every shader is
  `"""#version $1 ...""".format(version)` and the fragment shaders already carry
  `precision mediump float;`. `paratext/gl/text.nim` has the identical block (lines 9–13) plus
  `internalFmt: when defined(emscripten): GL_LUMINANCE else: GL_RED` for the glyph atlas
  (lines 87, 91). **[V]**
- `src/render.nim` writes **no shaders of its own** (no `#version`/`vertexSource` anywhere);
  it only uses paranim/paratext entities, so there is nothing to port. Its raw GL calls are
  `glEnable(GL_BLEND)`, `glBlendFunc`, `glDisable(GL_CULL_FACE/GL_DEPTH_TEST)`,
  `glClearColor/glClear/glViewport`; `initImageEntity`'s texture params are
  `GL_CLAMP_TO_EDGE` + `GL_NEAREST` (`paranim/gl/entities.nim:235-239`). All ES3-core, as is
  instancing (`glDrawArraysInstanced`, `glVertexAttribDivisor`). **[V]**
- Link flag: upstream uses `-s USE_WEBGL2=1`, which current emscripten `settings.js` line 544
  marks *"Deprecated. Pass -sMAX_WEBGL_VERSION=2"*. Prefer
  `-sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2` on a modern emsdk. `-sFULL_ES3` is **not**
  needed (it emulates client-side arrays; paranim uses VAOs/VBOs). **[V]**

### Q3 — Main loop: one `when defined(emscripten)` block, ~6 lines.

parakeet's `src/parakeet.nim` (fetched verbatim) **[V]**:
```nim
when defined(emscripten):
  proc emscripten_set_main_loop(f: proc() {.cdecl.}, a: cint, b: bool) {.importc.}
  proc emscripten_get_canvas_element_size(target: cstring, width: ptr cint, height: ptr cint): cint {.importc.}
...
proc mainLoop() {.cdecl.} =        # {.cdecl.} is required
  ...
  when defined(emscripten):
    var width, height: cint
    if emscripten_get_canvas_element_size("#canvas", width.addr, height.addr) >= 0:
      window.frameSizeCallback(width, height)
    try: game.tick()
    except Exception as ex: echo ex.msg
  else:
    game.tick()
  window.swapBuffers(); glfwPollEvents()
...
when defined(emscripten):
  emscripten_set_main_loop(mainLoop, 0, true)
else:
  while not window.windowShouldClose: mainLoop()
```
`src/parasurvivors.nim` is otherwise line-for-line the same file (same window hints, `density`
computation, callbacks). The canvas-size poll replaces the framebuffer-size callback because
the browser resizes the canvas via CSS, not GLFW. **[V]**

### Q4 — Audio: works in principle, blocked on size.

- **miniaudio has a first-class WebAudio backend and is single-threaded there.**
  `parasound/miniaudio.h` is miniaudio **0.11.7** (lines 3638-3640); line 6097 is
  `#if defined(MA_EMSCRIPTEN) / #define MA_SUPPORT_WEBAUDIO`, and `ma_engine_init` at line
  71624 reads `/* The Emscripten build cannot use threads. */ #if defined(MA_EMSCRIPTEN)
  resourceManagerConfig.jobThreadCount = 0; resourceManagerConfig.flags |=
  MA_RESOURCE_MANAGER_FLAG_NO_THREADING; #endif`. So **`-sUSE_PTHREADS` is not required** —
  the engine is designed to run on the main loop. The backend uses `ScriptProcessorNode`
  via `EM_ASM` (line 38219 ff.). **[V]**
- Documented constraint (miniaudio manual §15.5, line 3580): *"You cannot use `-std=c*`
  compiler flags, nor `-ansi`."* Nim's `/etc/nim/nim.cfg:286` sets
  `clang.options.always = "-w -ferror-limit=3 -fno-strict-aliasing"` — no `-std=`. OK. **[V]**
- **TinySoundFont is portable C**: `paramidi/tsf.nim` is `{.compile: "tsf.c".}`, no threads,
  no OS calls beyond `stdio`. `paramidi` itself is pure Nim. **[V]**
- **The blocker**: `src/audio.nim:62` does
  `const soundfont = staticRead("paramidi_soundfonts/generaluser.sf2")` under
  `when defined(release)`. That file is **31,277,462 bytes** (`aspirin.sf2` is 16,624,854),
  and the committed native binary is 35 MB — consistent with the SF2 being embedded.
  Shipping that as wasm is not viable. **[V]**
- The non-release path calls `getSoundFontPath(...)` → `tsf_load_filename` on a host path
  absent in the browser; it returns `nil` and `audio.nim` echoes *"soundfont not found,
  continuing silently"* — a debug web build is silently mute, not broken. **[V]**
- Autoplay risk: `ma_device_start__webaudio` (line 38411) is just `device.webaudio.resume()`,
  and `initAudio()` runs **before any user gesture**, so Chrome will likely leave the context
  suspended (miniaudio warns about this at line 3588). Fix: re-start the device on the first
  key press. **[I]**
- **`-d:noaudio` is a fully viable first web build**: `src/audio.nim` compiles the whole
  parasound/paramidi/tsf tree out behind `when defined(noaudio)`, leaving no-op stubs. **[V]**

### Q5 — Nim toolchain specifics.

The upstream block (see §3) uses `--os:linux --cpu:wasm32 --cc:clang --clang.exe:emcc
--clang.linkerexe:emcc`, `--gc:orc`, `--exceptions:goto`, `-d:noSignalHandler`,
`-d:useMalloc`, `--opt:size`, `--threads:off`, `--nimcache:tmp`. **[V]**
- `--gc:orc` still works in Nim 2.2.10 (alias of `--mm:orc`); the repo already uses it.
  `-d:useMalloc` appears in every upstream config **[V]**; the reason (Nim's own allocator
  wants `mmap`) is **[I]**.
- `--os:linux` makes `defined(linux)` **true**, so `config.nims`'s current
  `when defined(linux) and not defined(noaudio): switch("passL", "-ldl -lm -lpthread")`
  would fire under emscripten. Must be excluded. **[V]**
- Likewise the current `when defined(release): --app:gui` must become the `elif` form
  upstream uses, so `--app:gui` is not applied to the emscripten build. **[V]**
- Asset size: `src/assets/` is **664 KB** total (including the 171 KB TTF).
  `staticRead`ing that into the wasm data section is a non-issue. Only the soundfont matters. **[V]**
- Nim 2.2.10 is installed; `emcc` is **not** on this machine — nothing was compiled. **[V]**

### Q6 — Key handling under the Emscripten GLFW shim.

Read from `emscripten-core/emscripten` `src/lib/libglfw.js` (main branch) **[V]**:
- Keyboard listeners attach to **`window`**, not the canvas (lines 1438–1440), so the
  `tabindex=-1` canvas does **not** need focus. `onBlur` is handled (line 1441), so no
  stuck-key bug in `PressedKeys` when the tab loses focus.
- **Quirk that will bite**: `onKeydown` only calls `event.preventDefault()` for
  `Backspace` and `Tab` (lines 418–427). **Arrow keys and Space will scroll the page.**
  Mitigation belongs in the shell HTML: a `keydown` listener that `preventDefault()`s
  arrows/space. **[V] for the shim behaviour, [I] for the mitigation.**
- Key codes match GLFW3 exactly under `-sUSE_GLFW=3`: `Escape→256`, `Enter→257`,
  `Right→262`, `Left→263`, `Down→264`, `Up→265`, `A→65`, `1→49` — identical to
  `nimgl/glfw.nim`'s constants. (The file has a separate GLFW2 branch that is *not* used.) **[V]**
- `glfwGetTime` is implemented (line 1527). `glfwSetKeyCallback`,
  `glfwSetFramebufferSizeCallback`, `glfwSwapBuffers`, `glfwPollEvents` (no-op returning 0),
  `glfwWindowShouldClose` and `glfwSwapInterval` all exist. Only
  `glfwGetTimerValue`/`Frequency` `abort()`, and neither is used here. **[V]**

### Q7 — Reference builds.

`paranim/parakeet` is the documented reference and `src/parasurvivors.nim` is a fork of its
`src/parakeet.nim`. Build command, verbatim from its README: `nimble build -d:release -d:emscripten`.
Also verified: `paranim/paranim/examples` (paranim + paratext + stb_image) and all three
`paranim/paranim_examples` games carry the same config; `dungeon_crawler` is the only one
that adds `-s ALLOW_MEMORY_GROWTH=1`. **[V]**

## 3. Proposed build recipe

### `config.nims` — add this block **above** the existing content

Copied from `paranim/parakeet/config.nims`, with the two parasurvivors-specific guards
fixed. Marked **untested** — no emcc on this machine.

```nim
when defined(emscripten):
  --nimcache:tmp            # tmp/ is already gitignored

  --os:linux                # Emscripten pretends to be linux.
  --cpu:wasm32
  --cc:clang
  when defined(windows):   # upstream also sets .cpp.exe / .cpp.linkerexe to the same
    --clang.exe:emcc.bat
    --clang.linkerexe:emcc.bat
  else:
    --clang.exe:emcc
    --clang.linkerexe:emcc
  --listCmd

  --gc:orc
  --exceptions:goto
  --define:noSignalHandler
  --define:useMalloc
  --opt:size
  --threads:off

  switch("passL", "-o index.html -s ALLOW_MEMORY_GROWTH=1 " &
                  "-s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 " &
                  "--shell-file shell_minimal.html")
elif defined(release):
  --app:gui                 # was `when defined(release)` — must not apply to emscripten

--gc:orc

when defined(linux) and not defined(emscripten) and not defined(noaudio):
  switch("passL", "-ldl -lm -lpthread")   # ← add `not defined(emscripten)`

patchFile("pararules", "engine", "patches/pararules/engine")
```

Upstream uses `-s USE_WEBGL2=1`; substituted `MIN/MAX_WEBGL_VERSION=2` because
`settings.js` marks `USE_WEBGL2` deprecated. Either should work.

### Build command

```sh
# once
git clone https://github.com/emscripten-core/emsdk && cd emsdk
./emsdk install 3.1.0 && ./emsdk activate 3.1.0   # then add printed dirs to PATH

# then, from the repo root
nimble build -d:release -d:emscripten -d:noaudio
python3 -m http.server 8000    # open http://localhost:8000/index.html
```
Equivalent direct form: `nim c -d:release -d:emscripten -d:noaudio src/parasurvivors.nim`.
Output lands as `index.html` / `index.js` / `index.wasm` in the cwd (from the `-o` in
`passL`); add those to `.gitignore`.

### Minimal source changes

- `shell_minimal.html` (new, repo root) — copy from
  `https://raw.githubusercontent.com/paranim/parakeet/master/shell_minimal.html`. It defines
  `<canvas id="canvas" tabindex=-1>`, a `window.onresize` that syncs `canvas.width/height`,
  and a `Module` with a `webglcontextlost` handler. Add a `keydown` listener that
  `preventDefault()`s arrows/space (see Q6).
- `config.nims` — the block above.
- `src/parasurvivors.nim` — three edits, all mirroring parakeet:
  1. add the `when defined(emscripten): proc emscripten_set_main_loop(...)` /
     `emscripten_get_canvas_element_size(...)` `importc` declarations;
  2. mark `proc mainLoop()` as `{.cdecl.}`, and inside it poll the canvas size + wrap
     `game.tick()` in `try/except` under `when defined(emscripten)`;
  3. replace the `while not window.windowShouldClose: mainLoop()` tail with the
     `when defined(emscripten): emscripten_set_main_loop(mainLoop, 0, true)` / `else:` form.
  Leave `-d:keyscript` alone — it is opt-in and `os.getEnv` is meaningless in a browser.
- `src/render.nim`, `src/core.nim`, `src/rules.nim`, `src/systems.nim`, `src/data.nim` —
  **no changes**. Their only non-portable imports are `times` under `-d:perf` and `os` under
  `-d:keyscript`, both opt-in **[V]**. `randomize()` in `core.init` relies on
  `times.getTime()`, which emscripten implements **[I]**.
- `src/audio.nim` — no change for the first build (`-d:noaudio`). See §4 for the follow-up.

## 4. Open questions / risks

1. **Nothing here has been compiled.** No `emcc` on this machine. Every claim about the
   *build* is textual inference from upstream configs that are known to work for parakeet.
2. **Soundfont size is the real audio blocker.** Best fix: **pre-render the seven MIDI
   scores to WAV on the host at build time and `staticRead` the WAVs**, dropping
   TinySoundFont and the SF2 from the web build entirely — the music loop is ~7 s of
   44.1 kHz mono 16-bit ≈ 600 KB and the six SFX are fractions of a second, so well under
   1 MB total. Needs a `nimble` task plus a `when defined(emscripten)` branch in
   `src/audio.nim`. (Swapping to `aspirin.sf2` only halves it to 16 MB — not enough.)
3. **AudioContext autoplay.** `initAudio()` runs pre-gesture, so the context will probably
   stay suspended; needs a `ma_device_start` triggered from the first key press.
   `src/audio.nim` already hand-declares extra miniaudio symbols, so this is the same trick.
4. **emsdk version.** Upstream pins 3.1.0 (2022). Untested whether nimgl's `-s USE_GLFW=3`
   and Nim 2.2.10's generated C still build clean on emsdk 4.x.
5. **Size and speed are unmeasured.** pararules generates a lot of code; wasm size after the
   ~660 KB of assets is unknown. The README measures ~6 ms/tick at 300 enemies natively;
   wasm is typically 1.5–2x slower and `--opt:size` costs more, so late waves may not hold
   60 fps. Measure with `-d:perf -d:fastclock` before optimising.
6. **`patchFile` under emscripten** — the pararules O(N²) patch is a pure-Nim source swap so
   it should apply identically, but it has never been compiled through emcc.
7. `emscripten_get_canvas_element_size("#canvas", ...)` requires the shell HTML to use
   exactly `id="canvas"`. Keep parakeet's shell rather than writing a new one.
