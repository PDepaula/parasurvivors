when defined(release):
  --app:gui

--gc:orc

when defined(linux) and not defined(noaudio):
  # miniaudio needs these (see parasound/config.nims)
  switch("passL", "-ldl -lm -lpthread")
