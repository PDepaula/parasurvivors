when defined(emscripten):
  # Web build (see docs/superpowers/specs/2026-09-04-web-build-research.md §3).
  # Copied from paranim/parakeet's config.nims; outputs land in web/ (gitignored).
  --nimcache:tmp

  --os:linux                # Emscripten pretends to be linux.
  --cpu:wasm32
  --cc:clang
  when defined(windows):
    --clang.exe:emcc.bat
    --clang.linkerexe:emcc.bat
    --clang.cpp.exe:emcc.bat
    --clang.cpp.linkerexe:emcc.bat
  else:
    --clang.exe:emcc
    --clang.linkerexe:emcc
    --clang.cpp.exe:emcc
    --clang.cpp.linkerexe:emcc
  --listCmd

  --gc:orc
  --exceptions:goto
  --define:noSignalHandler  # Emscripten has no signal handlers.
  --define:useMalloc
  --opt:size
  --threads:off

  mkDir("web")
  # Emscripten's default 64 KB stack overflows inside the first running tick (the
  # pararules session code is deeply nested); match the 8 MB a Linux thread gets.
  switch("passL", "-o web/index.html -s ALLOW_MEMORY_GROWTH=1 -s STACK_SIZE=8388608 " &
                  "-s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 " &
                  "--shell-file shell_minimal.html")
elif defined(release):
  --app:gui

--gc:orc

when defined(linux) and not defined(emscripten) and not defined(noaudio):
  # miniaudio needs these (see parasound/config.nims)
  switch("passL", "-ldl -lm -lpthread")

# pararules 1.4.0 copies a leaf node's whole match table once per queued `then`
# (O(N^2) per tick with N per-entity rule firings). Swap in a one-line fix; see
# patches/pararules/engine.diff.
patchFile("pararules", "engine", "patches/pararules/engine")
