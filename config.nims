when defined(release):
  --app:gui

--gc:orc

when defined(linux) and not defined(noaudio):
  # miniaudio needs these (see parasound/config.nims)
  switch("passL", "-ldl -lm -lpthread")

# pararules 1.4.0 copies a leaf node's whole match table once per queued `then`
# (O(N^2) per tick with N per-entity rule firings). Swap in a one-line fix; see
# patches/pararules/engine.diff.
patchFile("pararules", "engine", "patches/pararules/engine")
